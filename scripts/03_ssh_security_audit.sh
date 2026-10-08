#!/usr/bin/env bash
# ==============================================================================
# Nazwa skryptu : 03_ssh_security_audit.sh
# Opis          : Audytor bezpieczeństwa i narzędzie do utwardzania usługi OpenSSH.
#                 Sprawdza kluczowe ustawienia według wytycznych CIS Benchmarks,
#                 oblicza wskaźnik bezpieczeństwa (0-100%) oraz umożliwia
#                 bezpieczne utwardzenie konfiguracji z testem składni sshd -t.
# Autor         : Dariusz Kisiel (xBestia2004)
# Licencja      : MIT
# ==============================================================================

# Bezpieczne ustawienia Basha
set -euo pipefail

WERSJA="1.2.0"
PLIK_KONFIG="/etc/ssh/sshd_config"
TYLKO_AUDYT=true
SYMULACJA=false
KATALOG_KOPII="/etc/ssh/kopie_zapasowe"

# Kolory komunikatów
if [[ -t 1 ]]; then
    K_RESET="\033[0m"
    K_POGRUBIENIE="\033[1m"
    K_CZERWONY="\033[1;31m"
    K_ZOLTY="\033[1;33m"
    K_ZIELONY="\033[1;32m"
    K_CYJAN="\033[1;36m"
else
    K_RESET=""
    K_POGRUBIENIE=""
    K_CZERWONY=""
    K_ZOLTY=""
    K_ZIELONY=""
    K_CYJAN=""
fi

wyswietl_pomoc() {
    cat << EOF
${K_POGRUBIENIE}Użycie:${K_RESET} $(basename "$0") [OPCJE]

${K_POGRUBIENIE}Audytor i narzędzie do utwardzania bezpieczeństwa serwera OpenSSH${K_RESET}

${K_POGRUBIENIE}OPCJE:${K_RESET}
    -a, --audit-only       Tylko audyt i ocena punktowa (tryb tylko do odczytu, domyślny)
    --harden               Zastosuj zalecany profil bezpieczeństwa (wymaga uprawnień root/sudo)
    -c, --config <plik>    Ścieżka do pliku sshd_config (domyślnie: $PLIK_KONFIG)
    --dry-run              Symulacja: pokaż co zostanie zmienione bez modyfikacji plików
    -v, --version          Pokaż wersję programu
    -h, --help             Pokaż to menu pomocy

${K_POGRUBIENIE}PRZYKŁADY:${K_RESET}
    # Zwykły audyt bezpieczeństwa (można uruchomić jako zwykły użytkownik jeśli plik jest czytelny):
    sudo $(basename "$0")

    # Podgląd zmian w trybie bezpiecznej symulacji:
    $(basename "$0") --harden --dry-run

    # Wdrożenie bezpiecznych ustawień na serwerze:
    sudo $(basename "$0") --harden
EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Przetwarzanie argumentów
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--audit-only)
            TYLKO_AUDYT=true
            shift
            ;;
        --harden)
            TYLKO_AUDYT=false
            shift
            ;;
        -c|--config)
            PLIK_KONFIG="$2"
            shift 2
            ;;
        --dry-run)
            SYMULACJA=true
            shift
            ;;
        -v|--version)
            echo "ssh_security_audit wersja $WERSJA"
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

# Sprawdzamy czy plik konfiguracyjny istnieje
if [[ ! -f "$PLIK_KONFIG" ]]; then
    echo -e "${K_CZERWONY}[BŁĄD] Plik konfiguracji SSH nie został znaleziony: $PLIK_KONFIG${K_RESET}" >&2
    exit 1
fi

# Sprawdzamy uprawnienia do odczytu
if [[ ! -r "$PLIK_KONFIG" ]]; then
    echo -e "${K_ZOLTY}[!] Uwaga: Brak uprawnień do odczytu pliku '$PLIK_KONFIG'.${K_RESET}"
    echo -e "${K_ZOLTY}[!] W wielu dystrybucjach plik sshd_config wymaga uprawnień roota.${K_RESET}"
    echo -e "${K_CYJAN}[i] Uruchom audyt z prawami administratora:${K_RESET} sudo $0"
    exit 1
fi

