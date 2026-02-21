# Ultra Service Automator

## Pregled sustava
Ultra Service Automator je automatizirani alat otvorenog koda namijenjen brzoj i standardiziranoj konfiguraciji mrežnih servisa na Debian i Linux Mint distribucijama. Skripta je inicijalno razvijena za potrebe natjecanja i okruženja u kojima je potrebna brza uspostava osnovne mrežne infrastrukture.

## Ključne funkcionalnosti

### 1. Mrežna konfiguracija (Netplan)
Automatizirana izmjena mrežnih postavki putem Netplan-a. Omogućuje postavljanje fiksne IP adrese, gateway-a i DNS poslužitelja. Skripta automatski generira backup postojeće konfiguracije prije svake promjene.

### 2. DHCP Server (Kea DHCPv4)
Implementacija modernog Kea DHCP poslužitelja. Modul uključuje:
- Definiranje podmreže (Subnetting)
- Upravljanje dinamičkim rasponom adresa (Pool)
- Konfiguraciju DHCP opcija (Gateways, Name Servers)
- Testiranje sintakse konfiguracijske datoteke prije pokretanja servisa

### 3. DNS Poslužitelj (Bind9)
Potpuna automatizacija Bind9 servisa koja uključuje:
- Kreiranje Forward zone (A i CNAME zapisi)
- Kreiranje Reverse zone (PTR zapisi)
- Automatsko ažuriranje serijskih brojeva zona na temelju trenutnog datuma
- Provjeru valjanosti zona pomoću `named-checkzone`

### 4. FTP Servis (vsftpd)
Postavljanje vsftpd servisa s fokusom na brzinu i osnovnu funkcionalnost:
- Automatsko kreiranje sistemskih korisnika
- Konfiguracija chroot zatvora za korisničke domene
- Integrirani statusni pregled mrežnih utičnica (sockets)

### 5. SSH i Sigurnost (OpenSSH + UFW)
- Uspostava SSH pristupa za daljinsko upravljanje.
- Upravljanje vatrozidom (UFW) s predefiniranim pravilima koja prate instalirane servise (TCP 21, 22, 53, UDP 67).

## Korištenje i implementacija

### Preduvjeti
Sustav mora biti zasnovan na Debian arhitekturi (Debian, Linux Mint, Ubuntu). Potrebne su privilegije superkorisnika (root).

### Instalacija i pokretanje
```bash
git clone https://github.com/MaNir007/krmis_konf.git
cd krmis_konf
chmod +x konf.sh
sudo ./konf.sh
```

## Tehničke karakteristike skripte
- **Logging:** Sve aktivnosti i greške bilježe se u `/var/log/service_automator.log`.
- **Sigurnosni backup:** Svaka sistemska datoteka koja se mijenja biva prethodno kopirana s vremenskom oznakom (`.bak.YYYYMMDDHHMMSS`).
- **Validacija unosa:** Skripta vrši provjeru prisutnosti obaveznih varijabli prije nastavka izvršavanja.
- **Error Handling:** Koristi se `set -euo pipefail` za prekid izvršavanja u slučaju fatalnih pogrešaka.

## Napomena o sigurnosti
Skripta je dizajnirana za razvojna i testna okruženja. U produkcijskim okruženjima preporuča se dodatno ručno otvrdnjavanje (hardening) generiranih konfiguracija prema specifičnim sigurnosnim policama organizacije.