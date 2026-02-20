#!/bin/bash

# ==========================================================================
# NAZIV: Ultra Service Automator (Linux Mint / Debian) - COMPETITION EDITION
# OPIS: Profesionalna automatizacija mrežne konfiguracije i servisa.
# ==========================================================================

# --- BOJE I STIL ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' 

# --- POMOĆNE FUNKCIJE ---
log_success() { echo -e "${GREEN}${BOLD}[✔] USPJEH:${NC} $1"; }
log_error() { echo -e "${RED}${BOLD}[✘] GREŠKA:${NC} $1"; }
log_info() { echo -e "${BLUE}${BOLD}[i] INFO:${NC} $1"; }
log_warn() { echo -e "${YELLOW}${BOLD}[!] UPOZORENJE:${NC} $1"; }
log_step() { echo -e "${PURPLE}${BOLD}➤ $1${NC}"; }

pause() {
    echo -e "\n${CYAN}──────────────────────────────────────────────────────────${NC}"
    read -p "Pritisnite [Enter] za povratak u glavni izbornik..."
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Ovu skriptu morate pokrenuti kao root (koristite sudo)."
        exit 1
    fi
}

print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
    ██████╗ ██╗   ██╗███╗   ██╗ █████╗ ███╗   ███╗██╗ ██████╗ 
    ██╔══██╗╚██╗ ██╔╝████╗  ██║██╔══██╗████╗ ████║██║██╔════╝ 
    ██║  ██║ ╚████╔╝ ██╔██╗ ██║███████║██╔████╔██║██║██║      
    ██║  ██║  ╚██╔╝  ██║╚██╗██║██╔══██║██║╚██╔╝██║██║██║      
    ██████╔╝   ██║   ██║ ╚████║██║  ██║██║ ╚═╝ ██║██║╚██████╗ 
    ╚═════╝    ╚═╝   ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝ ╚═════╝ 
             S E R V I C E   A U T O M A T O R  v2.0
EOF
    echo -e "${NC}"
}

# --- MODUL 1: STATIC IP CONFIGURATION ---
setup_static_ip() {
    log_step "KONFIGURACIJA STATIČKE IP ADRESE"
    ip -brief link show
    read -p "Unesite sučelje (npr. ens33): " INTERFACE
    read -p "Željena IP adresa (npr. 172.16.2.10): " REQ_IP
    read -p "Subnet maska (CIDR npr. 24): " MASK
    read -p "Gateway (npr. 172.16.2.1): " GW_IP

    log_info "Primjenjujem mrežne postavke..."
    ip addr flush dev "$INTERFACE"
    ip addr add "$REQ_IP/$MASK" dev "$INTERFACE"
    ip link set "$INTERFACE" up
    [ -n "$GW_IP" ] && ip route add default via "$GW_IP" 2>/dev/null
    
    SERVER_IP=$REQ_IP
    log_success "Mreža na $INTERFACE je uspješno podignuta."
    pause
}

# --- MODUL 2: DHCP (KEA) ---
setup_dhcp() {
    log_step "KONFIGURACIJA DHCP SERVERA (KEA)"
    [ -z "$SERVER_IP" ] && read -p "Unesite IP adresu servera: " SERVER_IP
    read -p "Mrežna adresa (npr. 172.16.2.0): " NETWORK
    read -p "CIDR (npr. 24): " MASK
    read -p "Pool početak: " P_START
    read -p "Pool kraj: " P_END

    log_info "Instalacija paketa i generiranje konfiguracije..."
    apt update && apt install kea-dhcp4-server -y

    cat <<EOF > /etc/kea/kea-dhcp4.conf
{
"Dhcp4": {
    "interfaces-config": { "interfaces": ["*"] },
    "control-socket": { "socket-type": "unix", "socket-name": "/tmp/kea4-ctrl-socket" },
    "lease-database": { "type": "memfile", "lfc-interval": 3600 },
    "subnet4": [
        {
            "subnet": "$NETWORK/$MASK",
            "pools": [ { "pool": "$P_START - $P_END" } ],
            "option-data": [
                { "name": "domain-name-servers", "data": "$SERVER_IP" },
                { "name": "routers", "data": "$SERVER_IP" }
            ],
            "valid-lifetime": 7200
        }
    ]
}
}
EOF
    ufw allow 67/udp && ufw allow 68/udp
    systemctl restart kea-dhcp4-server
    log_success "Kea DHCP je online. Portovi 67/68 otvoreni."
    
    echo -e "\n${BOLD}TESTNE NAREDBE:${NC}"
    echo "• sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf"
    echo "• sudo journalctl -u kea-dhcp4-server -n 10"
    pause
}

