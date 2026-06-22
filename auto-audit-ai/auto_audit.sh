#!/usr/bin/env bash
# =============================================
# Auto Audit AI - Laboratorio Etico v7.4
# Uso EXCLUSIVO em sistemas proprios ou autorizados
# =============================================

set -euo pipefail

VERSION="7.4"
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

GREEN='\e[1;32m'; RED='\e[1;31m'; YELLOW='\e[1;33m'; CYAN='\e[1;36m'; NC='\e[0m'

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

# ---------- CHAVES DE API ----------
setup_groq_key() {
    read -s -p "Chave Groq: " key; echo
    save_key "$GROQ_KEY_FILE" "$key"
    msg_info "Chave Groq salva."
}

setup_shodan_key() {
    read -s -p "Chave Shodan: " key; echo
    save_key "$SHODAN_KEY_FILE" "$key"
    msg_info "Chave Shodan salva."
}

setup_censys_keys() {
    read -p "API ID: " id; read -s -p "Secret: " secret; echo
    save_key "$CENSYS_ID_FILE" "$id"
    save_key "$CENSYS_SECRET_FILE" "$secret"
    msg_info "Chaves Censys salvas."
}

config_keys_menu() {
    while true; do
        echo -e "\n${YELLOW}=== Chaves de API ===${NC}"
        echo "1.Groq 2.Shodan 3.Censys 0.Voltar"
        read -p "Escolha: " kopt
        case $kopt in
            1) setup_groq_key;; 2) setup_shodan_key;; 3) setup_censys_keys;; 0) break;;
            *) msg_error "Invalido.";;
        esac
    done
}

# ---------- IA (GROQ) ----------
ia_groq() {
    local prompt="$1"; local max_tokens="${2:-500}"
    [ ! -f "$GROQ_KEY_FILE" ] && setup_groq_key
    local api_key=$(<"$GROQ_KEY_FILE")
    [ -z "$api_key" ] && { msg_error "Chave Groq vazia."; return 1; }
    local response
    response=$(curl -s -X POST "https://api.groq.com/openai/v1/chat/completions" \
        -H "Authorization: Bearer $api_key" -H "Content-Type: application/json" \
        -d '{"model":"llama3-70b-8192","messages":[{"role":"user","content":"'"${prompt//\"/\\\"}"'"}],"temperature":0.7,"max_tokens":'"$max_tokens"'}' \
        | jq -r '.choices[0].message.content' 2>/dev/null)
    [ -z "$response" ] || [ "$response" = "null" ] && { msg_error "Falha na API Groq."; return 1; }
    echo "$response"
    log "IA consultada"
}

# ---------- SHODAN / CENSYS ----------
shodan_info() { local t="$1"; [ ! -f "$SHODAN_KEY_FILE" ] && setup_shodan_key; local k=$(<"$SHODAN_KEY_FILE"); [ -z "$k" ] && return 1; curl -s "https://api.shodan.io/shodan/host/$t?key=$k" | jq '.' || msg_error "Falha Shodan."; }
censys_info() { local t="$1"; [ ! -f "$CENSYS_ID_FILE" ] || [ ! -f "$CENSYS_SECRET_FILE" ] && setup_censys_keys; local id=$(<"$CENSYS_ID_FILE"); local s=$(<"$CENSYS_SECRET_FILE"); [ -z "$id" ] && return 1; curl -s -u "$id:$s" "https://search.censys.io/api/v2/hosts/$t" | jq '.' || msg_error "Falha Censys."; }

# ---------- INSTALACAO ----------
install_deps() {
    echo -e "${GREEN}=== Instalando dependencias ===${NC}"
    if command -v apt >/dev/null 2>&1; then sudo apt update && sudo apt install -y nmap curl jq wkhtmltopdf net-tools dnsutils tcpdump whois; elif command -v pkg >/dev/null 2>&1; then pkg update && pkg install -y nmap curl jq net-tools dnsutils tcpdump whois; fi
    msg_info "Dependencias instaladas."
}

