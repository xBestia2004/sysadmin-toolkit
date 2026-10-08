#!/usr/bin/env bash
# ==============================================================================
# Nazwa skryptu : zarzadzaj.sh
# Opis          : Główny panel kontrolny (Centrum Dowodzenia) narzędzi SysAdmin.
#                 Umożliwia interaktywne uruchamianie każdego skryptu,
#                 sprawdzanie kalendarza publikacji oraz podgląd wyników.
# Autor         : Dariusz Kisiel (xBestia2004)
# ==============================================================================

set -euo pipefail

SKRYPTY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"
KALENDARZ_PLIK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/PUBLICATION_CALENDAR.md"

# Kolory interfejsu
K_RESET="\033[0m"
K_POGRUBIENIE="\033[1m"
K_CYJAN="\033[1;36m"
K_ZIELONY="\033[1;32m"
K_ZOLTY="\033[1;33m"
K_CZERWONY="\033[1;31m"
K_SZARY="\033[2m"

# Nadajemy uprawnienia wykonywalne w razie potrzeby
chmod +x "$SKRYPTY_DIR"/*.sh "$SKRYPTY_DIR"/*.py 2>/dev/null || true

wyswietl_naglowek() {
    clear 2>/dev/null || true
    echo -e "${K_CYJAN}${K_POGRUBIENIE}"
    echo "  ================================================================"
    echo "           CENTRUM ZARZĄDZANIA PAKIETEM SKRYPTÓW SYSADMIN         "
    echo "               Dariusz Kisiel | Portfolio Kariery IT              "
    echo "  ================================================================"
    echo -e "${K_RESET}"
}

menu_glowne() {
    while true; do
        wyswietl_naglowek
        echo -e "${K_POGRUBIENIE}Wybierz narzędzie do uruchomienia:${K_RESET}"
        echo ""
        echo -e "  ${K_ZIELONY}[1]${K_RESET} 🩺 Sprawdź stan serwera i telemetrię    ${K_SZARY}(01_system_health_reporter.sh)${K_RESET}"
        echo -e "  ${K_ZIELONY}[2]${K_RESET} 💾 Wykonaj bezpieczną kopię (Backup)    ${K_SZARY}(02_backup_rotator.sh)${K_RESET}"
        echo -e "  ${K_ZIELONY}[3]${K_RESET} 🛡️ Audyt bezpieczeństwa usługi SSH       ${K_SZARY}(03_ssh_security_audit.sh)${K_RESET}"
        echo -e "  ${K_ZIELONY}[4]${K_RESET} 🚨 Wykryj próby włamań SSH (Brute-Force) ${K_SZARY}(04_auth_log_sentinel.py)${K_RESET}"
        echo -e "  ${K_ZIELONY}[5]${K_RESET} 🐳 Posprzątaj i zoptymalizuj Dockera    ${K_SZARY}(05_docker_host_cleaner.sh)${K_RESET}"
        echo -e "  ${K_ZIELONY}[6]${K_RESET} 🌐 Sprawdź certyfikaty domen (SSL)      ${K_SZARY}(06_ssl_domain_inspector.py)${K_RESET}"
        echo ""
        echo -e "  ${K_ZOLTY}[7]${K_RESET} 📅 Pokaż kalendarz publikacji na ten tydzień"
        echo -e "  ${K_CZERWONY}[0]${K_RESET} 🚪 Wyjście z programu"
        echo ""
        read -rp "Twój wybór [0-7]: " wybor

        case "$wybor" in
            1)
                echo ""
                "$SKRYPTY_DIR/01_system_health_reporter.sh" || true
                echo ""
                read -rp "Naciśnij [Enter], aby wrócić do menu..." _
                ;;
            2)
                echo ""
                echo -e "${K_CYJAN}[?] Podaj katalog do zbackupowania (np. /home/dariusz):${K_RESET}"
                read -rp "Katalog źródłowy: " zrodlo
                if [[ -z "$zrodlo" || ! -d "$zrodlo" ]]; then
                    echo -e "${K_CZERWONY}[!] Wskazany katalog nie istnieje.${K_RESET}"
                else
                    echo -e "${K_CYJAN}[?] Gdzie zapisać kopię? (domyślnie: /tmp/kopie_test):${K_RESET}"
                    read -rp "Katalog docelowy [/tmp/kopie_test]: " cel
                    cel="${cel:-/tmp/kopie_test}"
                    "$SKRYPTY_DIR/02_backup_rotator.sh" -s "$zrodlo" -d "$cel" -k 5
                fi
                echo ""
                read -rp "Naciśnij [Enter], aby wrócić do menu..." _
                ;;
            3)
                echo ""
                if [[ $EUID -ne 0 ]]; then
                    echo -e "${K_ZOLTY}[!] Audyt SSH najlepiej działa z uprawnieniami administratora.${K_RESET}"
                    echo -e "Uruchamiam w trybie audytu (jeśli zapyta o hasło, podaj hasło sudo):"
                    sudo "$SKRYPTY_DIR/03_ssh_security_audit.sh" || true
                else
                    "$SKRYPTY_DIR/03_ssh_security_audit.sh" || true
                fi
                echo ""
                read -rp "Naciśnij [Enter], aby wrócić do menu..." _
                ;;
            4)
                echo ""
                echo -e "${K_CYJAN}Uruchamianie analizatora logów SSH...${K_RESET}"
                if [[ $EUID -ne 0 ]]; then
                    sudo python3 "$SKRYPTY_DIR/04_auth_log_sentinel.py" || true
                else
                    python3 "$SKRYPTY_DIR/04_auth_log_sentinel.py" || true
                fi
                echo ""
                read -rp "Naciśnij [Enter], aby wrócić do menu..." _
                ;;
            5)
                echo ""
                echo -e "${K_CYJAN}Uruchamianie audytu zasobów Dockera (symulacja --dry-run)...${K_RESET}"
                "$SKRYPTY_DIR/05_docker_host_cleaner.sh" --dry-run || true
                echo ""
                read -rp "Naciśnij [Enter], aby wrócić do menu..." _
                ;;
            6)
                echo ""
                read -rp "Podaj domeny do sprawdzenia (np. google.com kul.pl): " domeny
                domeny="${domeny:-google.com github.com kul.pl}"
                python3 "$SKRYPTY_DIR/06_ssl_domain_inspector.py" $domeny || true
                echo ""
                read -rp "Naciśnij [Enter], aby wrócić do menu..." _
                ;;
            7)
                echo ""
                if [[ -f "$KALENDARZ_PLIK" ]]; then
                    echo -e "${K_POGRUBIENIE}Zawartość kalendarza publikacji:${K_RESET}"
                    echo "----------------------------------------------------------------"
                    head -n 45 "$KALENDARZ_PLIK"
                    echo "----------------------------------------------------------------"
                    echo -e "${K_SZARY}(Pełny plik znajduje się w: $KALENDARZ_PLIK)${K_RESET}"
                fi
                echo ""
                read -rp "Naciśnij [Enter], aby wrócić do menu..." _
                ;;
            0)
                echo -e "${K_ZIELONY}Do zobaczenia! Powodzenia w rozwijaniu portfolio!${K_RESET}"
                exit 0
                ;;
            *)
                echo -e "${K_CZERWONY}Nieprawidłowy wybór. Spróbuj ponownie.${K_RESET}"
                sleep 1
                ;;
        esac
    done
}

menu_glowne
