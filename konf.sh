#!/bin/bash

# ==========================================================================
# ULTRA SERVICE AUTOMATOR v4.0 - COMPETITION PRO MAX
# Linux Mint / Debian Server Automation Suite
# ==========================================================================

set -euo pipefail
IFS=$'\n\t'

# ================= BOJE =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ================= GLOBAL =================
LOG_FILE="/var/log/service_automator.log"
exec > >(tee -a "$LOG_FILE") 2>&1

SERVER_IP=""

backup_file() {
    [ -f "$1" ] && cp "$1" "$1.bak.$(date +%Y%m%d%H%M%S)"
}

log_success() { echo -e "${GREEN}${BOLD}[✔]${NC} $1"; }
log_error() { echo -e "${RED}${BOLD}[✘]${NC} $1"; }
log_info() { echo -e "${BLUE}${BOLD}[i]${NC} $1"; }
log_warn() { echo -e "${YELLOW}${BOLD}[!]${NC} $1"; }
log_step() { echo -e "${PURPLE}${BOLD}➤ $1${NC}"; }

pause() {
    echo -e "\n${CYAN}────────────────────────────────────────────${NC}"
    read -p "ENTER za povratak..."
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Pokreni skriptu sa sudo."
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
        U L T R A   S E R V I C E   A U T O M A T O R
                    v4.0 PRO MAX
EOF
echo -e "${NC}"
}

# ================= STATIC IP =================
setup_static_ip() {
log_step "TRAJNA STATIC IP (NETPLAN)"

ip -brief link show
    while [[ -z "${IFACE:-}" ]]; do read -p "$(echo -e "${YELLOW}Interface${NC} (npr. eth0, ens33): ")" IFACE; done
    while [[ -z "${IP:-}" ]]; do read -p "$(echo -e "${YELLOW}IP adresa${NC} (npr. 192.168.1.10): ")" IP; done
    while [[ -z "${MASK:-}" ]]; do read -p "$(echo -e "${YELLOW}CIDR${NC} (npr. 24): ")" MASK; done
    while [[ -z "${GW:-}" ]]; do read -p "$(echo -e "${YELLOW}Gateway${NC} (npr. 192.168.1.1): ")" GW; done
    while [[ -z "${DNS:-}" ]]; do read -p "$(echo -e "${YELLOW}DNS${NC} (npr. 8.8.8.8): ")" DNS; done

    echo -e "\n${RED}${BOLD}UPOZORENJE:${NC} Promjena IP adrese može prekinuti vašu SSH sesiju!"
    echo -e "${BOLD}Spreman za primjenu:${NC} $IP/$MASK na $IFACE (GW: $GW, DNS: $DNS)"
    read -p "Želiš li nastaviti? [Y/n]: " confirm
    [[ "${confirm,,}" == "n" ]] && { log_info "Otkazano."; pause; return; }


NETPLAN="/etc/netplan/01-static.yaml"
backup_file "$NETPLAN"

cat <<EOF > "$NETPLAN"
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      addresses:
        - $IP/$MASK
      routes:
        - to: default
          via: $GW
      nameservers:
        addresses: [$DNS]
EOF

netplan apply
SERVER_IP="$IP"

log_success "Static IP konfiguriran."

echo -e "\n${BOLD}PROVJERA:${NC}"
ip a
ip route
ping -c 2 8.8.8.8 || true

pause
}