install_lab_tools() {
    echo -e "${GREEN}=== Instalando ferramentas do Lab ===${NC}"
    if command -v apt >/dev/null 2>&1; then
        sudo apt update
        sudo apt install -y nmap masscan nikto dirb gobuster ffuf sqlmap hydra john hashcat theharvester whois dnsutils aircrack-ng reaver bettercap exploitdb metasploit-framework set impacket-scripts evil-winrm enum4linux snmp whatweb wapiti owasp-zap burpsuite crackmapexec ligolo-ng chisel hcxdumptool hcxtools netcat socat proxychains arp-scan 2>/dev/null || true
        pip install holehe sherlock metagoofil spiderfoot snscrape arjun xsstrike nosqlmap phonenumbers phoneinfoga ghunt holehe socialscan maigret 2>/dev/null || true
        [ ! -d "$APP_DIR/tools/Photon" ] && git clone https://github.com/s0md3v/Photon.git "$APP_DIR/tools/Photon" --depth 1
        [ ! -d "$APP_DIR/tools/ParamSpider" ] && git clone https://github.com/devanshbatham/ParamSpider.git "$APP_DIR/tools/ParamSpider" --depth 1
        [ ! -d "$APP_DIR/tools/XSStrike" ] && git clone https://github.com/s0md3v/XSStrike.git "$APP_DIR/tools/XSStrike" --depth 1
        [ ! -d "$APP_DIR/tools/Sherlock" ] && git clone https://github.com/sherlock-project/sherlock.git "$APP_DIR/tools/Sherlock" --depth 1
        [ ! -d "$APP_DIR/tools/Maigret" ] && git clone https://github.com/soxoj/maigret.git "$APP_DIR/tools/Maigret" --depth 1
        [ ! -d "$APP_DIR/tools/GHunt" ] && git clone https://github.com/mxrch/GHunt.git "$APP_DIR/tools/GHunt" --depth 1
    elif command -v pkg >/dev/null 2>&1; then
        pkg update && pkg install -y nmap rustscan nikto dirb gobuster ffuf sqlmap hydra john hashcat theharvester whois dnsutils aircrack-ng reaver bettercap exploitdb whatweb wapiti crackmapexec ligolo-ng chisel hcxdumptool hcxtools netcat socat proxychains arp-scan -y 2>/dev/null || true
        pip install holehe sherlock metagoofil spiderfoot snscrape arjun xsstrike nosqlmap phonenumbers phoneinfoga ghunt holehe socialscan maigret 2>/dev/null || true
    fi
    msg_info "Ferramentas instaladas."
}

# ---------- RELATORIOS ----------
generate_html_report() {
    local target="$1" ts="$2" txt="$3" ia="$4"
    cat <<HTMLEOF
<!DOCTYPE html><html lang="pt-BR"><head><meta charset="UTF-8"><title>Auto Audit - $target ($ts)</title>
<style>body{font-family:Arial;background:#111;color:#0f0;padding:2em}pre{background:#222;padding:1em;white-space:pre-wrap}
.ia{background:#1a1a1a;border-left:4px solid #0f0;padding:1em}h1{color:#0f0}.footer{margin-top:2em;font-size:.8em;color:#666}</style></head>
<body><h1>Relatorio - $target</h1><p>$ts</p><h2>Resultado Nmap</h2><pre>$(cat "$txt")</pre><h2>Analise IA</h2><div class="ia">$ia</div>
<div class="footer">Auto Audit AI - uso educacional e autorizado.</div></body></html>
HTMLEOF
}

run_nmap_scan() {
    local target="$1"; local ts=$(date +%Y%m%d_%H%M%S); local txt="$REPORT_DIR/scan_$ts.txt"; local html="$HTML_DIR/scan_$ts.html"
    msg_info "Varredura Nmap em $target..."; nmap -sS -sV -O -T4 -oN "$txt" "$target"
    local summary=$(head -c 8000 "$txt"); local ia_analysis=$(ia_groq "Analise este Nmap e de recomendacoes (alvo autorizado):\n$summary" 800 || echo "")
    generate_html_report "$target" "$ts" "$txt" "$ia_analysis" > "$html"
    msg_info "Relatorio HTML: $html"
    command -v wkhtmltopdf >/dev/null 2>&1 && wkhtmltopdf "$html" "$PDF_DIR/scan_$ts.pdf" 2>/dev/null && msg_info "PDF gerado."
}

setup_cron() { local sp=$(realpath "$0"); read -p "Alvo: " ct; [ -z "$ct" ] && return; read -p "Cron (ex: 0 2 * * 0): " ctime; (crontab -l 2>/dev/null; echo "$ctime $sp --cron-scan $ct") | crontab -; msg_info "Agendado."; }
if [ "${1:-}" = "--cron-scan" ]; then shift; init_dirs; check_dep nmap curl jq || exit 1; run_nmap_scan "$1"; exit 0; fi

# ========== LAB ==========
enable_lab_mode() {
    [ -f "$LAB_FLAG" ] && { msg_warn "Modo LAB ja ativo."; return 0; }
    echo -e "\n${RED}======== ATIVACAO DO MODO LAB ========${NC}"; echo -e "${RED}ACESSO A FERRAMENTAS DE PENTEST${NC}"; echo -e "${RED}USE APENAS EM SISTEMAS PROPRIOS OU AUTORIZADOS${NC}"
    read -s -p "Senha: " ipass; echo; [ "$ipass" != "$LAB_PASS" ] && { msg_error "Senha incorreta."; return 1; }
    touch "$LAB_FLAG"; msg_info "Modo LAB ATIVADO."
}
disable_lab_mode() { rm -f "$LAB_FLAG"; msg_info "Modo LAB desativado."; }
is_lab_enabled() { [ -f "$LAB_FLAG" ]; }

# ================== SUBMENUS ==================
network_submenu() { while true; do echo -e "\n${YELLOW}--- Network Recon ---${NC}"; echo "1.nmap -sS -sV -O 2.netstat -tulnp 3.ss -tulnp 4.arp-scan -l 5.traceroute 6.whois 7.dig ANY 8.nslookup 9.tcpdump 10.Masscan 11.RustScan 0.Voltar"; read -p "Opcao: " nopt; case $nopt in 1) t=$(request_target) && confirm_run && nmap -sS -sV -O -T4 -oN "$REPORT_DIR/nmap_$(date +%Y%m%d%H%M%S).txt" "$t" || continue;; 2) confirm_run && netstat -tulnp || continue;; 3) confirm_run && ss -tulnp || continue;; 4) confirm_run && arp-scan -l || continue;; 5) read -p "Alvo: " t && confirm_run && traceroute "$t" || continue;; 6) t=$(request_target) && whois "$t" | tee "$REPORT_DIR/whois_$(date +%Y%m%d%H%M%S).txt" || continue;; 7) t=$(request_target) && dig "$t" ANY | tee "$REPORT_DIR/dig_$(date +%Y%m%d%H%M%S).txt" || continue;; 8) read -p "Alvo: " t && nslookup "$t" || continue;; 9) confirm_run && read -p "Interface: " i && tcpdump -i "$i" -n -c 100 || continue;; 10) t=$(request_target) && confirm_run && masscan -p1-65535 --rate=1000 -oL "$REPORT_DIR/masscan_$(date +%Y%m%d%H%M%S).txt" "$t" || continue;; 11) t=$(request_target) && confirm_run && rustscan -a "$t" --ulimit 5000 -- -sV -oN "$REPORT_DIR/rustscan_$(date +%Y%m%d%H%M%S).txt" || continue;; 0) break;; *) msg_error "Invalido.";; esac; done; }

