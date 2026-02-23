#!/bin/bash

# ==========================================================================
# ULTRA SERVICE AUTOMATOR v5.2 - SECURITY, USER & TESTING EDITION
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

print_test_guide() {
    echo -e "\n${YELLOW}${BOLD}────────── UPUTE ZA TESTIRANJE I SPAJANJE ──────────${NC}"
    echo -e "$1"
    echo -e "${YELLOW}${BOLD}────────────────────────────────────────────────────${NC}"
}

pause() {
    echo -e "\n${CYAN}────────────────────────────────────────────${NC}"
    read -p "ENTER za povratak u meni..."
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Pokreni skriptu sa sudo privilegijama."
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
                    v5.2 TESTING PLUS
EOF
echo -e "${NC}"
}

# ================= STATIC IP =================
setup_static_ip() {
    log_step "TRAJNA STATIC IP (NETPLAN)"
    ip -brief link show
    while [[ -z "${IFACE:-}" ]]; do read -p "Interface (npr. ens33): " IFACE; done
    while [[ -z "${IP:-}" ]]; do read -p "IP adresa (npr. 192.168.1.10): " IP; done
    while [[ -z "${MASK:-}" ]]; do read -p "CIDR (npr. 24): " MASK; done
    while [[ -z "${GW:-}" ]]; do read -p "Gateway (npr. 192.168.1.1): " GW; done
    while [[ -z "${DNS:-}" ]]; do read -p "DNS (npr. 8.8.8.8): " DNS; done

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
    log_success "Static IP konfiguriran na $IP."
    
    print_test_guide "LINUX:  ip a  (Provjeri sučelje $IFACE)\nWIN:    ipconfig /all\nTEST:   ping -c 4 $GW"
    pause
}

# ================= DHCP =================
setup_dhcp() {
    log_step "DHCP SERVER (KEA)"
    [ -z "$SERVER_IP" ] && read -p "IP servera: " SERVER_IP
    read -p "Network (npr. 192.168.1.0): " NETWORK
    read -p "CIDR (npr. 24): " MASK
    read -p "Pool start: " START
    read -p "Pool end: " END

    apt update && apt install -y kea-dhcp4-server
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

    systemctl restart kea-dhcp4-server
    log_success "DHCP pokrenut."

    print_test_guide "LINUX:  sudo dhclient -v -r && sudo dhclient -v\nWIN:    ipconfig /release && ipconfig /renew\nLOG:    tail -f /var/log/syslog | grep kea"
    pause
}

# ================= DNS =================
setup_dns() {
    log_step "DNS SERVER (BIND9)"
    [ -z "$SERVER_IP" ] && read -p "IP servera: " SERVER_IP
    read -p "Domena (npr. moj-server.local): " DOMAIN

    REV=$(echo "$SERVER_IP" | awk -F. '{print $3"."$2"."$1}')
    LAST=$(echo "$SERVER_IP" | awk -F. '{print $4}')

    apt update && apt install -y bind9 bind9utils dnsutils
    backup_file /etc/bind/named.conf.local

    cat <<EOF > /etc/bind/named.conf.local
zone "$DOMAIN" { type master; file "/etc/bind/db.$DOMAIN"; };
zone "$REV.in-addr.arpa" { type master; file "/etc/bind/db.rev"; };
EOF

    cat <<EOF > "/etc/bind/db.$DOMAIN"
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

    systemctl restart bind9
    log_success "DNS aktivan."

    print_test_guide "LINUX:  dig @$SERVER_IP $DOMAIN\nWIN:    nslookup $DOMAIN $SERVER_IP\nREVERSE: nslookup $SERVER_IP $SERVER_IP"
    pause
}

