#!/usr/bin/env bash
# =============================================
# Auto Audit AI - Laboratorio Etico v7.7
# Uso EXCLUSIVO em sistemas proprios ou autorizados
# =============================================

set -euo pipefail

VERSION="7.7"
APP_DIR="$HOME/autoaudit"
REPORT_DIR="$APP_DIR/reports"
HTML_DIR="$APP_DIR/html"
PDF_DIR="$APP_DIR/pdf"
KEYS_DIR="$HOME/.autoaudit_keys"
LOG_FILE="$APP_DIR/autoaudit.log"
LAB_FLAG="$APP_DIR/.lab_enabled"
LAB_PASS="autoaudit2026"

GROQ_KEY_FILE="$KEYS_DIR/groq_api_key"
SHODAN_KEY_FILE="$KEYS_DIR/shodan_api_key"
CENSYS_ID_FILE="$KEYS_DIR/censys_api_id"
CENSYS_SECRET_FILE="$KEYS_DIR/censys_api_secret"

GREEN='\e[1;32m'; RED='\e[1;31m'; YELLOW='\e[1;33m'; CYAN='\e[1;36m'; BLUE='\e[1;34m'; MAGENTA='\e[1;35m'; NC='\e[0m'

# ---------- UTILITARIOS ----------
log() { echo "[$(date '+%F %T')] $1" >> "$LOG_FILE"; }
msg_info()  { echo -e "${GREEN}[+]${NC} $1"; }
msg_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
msg_error() { echo -e "${RED}[ERRO]${NC} $1"; }

init_dirs() {
    mkdir -p "$APP_DIR" "$REPORT_DIR" "$HTML_DIR" "$PDF_DIR" "$KEYS_DIR"
    chmod 700 "$APP_DIR" "$KEYS_DIR"
    touch "$LOG_FILE"
}

cleanup() { rm -f /tmp/autoaudit_*; }
trap cleanup EXIT

save_key() { echo "$2" > "$1"; chmod 600 "$1"; }

check_dep() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || { msg_error "Dependencia ausente: $cmd"; return 1; }
    done
}

request_target() {
    read -p "Alvo autorizado (IP/dominio): " t
    [ -z "$t" ] && { msg_error "Alvo vazio."; return 1; }
    echo "$t"
}

confirm_run() {
    echo -e "${RED}!!! USE APENAS EM SISTEMAS AUTORIZADOS !!!${NC}"
    read -p "Digite SIM para continuar: " conf
    [ "$conf" != "SIM" ] && { msg_warn "Cancelado."; return 1; }
}

is_termux() { [ -d /data/data/com.termux/files/usr ]; }
is_linux() { command -v apt >/dev/null 2>&1 && ! is_termux; }

# ---------- CHAVES ----------
setup_groq_key() { read -s -p "Chave Groq: " k; echo; save_key "$GROQ_KEY_FILE" "$k"; msg_info "Salva."; }
setup_shodan_key() { read -s -p "Chave Shodan: " k; echo; save_key "$SHODAN_KEY_FILE" "$k"; msg_info "Salva."; }
setup_censys_keys() { read -p "ID: " i; read -s -p "Secret: " s; echo; save_key "$CENSYS_ID_FILE" "$i"; save_key "$CENSYS_SECRET_FILE" "$s"; msg_info "Salva."; }

config_keys_menu() {
    while true; do
        echo -e "\n${YELLOW}=== Chaves API ===${NC}"
        echo "1.Groq 2.Shodan 3.Censys 0.Voltar"
        read -p "Escolha: " o
        case $o in 1) setup_groq_key;; 2) setup_shodan_key;; 3) setup_censys_keys;; 0) break;; esac
    done
}

# ---------- IA ----------
ia_groq() {
    local p="$1"; local m="${2:-500}"
    [ ! -f "$GROQ_KEY_FILE" ] && setup_groq_key
    local k=$(<"$GROQ_KEY_FILE")
    [ -z "$k" ] && { msg_error "Chave vazia."; return 1; }
    local r=$(curl -s -X POST "https://api.groq.com/openai/v1/chat/completions" \
        -H "Authorization: Bearer $k" -H "Content-Type: application/json" \
        -d '{"model":"llama3-70b-8192","messages":[{"role":"user","content":"'"${p//\"/\\\"}"'"}],"temperature":0.7,"max_tokens":'"$m"'}' \
        | jq -r '.choices[0].message.content' 2>/dev/null)
    [ -z "$r" ] || [ "$r" = "null" ] && { msg_error "Falha API."; return 1; }
    echo "$r"
}