web_submenu() { while true; do echo -e "\n${YELLOW}--- Web Testing ---${NC}"; echo "1.curl -I 2.wget -r 3.ffuf 4.gobuster dir 5.nikto -h 6.sqlmap 7.WhatWeb 8.Wapiti 9.WPScan 10.Dirb 11.Arjun 12.ParamSpider 13.XSStrike 14.NoSQLMap 15.ZAP 16.Burp 17.IA 0.Voltar"; read -p "Opcao: " wopt; case $wopt in 1) read -p "URL: " u && confirm_run && curl -I "$u" || continue;; 2) read -p "URL: " u && confirm_run && wget -r -np "$u" || continue;; 3) read -p "URL: " u && read -p "Wordlist: " w && confirm_run && ffuf -u "$u/FUZZ" -w "$w" -of html -o "$REPORT_DIR/ffuf_$(date +%Y%m%d%H%M%S).html" || continue;; 4) read -p "URL: " u && confirm_run && gobuster dir -u "$u" -w /usr/share/wordlists/dirb/common.txt -o "$REPORT_DIR/gobuster_$(date +%Y%m%d%H%M%S).txt" || continue;; 5) t=$(request_target) && confirm_run && nikto -h "$t" | tee "$REPORT_DIR/nikto_$(date +%Y%m%d%H%M%S).txt" || continue;; 6) read -p "URL: " u && confirm_run && sqlmap -u "$u" --batch --wizard 2>&1 | tee "$REPORT_DIR/sqlmap_$(date +%Y%m%d%H%M%S).txt" || continue;; 7) t=$(request_target) && confirm_run && whatweb "$t" | tee "$REPORT_DIR/whatweb_$(date +%Y%m%d%H%M%S).txt" || continue;; 8) read -p "URL: " u && confirm_run && wapiti -u "$u" -o "$REPORT_DIR/wapiti_$(date +%Y%m%d%H%M%S)" || continue;; 9) read -p "URL WordPress: " u && confirm_run && wpscan --url "$u" --enumerate p,t,u | tee "$REPORT_DIR/wpscan_$(date +%Y%m%d%H%M%S).txt" || continue;; 10) read -p "URL: " u && confirm_run && dirb "$u" /usr/share/wordlists/dirb/common.txt -o "$REPORT_DIR/dirb_$(date +%Y%m%d%H%M%S).txt" || continue;; 11) read -p "URL: " u && confirm_run && (arjun -u "$u" -o "$REPORT_DIR/arjun_$(date +%Y%m%d%H%M%S).json" 2>/dev/null || msg_error "Arjun nao instalado.") || continue;; 12) t=$(request_target) && confirm_run && (paramspider -d "$t" -o "$REPORT_DIR/paramspider_$(date +%Y%m%d%H%M%S)" 2>/dev/null || msg_error "ParamSpider nao instalado.") || continue;; 13) read -p "URL: " u && confirm_run && (xsstrike -u "$u" | tee "$REPORT_DIR/xsstrike_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "XSStrike nao instalado.") || continue;; 14) read -p "URL: " u && confirm_run && (nosqlmap -u "$u" | tee "$REPORT_DIR/nosqlmap_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "NoSQLMap nao instalado.") || continue;; 15) confirm_run && (zap.sh & disown 2>/dev/null || msg_error "ZAP nao encontrado.") || continue;; 16) confirm_run && (burpsuite & disown 2>/dev/null || msg_error "Burp nao instalado.") || continue;; 17) read -p "Arquivo: " f; [ -f "$f" ] && ia_groq "Analise:\n$(head -c 6000 "$f")" || continue;; 0) break;; *) msg_error "Invalido.";; esac; done; }

