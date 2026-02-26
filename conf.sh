#!/bin/bash

# ==========================================================================
# ULTRA SERVICE AUTOMATOR v5.6 - EXAM PATHS & TESTING EDITION
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

# NOVA FUNKCIJA ZA ISPIS PUTANJA
print_config_paths() {
    echo -e "\n${CYAN}${BOLD}────────── KONFIGURACIJSKE DATOTEKE ──────────${NC}"
    echo -e "$1"
    echo -e "${CYAN}${BOLD}──────────────────────────────────────────────${NC}"
}

print_test_guide() {
    echo -e "\n${YELLOW}${BOLD}────────── KORISNE NAREDBE I TESTIRANJE ──────────${NC}"
    echo -e "$1"
    echo -e "${YELLOW}${BOLD}──────────────────────────────────────────────────${NC}"
}

pause() {
    echo -e "\n${CYAN}──────────────────────────────────────────────────${NC}"
    read -p "Pritisni ENTER za povratak u meni..."
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
                    v5.6 PATHS EDITION
EOF
echo -e "${NC}"
}

# ================= STATIC IP =================
setup_static_ip() {
    log_step "KONFIGURACIJA STATIČKE IP ADRESE"
    ip -brief link show
    while [[ -z "${IFACE:-}" ]]; do read -p "Interface (npr. ens33): " IFACE; done
    while [[ -z "${IP:-}" ]]; do read -p "IP adresa (npr. 172.16.1.20): " IP; done
    while [[ -z "${MASK:-}" ]]; do read -p "CIDR (npr. 24): " MASK; done
    while [[ -z "${GW:-}" ]]; do read -p "Gateway (npr. 172.16.1.1): " GW; done
    while [[ -z "${DNS:-}" ]]; do read -p "DNS (npr. 172.16.1.20): " DNS; done

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
    log_success "Mreža redefinirana na $IP."
    
    print_config_paths "MREŽA (Netplan): /etc/netplan/01-static.yaml"
    print_test_guide "PROVJERA: ip a show $IFACE\nPING:    ping -c 3 $GW\nRUTA:    ip route show"
    pause
}

# ================= DHCP =================
setup_dhcp() {
    log_step "DHCP SERVER (ISC-DHCP-SERVER)"
    [ -z "$SERVER_IP" ] && read -p "IP servera: " SERVER_IP
    read -p "Subnet (npr. 172.16.1.0): " NET
    read -p "Netmask (npr. 255.255.255.0): " NMASK
    read -p "Pool start: " START
    read -p "Pool end: " END
    read -p "Default lease time (sekunde, npr 360): " D_LEASE
    read -p "Max lease time (sekunde, npr 300): " M_LEASE

    apt update && apt install -y isc-dhcp-server
    
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    sed -i "s/INTERFACESv4=\"\"/INTERFACESv4=\"$IFACE\"/" /etc/default/isc-dhcp-server

    CONF="/etc/dhcp/dhcpd.conf"
    backup_file "$CONF"

    cat <<EOF > "$CONF"
default-lease-time $D_LEASE;
max-lease-time $M_LEASE;
authoritative;

subnet $NET netmask $NMASK {
  range $START $END;
  option routers ${NET%.*}.1;
  option domain-name-servers $SERVER_IP;
}
EOF

    systemctl restart isc-dhcp-server
    log_success "DHCP servis aktivan na $IFACE."

    print_config_paths "DHCP MAIN: /etc/dhcp/dhcpd.conf\nDHCP DEFAULTS: /etc/default/isc-dhcp-server"
    print_test_guide "STATUS:   systemctl status isc-dhcp-server\nLOGS:     tail -f /var/log/syslog | grep dhcpd\nZAKUP:    cat /var/lib/dhcp/dhcpd.leases"
    pause
}