shodan_info() { local t="$1"; [ ! -f "$SHODAN_KEY_FILE" ] && setup_shodan_key; local k=$(<"$SHODAN_KEY_FILE"); curl -s "https://api.shodan.io/shodan/host/$t?key=$k" | jq '.'; }
censys_info() { local t="$1"; [ ! -f "$CENSYS_ID_FILE" ] && setup_censys_keys; local i=$(<"$CENSYS_ID_FILE"); local s=$(<"$CENSYS_SECRET_FILE"); curl -s -u "$i:$s" "https://search.censys.io/api/v2/hosts/$t" | jq '.'; }

# ---------- INSTALACAO ----------
install_deps() {
    echo -e "${GREEN}=== Instalando dependencias ===${NC}"
    if is_termux; then pkg update -y && pkg install -y nmap curl jq net-tools dnsutils tcpdump whois
    elif is_linux; then sudo apt update && sudo apt install -y nmap curl jq wkhtmltopdf net-tools dnsutils tcpdump whois
    fi; msg_info "Pronto."
}

install_lab_tools() {
    echo -e "${GREEN}=== Instalando ferramentas ===${NC}"
    if is_termux; then pkg update -y && pkg install -y nmap rustscan nikto dirb gobuster ffuf sqlmap hydra john hashcat theharvester whois dnsutils aircrack-ng reaver bettercap exploitdb whatweb wapiti crackmapexec ligolo-ng chisel netcat socat proxychains arp-scan -y 2>/dev/null || true
    elif is_linux; then sudo apt update && sudo apt install -y nmap masscan nikto dirb gobuster ffuf sqlmap hydra john hashcat theharvester whois dnsutils aircrack-ng reaver bettercap exploitdb metasploit-framework set impacket-scripts evil-winrm enum4linux snmp whatweb wapiti owasp-zap burpsuite crackmapexec ligolo-ng chisel netcat socat proxychains arp-scan 2>/dev/null || true
    fi; msg_info "Pronto."
}

# ---------- RELATORIOS ----------
run_nmap_scan() {
    local t="$1"; local ts=$(date +%Y%m%d_%H%M%S); local tx="$REPORT_DIR/scan_$ts.txt"; local h="$HTML_DIR/scan_$ts.html"
    msg_info "Nmap em $t..."; nmap -sS -sV -O -T4 -oN "$tx" "$t"
    local s=$(head -c 8000 "$tx"); local ia=$(ia_groq "Analise:\n$s" 800 || echo "")
    cat <<EOF > "$h"
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Auto Audit - $t</title>
<style>body{font-family:Arial;background:#111;color:#0f0;padding:2em}pre{background:#222;padding:1em}
.ia{background:#1a1a1a;border-left:4px solid #0f0;padding:1em}h1{color:#0f0}</style></head>
<body><h1>Relatorio - $t</h1><p>$ts</p><h2>Nmap</h2><pre>$(cat "$tx")</pre>
<h2>IA</h2><div class="ia">$ia</div></body></html>
EOF
    msg_info "Relatorio: $h"
}

setup_cron() { local sp=$(realpath "$0"); read -p "Alvo: " c; read -p "Cron: " t; (crontab -l 2>/dev/null; echo "$t $sp --cron-scan $c") | crontab -; msg_info "OK."; }
if [ "${1:-}" = "--cron-scan" ]; then shift; init_dirs; run_nmap_scan "$1"; exit 0; fi

enable_lab() { [ -f "$LAB_FLAG" ] && { msg_warn "Ja ativo."; return 0; }; echo -e "\n${RED}=== ATIVAR LAB ===${NC}"; read -s -p "Senha: " p; echo; [ "$p" != "$LAB_PASS" ] && { msg_error "Errada."; return 1; }; touch "$LAB_FLAG"; msg_info "LAB ATIVADO."; }
disable_lab() { rm -f "$LAB_FLAG"; msg_info "LAB desativado."; }
is_lab() { [ -f "$LAB_FLAG" ]; }

distro_menu() {
    [ ! -d /data/data/com.termux/files/usr ] && { msg_error "So Termux."; return 1; }
    command -v proot-distro >/dev/null 2>&1 || pkg install -y proot-distro
    while true; do
        echo -e "\n${CYAN}=== Distros Termux ===${NC}"
        echo "1.Ubuntu 2.Kali 3.Debian 4.Arch 5.Fedora 6.Alpine 7.Manjaro 8.Void 0.Voltar"
        read -p "Escolha: " o
        case $o in 1) d="ubuntu";; 2) d="kali";; 3) d="debian";; 4) d="archlinux";; 5) d="fedora";; 6) d="alpine";; 7) d="manjaro";; 8) d="void";; 0) break;; *) continue;; esac
        proot-distro install "$d"; msg_info "$d instalado!"; echo -e "Login: ${GREEN}proot-distro login $d${NC}"; read -p "Enter..."
    done
}