crack_submenu() { while true; do echo -e "\n${YELLOW}--- Password & Hash ---${NC}"; echo "1.john 2.hashcat 3.hydra 4.cewl 5.crunch 0.Voltar"; read -p "Opcao: " copt; case $copt in 1) confirm_run && read -p "Hash: " h && [ -f "$h" ] && john --wordlist=/usr/share/wordlists/rockyou.txt "$h" | tee "$REPORT_DIR/john_$(date +%Y%m%d%H%M%S).txt" || continue;; 2) confirm_run && read -p "Hash: " h && [ -f "$h" ] && hashcat -m 0 -a 0 "$h" /usr/share/wordlists/rockyou.txt | tee "$REPORT_DIR/hashcat_$(date +%Y%m%d%H%M%S).txt" || continue;; 3) t=$(request_target) && confirm_run && read -p "Usuario: " u && read -p "Wordlist: " w && hydra -l "$u" -P "$w" ssh://"$t" -o "$REPORT_DIR/hydra_$(date +%Y%m%d%H%M%S).txt" || continue;; 4) read -p "URL: " u && confirm_run && cewl "$u" -w "$REPORT_DIR/cewl_$(date +%Y%m%d%H%M%S).txt" || continue;; 5) confirm_run && read -p "Min: " min && read -p "Max: " max && read -p "Chars: " ch && crunch "$min" "$max" "$ch" -o "$REPORT_DIR/crunch_$(date +%Y%m%d%H%M%S).txt" || continue;; 0) break;; *) msg_error "Invalido.";; esac; done; }