# ================= FTP =================
setup_ftp() {
    log_step "FTP SERVER (VSFTPD)"
    read -p "FTP korisnik: " FTP_USER
    read -s -p "Lozinka: " FTP_PASS; echo
    read -p "Ime novog direktorija: " FTP_DIR_NAME
    read -p "Ime testne datoteke (npr. test.txt): " FTP_FILE_NAME
    read -p "Sadržaj datoteke: " FTP_FILE_CONTENT

    apt update && apt install -y vsftpd
    backup_file /etc/vsftpd.conf

    cat <<EOF > /etc/vsftpd.conf
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=/home/\$USER/ftp
pasv_min_port=40000
pasv_max_port=40100
EOF

    # Kreiranje korisnika i strukture
    id "$FTP_USER" &>/dev/null || useradd -m -s /bin/bash "$FTP_USER"
    echo "$FTP_USER:$FTP_PASS" | chpasswd
    
    # Postavljanje chroot okruženja (Home mora biti root-owned ili ne-writable za vsftpd chroot)
    mkdir -p "/home/$FTP_USER/ftp/$FTP_DIR_NAME"
    echo "$FTP_FILE_CONTENT" > "/home/$FTP_USER/ftp/$FTP_DIR_NAME/$FTP_FILE_NAME"
    
    # Dozvole
    chown root:root "/home/$FTP_USER/ftp"
    chmod 555 "/home/$FTP_USER/ftp"
    chown -R "$FTP_USER:$FTP_USER" "/home/$FTP_USER/ftp/$FTP_DIR_NAME"
    
    systemctl restart vsftpd
    log_success "FTP konfiguriran s datotekom: $FTP_DIR_NAME/$FTP_FILE_NAME"

    print_test_guide "LINUX:  ftp $SERVER_IP -> cd $FTP_DIR_NAME -> get $FTP_FILE_NAME\nWIN CMD: ftp $SERVER_IP (login, cd $FTP_DIR_NAME, ls)\nFILEZILLA: Spoji se na port 21 i potraži '$FTP_FILE_NAME' u '$FTP_DIR_NAME'"
    pause
}

# ================= SSH =================
setup_ssh() {
    log_step "SSH SERVER KONFIGURACIJA"
    apt update && apt install -y openssh-server sudo

    read -p "Unesi korisničko ime za SSH: " SSH_USER
    if ! id "$SSH_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$SSH_USER"
        passwd "$SSH_USER"
    fi
    usermod -aG sudo "$SSH_USER"

    backup_file /etc/ssh/sshd_config
    sed -i '/^PermitRootLogin/d; /^PasswordAuthentication/d; /^AllowUsers/d' /etc/ssh/sshd_config
    
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    echo "AllowUsers $SSH_USER" >> /etc/ssh/sshd_config

    systemctl restart ssh
    log_success "SSH spreman za $SSH_USER."

    print_test_guide "LINUX/WIN: ssh $SSH_USER@$SERVER_IP\nNAPOMENA: Root login je ONEMOGUĆEN!"
    pause
}

# ================= FIREWALL =================
setup_firewall_secure() {
    log_step "FIREWALL SECURE MODE"
    ufw reset
    ufw default deny incoming
    ufw default allow outgoing
    for p in 22 53 67/udp 21 40000:40100/tcp; do ufw allow $p; done
    ufw --force enable
    log_success "Firewall aktivan."

    print_test_guide "PROVJERA: sudo ufw status verbose"
    pause
}

kill_firewall() {
    ufw disable
    log_warn "Firewall isključen."
    pause
}

view_logs() {
    log_step "LOG PREGLED"
    tail -n 50 "$LOG_FILE"
    pause
}

# ================= MAIN =================
check_root

while true; do
    clear
    print_banner
    echo -e "${CYAN}1) Static IP (Netplan)          6) Firewall Secure (ON)"
    echo "2) DHCP (Kea)                   7) Firewall OFF"
    echo "3) DNS (Bind9)                  8) Pregled Logova"
    echo "4) FTP (Vsftpd + Test File)     9) Exit"
    echo -e "5) SSH (Korisnički pristup)${NC}"
    echo
    read -p "Odaberi opciju [1-9]: " opt

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