# ================== SUBMENUS COMPLETOS ==================
network_menu() {
    while true; do
        echo -e "\n${YELLOW}=== Network Recon ===${NC}"
        echo "1.nmap -sS -sV -O  2.netstat -tulnp  3.ss -tulnp  4.arp-scan -l"
        echo "5.traceroute  6.whois  7.dig ANY  8.nslookup  9.tcpdump  10.Masscan  11.RustScan  0.Voltar"
        read -p "Opcao: " o
        case $o in
            1) t=$(request_target) && confirm_run && nmap -sS -sV -O -T4 "$t" | tee "$REPORT_DIR/nmap_$(date +%Y%m%d%H%M%S).txt" || continue;;
            2) netstat -tulnp || continue;;
            3) ss -tulnp || continue;;
            4) arp-scan -l || continue;;
            5) read -p "Alvo: " t && traceroute "$t" || continue;;
            6) t=$(request_target) && whois "$t" | tee "$REPORT_DIR/whois_$(date +%Y%m%d%H%M%S).txt" || continue;;
            7) t=$(request_target) && dig "$t" ANY | tee "$REPORT_DIR/dig_$(date +%Y%m%d%H%M%S).txt" || continue;;
            8) read -p "Alvo: " t && nslookup "$t" || continue;;
            9) read -p "Interface: " i && tcpdump -i "$i" -n -c 100 || continue;;
            10) t=$(request_target) && confirm_run && masscan -p1-65535 --rate=1000 "$t" | tee "$REPORT_DIR/masscan_$(date +%Y%m%d%H%M%S).txt" || continue;;
            11) t=$(request_target) && confirm_run && rustscan -a "$t" -- -sV | tee "$REPORT_DIR/rustscan_$(date +%Y%m%d%H%M%S).txt" || continue;;
            0) break;;
        esac
    done
}

web_menu() {
    while true; do
        echo -e "\n${YELLOW}=== Web Testing ===${NC}"
        echo "1.curl -I  2.wget -r  3.ffuf  4.gobuster  5.nikto  6.sqlmap  7.WhatWeb  8.Wapiti"
        echo "9.WPScan  10.Dirb  11.Arjun  12.ParamSpider  13.XSStrike  14.NoSQLMap  15.ZAP  16.Burp  0.Voltar"
        read -p "Opcao: " o
        case $o in
            1) read -p "URL: " u && curl -I "$u" || continue;;
            2) read -p "URL: " u && wget -r -np "$u" || continue;;
            3) read -p "URL: " u && read -p "Wordlist: " w && ffuf -u "$u/FUZZ" -w "$w" -of html -o "$REPORT_DIR/ffuf_$(date +%Y%m%d%H%M%S).html" || continue;;
            4) read -p "URL: " u && gobuster dir -u "$u" -w /usr/share/wordlists/dirb/common.txt -o "$REPORT_DIR/gobuster_$(date +%Y%m%d%H%M%S).txt" || continue;;
            5) t=$(request_target) && confirm_run && nikto -h "$t" | tee "$REPORT_DIR/nikto_$(date +%Y%m%d%H%M%S).txt" || continue;;
            6) read -p "URL: " u && confirm_run && sqlmap -u "$u" --batch --wizard 2>&1 | tee "$REPORT_DIR/sqlmap_$(date +%Y%m%d%H%M%S).txt" || continue;;
            7) t=$(request_target) && whatweb "$t" | tee "$REPORT_DIR/whatweb_$(date +%Y%m%d%H%M%S).txt" || continue;;
            8) read -p "URL: " u && wapiti -u "$u" -o "$REPORT_DIR/wapiti_$(date +%Y%m%d%H%M%S)" || continue;;
            9) read -p "URL WP: " u && confirm_run && wpscan --url "$u" --enumerate p,t,u | tee "$REPORT_DIR/wpscan_$(date +%Y%m%d%H%M%S).txt" || continue;;
            10) read -p "URL: " u && dirb "$u" /usr/share/wordlists/dirb/common.txt -o "$REPORT_DIR/dirb_$(date +%Y%m%d%H%M%S).txt" || continue;;
            11) read -p "URL: " u && (arjun -u "$u" -o "$REPORT_DIR/arjun_$(date +%Y%m%d%H%M%S).json" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            12) t=$(request_target) && (paramspider -d "$t" -o "$REPORT_DIR/paramspider_$(date +%Y%m%d%H%M%S)" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            13) read -p "URL: " u && (xsstrike -u "$u" | tee "$REPORT_DIR/xsstrike_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            14) read -p "URL: " u && (nosqlmap -u "$u" | tee "$REPORT_DIR/nosqlmap_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            15) (zap.sh & disown 2>/dev/null || msg_error "Nao instalado.") || continue;;
            16) (burpsuite & disown 2>/dev/null || msg_error "Nao instalado.") || continue;;
            0) break;;
        esac
    done
}

