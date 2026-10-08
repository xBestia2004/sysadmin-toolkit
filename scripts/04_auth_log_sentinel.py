#!/usr/bin/env python3
"""
Nazwa skryptu : 04_auth_log_sentinel.py
Opis          : Strażnik logów i wykrywacz ataków brute-force na serwer SSH.
                Parsuje pliki auth.log / secure lub dane z polecenia journalctl,
                wykrywa adresy IP przeprowadzające zmasowane próby logowania,
                agreguje atakowane konta i generuje gotowy skrypt blokujący w zaporze UFW.
Autor         : Dariusz Kisiel (xBestia2004)
Licencja      : MIT
Wymagania     : Python 3.8+ (Wyłącznie moduły wbudowane - brak zewnętrznych bibliotek pip)
"""

import argparse
import collections
import json
import os
import re
import subprocess
import sys
import urllib.request
from typing import Dict, List, Optional

WERSJA = "1.2.0"

# Kolory do wyświetlania w terminalu
class Kolory:
    RESET = "\033[0m"
    POGRUBIENIE = "\033[1m"
    SZARY = "\033[2m"
    CZERWONY = "\033[1;31m"
    ZIELONY = "\033[1;32m"
    ZOLTY = "\033[1;33m"
    CYJAN = "\033[1;36m"

# Wyrażenia regularne (regex) do wyłapywania zdarzeń SSH w logach
# Przykłady linii:
# Failed password for invalid user admin from 192.168.1.50 port 54321 ssh2
# Failed password for root from 10.0.0.1 port 22 ssh2
# Invalid user test from 1.2.3.4
WZRORZEC_BLAD_HASLA = re.compile(
    r"Failed password for (?:invalid user )?(?P<user>\S+) from (?P<ip>\d{1,3}(?:\.\d{1,3}){3})"
)
WZORZEC_ZLY_UZYTKOWNIK = re.compile(
    r"Invalid user (?P<user>\S+) from (?P<ip>\d{1,3}(?:\.\d{1,3}){3})"
)
WZORZEC_POPRAWNE_LOGOWANIE = re.compile(
    r"Accepted (?:password|publickey) for (?P<user>\S+) from (?P<ip>\d{1,3}(?:\.\d{1,3}){3})"
)


def pobierz_linie_logu(wskazana_sciezka: Optional[str]) -> List[str]:
    """Odczytuje linie z pliku wskazanego przez użytkownika lub z dziennika systemd."""
    # 1. Jeśli użytkownik podał plik parametrem -f
    if wskazana_sciezka:
        if not os.path.isfile(wskazana_sciezka):
            print(f"{Kolory.CZERWONY}[BŁĄD] Wskazany plik nie istnieje: '{wskazana_sciezka}'{Kolory.RESET}", file=sys.stderr)
            sys.exit(1)
        try:
            with open(wskazana_sciezka, "r", encoding="utf-8", errors="replace") as f:
                return f.readlines()
        except PermissionError:
            print(f"{Kolory.ZOLTY}[!] Brak uprawnień do odczytu pliku '{wskazana_sciezka}'. Uruchom z sudo.{Kolory.RESET}", file=sys.stderr)
            sys.exit(1)

    # 2. Przeszukaj standardowe lokalizacje logów na Debianie/Ubuntu lub RHEL/CentOS
    for sciezka in ["/var/log/auth.log", "/var/log/secure"]:
        if os.path.isfile(sciezka) and os.access(sciezka, os.R_OK):
            with open(sciezka, "r", encoding="utf-8", errors="replace") as f:
                return f.readlines()

    # 3. Zapasowo: spróbuj pobrać ostatnie wpisy przez journalctl (dla systemów bez rsyslog)
    try:
        proces = subprocess.run(
            ["journalctl", "-u", "ssh", "-u", "sshd", "--no-pager", "-n", "10000"],
            capture_output=True,
            text=True,
            check=False
        )
        if proces.returncode == 0 and proces.stdout.strip():
            return proces.stdout.splitlines()
    except FileNotFoundError:
        pass

    return []


def sprawdz_kraj_ip(ip: str) -> str:
    """Sprawdza kraj pochodzenia adresu IP przez darmowe publiczne API (bez bibliotek zewnętrznych)."""
    # Adresy prywatne (lokalne sieci LAN) pomijamy
    if ip.startswith(("10.", "172.16.", "192.168.", "127.")):
        return "Sieć lokalna (LAN)"
    try:
        url = f"http://ip-api.com/json/{ip}?fields=country,isp,status"
        zapytanie = urllib.request.Request(url, headers={"User-Agent": "Sentinel-PL/1.0"})
        with urllib.request.urlopen(zapytanie, timeout=1.5) as odp:
            dane = json.loads(odp.read().decode())
            if dane.get("status") == "success":
                kraj = dane.get("country", "Nieznany")
                dostawca = dane.get("isp", "Nieznany")
                return f"{kraj} ({dostawca})"
    except Exception:
        pass
    return "Brak danych"