# ------------------------------------------------------------------------------
# Funkcja pobierająca aktualną wartość parametru z konfiguracji SSH
# ------------------------------------------------------------------------------
pobierz_parametr_ssh() {
    local parametr="$1"
    local wartosc_domyslna="$2"
    local wartosc_efektywna=""

    # Jeśli jest polecenie sshd, pobieramy faktycznie obowiązującą wartość (wymaga root)
    if command -v sshd >/dev/null 2>&1; then
        wartosc_efektywna=$( { sshd -T -C user=root,host=localhost,addr=127.0.0.1 2>/dev/null || true; } | grep -i "^${parametr} " | awk '{print $2}' || true)
        if [[ -n "$wartosc_efektywna" ]]; then
            echo "$wartosc_efektywna"
            return
        fi
    fi

    # Zapasowo: szukamy bezpośrednio w pliku tekstowym
    local znaleziona=""
    znaleziona=$(grep -E -i "^\s*${parametr}\s+" "$PLIK_KONFIG" 2>/dev/null | tail -n 1 | awk '{print $2}' || true)
    if [[ -n "$znaleziona" ]]; then
        echo "$znaleziona"
    else
        echo "$wartosc_domyslna"
    fi
}

echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
echo -e "${K_CYJAN}${K_POGRUBIENIE}             AUDYT BEZPIECZEŃSTWA USŁUGI OPENSSH                     ${K_RESET}"
echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
echo -e "Badany plik konfiguracji: ${K_POGRUBIENIE}$PLIK_KONFIG${K_RESET}"
echo ""

LACZNIE_TESTOW=0
ZALICZONE_TESTY=0

# Funkcja testująca pojedyncze ustawienie
sprawdz_parametr() {
    local nazwa_testu="$1"
    local nazwa_parametru="$2"
    local oczekiwana_wartosc="$3"
    local wartosc_zapasowa="$4"
    local waga_bledu="$5" # NISKA, SREDNIA, WYSOKA

    LACZNIE_TESTOW=$(( LACZNIE_TESTOW + 1 ))
    local aktualna
    aktualna=$(pobierz_parametr_ssh "$nazwa_parametru" "$wartosc_zapasowa")

    printf "  %-38s : " "$nazwa_testu"
    if [[ "${aktualna,,}" == "${oczekiwana_wartosc,,}" ]]; then
        ZALICZONE_TESTY=$(( ZALICZONE_TESTY + 1 ))
        printf "${K_ZIELONY}[ZGODNE] %-10s${K_RESET}\n" "$aktualna"
    else
        local kolor="$K_ZOLTY"
        [[ "$waga_bledu" == "WYSOKA" ]] && kolor="$K_CZERWONY"
        printf "${kolor}[RYZYKO] %-10s${K_RESET} (Zalecane: %s)\n" "$aktualna" "$oczekiwana_wartosc"
    fi
}

# ------------------------------------------------------------------------------
# Lista sprawdzanych reguł bezpieczeństwa (wg wytycznych CIS)
# ------------------------------------------------------------------------------
sprawdz_parametr "Blokada logowania na konto root"       "permitrootlogin"        "no"  "prohibit-password" "WYSOKA"
sprawdz_parametr "Wyłączenie logowania hasłem"          "passwordauthentication" "no"  "yes"               "WYSOKA"
sprawdz_parametr "Uwierzytelnianie kluczem (SSH Key)"   "pubkeyauthentication"   "yes" "yes"               "WYSOKA"
sprawdz_parametr "Limit prób logowania (<= 3)"          "maxauthtries"           "3"   "6"                 "SREDNIA"
sprawdz_parametr "Wyłączenie przekazywania X11"         "x11forwarding"          "no"  "yes"               "NISKA"
sprawdz_parametr "Ignorowanie plików rhosts"            "ignorerhosts"           "yes" "yes"               "NISKA"
sprawdz_parametr "Limit bezczynności sesji (timeout)"   "clientaliveinterval"    "300" "0"                 "SREDNIA"
sprawdz_parametr "Blokada kont z pustymi hasłami"       "permitemptypasswords"   "no"  "no"                "WYSOKA"

# Wyliczamy wynik w procentach
WYNIK_PROCENT=$(( (ZALICZONE_TESTY * 100) / LACZNIE_TESTOW ))
echo ""
echo -e "${K_POGRUBIENIE}─── Podsumowanie Audytu ──────────────────────────────────────────────${K_RESET}"
kolor_wyniku="$K_ZIELONY"
(( WYNIK_PROCENT < 80 )) && kolor_wyniku="$K_ZOLTY"
(( WYNIK_PROCENT < 60 )) && kolor_wyniku="$K_CZERWONY"

