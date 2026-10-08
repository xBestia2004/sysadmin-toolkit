#!/usr/bin/env bash
# ==============================================================================
# Nazwa skryptu : 02_backup_rotator.sh
# Opis          : Automatyczny silnik kopii zapasowych z rotacją i retencją.
#                 Tworzy archiwa tar.gz/zstd, generuje sumy kontrolne SHA-256,
#                 usuwa stare kopie (FIFO) i zabezpiecza przed kolizjami.
# Autor         : Dariusz Kisiel (xBestia2004)
# Licencja      : MIT
# ==============================================================================

# Bezpieczne ustawienia Basha
set -euo pipefail

# ------------------------------------------------------------------------------
# Ustawienia domyślne
# ------------------------------------------------------------------------------
WERSJA="1.2.0"
KATALOG_ZRODLO=""
KATALOG_DOCELOWY=""
PREFIKS="kopia"
LICZBA_RETENCJI=7   # Domyślnie zostawiamy 7 najnowszych kopii
KOMPRESJA="gzip"    # gzip (.tar.gz) lub zstd (.tar.zst)
WYKLUCZENIA=()
SYMULACJA=false     # Tryb --dry-run
SPRAWDZAJ_SUME=true # Obliczanie sumy SHA-256
PLIK_LOGU=""
PLIK_BLOKADY="/tmp/backup_rotator.lock"

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

# ------------------------------------------------------------------------------
# Sprzątanie po zakończeniu pracy (usunięcie pliku blokady)
# ------------------------------------------------------------------------------
posprzataj() {
    if [[ -f "$PLIK_BLOKADY" ]]; then
        rm -f "$PLIK_BLOKADY"
    fi
}
# Wywołaj posprzataj przy wyjściu lub przerwaniu skryptu (Ctrl+C)
trap posprzataj EXIT INT TERM

# Funkcja do wypisywania czytelnych komunikatów
loguj() {
    local poziom="$1"; shift
    local wiadomosc="$*"
    local znacznik_czasu
    znacznik_czasu=$(date '+%Y-%m-%d %H:%M:%S')

    case "$poziom" in
        INFO)  echo -e "${K_CYJAN}[INFORMACJA]${K_RESET}  $wiadomosc" ;;
        SUKCES) echo -e "${K_ZIELONY}[   OK    ]${K_RESET}   $wiadomosc" ;;
        OSTRZ) echo -e "${K_ZOLTY}[OSTRZEŻENIE]${K_RESET} $wiadomosc" >&2 ;;
        BLAD)  echo -e "${K_CZERWONY}[  BŁĄD   ]${K_RESET}  $wiadomosc" >&2 ;;
    esac

    # Jeśli podano plik logu, zapisz również do pliku
    if [[ -n "$PLIK_LOGU" ]]; then
        echo "[$znacznik_czasu] [$poziom] $wiadomosc" >> "$PLIK_LOGU"
    fi
}

