# 🛠️ Zestaw Narzędzi Administracyjnych i Bezpieczeństwa Linux (`sysadmin-toolkit`)

[![Bash](https://img.shields.io/badge/Język-Bash_5.0+-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Python](https://img.shields.io/badge/Język-Python_3.8+-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Platforma](https://img.shields.io/badge/Platforma-Linux-FCC624?logo=linux&logoColor=black)](https://kernel.org)
[![Licencja: MIT](https://img.shields.io/badge/Licencja-MIT-blue.svg)](LICENSE)

Profesjonalny pakiet gotowych skryptów automatyzacyjnych, diagnostycznych i bezpieczeństwa dla administratorów systemów Linux, inżynierów DevOps i analityków cyberbezpieczeństwa (SOC / Blue Team).

Zaprojektowany z naciskiem na **niezawodność i prostotę**:
- 🛡️ **Zero zewnętrznych zależności** (Python działa w oparciu o czystą bibliotekę standardową bez potrzeby instalacji pakietów przez `pip`).
- 🇵🇱 **Pełne spolszczenie** komunikatów, menu pomocy (`--help`) oraz prostych komentarzy w kodzie.
- 🧪 **Bezpieczne testowanie (`--dry-run`)** tam, gdzie skrypt modyfikuje pliki lub zasoby.
- 🎛️ **Interaktywne Centrum Dowodzenia (`./zarzadzaj.sh`)** – możliwość uruchomienia każdego narzędzia z wygodnego menu.

---

## 🧭 Centrum Dowodzenia (`zarzadzaj.sh`)

Możesz zarządzać całym zestawem za pomocą jednego interaktywnego polecenia:

```bash
cd sysadmin-toolkit
./zarzadzaj.sh
```

W terminalu pojawi się menu wyboru:
```text
  [1] 🩺 Sprawdź stan serwera i telemetrię    (01_system_health_reporter.sh)
  [2] 💾 Wykonaj bezpieczną kopię (Backup)    (02_backup_rotator.sh)
  [3] 🛡️ Audyt bezpieczeństwa usługi SSH       (03_ssh_security_audit.sh)
  [4] 🚨 Wykryj próby włamań SSH (Brute-Force) (04_auth_log_sentinel.py)
  [5] 🐳 Posprzątaj i zoptymalizuj Dockera    (05_docker_host_cleaner.sh)
  [6] 🌐 Sprawdź certyfikaty domen (SSL)      (06_ssl_domain_inspector.py)
  [7] 📅 Pokaż kalendarz publikacji na ten tydzień
  [0] 🚪 Wyjście z programu
```

---

## 📂 Spis Skryptów i Przykłady Użycia

### 1. `01_system_health_reporter.sh` — Szybka diagnoza serwera
Kompleksowy audyt zasobów hosta (procesor, pamięć RAM, zajętość dysków, kluczowe usługi systemd, otwarte porty i sesje użytkowników).
```bash
# Standardowy raport w konsoli
./scripts/01_system_health_reporter.sh

# Własne progi ostrzeżeń i eksport do HTML
./scripts/01_system_health_reporter.sh --warn 75 --crit 85 --html raport.html

# Format JSON (idealny do integracji z API lub cronem)
./scripts/01_system_health_reporter.sh --json
```

---

### 2. `02_backup_rotator.sh` — Automatyczny backup z rotacją (retencją)
Pakuje wskazany katalog do archiwum `tar.gz` (lub `tar.zst`), generuje sumę kontrolną SHA-256 i usuwa najstarsze kopie, dbając o wolne miejsce na dysku.
```bash
# Bezpieczna symulacja (podgląd co zostałoby spakowane/usunięte)
./scripts/02_backup_rotator.sh -s /var/www/html -d /kopie --dry-run

# Prawdziwy backup: zachowaj ostatnie 14 kopii i wyklucz foldery cache
./scripts/02_backup_rotator.sh -s /opt/aplikacja -d /kopie -p app -k 14 -e "cache" -e ".git"
```

---

### 3. `03_ssh_security_audit.sh` — Audyt i utwardzanie serwera SSH
Sprawdza ustawienia OpenSSH pod kątem wytycznych CIS Benchmarks, liczy procentowy wskaźnik bezpieczeństwa (0–100%) i umożliwia bezpieczne wdrożenie poprawek z ochroną przed zablokowaniem dostępu (test `sshd -t`).
```bash
# Audyt z oceną punktową (read-only)
sudo ./scripts/03_ssh_security_audit.sh

# Symulacja utwardzania (podgląd wpisów)
./scripts/03_ssh_security_audit.sh --harden --dry-run

# Wdrożenie bezpiecznych ustawień
sudo ./scripts/03_ssh_security_audit.sh --harden
```

---

### 4. `04_auth_log_sentinel.py` — Detekcja ataków brute-force na SSH
Analizuje logi systemowe (`/var/log/auth.log` lub `journalctl`), namierza złośliwe adresy IP, geolokalizuje je i potrafi wygenerować gotowy skrypt blokujący w zaporze sieciowej (UFW / iptables).
```bash
# Analiza logów z progiem 5 nieudanych logowań
./scripts/04_auth_log_sentinel.py --threshold 5

# Geolokalizacja IP i wygenerowanie gotowego skryptu blokującego w UFW
./scripts/04_auth_log_sentinel.py --geoip --block-script zablokuj_atakujacych.sh
```

---

### 5. `05_docker_host_cleaner.sh` — Bezpieczne czyszczenie Dockera
Bada przestrzeń dyskową zajmowaną przez Dockera, znajduje zatrzymane kontenery, wiszące obrazy (`<none>`), osierocone wolumeny oraz build cache.
```bash
# Sprawdzenie ile GB można odzyskać bez usuwania czegokolwiek
./scripts/05_docker_host_cleaner.sh --dry-run

# Standardowe czyszczenie z pytaniem o potwierdzenie
./scripts/05_docker_host_cleaner.sh

# Automatyczne czyszczenie w cronie
./scripts/05_docker_host_cleaner.sh --force
```

---

### 6. `06_ssl_domain_inspector.py` — Badanie certyfikatów SSL/TLS
Bada datę wygaśnięcia certyfikatów na serwerach WWW, wersję protokołu TLS (v1.2/v1.3), wystawcę (CA) i informuje o zbliżającym się końcu ważności.
```bash
# Sprawdzenie kilku domen w konsoli
./scripts/06_ssl_domain_inspector.py google.com github.com kul.pl

# Ostrzegaj jeśli do wygaśnięcia zostało mniej niż 20 dni
./scripts/06_ssl_domain_inspector.py -f lista_domen.txt --warn-days 20
```

---

## 📅 Harmonogram Publikacji w Portfolio
Szczegółowy plan wrzucania po 1–2 skryptów tygodniowo na GitHub i LinkedIn wraz z **gotowymi szablonami postów** znajdziesz w pliku:  
👉 [`PUBLICATION_CALENDAR.md`](PUBLICATION_CALENDAR.md)

---

## 👤 Autor
**Dariusz Kisiel**  
- Portfolio: [xBestia2004.github.io](https://xbestia2004.github.io)  
- GitHub: [@xBestia2004](https://github.com/xBestia2004)  
- Specjalizacja: Administracja Linux | Sieci komputerowe | Cyberbezpieczeństwo | DevOps
