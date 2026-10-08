# 📅 Plan Publikacji Skryptów Administracyjnych (Portfolio Roadmap)

> **Cel:** Regularne budowanie wizerunku inżyniera Linuksa / DevOps / SecOps na GitHubie i LinkedInie poprzez publikowanie **1–2 dopracowanych skryptów tygodniowo**.

---

## 🧭 Jak publikować, żeby wyciągnąć maksimum korzyści?

1. **Jeden lub dwa skrypty w tygodniu:**
   - Nie wrzucaj wszystkiego naraz w jednym commicie. Rekruterzy i algorytmy cenią regularność (zielony wykres aktywności na GitHubie + stała obecność na feedzie LinkedIn).
2. **Format commita:**
   - Stosuj czytelne konwencje, np. Conventional Commits: `feat(monitoring): add system health audit script with JSON/HTML export`.
3. **Post na LinkedIn:**
   - Nie pisz "napisałem skrypt". Pisz o **problemie biznesowym**, **sposobie rozwiązania** i **czego się nauczyłeś** (poniżej masz gotowe szablony!).
   - Do każdego posta dołącz zrzut ekranu z ładnym kolorowym wyjściem z terminala (to przyciąga wzrok rekruterów).

---

## 🗓️ Tydzień 1: Monitoring i Automatyzacja Kopii Zapasowych

### 🔹 Dzień 1 (Wtorek): `01_system_health_reporter.sh`
* **Temat:** Kompleksowy skrypt monitoringu stanu systemu z obsługą alertów i eksportu do JSON/HTML.
* **Gotowy post na LinkedIn:**
  ```text
  Jednym z kluczowych zadań administratora jest szybka diagnoza hosta w momencie awarii lub rutynowej kontroli. Zamiast ręcznie klepać 'top', 'df -h', 'free -m' i 'ss -tulpn', stworzyłem narzędzie konsolowe w Bashu: System Health Reporter.

  Co potrafi skrypt?
  ✅ Monitoruje CPU, RAM (z progami alertów), dyski i stan kluczowych usług systemd.
  ✅ Sprawdza otwarte porty oraz próby ataków brute-force na SSH w ciągu ostatnich 24h.
  ✅ Posiada tryb JSON i HTML – idealny pod automatyzację w cronie lub integrację z dashboardem.
  ✅ Spełnia zasady defensywnego Basha (set -euo pipefail, czytelne kody powrotu).

  Kod i dokumentacja: [link do Twojego GitHuba]
  #Linux #SysAdmin #Bash #DevOps #Monitoring #OpenSource
  ```

### 🔹 Dzień 2 (Piątek): `02_backup_rotator.sh`
* **Temat:** Produkcyjny skrypt backupu katalogów z rotacją kopii, sumami SHA-256 i symulacją dry-run.
* **Gotowy post na LinkedIn:**
  ```text
  "Kopia zapasowa bez weryfikacji to tylko nadzieja, a nie backup." 

  W ramach mojego repozytorium narzędzi administracyjnych dodałem silnik do zarządzania kopiami zapasowymi z automatyczną retencją (FIFO).

  Dlaczego warto unikać zwykłego prostego skryptu z crona na rzecz dedykowanego narzędzia?
  🔒 Spójność: Skrypt automatycznie generuje i weryfikuje sumy kontrolne SHA-256 każdego archiwum.
  🧹 Porządek: Polityka retencji (--keep N) automatycznie usuwa przeterminowane archiwa, zapobiegając przepełnieniu dysku.
  🧪 Bezpieczeństwo: Tryb --dry-run pozwala przetestować reguły wykluczeń i rotację bez dotykania plików na produkcji.
  🛑 Blokady: Mechanizm lock-file chroni przed kolizją nakładających się procesów backupu.

  Repozytorium: [link do GitHuba]
  #Backup #Linux #DevOps #DataIntegrity #BashScripting
  ```

---

## 🗓️ Tydzień 2: Bezpieczeństwo Systemu & Analiza Incydentów (SecOps)

### 🔹 Dzień 1 (Wtorek): `03_ssh_security_audit.sh`
* **Temat:** Audyt zgodności konfiguracji OpenSSH z wyliczaniem wskaźnika bezpieczeństwa (0-100%) i bezpiecznym hardeningiem.
* **Gotowy post na LinkedIn:**
  ```text
  Niezabezpieczona usługa SSH to otwarte drzwi dla botnetów. Zbudowałem audytor konfiguracji sshd weryfikujący zgodność z zaleceniami CIS Benchmark.

  Co wyróżnia to narzędzie?
  📊 Wylicza procentowy wskaźnik bezpieczeństwa konfiguracji serwera (Security Score).
  🛡️ Bezpieczne utwardzanie: potrafi wygenerować konfigurację drop-in wyłączającą logowanie hasłem i roota.
  🚨 Ochrona przed lock-outem: przed jakimkolwiek restartem usługi wykonuje test składni 'sshd -t'. Jeśli test zawiedzie, skrypt automatycznie cofa zmiany, chroniąc administratora przed utratą dostępu zdalnego!

  Kod źródłowy: [link do GitHuba]
  #Cybersecurity #SSH #LinuxSecurity #Hardening #SysAdmin
  ```