def analizuj_logi(linie: List[str], prog_atakow: int):
    """Przetwarza linie logów i zlicza nieudane próby logowania."""
    nieudane_wg_ip = collections.defaultdict(int)
    uzytkownicy_wg_ip = collections.defaultdict(set)
    licznik_uzytkownikow = collections.defaultdict(int)
    poprawne_logowania = collections.defaultdict(list)

    for linia in linie:
        # Sprawdzamy czy to nieudane logowanie
        dopasowanie_blad = WZRORZEC_BLAD_HASLA.search(linia)
        if dopasowanie_blad:
            ip = dopasowanie_blad.group("ip")
            uzytkownik = dopasowanie_blad.group("user")
            nieudane_wg_ip[ip] += 1
            uzytkownicy_wg_ip[ip].add(uzytkownik)
            licznik_uzytkownikow[uzytkownik] += 1
            continue

        # Sprawdzamy próbę logowania na nieistniejące konto
        dopasowanie_zly = WZORZEC_ZLY_UZYTKOWNIK.search(linia)
        if dopasowanie_zly:
            ip = dopasowanie_zly.group("ip")
            uzytkownik = dopasowanie_zly.group("user")
            nieudane_wg_ip[ip] += 1
            uzytkownicy_wg_ip[ip].add(uzytkownik)
            licznik_uzytkownikow[uzytkownik] += 1
            continue

        # Sprawdzamy poprawne logowanie
        dopasowanie_ok = WZORZEC_POPRAWNE_LOGOWANIE.search(linia)
        if dopasowanie_ok:
            ip = dopasowanie_ok.group("ip")
            uzytkownik = dopasowanie_ok.group("user")
            poprawne_logowania[uzytkownik].append(ip)

    # Wybieramy tylko te adresy IP, które przekroczyły próg
    zlosliwe_ip = {
        ip: liczba for ip, liczba in nieudane_wg_ip.items()
        if liczba >= prog_atakow
    }

    return {
        "nieudane_wg_ip": nieudane_wg_ip,
        "uzytkownicy_wg_ip": uzytkownicy_wg_ip,
        "licznik_uzytkownikow": licznik_uzytkownikow,
        "poprawne_logowania": poprawne_logowania,
        "zlosliwe_ip": zlosliwe_ip,
        "lacznie_nieudanych": sum(nieudane_wg_ip.values())
    }