# ================== OSINT COMPLETO ==================
osint_submenu() {
    while true; do
        echo -e "\n${YELLOW}==================== OSINT - INTELIGENCIA DE FONTES ABERTAS ====================${NC}"
        echo -e "${CYAN}--- Coleta de Dominios e Subdominios ---${NC}"
        echo "1.theHarvester (emails, subdominios, hosts)"
        echo "2.Subfinder (enumera subdominios)"
        echo "3.Amass (mapeamento de superficie de ataque)"
        echo "4.Assetfinder (subdominios rapidos)"
        echo "5.dnsrecon (enum DNS completa)"
        echo "6.dnsenum (enum DNS avancada)"
        echo ""
        echo -e "${CYAN}--- Busca de Usuarios e Redes Sociais ---${NC}"
        echo "7.Sherlock (busca usuario em 300+ redes sociais)"
        echo "8.Maigret (busca usuario com relatorio detalhado)"
        echo "9.SocialScan (verifica email em redes sociais)"
        echo "10.GHunt (investigacao de contas Google)"
        echo "11.Holehe (verifica email em servicos)"
        echo ""
        echo -e "${CYAN}--- Informacoes de Dominio e Empresa ---${NC}"
        echo "12.whois (registro de dominio)"
        echo "13.dig (consultas DNS avancadas)"
        echo "14.nslookup (DNS simples)"
        echo "15.Photon (crawler de informacoes do site)"
        echo "16.EmailHarvester (extracao de emails)"
        echo ""
        echo -e "${CYAN}--- Vazamentos e Dados Expostos ---${NC}"
        echo "17.h8mail (busca em vazamentos de dados)"
        echo "18.LeakLooker (busca em leaks publicos)"
        echo "19.pwned (verifica email em Have I Been Pwned)"
        echo ""
        echo -e "${CYAN}--- Metadados e Documentos ---${NC}"
        echo "20.Metagoofil (extrai metadados de documentos)"
        echo "21.Exiftool (leitura de metadados)"
        echo ""
        echo -e "${CYAN}--- Infraestrutura e Certificados ---${NC}"
        echo "22.crt.sh (busca certificados SSL)"
        echo "23.Certspotter (monitora certificados)"
        echo "24.Shodan (dispositivos expostos)"
        echo "25.Censys (ativos na internet)"
        echo ""
        echo -e "${CYAN}--- Telefone e Geolocalizacao ---${NC}"
        echo "26.PhoneInfoga (informacoes de telefone)"
        echo "27.Snscrape (scraping de redes sociais)"
        echo ""
        echo -e "${CYAN}--- Frameworks Completos ---${NC}"
        echo "28.Recon-ng (framework modular)"
        echo "29.SpiderFoot (automacao OSINT)"
        echo ""
        echo -e "${CYAN}--- Utilitarios ---${NC}"
        echo "30.Baixar wordlists (rockyou, SecLists)"
        echo "31.Gerar relatorio OSINT consolidado"
        echo "0.Voltar"
        read -p "Opcao: " oopt
        case $oopt in
            1) t=$(request_target) && confirm_run && theHarvester -d "$t" -b all -f "$REPORT_DIR/harvester_$(date +%Y%m%d%H%M%S).html" || continue;;
            2) t=$(request_target) && confirm_run && (subfinder -d "$t" -o "$REPORT_DIR/subfinder_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Subfinder nao instalado.") || continue;;
            3) t=$(request_target) && confirm_run && (amass enum -passive -d "$t" -o "$REPORT_DIR/amass_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Amass nao instalado.") || continue;;
            4) t=$(request_target) && confirm_run && (assetfinder --subs-only "$t" | tee "$REPORT_DIR/assetfinder_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Assetfinder nao instalado.") || continue;;
            5) t=$(request_target) && confirm_run && (dnsrecon -d "$t" -t std | tee "$REPORT_DIR/dnsrecon_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "dnsrecon nao instalado.") || continue;;
            6) t=$(request_target) && confirm_run && (dnsenum "$t" | tee "$REPORT_DIR/dnsenum_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "dnsenum nao instalado.") || continue;;
            7) confirm_run && read -p "Usuario: " u && (python3 "$APP_DIR/tools/Sherlock/sherlock" "$u" --output "$REPORT_DIR/sherlock_$(date +%Y%m%d%H%M%S)" 2>/dev/null || msg_error "Sherlock nao instalado.") || continue;;
            8) confirm_run && read -p "Usuario: " u && (maigret "$u" --pdf -o "$REPORT_DIR/maigret_$(date +%Y%m%d%H%M%S)" 2>/dev/null || msg_error "Maigret nao instalado.") || continue;;
            9) confirm_run && read -p "Email: " e && (socialscan "$e" | tee "$REPORT_DIR/socialscan_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "SocialScan nao instalado.") || continue;;
            10) confirm_run && read -p "Email Gmail: " e && (python3 "$APP_DIR/tools/GHunt/ghunt.py" email "$e" 2>/dev/null || msg_error "GHunt nao instalado.") || continue;;
            11) confirm_run && read -p "Email: " e && (holehe "$e" --only-used | tee "$REPORT_DIR/holehe_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Holehe nao instalado.") || continue;;
            12) t=$(request_target) && whois "$t" | tee "$REPORT_DIR/whois_$(date +%Y%m%d%H%M%S).txt" || continue;;
            13) t=$(request_target) && read -p "Tipo: " tp && dig "$t" "$tp" | tee "$REPORT_DIR/dig_$(date +%Y%m%d%H%M%S).txt" || continue;;
            14) read -p "Alvo: " t && nslookup "$t" || continue;;
            15) t=$(request_target) && confirm_run && (python3 "$APP_DIR/tools/Photon/photon.py" -u "$t" -o "$REPORT_DIR/photon_$(date +%Y%m%d%H%M%S)" -l 2 2>/dev/null || msg_error "Photon nao encontrado.") || continue;;
            16) t=$(request_target) && confirm_run && (emailharvester -d "$t" -e google,bing -o "$REPORT_DIR/emailharvester_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "EmailHarvester nao instalado.") || continue;;
            17) confirm_run && read -p "Email: " e && (h8mail -t "$e" -o "$REPORT_DIR/h8mail_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "h8mail nao instalado.") || continue;;
            18) confirm_run && read -p "Termo: " q && (leaklooker "$q" 2>/dev/null || msg_error "LeakLooker nao instalado.") || continue;;
            19) confirm_run && read -p "Email: " e && (curl -s "https://haveibeenpwned.com/api/v3/breachedaccount/$e" | jq '.' | tee "$REPORT_DIR/pwned_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Erro na consulta.") || continue;;
            20) t=$(request_target) && confirm_run && (metagoofil -d "$t" -t pdf,doc,xls -l 50 -n 5 -o "$REPORT_DIR/metagoofil_$(date +%Y%m%d%H%M%S)" 2>/dev/null || msg_error "Metagoofil nao instalado.") || continue;;
            21) confirm_run && read -p "Arquivo: " f && [ -f "$f" ] && exiftool "$f" | tee "$REPORT_DIR/exiftool_$(date +%Y%m%d%H%M%S).txt" || msg_error "Arquivo nao existe." || continue;;
            22) t=$(request_target) && curl -s "https://crt.sh/?q=%25.$t&output=json" | jq -r '.[].name_value' | sort -u | tee "$REPORT_DIR/crtsh_$(date +%Y%m%d%H%M%S).txt" || continue;;
            23) t=$(request_target) && (curl -s "https://api.certspotter.com/v1/issuances?domain=$t&expand=dns_names" | jq '.' | tee "$REPORT_DIR/certspotter_$(date +%Y%m%d%H%M%S).json" 2>/dev/null || msg_error "Erro Certspotter.") || continue;;
            24) read -p "IP para Shodan: " sip && shodan_info "$sip" || continue;;
            25) read -p "IP para Censys: " cip && censys_info "$cip" || continue;;
            26) confirm_run && read -p "Telefone: " p && (phoneinfoga scan -n "$p" | tee "$REPORT_DIR/phoneinfoga_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "PhoneInfoga nao instalado.") || continue;;
            27) confirm_run && read -p "Busca: " q && (snscrape twitter-search "$q" | tee "$REPORT_DIR/snscrape_$(date +%Y%m%d%H%M%S).json" 2>/dev/null || msg_error "Snscrape nao instalado.") || continue;;
            28) confirm_run && (recon-ng 2>/dev/null || msg_error "Recon-ng nao instalado.") || continue;;
            29) t=$(request_target) && confirm_run && (spiderfoot -s "$t" -o "$REPORT_DIR/spiderfoot_$(date +%Y%m%d%H%M%S).json" 2>/dev/null || msg_error "SpiderFoot nao instalado.") || continue;;
            30) mkdir -p "$APP_DIR/wordlists"; [ ! -f "$APP_DIR/wordlists/rockyou.txt" ] && wget -q https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt -O "$APP_DIR/wordlists/rockyou.txt"; [ ! -d "$APP_DIR/wordlists/SecLists" ] && git clone https://github.com/danielmiessler/SecLists.git "$APP_DIR/wordlists/SecLists" --depth 1; msg_info "Wordlists em $APP_DIR/wordlists" || continue;;
            31) echo -e "${CYAN}Gerando relatorio consolidado...${NC}"; ls -la "$REPORT_DIR" | grep -E "whois|dig|dns|harvester|subfinder|amass|assetfinder|sherlock|holehe" | awk '{print $NF}' > "$REPORT_DIR/osint_report_$(date +%Y%m%d%H%M%S).txt"; msg_info "Relatorio OSINT gerado em $REPORT_DIR" || continue;;
            0) break;;
            *) msg_error "Invalido.";;
        esac
    done
}

