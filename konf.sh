#!/bin/bash

# --- GLOBALNE FUNKCIJE ---
log_success() { echo -e "\e[32m[USPJEH]\e[0m $1"; }
log_error() { echo -e "\e[31m[GREŠKA]\e[0m $1"; }
log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }

pause(){
   read -p "Pritisnite [Enter] za nastavak..." fackEnterKey
}

setup_ip() {
    echo "--- MREŽNA KONFIGURACIJA ---"
    read -p "Unesite naziv sučelja (npr. ens33): " INTERFACE
    read -p "Unesite željenu statičku IP adresu (npr. 172.16.2.10): " REQ_IP
    read -p "Unesite subnet masku (CIDR, npr. 24): " MASK

    CURRENT_IP=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)

    if [ "$CURRENT_IP" != "$REQ_IP" ]; then
        log_info "Postavljanje IP adrese $REQ_IP na $INTERFACE..."
        sudo ip addr flush dev $INTERFACE
        sudo ip addr add $REQ_IP/$MASK dev $INTERFACE
        sudo ip link set $INTERFACE up
        if [ $? -eq 0 ]; then log_success "IP adresa postavljena."; else log_error "Neuspjelo postavljanje IP-a."; exit 1; fi
    else
        log_success "Sučelje već ima ispravnu adresu: $CURRENT_IP."
    fi
    SERVER_IP=$REQ_IP
}

# --- GLAVNI MENU ---
clear
echo "=========================================================="
echo "    DINAMIČKA AUTOMATIZACIJA SERVISA (LV8 - LV11)        "
echo "=========================================================="
echo "1) DHCP (Kea) - [LV8]"
echo "2) DNS (Bind9) - [LV9]"
echo "3) FTP (vsftpd) - [LV10]"
echo "4) SSH (OpenSSH) - [LV11]"
echo "5) Izlaz"
echo "=========================================================="
read -p "Odaberite opciju [1-5]: " opcija

case $opcija in
    1)
        echo "--- KONFIGURACIJA DHCP (KEA) - LV8 ---"
        setup_ip
        read -p "Unesite mrežnu adresu (npr. 172.16.2.0): " NETWORK
        read -p "Unesite POOL START (npr. 172.16.2.30): " P_START
        read -p "Unesite POOL END (npr. 172.16.2.50): " P_END
        read -p "Unesite IP Gateway-a: " GW
        read -p "Unesite IP DNS-a: " DNS_IP

        log_info "Instalacija Kea DHCP servera..."
        sudo apt update && sudo apt install kea-dhcp4-server -y

        cat <<EOF | sudo tee /etc/kea/kea-dhcp4.conf
{
"Dhcp4": {
    "interfaces-config": { "interfaces": ["$INTERFACE"] },
    "control-socket": { "socket-type": "unix", "socket-name": "/tmp/kea4-ctrl-socket" },
    "lease-database": { "type": "memfile", "lfc-interval": 3600 },
    "subnet4": [
        {
            "subnet": "$NETWORK/$MASK",
            "pools": [ { "pool": "$P_START - $P_END" } ],
            "option-data": [
                { "name": "domain-name-servers", "data": "$DNS_IP" },
                { "name": "routers", "data": "$GW" }
            ],
            "valid-lifetime": 7200
        }
    ]
}
}
EOF
        sudo systemctl restart kea-dhcp4-server
        log_success "DHCP (Kea) je konfiguriran."
        
        echo -e "\n--- TESTNE NAREDBE (KOPIRAJ U DRUGI TERMINAL) ---"
        echo "1. Provjera statusa: sudo systemctl status kea-dhcp4-server"
        echo "2. Logovi u realnom vremenu: sudo journalctl -u kea-dhcp4-server -f"
        echo "3. Provjera konfiguracije: sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf"
        pause
        ;;

    2)
        echo "--- KONFIGURACIJA DNS (BIND9) - LV9 ---"
        setup_ip
        read -p "Unesite naziv domene (npr. krmis.tsrb.com): " DOMAIN
        FWD_FILE="db.$DOMAIN"
        
        # Izračun reverse zone
        REV_ZONE_NAME=$(echo $SERVER_IP | awk -F. '{print $3"."$2"."$1}')
        REV_FILE="db.$REV_ZONE_NAME"
        LAST_OCTET=$(echo $SERVER_IP | awk -F. '{print $4}')

        log_info "Instalacija BIND9..."
        sudo apt update && sudo apt install bind9 bind9utils bind9-doc -y

        # named.conf.local
        cat <<EOF | sudo tee /etc/bind/named.conf.local
