#!/usr/bin/env bash
# ==============================================================================
# Nazwa skryptu : 01_system_health_reporter.sh
# Opis          : Narzędzie do sprawdzania stanu serwera i telemetrii.
#                 Bada zużycie procesora, pamięci RAM, dysków, stan usług systemd,
#                 otwarte porty sieciowe i nieudane logowania.
# Autor         : Dariusz Kisiel (xBestia2004)
# Licencja      : MIT
# ==============================================================================

# Bezpieczne ustawienia Basha:
# -e: przerwij jeśli wystąpi błąd
# -u: traktuj niezdefiniowane zmienne jako błąd
# -o pipefail: wyłapuj błędy w potokach (np. komenda1 | komenda2)
set -euo pipefail

# ------------------------------------------------------------------------------
# Ustawienia domyślne
# ------------------------------------------------------------------------------
WERSJA="1.2.0"
PROG_OSTRZEZENIE=80  # Próg ostrzeżenia dla RAM i dysku (w procentach)
PROG_KRYTYCZNY=90    # Próg krytyczny dla RAM i dysku (w procentach)
TRYB_WYJSCIA="tekst" # Możliwe tryby: tekst, json, html
PLIK_HTML=""
BEZ_KOLOROW=false
TRYB_CICHY=false
SPRAWDZANE_USLUGI=("ssh" "sshd" "docker" "cron" "ufw" "nginx")

# Kolory w terminalu (włączane tylko jeśli terminal je obsługuje)
if [[ -t 1 ]] && [[ "$BEZ_KOLOROW" == false ]]; then
    K_RESET="\033[0m"
    K_POGRUBIENIE="\033[1m"
    K_SZARY="\033[2m"
    K_CZERWONY="\033[1;31m"
    K_ZOLTY="\033[1;33m"
    K_ZIELONY="\033[1;32m"
    K_CYJAN="\033[1;36m"
else
    K_RESET=""
    K_POGRUBIENIE=""
    K_SZARY=""
    K_CZERWONY=""
    K_ZOLTY=""
    K_ZIELONY=""
    K_CYJAN=""
fi

# Zmienne śledzące czy wykryto jakiekolwiek problemy
CZY_OSTRZEZENIE=false
CZY_KRYTYCZNY=false

# ------------------------------------------------------------------------------
# Funkcje pomocnicze
# ------------------------------------------------------------------------------

# Wyświetlanie pomocy
wyswietl_pomoc() {
    cat << EOF
${K_POGRUBIENIE}Użycie:${K_RESET} $(basename "$0") [OPCJE]

${K_POGRUBIENIE}Audytor stanu i bezpieczeństwa systemu Linux${K_RESET}

${K_POGRUBIENIE}OPCJE:${K_RESET}
    -w, --warn <procent>    Próg ostrzeżenia dla RAM i dysku (domyślnie: ${PROG_OSTRZEZENIE}%)
    -c, --crit <procent>    Próg krytyczny dla RAM i dysku (domyślnie: ${PROG_KRYTYCZNY}%)
    -j, --json              Eksport wyników do formatu JSON (dla maszyn i API)
    -H, --html <plik>       Zapis raportu do wskazanego pliku HTML
    -s, --services <lista>  Lista usług po przecinku (np. "ssh,docker,nginx")
    -n, --no-color          Wyłącz kolory w terminalu
    -q, --quiet             Tryb cichy (wypisuje tylko w razie przekroczenia progów)
    -v, --version           Wyświetl wersję skryptu
    -h, --help              Pokaż to menu pomocy

${K_POGRUBIENIE}KODY POWROTU:${K_RESET}
    0 = Wszystkie parametry w normie
    1 = Przekroczono próg ostrzeżenia lub wykryto błąd

${K_POGRUBIENIE}PRZYKŁADY:${K_RESET}
    $(basename "$0")
    $(basename "$0") --warn 75 --crit 85
    $(basename "$0") --json
    $(basename "$0") --html /var/www/html/raport.html
EOF
    exit 0
}

# Proste logowanie komunikatów
log_info() { [[ "$TRYB_CICHY" == false ]] && echo -e "${K_CYJAN}[INFORMACJA]${K_RESET} $*"; }
log_ok()   { [[ "$TRYB_CICHY" == false ]] && echo -e "${K_ZIELONY}[   OK    ]${K_RESET} $*"; }
log_ostrz(){ echo -e "${K_ZOLTY}[OSTRZEŻENIE]${K_RESET} $*" >&2; CZY_OSTRZEZENIE=true; }
log_kryt() { echo -e "${K_CZERWONY}[KRYTYCZNY]${K_RESET} $*" >&2; CZY_KRYTYCZNY=true; }