crack_menu() {
    while true; do
        echo -e "\n${YELLOW}=== Password/Hash ===${NC}"
        echo "1.john  2.hashcat  3.hydra  4.cewl  5.crunch  0.Voltar"
        read -p "Opcao: " o
        case $o in
            1) read -p "Hash: " h && [ -f "$h" ] && john "$h" | tee "$REPORT_DIR/john_$(date +%Y%m%d%H%M%S).txt" || continue;;
            2) read -p "Hash: " h && [ -f "$h" ] && hashcat -m 0 -a 0 "$h" /usr/share/wordlists/rockyou.txt | tee "$REPORT_DIR/hashcat_$(date +%Y%m%d%H%M%S).txt" || continue;;
            3) t=$(request_target) && confirm_run && read -p "User: " u && read -p "Wordlist: " w && hydra -l "$u" -P "$w" ssh://"$t" -o "$REPORT_DIR/hydra_$(date +%Y%m%d%H%M%S).txt" || continue;;
            4) read -p "URL: " u && cewl "$u" -w "$REPORT_DIR/cewl_$(date +%Y%m%d%H%M%S).txt" || continue;;
            5) read -p "Min: " a && read -p "Max: " b && read -p "Chars: " c && crunch "$a" "$b" "$c" -o "$REPORT_DIR/crunch_$(date +%Y%m%d%H%M%S).txt" || continue;;
            0) break;;
        esac
    done
}