### 🔹 Dzień 2 (Piątek): `04_auth_log_sentinel.py`
* **Temat:** Analizator logów uwierzytelniania w Pythonie, detektor ataków brute-force i automatyczne generowanie reguł UFW/iptables.
* **Gotowy post na LinkedIn:**
  ```text
  Ile prób nieautoryzowanego logowania przyjmuje Twój serwer każdego dnia?

  Napisałem w Pythonie narzędzie Sentinel do analizy logów auth.log i journald. Skrypt:
  🔍 Wykrywa skoordynowane ataki brute-force na SSH według konfigurowalnego progu prób.
  🗺️ Pozwala na geolokalizację złośliwych adresów IP i agreguje najczęściej atakowane nazwy użytkowników.
  🚫 Generuje gotowy, bezpieczny skrypt blokujący napastników w zaporze sieciowej (UFW / iptables).
  ⚡ Działa w oparciu o czystą bibliotekę standardową Pythona – zero zewnętrznych zależności (pip), działa od razu na każdym środowisku.

  Sprawdź projekt na GitHubie: [link do GitHuba]
  #Python #Cybersecurity #SOC #IncidentResponse #ThreatHunting
  ```

---

## 🗓️ Tydzień 3: Konteneryzacja & Badanie Domen

### 🔹 Dzień 1 (Wtorek): `05_docker_host_cleaner.sh`
* **Temat:** Zarządzanie pamięcią dyskową hosta Dockera, czyszczenie nieużywanych wolumenów i pamięci cache.
* **Gotowy post na LinkedIn:**
  ```text
  Każdy, kto wdraża kontenery na VPS-ie wie, jak szybko gromadzą się wiszące obrazy (<none>), stare build-cache i osierocone wolumeny.

  Stworzyłem skrypt do inteligentnego audytu i czyszczenia środowiska Dockera:
  - W trybie --dry-run raportuje dokładną ilość gigabajtów możliwych do odzyskania.
  - Posiada bezpieczny tryb interaktywny z potwierdzeniem oraz flagę --force pod zadania cykliczne.
  - Wyraźnie rozdziela czyszczenie bezpiecznych obrazów od wolumenów danych, zapobiegając przypadkowej utracie danych aplikacji.

  Repozytorium: [link do GitHuba]
  #Docker #DevOps #Containers #Linux #CleanCode
  ```

### 🔹 Dzień 2 (Piątek): `06_ssl_domain_inspector.py`
* **Temat:** Monitor wygasania certyfikatów SSL/TLS i bezpieczeństwa protokołów w Pythonie.
* **Gotowy post na LinkedIn:**
  ```text
  Wygaśnięcie certyfikatu SSL na produkcji to jeden z najbardziej wstydliwych, a jednocześnie częstych incydentów w IT.

  Napisałem szybkie narzędzie w Pythonie sprawdzające stan certyfikatów dla listy domen:
  🔐 Odpytuje gniazda TLS o stan certyfikatu X.509, datę ważności, wystawcę oraz wersję protokołu (TLSv1.2 vs TLSv1.3).
  ⏱️ Wylicza pozostałe dni i alarmuje z kodem wyjścia 1, jeśli termin ważności zbliża się do krytycznego progu.
  📦 Eksportuje dane do formatu JSON pod integrację z powiadomieniami na Slacka lub Discorda.

  Link do repozytorium: [link do GitHuba]
  #Networking #TLS #SSL #Python #WebSecurity #DevOps
  ```

---

## 🔮 Pomysły na kolejne tygodnie (Tygodnie 4–6)

Gdy wrzucisz powyższe 6 skryptów, oto lista kolejnych narzędzi do dopisania:
1. **`07_network_port_sentinel.sh`** – monitorowanie zmian w otwartych portach sieciowych na serwerze (alertowanie gdy pojawi się nowa nasłuchująca usługa).
2. **`08_database_dump_vault.sh`** – skrypt wykonujący automatyczny zrzut bazy MySQL/PostgreSQL, szyfrujący go kluczem GPG i wysyłający na zewnętrzny storage S3/SFTP.
3. **`09_wireguard_peer_manager.sh`** – automatyzacja dodawania nowych użytkowników VPN z generowaniem kodów QR i konfiguracji klientów.
4. **`10_nginx_rate_limit_auditor.py`** – analiza logów dostępowych Nginx pod kątem botów zgłaszających zbyt wiele zapytań na sekundę (DDoS / scrapery).