# ------------------------------------------------------------------------------
# Przetwarzanie argumentów podanych przez użytkownika
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--warn)
            PROG_OSTRZEZENIE="$2"
            shift 2
            ;;
        -c|--crit)
            PROG_KRYTYCZNY="$2"
            shift 2
            ;;
        -j|--json)
            TRYB_WYJSCIA="json"
            shift
            ;;
        -H|--html)
            TRYB_WYJSCIA="html"
            PLIK_HTML="$2"
            shift 2
            ;;
        -s|--services)
            IFS=',' read -r -a SPRAWDZANE_USLUGI <<< "$2"
            shift 2
            ;;
        -n|--no-color)
            BEZ_KOLOROW=true
            K_RESET=""; K_POGRUBIENIE=""; K_SZARY=""; K_CZERWONY=""; K_ZOLTY=""; K_ZIELONY=""; K_CYJAN=""
            shift
            ;;
        -q|--quiet)
            TRYB_CICHY=true
            shift
            ;;
        -v|--version)
            echo "system_health_reporter wersja $WERSJA"
            exit 0
            ;;
        -h|--help)
            wyswietl_pomoc
            ;;
        *)
            echo "Nieznana opcja: $1" >&2
            wyswietl_pomoc
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Zbieranie danych o systemie
# ------------------------------------------------------------------------------

# 1. Podstawowe informacje: data, nazwa hosta, wersja systemu i jądra
CZAS_RAPORTU=$(date '+%Y-%m-%d %H:%M:%S')
NAZWA_HOSTA=$(hostname -f 2>/dev/null || hostname)
SYSTEM_NAZWA="Linux"
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    SYSTEM_NAZWA=$(source /etc/os-release && echo "${PRETTY_NAME:-$NAME}")
fi
WERSJA_JADRA=$(uname -r)
CZAS_DZIALANIA=$(uptime -p 2>/dev/null || uptime | awk -F'( |,|:)+' '{print $6,"godz,", $7,"min"}')

# 2. Obciążenie procesora (liczba rdzeni i średnie obciążenie)
LICZBA_RDZENI=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo || echo 1)
OBCIAZENIE_SREDNIE=$(awk '{print $1, $2, $3}' /proc/loadavg)
OBCIAZENIE_1M=$(awk '{print $1}' /proc/loadavg)

# 3. Pamięć RAM (odczyt bezpośrednio z jądra z /proc/meminfo)
RAM_TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
RAM_AVAIL_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
if [[ -z "$RAM_AVAIL_KB" ]]; then
    # Zapasowa metoda dla starszych wersji kernela
    RAM_FREE_KB=$(awk '/MemFree/ {print $2}' /proc/meminfo)
    RAM_BUFF_KB=$(awk '/Buffers/ {print $2}' /proc/meminfo)
    RAM_CACHED_KB=$(awk '/Cached/ {print $2}' /proc/meminfo)
    RAM_AVAIL_KB=$(( RAM_FREE_KB + RAM_BUFF_KB + RAM_CACHED_KB ))
fi
RAM_USED_KB=$(( RAM_TOTAL_KB - RAM_AVAIL_KB ))
RAM_PROCENT=$(( (RAM_USED_KB * 100) / RAM_TOTAL_KB ))
RAM_TOTAL_MB=$(( RAM_TOTAL_KB / 1024 ))
RAM_USED_MB=$(( RAM_USED_KB / 1024 ))
RAM_AVAIL_MB=$(( RAM_AVAIL_KB / 1024 ))

# Pamięć wymiany (SWAP)
SWAP_TOTAL_KB=$(awk '/SwapTotal/ {print $2}' /proc/meminfo || echo 0)
SWAP_FREE_KB=$(awk '/SwapFree/ {print $2}' /proc/meminfo || echo 0)
SWAP_USED_KB=$(( SWAP_TOTAL_KB - SWAP_FREE_KB ))
SWAP_PROCENT=0
if [[ "$SWAP_TOTAL_KB" -gt 0 ]]; then
    SWAP_PROCENT=$(( (SWAP_USED_KB * 100) / SWAP_TOTAL_KB ))
fi