osint_menu() {
    while true; do
        echo -e "\n${YELLOW}==================== OSINT (31 ferramentas) ====================${NC}"
        echo -e "${CYAN}--- Dominios/Subdominios ---${NC}"
        echo "1.theHarvester  2.Subfinder  3.Amass  4.Assetfinder  5.dnsrecon  6.dnsenum"
        echo -e "${CYAN}--- Usuarios/Redes Sociais ---${NC}"
        echo "7.Sherlock  8.Maigret  9.SocialScan  10.GHunt  11.Holehe"
        echo -e "${CYAN}--- Dominio/Empresa ---${NC}"
        echo "12.whois  13.dig  14.nslookup  15.Photon  16.EmailHarvester"
        echo -e "${CYAN}--- Vazamentos ---${NC}"
        echo "17.h8mail  18.LeakLooker  19.Have I Been Pwned"
        echo -e "${CYAN}--- Metadados ---${NC}"
        echo "20.Metagoofil  21.Exiftool"
        echo -e "${CYAN}--- Infra/Certificados ---${NC}"
        echo "22.crt.sh  23.Certspotter  24.Shodan  25.Censys"
        echo -e "${CYAN}--- Telefone/Geo ---${NC}"
        echo "26.PhoneInfoga  27.Snscrape"
        echo -e "${CYAN}--- Frameworks ---${NC}"
        echo "28.Recon-ng  29.SpiderFoot"
        echo -e "${CYAN}--- Utilitarios ---${NC}"
        echo "30.Wordlists  31.Relatorio consolidado  0.Voltar"
        read -p "Opcao: " o
        case $o in
            1) t=$(request_target) && theHarvester -d "$t" -b all -f "$REPORT_DIR/harvester_$(date +%Y%m%d%H%M%S).html" || continue;;
            2) t=$(request_target) && (subfinder -d "$t" -o "$REPORT_DIR/subfinder_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            3) t=$(request_target) && (amass enum -passive -d "$t" -o "$REPORT_DIR/amass_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            4) t=$(request_target) && (assetfinder --subs-only "$t" | tee "$REPORT_DIR/assetfinder_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            5) t=$(request_target) && (dnsrecon -d "$t" -t std | tee "$REPORT_DIR/dnsrecon_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            6) t=$(request_target) && (dnsenum "$t" | tee "$REPORT_DIR/dnsenum_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            7) read -p "Usuario: " u && (python3 "$APP_DIR/tools/Sherlock/sherlock" "$u" --output "$REPORT_DIR/sherlock_$(date +%Y%m%d%H%M%S)" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            8) read -p "Usuario: " u && (maigret "$u" --pdf -o "$REPORT_DIR/maigret_$(date +%Y%m%d%H%M%S)" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            9) read -p "Email: " e && (socialscan "$e" | tee "$REPORT_DIR/socialscan_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            10) read -p "Email Gmail: " e && (python3 "$APP_DIR/tools/GHunt/ghunt.py" email "$e" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            11) read -p "Email: " e && (holehe "$e" --only-used | tee "$REPORT_DIR/holehe_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            12) t=$(request_target) && whois "$t" | tee "$REPORT_DIR/whois_$(date +%Y%m%d%H%M%S).txt" || continue;;
            13) t=$(request_target) && read -p "Tipo: " tp && dig "$t" "$tp" | tee "$REPORT_DIR/dig_$(date +%Y%m%d%H%M%S).txt" || continue;;
            14) read -p "Alvo: " t && nslookup "$t" || continue;;
            15) t=$(request_target) && (python3 "$APP_DIR/tools/Photon/photon.py" -u "$t" -o "$REPORT_DIR/photon_$(date +%Y%m%d%H%M%S)" -l 2 2>/dev/null || msg_error "Nao instalado.") || continue;;
            16) t=$(request_target) && (emailharvester -d "$t" -e google,bing -o "$REPORT_DIR/emailharvester_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            17) read -p "Email: " e && (h8mail -t "$e" -o "$REPORT_DIR/h8mail_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            18) read -p "Termo: " q && (leaklooker "$q" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            19) read -p "Email: " e && curl -s "https://haveibeenpwned.com/api/v3/breachedaccount/$e" | jq '.' | tee "$REPORT_DIR/pwned_$(date +%Y%m%d%H%M%S).txt" || continue;;
            20) t=$(request_target) && (metagoofil -d "$t" -t pdf,doc,xls -l 50 -n 5 -o "$REPORT_DIR/metagoofil_$(date +%Y%m%d%H%M%S)" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            21) read -p "Arquivo: " f && [ -f "$f" ] && exiftool "$f" | tee "$REPORT_DIR/exiftool_$(date +%Y%m%d%H%M%S).txt" || continue;;
            22) t=$(request_target) && curl -s "https://crt.sh/?q=%25.$t&output=json" | jq -r '.[].name_value' | sort -u | tee "$REPORT_DIR/crtsh_$(date +%Y%m%d%H%M%S).txt" || continue;;
            23) t=$(request_target) && curl -s "https://api.certspotter.com/v1/issuances?domain=$t&expand=dns_names" | jq '.' | tee "$REPORT_DIR/certspotter_$(date +%Y%m%d%H%M%S).json" || continue;;
            24) read -p "IP Shodan: " s && shodan_info "$s" || continue;;
            25) read -p "IP Censys: " c && censys_info "$c" || continue;;
            26) read -p "Telefone: " p && (phoneinfoga scan -n "$p" | tee "$REPORT_DIR/phoneinfoga_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            27) read -p "Busca: " q && (snscrape twitter-search "$q" | tee "$REPORT_DIR/snscrape_$(date +%Y%m%d%H%M%S).json" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            28) (recon-ng 2>/dev/null || msg_error "Nao instalado.") || continue;;
            29) t=$(request_target) && (spiderfoot -s "$t" -o "$REPORT_DIR/spiderfoot_$(date +%Y%m%d%H%M%S).json" 2>/dev/null || msg_error "Nao instalado.") || continue;;
            30) mkdir -p "$APP_DIR/wordlists"; wget -q https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt -O "$APP_DIR/wordlists/rockyou.txt" 2>/dev/null; msg_info "Wordlists em $APP_DIR/wordlists" || continue;;
            31) ls "$REPORT_DIR" > "$REPORT_DIR/osint_report_$(date +%Y%m%d%H%M%S).txt"; msg_info "Relatorio gerado." || continue;;
            0) break;;
        esac
    done
}