wireless_submenu() { while true; do echo -e "\n${RED}--- Wireless ---${NC}"; echo "1.airmon-ng 2.airodump-ng 3.aireplay-ng 4.aircrack-ng 5.reaver 6.bettercap 7.hcxdumptool 8.btlejuice 0.Voltar"; read -p "Opcao: " wiopt; case $wiopt in 1) confirm_run && read -p "Interface: " i && airmon-ng start "$i" || continue;; 2) confirm_run && read -p "Interface: " i && airodump-ng "$i" -w "$REPORT_DIR/airodump_$(date +%Y%m%d%H%M%S)" || continue;; 3) confirm_run && read -p "Interface: " i && read -p "BSSID: " b && aireplay-ng --deauth 10 -a "$b" "$i" || continue;; 4) confirm_run && read -p "Wordlist: " w && read -p "Captura: " c && aircrack-ng -w "$w" "$c" || continue;; 5) confirm_run && read -p "Interface: " i && read -p "BSSID: " b && read -p "Canal: " c && reaver -i "$i" -b "$b" -c "$c" -vv | tee "$REPORT_DIR/reaver_$(date +%Y%m%d%H%M%S).txt" || continue;; 6) confirm_run && bettercap -eval "net.probe on; net.recon on; net.show" || continue;; 7) confirm_run && read -p "Interface: " i && hcxdumptool -i "$i" -o "$REPORT_DIR/hcxdump_$(date +%Y%m%d%H%M%S).pcapng" 2>/dev/null || msg_error "hcxdumptool nao instalado." || continue;; 8) confirm_run && (btlejuice 2>/dev/null || msg_error "btlejuice nao instalado.") || continue;; 0) break;; *) msg_error "Invalido.";; esac; done; }

priv_esc_submenu() { while true; do echo -e "\n${RED}--- Privilege Escalation ---${NC}"; echo "1.linpeas 2.winpeas(info) 3.sudo -l 4.uname -a 5.id 6.ps aux 7.find 8.grep 0.Voltar"; read -p "Opcao: " popt; case $popt in 1) confirm_run && (./linpeas.sh 2>/dev/null || msg_error "linpeas.sh nao encontrado.") || continue;; 2) echo "Execute winpeas.exe no Windows alvo." || continue;; 3) confirm_run && sudo -l || continue;; 4) confirm_run && uname -a || continue;; 5) confirm_run && id || continue;; 6) confirm_run && ps aux || continue;; 7) confirm_run && read -p "Caminho: " d && read -p "Perm: " p && find "$d" "$p" 2>/dev/null || continue;; 8) confirm_run && read -p "Arquivo: " f && read -p "String: " s && grep -r "$s" "$f" 2>/dev/null || continue;; 0) break;; *) msg_error "Invalido.";; esac; done; }