# 4. Dysk główny (partycja /)
DYSK_CALKOWITY=$(df -h / | awk 'NR==2 {print $2}')
DYSK_ZAJETY=$(df -h / | awk 'NR==2 {print $3}')
DYSK_WOLNY=$(df -h / | awk 'NR==2 {print $4}')
DYSK_PROCENT=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')

# 5. Sieć i otwarte porty
OTWARTE_PORTY=$(ss -tlpn 2>/dev/null | grep -c LISTEN || netstat -tlpn 2>/dev/null | grep -c LISTEN || echo "0")
GLOWNY_ADRES_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")

# 6. Aktywne sesje użytkowników
ZALOGOWANI_UZYTKOWNICY=$(who | awk '{print $1}' | sort -u | tr '\n' ' ' | sed 's/ $//')
[[ -z "$ZALOGOWANI_UZYTKOWNICY" ]] && ZALOGOWANI_UZYTKOWNICY="brak"
LICZBA_SESJI=$(who | wc -l)

# 7. Nieudane próby logowania SSH z ostatnich 24 godzin (objaw ataków brute-force)
NIEUDANE_LOGOWANIA=0
if command -v journalctl >/dev/null 2>&1; then
    NIEUDANE_LOGOWANIA=$(journalctl -u ssh -u sshd --since "24 hours ago" 2>/dev/null | grep -c "Failed password" || true)
elif [[ -f /var/log/auth.log ]]; then
    NIEUDANE_LOGOWANIA=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || true)
fi

# Sprawdzanie czy przekroczono zdefiniowane progi
if (( RAM_PROCENT >= PROG_KRYTYCZNY )); then
    log_kryt "Zużycie pamięci RAM jest krytyczne: ${RAM_PROCENT}% (Próg: ${PROG_KRYTYCZNY}%)"
elif (( RAM_PROCENT >= PROG_OSTRZEZENIE )); then
    log_ostrz "Zużycie pamięci RAM jest podwyższone: ${RAM_PROCENT}% (Próg: ${PROG_OSTRZEZENIE}%)"
fi

if (( DYSK_PROCENT >= PROG_KRYTYCZNY )); then
    log_kryt "Zajętość dysku głównego jest krytyczna: ${DYSK_PROCENT}% (Próg: ${PROG_KRYTYCZNY}%)"
elif (( DYSK_PROCENT >= PROG_OSTRZEZENIE )); then
    log_ostrz "Zajętość dysku głównego jest podwyższona: ${DYSK_PROCENT}% (Próg: ${PROG_OSTRZEZENIE}%)"
fi

# ------------------------------------------------------------------------------
# Tryb wyjścia: JSON (do automatyzacji i API)
# ------------------------------------------------------------------------------
if [[ "$TRYB_WYJSCIA" == "json" ]]; then
    cat << EOF
{
  "znacznik_czasu": "$CZAS_RAPORTU",
  "system": {
    "host": "$NAZWA_HOSTA",
    "system_operacyjny": "$SYSTEM_NAZWA",
    "wersja_jadra": "$WERSJA_JADRA",
    "czas_dzialania": "$CZAS_DZIALANIA",
    "rdzenie_cpu": $LICZBA_RDZENI,
    "obciazenie_srednie": "$OBCIAZENIE_SREDNIE",
    "adres_ip": "$GLOWNY_ADRES_IP"
  },
  "pamiec_ram": {
    "calkowita_mb": $RAM_TOTAL_MB,
    "uzyta_mb": $RAM_USED_MB,
    "dostepna_mb": $RAM_AVAIL_MB,
    "procent_uzycia": $RAM_PROCENT,
    "swap_procent": $SWAP_PROCENT
  },
  "dysk": {
    "calkowity": "$DYSK_CALKOWITY",
    "zajety": "$DYSK_ZAJETY",
    "wolny": "$DYSK_WOLNY",
    "procent_zajecia": $DYSK_PROCENT
  },
  "bezpieczenstwo": {
    "otwarte_porty_tcp": "$OTWARTE_PORTY",
    "liczba_sesji": $LICZBA_SESJI,
    "zalogowani_uzytkownicy": "$ZALOGOWANI_UZYTKOWNICY",
    "nieudane_logowania_ssh_24h": $NIEUDANE_LOGOWANIA
  },
  "status": {
    "ostrzezenie": $CZY_OSTRZEZENIE,
    "krytyczny": $CZY_KRYTYCZNY
  }
}
EOF
    if [[ "$CZY_KRYTYCZNY" == true || "$CZY_OSTRZEZENIE" == true ]]; then
        exit 1
    fi
    exit 0