wireless_menu() {
    while true; do
        echo -e "\n${RED}=== Wireless ===${NC}"
        echo "1.airmon-ng  2.airodump-ng  3.aireplay-ng  4.aircrack-ng  5.reaver  6.bettercap  7.hcxdumptool  8.btlejuice  0.Voltar"
        read -p "Opcao: " o
        case $o in
            1) read -p "Interface: " i && airmon-ng start "$i" || continue;;
            2) read -p "Interface: " i && airodump-ng "$i" -w "$REPORT_DIR/airodump_$(date +%Y%m%d%H%M%S)" || continue;;
            3) read -p "Interface: " i && read -p "BSSID: " b && aireplay-ng --deauth 10 -a "$b" "$i" || continue;;
            4) read -p "Wordlist: " w && read -p "Captura: " c && aircrack-ng -w "$w" "$c" || continue;;
            5) read -p "Interface: " i && read -p "BSSID: " b && read -p "Canal: " c && reaver -i "$i" -b "$b" -c "$c" -vv | tee "$REPORT_DIR/reaver_$(date +%Y%m%d%H%M%S).txt" || continue;;
            6) bettercap -eval "net.probe on; net.recon on; net.show" || continue;;
            7) read -p "Interface: " i && hcxdumptool -i "$i" -o "$REPORT_DIR/hcxdump_$(date +%Y%m%d%H%M%S).pcapng" 2>/dev/null || msg_error "Nao instalado." || continue;;
            8) (btlejuice 2>/dev/null || msg_error "Nao instalado.") || continue;;
            0) break;;
        esac
    done
}

priv_menu() {
    while true; do
        echo -e "\n${RED}=== Privilege Escalation ===${NC}"
        echo "1.linpeas  2.winpeas(info)  3.sudo -l  4.uname -a  5.id  6.ps aux  7.find  8.grep  0.Voltar"
        read -p "Opcao: " o
        case $o in
            1) (./linpeas.sh 2>/dev/null || msg_error "Nao encontrado.") || continue;;
            2) echo "Execute winpeas.exe no Windows alvo." || continue;;
            3) sudo -l || continue;;
            4) uname -a || continue;;
            5) id || continue;;
            6) ps aux || continue;;
            7) read -p "Caminho: " d && read -p "Perm: " p && find "$d" "$p" 2>/dev/null || continue;;
            8) read -p "Arquivo: " f && read -p "String: " s && grep -r "$s" "$f" 2>/dev/null || continue;;
            0) break;;
        esac
    done
}

framework_menu() {
    while true; do
        echo -e "\n${YELLOW}=== Frameworks ===${NC}"
        echo "1.Metasploit  2.Searchsploit  3.SET  0.Voltar"
        read -p "Opcao: " o
        case $o in
            1) (msfconsole 2>/dev/null || msg_error "Nao instalado.") || continue;;
            2) read -p "Busca: " t && searchsploit "$t" | tee "$REPORT_DIR/searchsploit_$(date +%Y%m%d%H%M%S).txt" || continue;;
            3) echo -e "${RED}APENAS LAB ISOLADO!${NC}"; (setoolkit 2>/dev/null || msg_error "Nao instalado.") || continue;;
            0) break;;
        esac
    done
}

post_menu() {
    while true; do
        echo -e "\n${RED}=== Pos-Exploracao ===${NC}"
        echo "1.nc -lvnp  2.socat  3.Impacket  4.Evil-WinRM  5.enum4linux  6.snmpwalk  7.CrackMapExec"
        echo "8.Ligolo-ng  9.Chisel  10.proxychains  11.Mimikatz(info)  12.Rubeus(info)  13.BloodHound(info)  0.Voltar"
        read -p "Opcao: " o
        case $o in
            1) read -p "Porta: " p && nc -lvnp "$p" || continue;;
            2) read -p "Comando: " c && eval "$c" || continue;;
            3) read -p "Comando: " c && eval "$c" 2>&1 | tee "$REPORT_DIR/impacket_$(date +%Y%m%d%H%M%S).txt" || continue;;
            4) read -p "Alvo: " t && read -p "User: " u && read -s -p "Senha: " p && echo && evil-winrm -i "$t" -u "$u" -p "$p" 2>&1 | tee "$REPORT_DIR/evilwinrm_$(date +%Y%m%d%H%M%S).txt" || continue;;
            5) t=$(request_target) && enum4linux "$t" | tee "$REPORT_DIR/enum4linux_$(date +%Y%m%d%H%M%S).txt" || continue;;
            6) t=$(request_target) && snmpwalk -v2c -c public "$t" | tee "$REPORT_DIR/snmpwalk_$(date +%Y%m%d%H%M%S).txt" || continue;;
            7) read -p "Alvo: " t && read -p "User: " u && read -s -p "Senha: " p && echo && crackmapexec smb "$t" -u "$u" -p "$p" | tee "$REPORT_DIR/cme_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Nao instalado." || continue;;
            8) echo "1.Proxy 2.Cliente"; read -p "Opcao: " l; case $l in 1) read -p "Interface: " i && ligolo-proxy -bind 0.0.0.0:10001 -iface "$i" | tee "$REPORT_DIR/ligolo_$(date +%Y%m%d%H%M%S).txt";; 2) read -p "IP:porta: " a && ligolo-client -connect "$a" | tee "$REPORT_DIR/ligolo_$(date +%Y%m%d%H%M%S).txt";; esac || continue;;
            9) echo "1.Server 2.Client"; read -p "Opcao: " c; case $c in 1) read -p "Porta: " p && chisel server -p "$p" --reverse | tee "$REPORT_DIR/chisel_$(date +%Y%m%d%H%M%S).txt";; 2) read -p "IP:porta: " a && read -p "Porta local: " l && chisel client "$a" R:"$l":127.0.0.1:"$l" | tee "$REPORT_DIR/chisel_$(date +%Y%m%d%H%M%S).txt";; esac || continue;;
            10) read -p "Comando: " c && proxychains "$c" || continue;;
            11) echo "Mimikatz: sekurlsa::logonpasswords" || continue;;
            12) echo "Rubeus: kerberoast, asreproast" || continue;;
            13) echo "BloodHound: SharpHound.exe no alvo" || continue;;
            0) break;;
        esac
    done
}

