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
read -p "Interface: " IFACE
read -p "IP adresa: " IP
read -p "CIDR (24): " MASK
read -p "Gateway: " GW
read -p "DNS: " DNS

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

[ -z "$SERVER_IP" ] && read -p "IP servera: " SERVER_IP
read -p "Network: " NETWORK
read -p "CIDR: " MASK
read -p "Pool start: " START
read -p "Pool end: " END

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

[ -z "$SERVER_IP" ] && read -p "IP servera: " SERVER_IP
read -p "Domena: " DOMAIN

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
log_step "FTP SERVER (VSFTPD)"

read -p "FTP korisnik: " USER
read -s -p "Lozinka: " PASS; echo

apt update
apt install -y vsftpd

useradd -m -s /bin/bash "$USER"
echo "$USER:$PASS" | chpasswd

systemctl restart vsftpd

log_success "FTP aktivan."

echo -e "\n${BOLD}STATUS:${NC}"
systemctl status vsftpd --no-pager
ss -tulpn | grep 21 || true

echo -e "\n${BOLD}LINUX SPAJANJE:${NC}"
echo "ftp $SERVER_IP"
echo "lftp $SERVER_IP"

echo -e "\n${BOLD}WINDOWS SPAJANJE:${NC}"
echo "FileZilla → Host: $SERVER_IP"
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

echo -e "\n${BOLD}LINUX/MAC:${NC}"
echo "ssh korisnik@$SERVER_IP"

echo -e "\n${BOLD}WINDOWS:${NC}"
echo "PowerShell → ssh korisnik@$SERVER_IP"

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
echo "8) Exit${NC}"
echo
read -p "Odaberi opciju: " opt

case $opt in
1) setup_static_ip ;;
2) setup_dhcp ;;
3) setup_dns ;;
4) setup_ftp ;;
5) setup_ssh ;;
6) setup_firewall_secure ;;
7) kill_firewall ;;
8) exit 0 ;;
*) log_error "Pogrešan odabir"; sleep 1 ;;
esac
done