zone "$DOMAIN" IN { type master; file "/etc/bind/$FWD_FILE"; };
zone "$REV_ZONE_NAME.in-addr.arpa" { type master; file "/etc/bind/$REV_FILE"; };
EOF

        # Forward Zone
        cat <<EOF | sudo tee /etc/bind/$FWD_FILE
\$TTL 604800
@ IN SOA ns.$DOMAIN. admin.$DOMAIN. ( $(date +%Y%m%d)01 604800 86400 2419200 604800 )
@ IN NS ns.$DOMAIN.
ns IN A $SERVER_IP
@ IN A $SERVER_IP
www IN CNAME @
EOF

        # Reverse Zone
        cat <<EOF | sudo tee /etc/bind/$REV_FILE
\$TTL 604800
@ IN SOA ns.$DOMAIN. root.ns.$DOMAIN. ( $(date +%Y%m%d)01 604800 86400 2419200 604800 )
@ IN NS ns.$DOMAIN.
$LAST_OCTET IN PTR ns.$DOMAIN.
EOF

        sudo chown bind:bind /etc/bind/$FWD_FILE /etc/bind/$REV_FILE
        sudo named-checkconf && log_success "Konfiguracija ispravna." || log_error "Greška u DNS sintaksi."
        sudo systemctl restart bind9
        
        echo -e "\n--- TESTNE NAREDBE (KOPIRAJ U DRUGI TERMINAL) ---"
        echo "1. Provjera Forward: nslookup $DOMAIN $SERVER_IP"
        echo "2. Provjera Reverse: nslookup $SERVER_IP $SERVER_IP"
        echo "3. Provjera datoteke zone: named-checkzone $DOMAIN /etc/bind/$FWD_FILE"
        pause
        ;;

    3)
        echo "--- KONFIGURACIJA FTP (VSFTPD) - LV10 ---"
        setup_ip
        read -p "Unesite korisničko ime (vježba: fifi): " FTP_USER
        read -s -p "Unesite lozinku: " FTP_PASS; echo

        log_info "Instalacija VSFTPD..."
        sudo apt update && sudo apt install vsftpd -y
        sudo cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

        cat <<EOF | sudo tee /etc/vsftpd.conf
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
ftpd_banner=Dobro došli na FTP servis!
user_sub_token=\$USER
local_root=/home/\$USER/ftp
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
EOF

        # Korisnik i dozvole (Točno prema koraku 3.2 u PDF-u)
        sudo useradd -m -s /bin/bash $FTP_USER
        echo "$FTP_USER:$FTP_PASS" | sudo chpasswd
        echo "$FTP_USER" | sudo tee -a /etc/vsftpd.userlist
        
        sudo mkdir -p /home/$FTP_USER/ftp/dupload
        sudo chmod 755 /home /home/$FTP_USER /home/$FTP_USER/ftp
        sudo chown -R $FTP_USER:$FTP_USER /home/$FTP_USER/ftp/dupload
        sudo chmod 777 /home/$FTP_USER/ftp/dupload

        echo "Test datoteka za LV10" | sudo tee /home/$FTP_USER/ftp/dupload/test.txt
        sudo systemctl restart vsftpd
        
        echo -e "\n--- TESTNE NAREDBE (KOPIRAJ U DRUGI TERMINAL) ---"
        echo "1. Lokalni test: ftp localhost"
        echo "2. Provjera porta 21: sudo netstat -tunlp | grep :21"
        echo "3. Status servisa: sudo systemctl status vsftpd"
        pause
        ;;

    4)
        echo "--- KONFIGURACIJA SSH - LV11 ---"
        setup_ip
        log_info "Instalacija OpenSSH servera..."
        sudo apt update && sudo apt install openssh-server -y
        
        sudo systemctl enable ssh
        sudo systemctl start ssh
        
        log_success "SSH je spreman na $SERVER_IP."
        echo -e "\n--- TESTNE NAREDBE (KOPIRAJ U DRUGI TERMINAL) ---"
        echo "1. Spajanje: ssh $USER@$SERVER_IP"
        echo "2. Provjera porta 22: ss -lnt | grep :22"
        pause
        ;;

    5) exit 0 ;;
    *) log_error "Pogrešan unos."; sleep 1; $0 ;;
esac