# ================= DHCP =================
setup_dhcp() {
log_step "DHCP SERVER (KEA)"

    if [ -z "$SERVER_IP" ]; then
        while [[ -z "${SERVER_IP:-}" ]]; do read -p "$(echo -e "${YELLOW}IP servera${NC} (npr. 192.168.1.10): ")" SERVER_IP; done
    fi
    while [[ -z "${NETWORK:-}" ]]; do read -p "$(echo -e "${YELLOW}Network${NC} (npr. 192.168.1.0): ")" NETWORK; done
    while [[ -z "${MASK:-}" ]]; do read -p "$(echo -e "${YELLOW}CIDR${NC} (npr. 24): ")" MASK; done
    while [[ -z "${START:-}" ]]; do read -p "$(echo -e "${YELLOW}Pool start${NC} (npr. 192.168.1.100): ")" START; done
    while [[ -z "${END:-}" ]]; do read -p "$(echo -e "${YELLOW}Pool end${NC} (npr. 192.168.1.200): ")" END; done


apt update
apt install -y kea-dhcp4-server

backup_file /etc/kea/kea-dhcp4.conf

cat <<EOF > /etc/kea/kea-dhcp4.conf
{
 "Dhcp4": {
   "interfaces-config": { "interfaces": ["*"] },
   "lease-database": { "type": "memfile" },
   "subnet4": [{
     "subnet": "$NETWORK/$MASK",
     "pools": [{ "pool": "$START - $END" }],
     "option-data": [
       { "name": "routers", "data": "$SERVER_IP" },
       { "name": "domain-name-servers", "data": "$SERVER_IP" }
     ]
   }]
 }
}
EOF

kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
systemctl restart kea-dhcp4-server

log_success "DHCP pokrenut."

echo -e "\n${BOLD}STATUS:${NC}"
systemctl status kea-dhcp4-server --no-pager
ss -ulpn | grep 67 || true

echo -e "\n${BOLD}LEASEOVI:${NC}"
cat /var/lib/kea/kea-leases4.csv 2>/dev/null || echo "Još nema leaseova."

echo -e "\n${BOLD}TEST NA LINUX KLIJENTU:${NC}"
echo "sudo dhclient -v"
echo "ip a"
echo "ip route"

echo -e "\n${BOLD}TEST NA WINDOWS KLIJENTU:${NC}"
echo "ipconfig /release"
echo "ipconfig /renew"
echo "ipconfig /all"

pause
}

# ================= DNS =================
setup_dns() {
log_step "DNS SERVER (BIND9)"

    if [ -z "$SERVER_IP" ]; then
        while [[ -z "${SERVER_IP:-}" ]]; do read -p "$(echo -e "${YELLOW}IP servera${NC} (npr. 192.168.1.10): ")" SERVER_IP; done
    fi
    while [[ -z "${DOMAIN:-}" ]]; do read -p "$(echo -e "${YELLOW}Domena${NC} (npr. moj-server.local): ")" DOMAIN; done


REV=$(echo "$SERVER_IP" | awk -F. '{print $3"."$2"."$1}')
LAST=$(echo "$SERVER_IP" | awk -F. '{print $4}')

apt update
apt install -y bind9 bind9utils dnsutils

backup_file /etc/bind/named.conf.local

cat <<EOF > /etc/bind/named.conf.local
zone "$DOMAIN" {
 type master;
 file "/etc/bind/db.$DOMAIN";
};
zone "$REV.in-addr.arpa" {
 type master;
 file "/etc/bind/db.rev";
};
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
$LAST IN PTR $DOMAIN.
EOF

named-checkconf
named-checkzone "$DOMAIN" /etc/bind/db.$DOMAIN

systemctl restart bind9

log_success "DNS aktivan."

echo -e "\n${BOLD}STATUS:${NC}"
systemctl status bind9 --no-pager
ss -tulpn | grep 53 || true

echo -e "\n${BOLD}FORWARD TEST:${NC}"
dig @$SERVER_IP $DOMAIN
dig @$SERVER_IP www.$DOMAIN

echo -e "\n${BOLD}REVERSE TEST:${NC}"
dig -x $SERVER_IP @$SERVER_IP

echo -e "\n${BOLD}WINDOWS TEST:${NC}"
echo "nslookup $DOMAIN $SERVER_IP"
echo "nslookup $SERVER_IP $SERVER_IP"

pause
}