fi

# ------------------------------------------------------------------------------
# Tryb wyjścia: HTML (raport do przeglądarki)
# ------------------------------------------------------------------------------
if [[ "$TRYB_WYJSCIA" == "html" ]]; then
    [[ -z "$PLIK_HTML" ]] && PLIK_HTML="raport_stanu.html"
    cat > "$PLIK_HTML" << EOF
<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8">
    <title>Stan Systemu: $NAZWA_HOSTA</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #e2e8f0; margin: 40px; }
        .karta { background: #1e293b; border-radius: 8px; padding: 20px; margin-bottom: 20px; }
        h1 { color: #38bdf8; margin-top: 0; }
        h2 { color: #94a3b8; font-size: 1.1rem; border-bottom: 1px solid #334155; padding-bottom: 8px; }
        .siatka { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 15px; }
        .metryka { background: #0f172a; padding: 12px; border-radius: 6px; }
        .etykieta { font-size: 0.8rem; color: #64748b; text-transform: uppercase; }
        .wartosc { font-size: 1.4rem; font-weight: bold; margin-top: 4px; color: #f8fafc; }
    </style>
</head>
<body>
    <h1>Raport Stanu Systemu: $NAZWA_HOSTA</h1>
    <p>Wygenerowano: $CZAS_RAPORTU | System: $SYSTEM_NAZWA | Jądro: $WERSJA_JADRA</p>

    <div class="karta">
        <h2>Wykorzystanie Zasobów</h2>
        <div class="siatka">
            <div class="metryka"><div class="etykieta">Rdzenie CPU i Obciążenie</div><div class="wartosc">$LICZBA_RDZENI rdzeni / $OBCIAZENIE_1M</div></div>
            <div class="metryka"><div class="etykieta">Użycie RAM</div><div class="wartosc">$RAM_PROCENT% ($RAM_USED_MB / $RAM_TOTAL_MB MB)</div></div>
            <div class="metryka"><div class="etykieta">Zajętość Dysku (/)</div><div class="wartosc">$DYSK_PROCENT% ($DYSK_ZAJETY / $DYSK_CALKOWITY)</div></div>
            <div class="metryka"><div class="etykieta">Otwarte Porty TCP</div><div class="wartosc">$OTWARTE_PORTY</div></div>
        </div>
    </div>

    <div class="karta">
        <h2>Bezpieczeństwo i Sesje</h2>
        <div class="siatka">
            <div class="metryka"><div class="etykieta">Aktywne Sesje</div><div class="wartosc">$LICZBA_SESJI ($ZALOGOWANI_UZYTKOWNICY)</div></div>
            <div class="metryka"><div class="etykieta">Nieudane Logowania SSH (24h)</div><div class="wartosc">$NIEUDANE_LOGOWANIA</div></div>
        </div>
    </div>
</body>
</html>
EOF
    log_ok "Raport HTML został pomyślnie zapisany w pliku: $PLIK_HTML"
    exit 0
fi

# ------------------------------------------------------------------------------
# Tryb domyślny: Wyświetlanie w terminalu
# ------------------------------------------------------------------------------
if [[ "$TRYB_CICHY" == false ]]; then
    echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
    echo -e "${K_CYJAN}${K_POGRUBIENIE}             RAPORT STANU I TELEMETRII SYSTEMU LINUX                  ${K_RESET}"
    echo -e "${K_SZARY}             Czas: $CZAS_RAPORTU | Host: $NAZWA_HOSTA${K_RESET}"
    echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
    echo ""

    # Sekcja 1: Sprzęt i system
    echo -e "${K_POGRUBIENIE}─── Informacje o Systemie ───────────────────────────────────────────${K_RESET}"
    printf "  %-22s : %s\n" "System operacyjny" "$SYSTEM_NAZWA"
    printf "  %-22s : %s\n" "Wersja jądra" "$WERSJA_JADRA"
    printf "  %-22s : %s\n" "Czas działania (uptime)" "$CZAS_DZIALANIA"
    printf "  %-22s : %s (Główny adres IP: %s)\n" "Procesor / Architektura" "$LICZBA_RDZENI Rdzeni / $(uname -m)" "$GLOWNY_ADRES_IP"
    printf "  %-22s : %s (1 min, 5 min, 15 min)\n" "Średnie obciążenie" "$OBCIAZENIE_SREDNIE"
    echo ""

    # Sekcja 2: Pamięć i dysk
    echo -e "${K_POGRUBIENIE}─── Wykorzystanie Zasobów ───────────────────────────────────────────${K_RESET}"
    kolor_ram="$K_ZIELONY"
    (( RAM_PROCENT >= PROG_OSTRZEZENIE )) && kolor_ram="$K_ZOLTY"
    (( RAM_PROCENT >= PROG_KRYTYCZNY )) && kolor_ram="$K_CZERWONY"
    printf "  %-22s : ${kolor_ram}%d%%${K_RESET} (%d MB użyte / %d MB łącznie)\n" "Pamięć RAM" "$RAM_PROCENT" "$RAM_USED_MB" "$RAM_TOTAL_MB"

    printf "  %-22s : %d%% (%d MB użyte / %d MB łącznie)\n" "Pamięć wymiany (SWAP)" "$SWAP_PROCENT" "$(( SWAP_USED_KB / 1024 ))" "$(( SWAP_TOTAL_KB / 1024 ))"

    kolor_dysk="$K_ZIELONY"
    (( DYSK_PROCENT >= PROG_OSTRZEZENIE )) && kolor_dysk="$K_ZOLTY"
    (( DYSK_PROCENT >= PROG_KRYTYCZNY )) && kolor_dysk="$K_CZERWONY"
    printf "  %-22s : ${kolor_dysk}%d%%${K_RESET} (%s zajęte / %s łącznie)\n" "Główny dysk (/)" "$DYSK_PROCENT" "$DYSK_ZAJETY" "$DYSK_CALKOWITY"
    echo ""

    # Sekcja 3: Usługi systemowe
    echo -e "${K_POGRUBIENIE}─── Stan Kluczowych Usług (systemd) ─────────────────────────────────${K_RESET}"
    if command -v systemctl >/dev/null 2>&1; then
        for usluga in "${SPRAWDZANE_USLUGI[@]}"; do
            if systemctl list-unit-files "${usluga}.service" >/dev/null 2>&1 || systemctl is-active --quiet "$usluga" 2>/dev/null; then
                if systemctl is-active --quiet "$usluga" 2>/dev/null; then
                    printf "  %-22s : ${K_ZIELONY}● AKTYWNA (Działa)${K_RESET}\n" "$usluga"
                else
                    printf "  %-22s : ${K_SZARY}○ NIEAKTYWNA / ZATRZYMANA${K_RESET}\n" "$usluga"
                fi
            fi
        done
    else
        echo "  [systemctl nie jest dostępny na tym hoście]"
    fi
    echo ""

    # Sekcja 4: Bezpieczeństwo i sesje
    echo -e "${K_POGRUBIENIE}─── Bezpieczeństwo i Sesje ──────────────────────────────────────────${K_RESET}"
    printf "  %-22s : %s\n" "Zalogowani" "$ZALOGOWANI_UZYTKOWNICY ($LICZBA_SESJI aktywnych sesji)"
    printf "  %-22s : %s\n" "Otwarte porty TCP" "$OTWARTE_PORTY"
    if [[ "$NIEUDANE_LOGOWANIA" -gt 0 ]]; then
        printf "  %-22s : ${K_ZOLTY}%s nieudanych prób${K_RESET}\n" "Ataki SSH (ostatnie 24h)" "$NIEUDANE_LOGOWANIA"
    else
        printf "  %-22s : ${K_ZIELONY}0 (brak podejrzanej aktywności)${K_RESET}\n" "Ataki SSH (ostatnie 24h)"
    fi
    echo ""

    # Sekcja 5: Procesy zużywające najwięcej pamięci
    echo -e "${K_POGRUBIENIE}─── Top 3 Procesy wg Zużycia RAM ────────────────────────────────────${K_RESET}"
    ps -eo pid,user,%mem,%cpu,comm --sort=-%mem | head -n 4 | awk 'NR>1 {printf "  PID: %-7s UŻYTKOWNIK: %-10s RAM: %-5s%% CPU: %-5s%% PROCES: %s\n", $1, $2, $3, $4, $5}'
    echo ""
    echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
fi

# Zwracamy kod błędu 1 jeśli cokolwiek przekroczyło progi
if [[ "$CZY_KRYTYCZNY" == true || "$CZY_OSTRZEZENIE" == true ]]; then
    exit 1
fi

exit 0