# ================== MENU PRINCIPAL ==================
show_menu() {
    clear
    echo -e "${GREEN}"
    cat << "EOF"
⣿⣿⣿⣿⣿⣷⣿⣿⣿⡅⡹⢿⠆⠙⠋⠉⠻⠿⣿⣿⣿⣿⣿⣿⣮⠻⣦⡙⢷⡑⠘⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣌⠡⠌⠂⣙⠻⣛⠻⠷⠐⠈⠛⢱⣮⣷⣽⣿
⣿⣿⣿⣿⡇⢿⢹⣿⣶⠐⠁⠀⣀⣠⣤⠄⠀⠀⠈⠙⠻⣿⣿⣿⣦⣵⣌⠻⣷⢝⠦⠚⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢟⣻⣿⣊⡃⠀⣙⠿⣿⣿⣿⣎⢮⡀⢮⣽⣿⣿
⢿⣿⣿⣿⣧⡸⡎⡛⡩⠖⠀⣴⣿⣿⣿⠀⠀⠀⠀⠸⠇⠀⠙⢿⣿⣿⣿⣷⣌⢷⣑⢷⣄⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣫⠶⠛⠉⠀⠁⠀⠈⠈⠀⠠⠜⠻⣿⣆⢿⣼⣿⣿⣿
⢐⣿⣿⣿⣿⣧⢧⣧⢻⣦⢀⣹⣿⣿⣿⣇⠀⠄⠀⠀⠀⡀⠀⠈⢻⣿⣿⣿⣿⣷⣝⢦⡹⠷⡙⢿⣿⣿⣿⣿⣿⣿⣿⣿⠈⠁⠀⠀⠀⠁⠀⠀⠀⠱⣶⣄⡀⠀⠈⠛⠜⣿⣿⣿⣿
⠀⠊⢫⣿⣏⣿⡌⣼⣄⢫⡌⣿⣿⣿⣿⣿⣦⡈⠲⣄⣤⣤⡡⢀⣠⣿⣿⣿⣿⣿⣿⣷⣼⣍⢬⣦⡙⣿⣿⣿⣿⣿⣯⢁⡄⠀⡀⡀⠀⠄⢈⣠⢪⠀⣿⣿⣿⣦⠀⢉⢂⠹⡿⣿⣿
⠀⠀⠄⢹⢃⢻⣟⠙⣿⣦⠱⢻⣿⣿⣿⣿⣿⣿⣷⣬⣍⣭⣥⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⡙⢿⣼⡿⣿⣿⣿⣿⣿⣷⣄⠘⣱⢦⣤⡴⡿⢈⣼⣿⣿⣿⣇⣴⣶⣮⣅⢻⣿⡏
⠀⠀⠈⠹⣇⢡⢿⡆⠻⣿⣷⠀⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣍⡻⣿⣟⣻⣿⣿⣿⣿⣷⣦⣥⣬⣤⣴⣾⣿⣿⣿⣿⣷⣿⣿⣿⣿⣷⡜⠃
⠀⠀⠀⢀⣘⠈⢂⠃⣧⡹⣿⣷⡄⠙⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣮⣅⡙⢿⣟⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠋⡕⠂
⠀⠀⠀⠀⠀⠀⠛⢷⣜⢷⡌⠻⣿⣿⣦⣝⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⣹⣷⣦⣹⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠉⠃⠀
EOF
    echo -e "${NC}"
    echo -e "${GREEN}═══════════════ AUTO AUDIT AI v7.7 ═══════════════${NC}"
    echo -e "${GREEN}     Laboratorio de Seguranca Etica Completo      ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}\n"
    
    echo -e "${YELLOW}=================== INSTALACAO E CONFIGURACAO ===================${NC}"
    echo -e "${GREEN} 1${NC}. Instalar dependencias basicas"
    echo -e "${GREEN} 2${NC}. Instalar TODAS as ferramentas do laboratorio"
    echo -e "${GREEN} 3${NC}. Gerenciar chaves de API (Groq, Shodan, Censys)"
    echo -e "${GREEN} 4${NC}. Instalar distribuicoes Linux (Termux)\n"
    
    echo -e "${YELLOW}=================== AUDITORIA AUTOMATICA ===================${NC}"
    echo -e "${GREEN} 5${NC}. Auditoria Nmap + IA + Relatorio"
    echo -e "${GREEN} 6${NC}. Agendar auditoria periodica (cron)\n"
    
    echo -e "${YELLOW}=================== CONSULTAS RAPIDAS ===================${NC}"
    echo -e "${GREEN} 7${NC}. Perguntar a IA"
    echo -e "${GREEN} 8${NC}. Consultar Shodan"
    echo -e "${GREEN} 9${NC}. Consultar Censys\n"
    
    echo -e "${YELLOW}=================== CATEGORIAS DE FERRAMENTAS ===================${NC}"
    echo -e "${RED}10${NC}. ${RED}[LAB]${NC} Network Recon (11 ferramentas)"
    echo -e "${RED}11${NC}. ${RED}[LAB]${NC} Web Testing (16 ferramentas)"
    echo -e "${RED}12${NC}. ${RED}[LAB]${NC} Password/Hash (5 ferramentas)"
    echo -e "${RED}13${NC}. ${RED}[LAB]${NC} OSINT (31 ferramentas)"
    echo -e "${RED}14${NC}. ${RED}[LAB]${NC} Wireless (8 ferramentas)"
    echo -e "${RED}15${NC}. ${RED}[LAB]${NC} Privilege Escalation (8 ferramentas)"
    echo -e "${RED}16${NC}. ${RED}[LAB]${NC} Frameworks (3 ferramentas)"
    echo -e "${RED}17${NC}. ${RED}[LAB]${NC} Pos-Exploracao (13 ferramentas)\n"
    
    echo -e "${YELLOW}=================== SISTEMA ===================${NC}"
    echo -e "${GREEN}18${NC}. Ver logs de execucao"
    echo -e "${GREEN}19${NC}. Ativar/Desativar modo LAB"
    echo -e "${GREEN} 0${NC}. Sair\n"
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
}