# ================= FTP =================
setup_ftp() {
    log_step "FTP SERVER (VSFTPD) - DETALJNA KONFIGURACIJA"

    # 1. Prikupljanje podataka
    while [[ -z "${FTP_USER:-}" ]]; do read -p "$(echo -e "${YELLOW}FTP korisnik${NC} (umjesto 'fifi'): ")" FTP_USER; done
    while [[ -z "${FTP_PASS:-}" ]]; do 
        read -s -p "$(echo -e "${YELLOW}Lozinka za $FTP_USER${NC}: ")" FTP_PASS
        echo
    done
    while [[ -z "${FTP_DIR_NAME:-}" ]]; do read -p "$(echo -e "${YELLOW}Ime poddirektorija${NC} (umjesto 'dupload'): ")" FTP_DIR_NAME; done
    while [[ -z "${FTP_MSG:-}" ]]; do read -p "$(echo -e "${YELLOW}Sadržaj testne datoteke${NC}: ")" FTP_MSG; done

    apt update
    apt install -y vsftpd net-tools

    # 2. Konfiguracija FTP servisa
    log_info "Konfiguracija /etc/vsftpd.conf..."
    [ -f /etc/vsftpd.conf ] && cp /etc/vsftpd.conf /etc/vsftpd.conf.orig
    
    cat <<EOF > /etc/vsftpd.conf
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
ftpd_banner=Dobro došli na FTP servis!
user_sub_token=\$USER
local_root=/home/\$USER/ftp
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
allow_writeable_chroot=YES
pasv_min_port=40000
pasv_max_port=40100
EOF

    # 3. Kreiranje korisnika i dodjela prava
    log_info "Kreiranje korisnika $FTP_USER..."
    if id "$FTP_USER" &>/dev/null; then
        echo "$FTP_USER:$FTP_PASS" | chpasswd
    else
        useradd -m -s /bin/bash "$FTP_USER"
        echo "$FTP_USER:$FTP_PASS" | chpasswd
    fi

    # Dodavanje u userlist
    echo "$FTP_USER" | tee -a /etc/vsftpd.userlist

    # Postavljanje direktorija i prava (755 prema uputama)
    log_info "Postavljanje strukture direktorija..."
    mkdir -p "/home/$FTP_USER/ftp/$FTP_DIR_NAME"
    
    chmod 755 /home
    chmod 755 "/home/$FTP_USER"
    chmod 755 "/home/$FTP_USER/ftp"
    
    # 4. Kreiranje testne datoteke
    echo "$FTP_MSG" > "/home/$FTP_USER/ftp/$FTP_DIR_NAME/test_download.txt"
    
    # Postavljanje vlasništva nad upload direktorijem
    chown -R "$FTP_USER:$FTP_USER" "/home/$FTP_USER/ftp/$FTP_DIR_NAME"

    # Restart i provjera
    systemctl restart vsftpd
    log_success "FTP servis je konfiguriran."

    echo -e "\n${BOLD}PROVJERA STATUSA:${NC}"
    vsftpd /etc/vsftpd.conf || true
    netstat -tuln | grep :21 || true

    echo -e "\n${BOLD}LINUX SPAJANJE:${NC}"
    echo "ftp $SERVER_IP"
    echo "lftp -u $FTP_USER,$FTP_PASS $SERVER_IP"

    echo -e "\n${BOLD}WINDOWS SPAJANJE:${NC}"
    echo "FileZilla → Host: $SERVER_IP, User: $FTP_USER, Pass: $FTP_PASS"
    echo "cmd → ftp $SERVER_IP"

    pause
}

# ================= SSH =================
setup_ssh() {
log_step "SSH SERVER"

apt update
apt install -y openssh-server
systemctl enable --now ssh

log_success "SSH aktivan."

echo -e "\n${BOLD}STATUS:${NC}"
systemctl status ssh --no-pager
ss -tulpn | grep 22 || true

    echo -e "\n${BOLD}LINUX / MAC SPAJANJE:${NC}"
    echo "ssh $USER@$SERVER_IP"
    echo "ssh root@$SERVER_IP"

    echo -e "\n${BOLD}WINDOWS SPAJANJE:${NC}"
    echo "PowerShell → ssh $USER@$SERVER_IP"
    echo "Putty → Host: $SERVER_IP, Port: 22"

    pause
}

# ================= FIREWALL =================
setup_firewall_secure() {
log_step "FIREWALL SECURE MODE"

ufw reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22
ufw allow 53
ufw allow 67/udp
ufw allow 21
ufw allow 40000:40100/tcp
ufw --force enable

log_success "Firewall postavljen (secure)."
ufw status verbose
pause
}

kill_firewall() {
log_warn "GASI SE FIREWALL"
ufw disable
pause
}

view_logs() {
    log_step "PREGLED LOGOVA (/var/log/service_automator.log)"
    tail -n 50 "$LOG_FILE"
    pause
}

# ================= MAIN =================
check_root

while true; do
clear
print_banner
echo -e "${CYAN}1) Static IP"
echo "2) DHCP"
echo "3) DNS"
echo "4) FTP"
echo "5) SSH"
echo "6) Firewall Secure"
echo "7) Firewall OFF"
echo "8) Pregled Logova"
echo "9) Exit${NC}"
echo
read -p "$(echo -e "${YELLOW}Odaberi opciju [1-9]:${NC} ")" opt

case $opt in
1) setup_static_ip ;;
2) setup_dhcp ;;
3) setup_dns ;;
4) setup_ftp ;;
5) setup_ssh ;;
6) setup_firewall_secure ;;
7) kill_firewall ;;
8) view_logs ;;
9) exit 0 ;;
*) log_error "Pogrešan odabir"; sleep 1 ;;
esac
done