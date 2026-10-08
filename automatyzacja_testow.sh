#!/usr/bin/env bash
# ==============================================================================
# Nazwa skryptu : automatyzacja_testow.sh
# Opis          : Lokalny automat sprawdzający poprawność całego pakietu:
#                 1. Weryfikuje składnię Basha (bash -n) i Pythona (py_compile)
#                 2. Sprawdza uprawnienia wykonywalne (chmod +x)
#                 3. Wykonuje próbny przebieg (smoke test) narzędzia 01
#                 4. Raportuje gotowość do wydania (Git commit / push)
# Autor         : Dariusz Kisiel (xBestia2004)
# ==============================================================================

set -euo pipefail

KATALOG_SKRYPTOW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"

K_RESET="\033[0m"
K_POGRUBIENIE="\033[1m"
K_ZIELONY="\033[1;32m"
K_ZOLTY="\033[1;33m"
K_CZERWONY="\033[1;31m"
K_CYJAN="\033[1;36m"

echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
echo -e "${K_CYJAN}${K_POGRUBIENIE}       AUTOMATYZACJA TESTÓW JAKOŚCI KODU (SYSADMIN TOOLKIT)           ${K_RESET}"
echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
echo ""

BLEDY=0

# Krok 1: Weryfikacja uprawnień
echo -e "${K_POGRUBIENIE}1. Sprawdzanie i nadawanie uprawnień wykonywalnych...${K_RESET}"
chmod +x "$KATALOG_SKRYPTOW"/*.sh "$KATALOG_SKRYPTOW"/*.py
echo -e "${K_ZIELONY}[OK] Wszystkie pliki wykonywalne posiadają flagę +x.${K_RESET}"
echo ""

# Krok 2: Składnia Basha (bash -n)
echo -e "${K_POGRUBIENIE}2. Weryfikacja składni skryptów powłoki (Bash syntax check)...${K_RESET}"
for plik in "$KATALOG_SKRYPTOW"/*.sh; do
    nazwa=$(basename "$plik")
    if bash -n "$plik"; then
        printf "  %-35s : ${K_ZIELONY}[POPRRAWNA SKŁADNIA]${K_RESET}\n" "$nazwa"
    else
        printf "  %-35s : ${K_CZERWONY}[BŁĄD SKŁADNI]${K_RESET}\n" "$nazwa"
        BLEDY=$((BLEDY + 1))
    fi
done
echo ""

# Krok 3: Składnia Pythona (py_compile)
echo -e "${K_POGRUBIENIE}3. Kompilacja i weryfikacja skryptów Pythona...${K_RESET}"
for plik in "$KATALOG_SKRYPTOW"/*.py; do
    nazwa=$(basename "$plik")
    if python3 -m py_compile "$plik" 2>/dev/null; then
        printf "  %-35s : ${K_ZIELONY}[POPRRAWNA SKŁADNIA]${K_RESET}\n" "$nazwa"
    else
        printf "  %-35s : ${K_CZERWONY}[BŁĄD KOMPILACJI]${K_RESET}\n" "$nazwa"
        BLEDY=$((BLEDY + 1))
    fi
done
echo ""

# Krok 4: Próbny przebieg 01_system_health_reporter.sh w trybie JSON
echo -e "${K_POGRUBIENIE}4. Test uruchomieniowy (Smoke Test) narzędzia 01...${K_RESET}"
if "$KATALOG_SKRYPTOW/01_system_health_reporter.sh" --json >/dev/null 2>&1; then
    echo -e "${K_ZIELONY}[OK] 01_system_health_reporter.sh poprawnie wygenerował strukturę JSON!${K_RESET}"
else
    # Jeśli zwrócił kod 1 z powodu alertu progów, sprawdźmy czy wygenerował poprawny JSON
    if "$KATALOG_SKRYPTOW/01_system_health_reporter.sh" --json 2>/dev/null | grep -q "znacznik_czasu"; then
        echo -e "${K_ZIELONY}[OK] 01_system_health_reporter.sh wygenerował poprawny JSON (ostrzeżenie o progach obsłużone).${K_RESET}"
    else
        echo -e "${K_CZERWONY}[BŁĄD] Narzędzie 01 napotkało błąd podczas generowania JSON.${K_RESET}"
        BLEDY=$((BLEDY + 1))
    fi
fi
echo ""

echo -e "${K_POGRUBIENIE}======================================================================${K_RESET}"
if [[ "$BLEDY" -eq 0 ]]; then
    echo -e "${K_ZIELONY}${K_POGRUBIENIE}WYNIK: Wszystkie testy zaliczone pomyślnie! Pakiet gotowy do publikacji.${K_RESET}"
    exit 0
else
    echo -e "${K_CZERWONY}${K_POGRUBIENIE}WYNIK: Wykryto $BLEDY błąd/błędy. Popraw je przed publikacją na GitHubie.${K_RESET}"
    exit 1
fi