def main():
    parser = argparse.ArgumentParser(
        description="Strażnik logów SSH i wykrywacz ataków brute-force",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Przykłady użycia:
  %(prog)s
  %(prog)s -f /var/log/auth.log --threshold 10
  %(prog)s --geoip --block-script zablokuj_atakujacych.sh
  %(prog)s --json
        """
    )
    parser.add_argument("-f", "--file", help="Ścieżka do analizowanego pliku logów (np. /var/log/auth.log)")
    parser.add_argument("-t", "--threshold", type=int, default=5, help="Minimalna liczba błędów, by uznać IP za napastnika (domyślnie: 5)")
    parser.add_argument("-g", "--geoip", action="store_true", help="Pobierz kraj pochodzenia i dostawcę internetu dla podejrzanych IP")
    parser.add_argument("-b", "--block-script", help="Utwórz gotowy skrypt powłoki z regułami blokującymi w zaporze UFW/iptables")
    parser.add_argument("-j", "--json", action="store_true", help="Wypisz wynik w formacie maszynowym JSON")
    parser.add_argument("-v", "--version", action="version", version=f"%(prog)s {WERSJA}")

    args = parser.parse_args()

    linie = pobierz_linie_logu(args.file)
    if not linie:
        print(f"{Kolory.ZOLTY}[!] Brak wpisów w logach lub brak uprawnień do plików systemowych.{Kolory.RESET}", file=sys.stderr)
        print(f"[i] Wskazówka: Uruchom skrypt z prawami administratora: sudo {sys.argv[0]}", file=sys.stderr)
        sys.exit(0)

    wyniki = analizuj_logi(linie, args.threshold)
    zlosliwe_ip = wyniki["zlosliwe_ip"]
    licznik_uzytkownikow = wyniki["licznik_uzytkownikow"]

    # Opcjonalne pobieranie geolokalizacji
    mapa_geoip = {}
    if args.geoip:
        for ip in sorted(zlosliwe_ip.keys(), key=lambda x: zlosliwe_ip[x], reverse=True)[:15]:
            mapa_geoip[ip] = sprawdz_kraj_ip(ip)

    # Tryb JSON
    if args.json:
        dane_json = {
            "wersja": WERSJA,
            "prog_atakow": args.threshold,
            "lacznie_nieudanych_logowan": wyniki["lacznie_nieudanych"],
            "liczba_zlosliwych_ip": len(zlosliwe_ip),
            "wykryte_zagrozenia": [
                {
                    "ip": ip,
                    "liczba_prob": liczba,
                    "atakowane_konta": list(wyniki["uzytkownicy_wg_ip"][ip]),
                    "geolokalizacja": mapa_geoip.get(ip, "Brak")
                }
                for ip, liczba in sorted(zlosliwe_ip.items(), key=lambda x: x[1], reverse=True)
            ],
            "najczesciej_atakowane_konta": dict(
                sorted(licznik_uzytkownikow.items(), key=lambda x: x[1], reverse=True)[:10]
            )
        }
        print(json.dumps(dane_json, indent=2, ensure_ascii=False))
        return

    # Czytelne wyjście w terminalu
    print(f"{Kolory.POGRUBIENIE}======================================================================{Kolory.RESET}")
    print(f"{Kolory.CYJAN}{Kolory.POGRUBIENIE}          STRAŻNIK LOGÓW SSH I WYKRYWACZ BRUTE-FORCE                  {Kolory.RESET}")
    print(f"{Kolory.POGRUBIENIE}======================================================================{Kolory.RESET}")
    print(f" Przeanalizowane linie logu : {len(linie)}")
    kolor_prob = Kolory.CZERWONY if wyniki['lacznie_nieudanych'] > 0 else Kolory.ZIELONY
    print(f" Nieudane próby logowania   : {kolor_prob}{wyniki['lacznie_nieudanych']}{Kolory.RESET}")
    print(f" Próg kwalifikacji do ataku : >= {args.threshold} nieudanych prób z jednego IP")
    print(f" Zidentyfikowane złośliwe IP: {len(zlosliwe_ip)}")
    print("")

    # Tabela złośliwych adresów IP
    print(f"{Kolory.POGRUBIENIE}─── Podejrzane Adresy IP (Ataki Brute-Force) ────────────────────────{Kolory.RESET}")
    if not zlosliwe_ip:
        print(f"  {Kolory.ZIELONY}[✓] Żaden adres IP nie przekroczył progu {args.threshold} nieudanych prób logowania.{Kolory.RESET}")
    else:
        print(f"  {'ADRES IP':<18} {'PRÓBY':<10} {'ATAKOWANE KONTA':<25} {'GEOLOKALIZACJA'}")
        print("  " + "-" * 75)
        for ip, liczba in sorted(zlosliwe_ip.items(), key=lambda x: x[1], reverse=True)[:15]:
            konta = ", ".join(list(wyniki["uzytkownicy_wg_ip"][ip])[:3])
            if len(wyniki["uzytkownicy_wg_ip"][ip]) > 3:
                konta += "..."
            geo = mapa_geoip.get(ip, "")
            print(f"  {Kolory.CZERWONY}{ip:<18}{Kolory.RESET} {liczba:<10} {konta:<25} {geo}")

    print("")

    # Najczęściej atakowane loginy
    print(f"{Kolory.POGRUBIENIE}─── Najczęściej Celowane Nazwy Użytkowników ─────────────────────────{Kolory.RESET}")
    if not licznik_uzytkownikow:
        print(f"  {Kolory.SZARY}Brak zarejestrowanych prób.{Kolory.SZARY}")
    else:
        for uzytkownik, liczba in sorted(licznik_uzytkownikow.items(), key=lambda x: x[1], reverse=True)[:8]:
            print(f"  {Kolory.ZOLTY}{uzytkownik:<18}{Kolory.RESET} : {liczba} prób(y)")

    print("")

    # Zarejestrowane poprawne logowania
    print(f"{Kolory.POGRUBIENIE}─── Zweryfikowane Prawidłowe Logowania (Sukces) ─────────────────────{Kolory.RESET}")
    if not wyniki["poprawne_logowania"]:
        print(f"  {Kolory.SZARY}W badanym okresie nie odnotowano poprawnych logowań.{Kolory.RESET}")
    else:
        for uzytkownik, adresy in wyniki["poprawne_logowania"].items():
            unikalne_ip = ", ".join(set(adresy))
            print(f"  {Kolory.ZIELONY}{uzytkownik:<18}{Kolory.RESET} : {len(adresy)} udanych sesji z adresu/ów: {unikalne_ip}")

    print(f"{Kolory.POGRUBIENIE}======================================================================{Kolory.RESET}")

    # Generowanie gotowego skryptu blokującego w zaporze sieciowej
    if args.block_script and zlosliwe_ip:
        with open(args.block_script, "w", encoding="utf-8") as plik_blokady:
            plik_blokady.write("#!/bin/bash\n")
            plik_blokady.write("# Skrypt wygenerowany automatycznie przez 04_auth_log_sentinel.py\n")
            plik_blokady.write("# Blokowanie napastników w zaporze sieciowej UFW / iptables\n")
            plik_blokady.write("set -e\n\n")
            for ip in sorted(zlosliwe_ip.keys(), key=lambda x: zlosliwe_ip[x], reverse=True):
                plik_blokady.write(f"# Blokuj IP: {ip} ({zlosliwe_ip[ip]} prób ataku)\n")
                plik_blokady.write(f"ufw insert 1 deny from {ip} to any comment 'Sentinel auto-blokada' 2>/dev/null || iptables -I INPUT -s {ip} -j DROP\n")
        os.chmod(args.block_script, 0o755)
        print(f"\n{Kolory.ZIELONY}[✓] Wygenerowano skrypt blokujący zaporę: {args.block_script}{Kolory.RESET}")
        print(f"    Aby wdrożyć blokadę na serwerze, wpisz: sudo ./{args.block_script}")


if __name__ == "__main__":
    main()
