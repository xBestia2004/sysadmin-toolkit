#!/usr/bin/env bash
# ==============================================================================
# Nazwa skryptu : 05_docker_host_cleaner.sh
# Opis          : Narzędzie do optymalizacji i czyszczenia zasobów Dockera.
#                 Wykrywa nieużywane kontenery, wiszące obrazy (<none>),
#                 osierocone wolumeny oraz pamięć podręczną (build cache).
#                 Posiada bezpieczny tryb symulacji (--dry-run).
# Autor         : Dariusz Kisiel (xBestia2004)
# Licencja      : MIT
# ==============================================================================

# Bezpieczne ustawienia Basha
set -euo pipefail

WERSJA="1.2.0"
SYMULACJA=false
BEZ_PYTANIA=false
CZYSC_WOLUMENY=false
CZYSC_WSZYSTKIE_OBRAZY=false # domyślnie czyści tylko wiszące (<none>)

# Kolory w terminalu
if [[ -t 1 ]]; then
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

wyswietl_pomoc() {
    cat << EOF
${K_POGRUBIENIE}Użycie:${K_RESET} $(basename "$0") [OPCJE]

${K_POGRUBIENIE}Optymalizator i czyściciel niepotrzebnych zasobów Dockera${K_RESET}

${K_POGRUBIENIE}OPCJE:${K_RESET}
    -d, --dry-run          Symulacja: pokaż co można usunąć i ile miejsca zwolnić (bez usuwania)
    -f, --force            Tryb automatyczny bez pytań (idealny do zadań w cronie)
    --volumes              Wyczyść także osierocone wolumeny danych (Uwaga: trwale usuwa dane!)
    --all-images           Usuń wszystkie nieużywane obrazy, a nie tylko wiszące (<none>)
    -v, --version          Pokaż wersję skryptu
    -h, --help             Pokaż to menu pomocy

${K_POGRUBIENIE}PRZYKŁADY:${K_RESET}
    # Bezpieczny podgląd (symulacja):
    $(basename "$0") --dry-run

    # Standardowe czyszczenie z pytaniem o potwierdzenie:
    $(basename "$0")

    # Automatyczne czyszczenie w nocy przez crona:
    $(basename "$0") --force
EOF
    exit 0
}

# Przetwarzanie argumentów
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run)
            SYMULACJA=true
            shift
            ;;
        -f|--force)
            BEZ_PYTANIA=true
            shift
            ;;
        --volumes)
            CZYSC_WOLUMENY=true
            shift
            ;;
        --all-images)
            CZYSC_WSZYSTKIE_OBRAZY=true
            shift
            ;;
        -v|--version)
            echo "docker_host_cleaner wersja $WERSJA"
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

# Sprawdzamy czy Docker jest zainstalowany w systemie
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${K_CZERWONY}[BŁĄD] Polecenie 'docker' nie zostało znalezione w systemie.${K_RESET}" >&2
    exit 1
fi

# Sprawdzamy czy demon Dockera jest uruchomiony i czy użytkownik ma uprawnienia
if ! docker info >/dev/null 2>&1; then
    echo -e "${K_CZERWONY}[BŁĄD] Brak połączenia z demonem Dockera. Upewnij się, że usługa działa (systemctl status docker) lub użyj sudo.${K_RESET}" >&2
    exit 1
fi

echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
echo -e "${K_CYJAN}${K_POGRUBIENIE}              AUDYT I CZYSZCZENIE ZASOBÓW DOCKERA                     ${K_RESET}"
echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"

# Wyświetlamy aktualne zużycie dysku przez Dockera
echo -e "${K_POGRUBIENIE}─── Aktualne Użycie Dysku przez Dockera ──────────────────────────────${K_RESET}"
docker system df
echo ""