framework_submenu() { while true; do echo -e "\n${YELLOW}--- Frameworks ---${NC}"; echo "1.Metasploit 2.Searchsploit 3.SET 0.Voltar"; read -p "Opcao: " fopt; case $fopt in 1) confirm_run && (msfconsole 2>/dev/null || msg_error "Metasploit nao instalado.") || continue;; 2) confirm_run && read -p "Busca: " t && searchsploit "$t" | tee "$REPORT_DIR/searchsploit_$(date +%Y%m%d%H%M%S).txt" || continue;; 3) echo -e "${RED}SET - APENAS LAB ISOLADO!${NC}"; confirm_run && (setoolkit 2>/dev/null || msg_error "SET nao instalado.") || continue;; 0) break;; *) msg_error "Invalido.";; esac; done; }

post_exploit_submenu() { while true; do echo -e "\n${RED}--- Pos-Exploracao ---${NC}"; echo "1.nc -lvnp 2.socat 3.Impacket 4.Evil-WinRM 5.enum4linux 6.snmpwalk 7.CrackMapExec 8.Ligolo-ng 9.Chisel 10.proxychains 11.Mimikatz 12.Rubeus 13.BloodHound 0.Voltar"; read -p "Opcao: " xopt; case $xopt in 1) confirm_run && read -p "Porta: " p && nc -lvnp "$p" || continue;; 2) confirm_run && read -p "Comando: " c && eval "$c" || continue;; 3) confirm_run && read -p "Comando: " c && eval "$c" 2>&1 | tee "$REPORT_DIR/impacket_$(date +%Y%m%d%H%M%S).txt" || continue;; 4) confirm_run && read -p "Alvo: " t && read -p "Usuario: " u && read -s -p "Senha: " p && echo && evil-winrm -i "$t" -u "$u" -p "$p" 2>&1 | tee "$REPORT_DIR/evilwinrm_$(date +%Y%m%d%H%M%S).txt" || continue;; 5) t=$(request_target) && confirm_run && enum4linux "$t" | tee "$REPORT_DIR/enum4linux_$(date +%Y%m%d%H%M%S).txt" || continue;; 6) t=$(request_target) && confirm_run && snmpwalk -v2c -c public "$t" | tee "$REPORT_DIR/snmpwalk_$(date +%Y%m%d%H%M%S).txt" || continue;; 7) confirm_run && read -p "Alvo: " t && read -p "Usuario: " u && read -s -p "Senha: " p && echo && read -p "Extra: " e && crackmapexec smb "$t" -u "$u" -p "$p" $e | tee "$REPORT_DIR/cme_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "CME nao instalado." || continue;; 8) echo "Ligolo: 1.Proxy 2.Cliente"; read -p "Opcao: " l; case $l in 1) read -p "Interface: " i && ligolo-proxy -bind 0.0.0.0:10001 -iface "$i" | tee "$REPORT_DIR/ligolo_proxy_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Ligolo nao instalado.";; 2) read -p "IP:porta: " a && ligolo-client -connect "$a" | tee "$REPORT_DIR/ligolo_client_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Ligolo nao instalado.";; esac || continue;; 9) echo "Chisel: 1.Server 2.Client"; read -p "Opcao: " c; case $c in 1) read -p "Porta: " p && chisel server -p "$p" --reverse | tee "$REPORT_DIR/chisel_server_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Chisel nao instalado.";; 2) read -p "IP:porta: " a && read -p "Porta local: " l && chisel client "$a" R:"$l":127.0.0.1:"$l" | tee "$REPORT_DIR/chisel_client_$(date +%Y%m%d%H%M%S).txt" 2>/dev/null || msg_error "Chisel nao instalado.";; esac || continue;; 10) confirm_run && read -p "Comando: " c && proxychains "$c" || continue;; 11) echo "Mimikatz: sekurlsa::logonpasswords" || continue;; 12) echo "Rubeus: kerberoast, asreproast" || continue;; 13) echo "BloodHound: SharpHound.exe no alvo" || continue;; 0) break;; *) msg_error "Invalido.";; esac; done; }

networking_submenu() { while true; do echo -e "\n${CYAN}--- Useful Networking ---${NC}"; echo "1.nc -lvnp 2.socat 3.ping 4.iptables 5.proxychains 0.Voltar"; read -p "Opcao: " uopt; case $uopt in 1) confirm_run && read -p "Porta: " p && nc -lvnp "$p" || continue;; 2) confirm_run && read -p "Comando: " c && eval "$c" || continue;; 3) read -p "Alvo: " t && ping -c 4 "$t" || continue;; 4) confirm_run && iptables -L || continue;; 5) confirm_run && read -p "Comando: " c && proxychains "$c" || continue;; 0) break;; *) msg_error "Invalido.";; esac; done; }