# ================= DNS =================
setup_dns() {
    log_step "DNS SERVER (BIND9)"
    [ -z "$SERVER_IP" ] && read -p "IP servera: " SERVER_IP
    read -p "Domena (npr. test.tsrb.com): " DOMAIN

    IFS='.' read -r i1 i2 i3 i4 <<< "$SERVER_IP"
    REV_ZONE="$i3.$i2.$i1.in-addr.arpa"

    apt update && apt install -y bind9 bind9utils dnsutils
    backup_file /etc/bind/named.conf.local

    cat <<EOF > /etc/bind/named.conf.local
zone "$DOMAIN" { type master; file "/etc/bind/db.$DOMAIN"; };
zone "$REV_ZONE" { type master; file "/etc/bind/db.rev"; };
EOF

    cat <<EOF > "/etc/bind/db.$DOMAIN"
\$TTL 604800
@ IN SOA ns.$DOMAIN. root.$DOMAIN. ( $(date +%Y%m%d)01 604800 86400 2419200 604800 )
@ IN NS ns.$DOMAIN.
ns IN A $SERVER_IP
@ IN A $SERVER_IP
www IN A $SERVER_IP
EOF

    cat <<EOF > /etc/bind/db.rev
\$TTL 604800
@ IN SOA ns.$DOMAIN. root.$DOMAIN. ( $(date +%Y%m%d)01 604800 86400 2419200 604800 )
@ IN NS ns.$DOMAIN.
$i4 IN PTR $DOMAIN.
EOF

    systemctl restart bind9
    log_success "DNS zone za $DOMAIN kreirane."

    print_config_paths "DNS ZONES:    /etc/bind/named.conf.local\nFORWARD ZONE: /etc/bind/db.$DOMAIN\nREVERSE ZONE: /etc/bind/db.rev"
    print_test_guide "TEST:     nslookup $DOMAIN $SERVER_IP\nDIG:      dig @$SERVER_IP $DOMAIN\nREVERSE:  host $SERVER_IP\nCONF CHK: named-checkconf /etc/bind/named.conf.local"
    pause
}

# ================= FTP =================
setup_ftp() {
    log_step "FTP SERVER (VSFTPD)"
    read -p "FTP korisnik: " FTP_USER
    read -s -p "Lozinka: " FTP_PASS; echo
    read -p "Dozvoli anonimni pristup? (YES/NO): " ANON

    apt update && apt install -y vsftpd
    backup_file /etc/vsftpd.conf

    cat <<EOF > /etc/vsftpd.conf
listen=YES
anonymous_enable=$ANON
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=\$USER
local_root=/home/\$USER/ftp
pasv_min_port=40000
pasv_max_port=40100
EOF

    if ! id "$FTP_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$FTP_USER"
    fi
    echo "$FTP_USER:$FTP_PASS" | chpasswd
    
    mkdir -p "/home/$FTP_USER/ftp/upload"
    chown root:root "/home/$FTP_USER/ftp"
    chmod 555 "/home/$FTP_USER/ftp"
    chown "$FTP_USER:$FTP_USER" "/home/$FTP_USER/ftp/upload"
    
    systemctl restart vsftpd
    log_success "FTP servis spreman."

    print_config_paths "FTP KONFIG: /etc/vsftpd.conf"
    print_test_guide "POVEZIVANJE: ftp $SERVER_IP\nISPIT (Konfig): grep 'anonymous_enable' /etc/vsftpd.conf\nLOGS:    tail -f /var/log/vsftpd.log"
    pause
}

# ================= SSH =================
setup_ssh() {
    log_step "SSH SERVER KONFIGURACIJA"
    apt update && apt install -y openssh-server

    read -p "Korisnik za SSH pristup: " SSH_USER
    if ! id "$SSH_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$SSH_USER"
        passwd "$SSH_USER"
    fi
    
    backup_file /etc/ssh/sshd_config
    
    sed -i '/^PermitRootLogin/d; /^PasswordAuthentication/d; /^AllowUsers/d' /etc/ssh/sshd_config
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    echo "AllowUsers $SSH_USER" >> /etc/ssh/sshd_config

    systemctl restart ssh
    log_success "SSH konfiguriran za korisnika $SSH_USER."

    print_config_paths "SSH SERVER KONFIG: /etc/ssh/sshd_config"
    print_test_guide "STATUS:   systemctl status ssh | grep Active\nTEST:     ssh $SSH_USER@localhost\nISPIT:    Pokazati da je Root login 'no' u /etc/ssh/sshd_config"
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

    print_config_paths "UFW STATUS: sudo ufw status"
    pause
}

kill_firewall() {
    ufw disable
    log_warn "Firewall je isključen."
    pause
}

view_logs() {
    log_step "PREGLED LOGOVA"
    [ -f "$LOG_FILE" ] && tail -n 40 "$LOG_FILE" || log_error "Log datoteka nije pronađena."
    pause
}

# ================= MAIN LOOP =================
check_root

while true; do
    clear
    print_banner
    [ -n "$SERVER_IP" ] && echo -e "${CYAN}TRENUTNI IP: ${YELLOW}$SERVER_IP${NC}\n" || echo -e "${RED}IP NIJE DEFINIRAN!${NC}\n"
    
    echo -e "${CYAN}1) Static IP (Manual)           6) Firewall Secure (ON)"
    echo "2) DHCP (Manual + Lease)        7) Firewall OFF"
    echo "3) DNS (Manual Zone)            8) Pregled Logova"
    echo "4) FTP (User + Anon setup)      9) Exit"
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
        9) log_info "Gasim Automator..."; exit 0 ;;
        *) log_error "Pogrešan odabir"; sleep 1 ;;
    esac
done