# Zliczamy zasoby kwalifikujące się do usunięcia
ZATRZYMANE_KONTENERY=$(docker ps -aq --filter "status=exited" --filter "status=dead" | wc -l)
WISZACE_OBRAZY=$(docker images -f "dangling=true" -q | wc -l)
LACZNIE_OBRAZOW=$(docker images -q | sort -u | wc -l)
NIEUZYWANE_WOLUMENY=$(docker volume ls -qf "dangling=true" | wc -l)

echo -e "${K_POGRUBIENIE}─── Wykryte Elementy do Posprzątania ─────────────────────────────────${K_RESET}"
printf "  %-36s : %d\n" "Zatrzymane / Martwe Kontenery" "$ZATRZYMANE_KONTENERY"
printf "  %-36s : %d (spośród %d wszystkich)\n" "Wiszące obrazy (<none>)" "$WISZACE_OBRAZY" "$LACZNIE_OBRAZOW"
if [[ "$CZYSC_WOLUMENY" == true ]]; then
    printf "  %-36s : %d (Zostaną wyczyszczone)\n" "Osierocone wolumeny" "$NIEUZYWANE_WOLUMENY"
else
    printf "  %-36s : %d (Pominięte, użyj --volumes aby włączyć)\n" "Osierocone wolumeny" "$NIEUZYWANE_WOLUMENY"
fi
echo ""

# Obsługa trybu symulacji (--dry-run)
if [[ "$SYMULACJA" == true ]]; then
    echo -e "${K_ZOLTY}[SYMULACJA] Włączono tryb podglądu. Żadne kontenery ani obrazy nie zostały usunięte.${K_RESET}"
    echo -e "${K_ZOLTY}[SYMULACJA] Aby wykonać faktyczne czyszczenie, uruchom skrypt bez flagi --dry-run.${K_RESET}"
    echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
    exit 0
fi

# Pytanie o potwierdzenie w trybie interaktywnym
if [[ "$BEZ_PYTANIA" == false ]]; then
    read -rp "Czy na pewno chcesz usunąć niepotrzebne zasoby Dockera? [t/N]: " zgoda
    if [[ ! "$zgoda" =~ ^[TtYy]$ ]]; then
        echo -e "${K_ZOLTY}[!] Operacja anulowana przez użytkownika.${K_RESET}"
        exit 0
    fi
fi

echo -e "${K_POGRUBIENIE}─── Wykonywanie Operacji Czyszczenia ─────────────────────────────────${K_RESET}"

# 1. Usuwanie zatrzymanych kontenerów
echo -e "${K_CYJAN}[INFORMACJA] Usuwanie zatrzymanych kontenerów...${K_RESET}"
docker container prune -f

# 2. Usuwanie niepotrzebnych obrazów
if [[ "$CZYSC_WSZYSTKIE_OBRAZY" == true ]]; then
    echo -e "${K_CYJAN}[INFORMACJA] Usuwanie wszystkich nieużywanych obrazów...${K_RESET}"
    docker image prune -a -f
else
    echo -e "${K_CYJAN}[INFORMACJA] Usuwanie wiszących obrazów (<none>)...${K_RESET}"
    docker image prune -f
fi

# 3. Usuwanie wolumenów (jeśli zaznaczono)
if [[ "$CZYSC_WOLUMENY" == true ]]; then
    echo -e "${K_CYJAN}[INFORMACJA] Usuwanie nieużywanych wolumenów...${K_RESET}"
    docker volume prune -f
fi

# 4. Usuwanie pamięci podręcznej budowania (build cache)
echo -e "${K_CYJAN}[INFORMACJA] Czyszczenie pamięci podręcznej buildera...${K_RESET}"
docker builder prune -f

echo ""
echo -e "${K_ZIELONY}[SUKCES] Czyszczenie Dockera zakończone pomyślnie!${K_RESET}"
echo -e "${K_POGRUBIENIE}─── Zaktualizowany Stan Dysku Dockera ────────────────────────────────${K_RESET}"
docker system df
echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