main() {
    init_dirs
    while true; do
        show_menu
        read -p "Escolha uma opcao: " opcao
        case $opcao in
            1) install_deps;;
            2) install_lab_tools;;
            3) config_keys_menu;;
            4) distro_menu;;
            5) check_dep nmap curl jq || { msg_error "Instale dependencias (opcao 1)."; read -p "Enter..."; continue; }; read -p "Alvo: " t; [ -n "$t" ] && run_nmap_scan "$t";;
            6) setup_cron;;
            7) read -p "Pergunta: " p; [ -n "$p" ] && ia_groq "$p";;
            8) read -p "IP: " s; [ -n "$s" ] && shodan_info "$s";;
            9) read -p "IP: " c; [ -n "$c" ] && censys_info "$c";;
            10) is_lab || enable_lab || continue; network_menu;;
            11) is_lab || enable_lab || continue; web_menu;;
            12) is_lab || enable_lab || continue; crack_menu;;
            13) is_lab || enable_lab || continue; osint_menu;;
            14) is_lab || enable_lab || continue; wireless_menu;;
            15) is_lab || enable_lab || continue; priv_menu;;
            16) is_lab || enable_lab || continue; framework_menu;;
            17) is_lab || enable_lab || continue; post_menu;;
            18) [ -f "$LOG_FILE" ] && less "$LOG_FILE" || msg_warn "Sem logs.";;
            19) is_lab && disable_lab || enable_lab;;
            0) echo -e "${GREEN}Fique etico!${NC}"; exit 0;;
            *) msg_error "Invalida.";;
        esac
        echo; read -p "Pressione Enter para voltar..."
    done
}

main "$@"