distro_menu() {
    [ ! -d /data/data/com.termux/files/usr ] && { msg_error "Exclusivo para Termux."; return 1; }
    command -v proot-distro >/dev/null 2>&1 || { pkg install -y proot-distro; msg_info "proot-distro instalado."; }
    while true; do echo -e "\n${CYAN}=== Distros Linux Termux ===${NC}"; echo "1.Ubuntu 2.Kali 3.Debian 4.Arch 5.Fedora 6.Alpine 7.Manjaro 8.Void 0.Voltar"; read -p "Escolha: " dopt; case $dopt in 1) d="ubuntu";; 2) d="kali";; 3) d="debian";; 4) d="archlinux";; 5) d="fedora";; 6) d="alpine";; 7) d="manjaro";; 8) d="void";; 0) break;; *) msg_error "Invalido."; continue;; esac; proot-distro install "$d"; msg_info "$d instalado!"; echo -e "\n${CYAN}--- Como usar ---${NC}"; echo "Login: ${GREEN}proot-distro login $d${NC}"; echo -e "\n${CYAN}--- VNC ---${NC}"; echo "apt install xfce4 xfce4-goodies tigervnc-standalone-server -y"; echo "vncserver :1 -geometry 1280x720 -depth 24"; echo "Conecte em: ${GREEN}localhost:1${NC}"; echo -e "\n${CYAN}--- Termux X11 ---${NC}"; echo "pkg install x11-repo && pkg install termux-x11-nightly"; echo "termux-x11 :0 -ac &"; echo "export DISPLAY=:0 && startxfce4 &"; read -p "Enter para continuar..."; done; }

# ---------- MENUS PRINCIPAIS ----------
lab_menu() {
    while true; do
        clear
        echo -e "${RED}╔════════ MODO LABORATORIO v7.4 ════════╗${NC}"
        echo "1.Network Recon  2.Web Testing  3.Password/Hash"
        echo "4.OSINT (31 ferramentas)  5.Wireless  6.Privilege Escalation"
        echo "7.Frameworks  8.Pos-Exploracao  9.Networking"
        echo "10.Shell interativo  0.Voltar"
        read -p "Escolha: " opt
        case $opt in
            1) network_submenu;; 2) web_submenu;; 3) crack_submenu;;
            4) osint_submenu;; 5) wireless_submenu;; 6) priv_esc_submenu;;
            7) framework_submenu;; 8) post_exploit_submenu;; 9) networking_submenu;;
            10) bash;; 0) break;;
            *) msg_error "Invalido.";;
        esac
        read -p "Enter para continuar..."
    done
}

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
    echo -e "${GREEN}AUTO AUDIT AI v7.4${NC}"
    echo -e "${GREEN}Laboratorio de Seguranca Etica${NC}\n"
    echo "1.Instalar deps  2.Auditoria Nmap+IA  3.Consultar IA  4.Ver logs"
    echo "5.Chaves API  6.Shodan  7.Censys  8.Agendar Cron"
    echo "9.Instalar ferramentas Lab  10.Ativar/Desativar LAB"
    is_lab_enabled && echo "11.ENTRAR NO LAB" || true
    echo "12.Distribuicoes Linux (Termux)  0.Sair"
    echo
}

main() {
    init_dirs
    while true; do
        show_menu
        read -p "Escolha: " opcao
        case $opcao in
            1) install_deps;;
            2) check_dep nmap curl jq || { msg_error "Instale dependencias primeiro."; read -p "Enter..."; continue; }; read -p "Alvo autorizado: " target; [ -n "$target" ] && run_nmap_scan "$target";;
            3) read -p "Pergunta: " p; [ -n "$p" ] && ia_groq "$p";;
            4) [ -f "$LOG_FILE" ] && less "$LOG_FILE" || msg_warn "Sem logs.";;
            5) config_keys_menu;;
            6) read -p "IP para Shodan: " s; [ -n "$s" ] && shodan_info "$s";;
            7) read -p "IP para Censys: " c; [ -n "$c" ] && censys_info "$c";;
            8) setup_cron;;
            9) install_lab_tools;;
            10) is_lab_enabled && disable_lab_mode || enable_lab_mode;;
            11) is_lab_enabled && lab_menu || msg_warn "Ative o modo LAB primeiro (opcao 10).";;
            12) distro_menu;;
            0) echo -e "${GREEN}Fique etico!${NC}"; exit 0;;
            *) msg_error "Opcao invalida.";;
        esac
        echo; read -p "Pressione Enter para voltar..."
    done
}

main "$@"