# --- MODUL 3: DNS (BIND9) ---
setup_dns() {
    log_step "KONFIGURACIJA DNS SERVERA (BIND9)"
    [ -z "$SERVER_IP" ] && read -p "IP adresa servera: " SERVER_IP
    read -p "Domena (npr. natjecanje.hr): " DOMAIN

    REV_ZONE=$(echo "$SERVER_IP" | awk -F. '{print $3"."$2"."$1}')
    LAST_OCTET=$(echo "$SERVER_IP" | awk -F. '{print $4}')

    apt update && apt install bind9 bind9utils -y

    cat <<EOF > /etc/bind/named.conf.local
zone "$DOMAIN" { type master; file "/etc/bind/db.$DOMAIN"; };
zone "$REV_ZONE.in-addr.arpa" { type master; file "/etc/bind/db.rev"; };
EOF

    cat <<EOF > /etc/bind/db.$DOMAIN
\$TTL 604800
@ IN SOA ns.$DOMAIN. root.$DOMAIN. ( $(date +%Y%m%d)01 604800 86400 2419200 604800 )
@ IN NS ns.$DOMAIN.
ns IN A $SERVER_IP
@ IN A $SERVER_IP
www IN CNAME @
EOF

    cat <<EOF > /etc/bind/db.rev
\$TTL 604800
@ IN SOA ns.$DOMAIN. root.$DOMAIN. ( $(date +%Y%m%d)01 604800 86400 2419200 604800 )
@ IN NS ns.$DOMAIN.
$LAST_OCTET IN PTR ns.$DOMAIN.
EOF

    ufw allow 53/tcp && ufw allow 53/udp
    chown bind:bind /etc/bind/db.$DOMAIN /etc/bind/db.rev
    systemctl restart bind9
    log_success "DNS (Bind9) podignut. Port 53 otvoren."
    
    echo -e "\n${BOLD}TESTNE NAREDBE:${NC}"
    echo "• nslookup $DOMAIN localhost"
    echo "• named-checkconf /etc/bind/named.conf.local"
    pause
}

# --- MODUL 4: FTP (VSFTPD) ---
setup_ftp() {
    log_step "KONFIGURACIJA FTP SERVERA (VSFTPD)"
    read -p "Korisnik: " FTP_USER
    read -s -p "Lozinka: " FTP_PASS; echo

    apt update && apt install vsftpd -y

    cat <<EOF > /etc/vsftpd.conf
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=/home/\$USER/ftp
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
pasv_enable=YES
pasv_min_port=10000
pasv_max_port=10100
EOF

    useradd -m -s /bin/bash "$FTP_USER"
    echo "$FTP_USER:$FTP_PASS" | chpasswd
    echo "$FTP_USER" > /etc/vsftpd.userlist

    mkdir -p "/home/$FTP_USER/ftp/upload"
    chown -R "$FTP_USER:$FTP_USER" "/home/$FTP_USER/ftp/upload"
    chmod 550 "/home/$FTP_USER/ftp"
    chmod 770 "/home/$FTP_USER/ftp/upload"

    ufw allow 20/tcp && ufw allow 21/tcp && ufw allow 10000:10100/tcp
    systemctl restart vsftpd
    log_success "FTP spreman. Pasivni portovi 10000-10100 otvoreni."
    pause
}

# --- MODUL 5: SSH (OPENSSH) ---
setup_ssh() {
    log_step "KONFIGURACIJA SSH"
    apt update && apt install openssh-server -y
    ufw allow 22/tcp
    systemctl enable --now ssh
    log_success "SSH klijent/server konfiguriran. Port 22 otvoren."

    echo -e "\n${BOLD}WINDOWS POWERSHELL QUICK-START:${NC}"
    echo "• Instalacija: Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"
    echo "• Spajanje: ssh $(whoami)@${SERVER_IP:-VAŠA_IP}"
    pause
}

# --- MODUL 7: FIREWALL SHUTDOWN ---
kill_firewall() {
    log_warn "ISKLJUČIVANJE FIREWALL-A (SIGURNOST ĆE BITI KOMPROMITIRANA)"
    ufw disable
    log_success "UFW (Uncomplicated Firewall) je isključen."
    pause
}

# --- GLAVNI CIKLUS ---
check_root

while true; do
    clear
    print_banner
    echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${YELLOW}1)${NC} KONFIGURACIJA STATIC IP (ENS33...)"
    echo -e "  ${YELLOW}2)${NC} DHCP SERVER (KEA)"
    echo -e "  ${YELLOW}3)${NC} DNS SERVER (BIND9)"
    echo -e "  ${YELLOW}4)${NC} FTP SERVER (VSFTPD)"
    echo -e "  ${YELLOW}5)${NC} SSH SERVER & WINDOWS POWERSHELL"
    echo -e "  ${YELLOW}6)${NC} FIREWALL: RESETIRAJ & DOPUSTI SVE PORTOVE"
    echo -e "  ${YELLOW}7)${NC} FIREWALL: POTPUNO UGASI (OFF)"
    echo -e "  ${YELLOW}8)${NC} IZLAZ"
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    read -p "Odaberite broj zadatka: " opt

    case $opt in
        1) setup_static_ip ;;
        2) setup_dhcp ;;
        3) setup_dns ;;
        4) setup_ftp ;;
        5) setup_ssh ;;
        6) ufw --force enable && ufw default allow incoming && log_success "UFW omogućen u 'Allow' modu." && pause ;;
        7) kill_firewall ;;
        8) log_info "Skripta završena. Sretno na natjecanju!"; exit 0 ;;
        *) log_error "Pogrešan odabir."; sleep 1 ;;
    esac
done