wyswietl_pomoc() {
    cat << EOF
${K_POGRUBIENIE}Użycie:${K_RESET} $(basename "$0") -s <katalog_źródłowy> -d <katalog_docelowy> [OPCJE]

${K_POGRUBIENIE}Automatyczny system kopii zapasowych z rotacją i sumą SHA-256${K_RESET}

${K_POGRUBIENIE}WYMAGANE ARGUMENTY:${K_RESET}
    -s, --source <katalog>   Katalog, którego kopię chcesz utworzyć
    -d, --dest <katalog>     Katalog docelowy, gdzie trafią spakowane archiwa

${K_POGRUBIENIE}OPCJE DODATKOWE:${K_RESET}
    -p, --prefix <nazwa>     Prefiks nazwy pliku (domyślnie: "$PREFIKS")
    -k, --keep <liczba>      Ile najnowszych kopii zachować (domyślnie: $LICZBA_RETENCJI)
    -c, --compress <format>  Format kompresji: 'gzip' lub 'zstd' (domyślnie: gzip)
    -e, --exclude <wzorzec>  Wzorzec do wykluczenia (można powtarzać, np. -e "cache")
    -l, --log <plik>         Ścieżka do pliku z logami operacji
    --no-verify              Pomiń wyliczanie sumy kontrolnej SHA-256
    --dry-run                Symulacja: pokaż co zostanie zrobione bez dotykania plików
    -v, --version            Pokaż wersję programu
    -h, --help               Pokaż to menu pomocy

${K_POGRUBIENIE}PRZYKŁADY:${K_RESET}
    # Zwykła kopia z domyślnym zachowaniem 7 ostatnich wersji:
    $(basename "$0") -s /var/www/html -d /kopie/web

    # Kopia z zachowaniem 14 wersji i wykluczeniem katalogów cache:
    $(basename "$0") -s /opt/projekt -d /kopie -p projekt -k 14 -e ".git" -e "cache"

    # Bezpieczne testowanie parametrów (symulacja):
    $(basename "$0") -s /home/dariusz -d /tmp/kopie --dry-run
EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Odczyt argumentów z wiersza poleceń
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--source)
            KATALOG_ZRODLO="$2"
            shift 2
            ;;
        -d|--dest)
            KATALOG_DOCELOWY="$2"
            shift 2
            ;;
        -p|--prefix)
            PREFIKS="$2"
            shift 2
            ;;
        -k|--keep)
            LICZBA_RETENCJI="$2"
            shift 2
            ;;
        -c|--compress)
            KOMPRESJA="$2"
            shift 2
            ;;
        -e|--exclude)
            WYKLUCZENIA+=("--exclude=$2")
            shift 2
            ;;
        -l|--log)
            PLIK_LOGU="$2"
            shift 2
            ;;
        --no-verify)
            SPRAWDZAJ_SUME=false
            shift
            ;;
        --dry-run)
            SYMULACJA=true
            shift
            ;;
        -v|--version)
            echo "backup_rotator wersja $WERSJA"
            exit 0
            ;;
        -h|--help)
            wyswietl_pomoc
            ;;
        *)
            loguj BLAD "Nieznana opcja: $1"
            wyswietl_pomoc
            ;;
    esac
done

# Sprawdzamy czy podano wymagane katalogi
if [[ -z "$KATALOG_ZRODLO" || -z "$KATALOG_DOCELOWY" ]]; then
    loguj BLAD "Podanie katalogu źródłowego (-s) i docelowego (-d) jest obowiązkowe!"
    echo ""
    wyswietl_pomoc
fi

if [[ ! -d "$KATALOG_ZRODLO" ]]; then
    loguj BLAD "Katalog źródłowy nie istnieje: $KATALOG_ZRODLO"
    exit 2
fi

# Zabezpieczenie przed jednoczesnym uruchomieniem dwóch kopii (plik blokady)
if [[ "$SYMULACJA" == false ]]; then
    mkdir -p "$KATALOG_DOCELOWY"
    if [[ -f "$PLIK_BLOKADY" ]]; then
        loguj BLAD "Inny proces backupu jest już w trakcie działania (plik: $PLIK_BLOKADY)."
        exit 3
    fi
    echo "$$" > "$PLIK_BLOKADY"
fi

# ------------------------------------------------------------------------------
# Przygotowanie nazwy pliku i narzędzia do pakowania
# ------------------------------------------------------------------------------
ZNACZNIK_CZASU=$(date '+%Y%m%d_%H%M%S')
ROZSZERZENIE="tar.gz"
OPCJE_TAR=("-czf")

# Jeśli wybrano szybszą kompresję zstd, sprawdzamy czy program jest zainstalowany
if [[ "$KOMPRESJA" == "zstd" ]]; then
    if ! command -v zstd >/dev/null 2>&1; then
        loguj OSTRZ "Program 'zstd' nie został znaleziony. Przełączam na gzip."
    else
        ROZSZERZENIE="tar.zst"
        OPCJE_TAR=("--zstd" "-cf")
    fi
fi

NAZWA_ARCHIWUM="${PREFIKS}_${ZNACZNIK_CZASU}.${ROZSZERZENIE}"
SCIEZKA_ARCHIWUM="${KATALOG_DOCELOWY}/${NAZWA_ARCHIWUM}"

loguj INFO "Rozpoczynanie procesu tworzenia kopii zapasowej..."
loguj INFO "Źródło      : $KATALOG_ZRODLO"
loguj INFO "Cel         : $KATALOG_DOCELOWY"
loguj INFO "Nazwa pliku : $NAZWA_ARCHIWUM"