printf "  Zaliczone testy     : %d / %d\n" "$ZALICZONE_TESTY" "$LACZNIE_TESTOW"
printf "  Wskaźnik Bezpieczeństwa : ${kolor_wyniku}%d%%${K_RESET}\n" "$WYNIK_PROCENT"
echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"

# ------------------------------------------------------------------------------
# Tryb Utwardzania Konfiguracji (--harden)
# ------------------------------------------------------------------------------
if [[ "$TYLKO_AUDYT" == false ]]; then
    echo ""
    echo -e "${K_POGRUBIENIE}─── Wdrażanie Bezpiecznego Profilu Hardeningu ────────────────────────${K_RESET}"

    # Wymagamy roota chyba, że włączono symulację
    if [[ "$SYMULACJA" == false && "$EUID" -ne 0 ]]; then
        echo -e "${K_CZERWONY}[BŁĄD] Wdrożenie zmian wymaga uprawnień administratora. Uruchom z sudo.${K_RESET}" >&2
        exit 1
    fi

    KATALOG_DROPIN="/etc/ssh/sshd_config.d"
    PLIK_DROPIN="${KATALOG_DROPIN}/99-bezpieczne-ustawienia.conf"

    if [[ "$SYMULACJA" == true ]]; then
        echo -e "${K_ZOLTY}[SYMULACJA] Zostałby utworzony plik konfiguracyjny: $PLIK_DROPIN o treści:${K_RESET}"
        cat << 'EOF'
# Utwardzone ustawienia wygenerowane przez 03_ssh_security_audit.sh
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
X11Forwarding no
IgnoreRhosts yes
ClientAliveInterval 300
ClientAliveCountMax 2
PermitEmptyPasswords no
EOF
        echo -e "${K_ZOLTY}[SYMULACJA] Zostałby wykonany test składni poleceniem: sshd -t${K_RESET}"
        echo -e "${K_ZOLTY}[SYMULACJA] Usługa zostałaby bezpiecznie przeładowana.${K_RESET}"
        exit 0
    fi

    # Tworzymy kopię zapasową przed jakąkolwiek modyfikacją
    mkdir -p "$KATALOG_KOPII"
    PLIK_KOPII="${KATALOG_KOPII}/sshd_config.$(date +%Y%m%d_%H%M%S).bak"
    cp "$PLIK_KONFIG" "$PLIK_KOPII"
    echo -e "${K_ZIELONY}[OK] Utworzono kopię zapasową pliku w: $PLIK_KOPII${K_RESET}"

    # Tworzymy plik nadpisujący konfigurację
    mkdir -p "$KATALOG_DROPIN"
    cat > "$PLIK_DROPIN" << 'EOF'
# Utwardzone ustawienia wygenerowane przez 03_ssh_security_audit.sh
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
X11Forwarding no
IgnoreRhosts yes
ClientAliveInterval 300
ClientAliveCountMax 2
PermitEmptyPasswords no
EOF
    echo -e "${K_ZIELONY}[OK] Zapisano bezpieczny profil w: $PLIK_DROPIN${K_RESET}"

    # Kluczowy test: sprawdzamy składnię poleceniem sshd -t
    echo -e "${K_CYJAN}[INFORMACJA] Testowanie poprawności składni OpenSSH przed przeładowaniem...${K_RESET}"
    if sshd -t; then
        echo -e "${K_ZIELONY}[OK] Składnia konfiguracji jest w 100% poprawna! Przeładowuję usługę SSH...${K_RESET}"
        if systemctl is-active --quiet ssh; then
            systemctl reload ssh
        elif systemctl is-active --quiet sshd; then
            systemctl reload sshd
        fi
        echo -e "${K_ZIELONY}[SUKCES] Konfiguracja SSH została pomyślnie utwardzona i przeładowana!${K_RESET}"
    else
        # W razie błędu wycofujemy zmiany aby administrator nie utracił dostępu do serwera
        echo -e "${K_CZERWONY}[KRYTYCZNY BŁĄD] Test składni nie powiódł się! Automatyczne wycofywanie zmian...${K_RESET}" >&2
        rm -f "$PLIK_DROPIN"
        exit 1
    fi
fi