# ------------------------------------------------------------------------------
# Tworzenie archiwum
# ------------------------------------------------------------------------------
if [[ "$SYMULACJA" == true ]]; then
    loguj OSTRZ "[SYMULACJA] Zostałoby utworzone archiwum: $SCIEZKA_ARCHIWUM"
    loguj OSTRZ "[SYMULACJA] Reguły wykluczeń: ${WYKLUCZENIA[*]:-brak}"
else
    CZAS_START=$(date +%s)

    # Pakujemy katalog
    KATALOG_RODZIC=$(dirname "$KATALOG_ZRODLO")
    KATALOG_CEL=$(basename "$KATALOG_ZRODLO")

    tar "${OPCJE_TAR[@]}" "$SCIEZKA_ARCHIWUM" \
        -C "$KATALOG_RODZIC" \
        "${WYKLUCZENIA[@]}" \
        "$KATALOG_CEL" 2>/dev/null

    CZAS_TRWANIA=$(( $(date +%s) - CZAS_START ))
    ROZMIAR_PLIKU=$(du -h "$SCIEZKA_ARCHIWUM" | awk '{print $1}')
    loguj SUKCES "Archiwum utworzone pomyślnie: $SCIEZKA_ARCHIWUM (Rozmiar: $ROZMIAR_PLIKU, Czas: ${CZAS_TRWANIA}s)"

    # Generowanie sumy kontrolnej SHA-256 dla sprawdzenia spójności danych
    if [[ "$SPRAWDZAJ_SUME" == true ]]; then
        loguj INFO "Obliczanie sumy kontrolnej SHA-256 dla weryfikacji spójności..."
        (cd "$KATALOG_DOCELOWY" && sha256sum "$NAZWA_ARCHIWUM" > "${NAZWA_ARCHIWUM}.sha256")
        loguj SUKCES "Plik sumy kontrolnej utworzony: ${NAZWA_ARCHIWUM}.sha256"
    fi
fi

# ------------------------------------------------------------------------------
# Rotacja i usuwanie starych kopii (Polityka Retencji)
# ------------------------------------------------------------------------------
loguj INFO "Sprawdzanie polityki retencji (zachowaj najnowsze: $LICZBA_RETENCJI sztuk)..."

# Szukamy istniejących archiwów o tym samym prefiksie, posortowanych od najnowszych
ISTNIEJACE_KOPIE=()
if [[ -d "$KATALOG_DOCELOWY" ]]; then
    while IFS= read -r -d $'\0' plik; do
        ISTNIEJACE_KOPIE+=("$plik")
    done < <(find "$KATALOG_DOCELOWY" -maxdepth 1 -type f -name "${PREFIKS}_*.${ROZSZERZENIE}" -print0 | sort -z -r)
fi

LACZNIE_KOPII=${#ISTNIEJACE_KOPIE[@]}
loguj INFO "Znaleziono łącznie $LACZNIE_KOPII kopii o prefiksie '$PREFIKS'."

# Jeśli jest ich więcej niż ustalony limit, usuwamy najstarsze
if (( LACZNIE_KOPII > LICZBA_RETENCJI )); then
    ILE_USUNAC=$(( LACZNIE_KOPII - LICZBA_RETENCJI ))
    loguj INFO "Usuwanie $ILE_USUNAC najstarszych kopii w celu zachowania limitu..."

    for (( i=LICZBA_RETENCJI; i<LACZNIE_KOPII; i++ )); do
        STARY_PLIK="${ISTNIEJACE_KOPIE[$i]}"
        STARA_SUMA="${STARY_PLIK}.sha256"

        if [[ "$SYMULACJA" == true ]]; then
            loguj OSTRZ "[SYMULACJA] Zostałaby usunięta przeterminowana kopia: $(basename "$STARY_PLIK")"
        else
            rm -f "$STARY_PLIK"
            [[ -f "$STARA_SUMA" ]] && rm -f "$STARA_SUMA"
            loguj SUKCES "Usunięto przeterminowaną kopię: $(basename "$STARY_PLIK")"
        fi
    done
else
    loguj SUKCES "Liczba kopii mieści się w limicie ($LACZNIE_KOPII <= $LICZBA_RETENCJI). Żadne pliki nie zostały usunięte."
fi

loguj SUKCES "Operacja tworzenia kopii zapasowej zakończona pomyślnie!"
exit 0
