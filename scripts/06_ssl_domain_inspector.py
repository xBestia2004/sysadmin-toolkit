#!/usr/bin/env python3
"""
Nazwa skryptu : 06_ssl_domain_inspector.py
Opis          : Inspektor ważności certyfikatów SSL/TLS oraz domen.
                Sprawdza datę ważności certyfikatów X.509, oblicza ile dni pozostało,
                odczytuje wystawcę (CA), wersję szyfrowania (TLSv1.2/TLSv1.3)
                oraz generuje alerty o zbliżającym się wygaśnięciu.
Autor         : Dariusz Kisiel (xBestia2004)
Licencja      : MIT
Wymagania     : Python 3.8+ (Czysta biblioteka standardowa Pythona - brak pip)
"""

import argparse
from datetime import datetime, timezone
import json
import socket
import ssl
import sys
from typing import Any, Dict, List, Optional

WERSJA = "1.2.0"

# Kolory wyświetlania w terminalu
class Kolory:
    RESET = "\033[0m"
    POGRUBIENIE = "\033[1m"
    SZARY = "\033[2m"
    CZERWONY = "\033[1;31m"
    ZIELONY = "\033[1;32m"
    ZOLTY = "\033[1;33m"
    CYJAN = "\033[1;36m"


def zbadaj_certyfikat_ssl(domena: str, port: int = 443, limit_czasu: float = 4.0) -> Dict[str, Any]:
    """Łączy się z domeną przez gniazdo SSL/TLS i pobiera szczegóły certyfikatu."""
    # Oczyszczamy adres domeny z ewentualnych przedrostków http/https i ukośników
    domena = domena.strip().replace("https://", "").replace("http://", "").split("/")[0].split(":")[0]

    wynik: Dict[str, Any] = {
        "domena": domena,
        "port": port,
        "status": "blad",
        "komunikat_bledu": None,
        "wystawca": "Nieznany",
        "wazny_od": None,
        "wazny_do": None,
        "pozostalo_dni": None,
        "wersja_tls": None,
        "szyfr": None,
        "alternatywne_nazwy_san": [],
        "adres_ip": None
    }

    try:
        # Rozwiązujemy adres IP domeny przez DNS
        ip = socket.gethostbyname(domena)
        wynik["adres_ip"] = ip

        # Tworzymy bezpieczny kontekst SSL
        kontekst = ssl.create_default_context()
        with socket.create_connection((domena, port), timeout=limit_czasu) as gniazdo:
            with kontekst.wrap_socket(gniazdo, server_hostname=domena) as gniazdo_ssl:
                certyfikat = gniazdo_ssl.getpeercert()
                informacje_szyfru = gniazdo_ssl.cipher()
                wersja_tls = gniazdo_ssl.version()

                wynik["wersja_tls"] = wersja_tls
                if informacje_szyfru:
                    wynik["szyfr"] = informacje_szyfru[0]

                # Odczytujemy datę ważności (np. "May 25 12:00:00 2027 GMT")
                data_konca_napis = certyfikat.get("notAfter")
                data_poczatku_napis = certyfikat.get("notBefore")

                if data_konca_napis:
                    data_konca = datetime.strptime(data_konca_napis, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
                    wynik["wazny_do"] = data_konca.strftime("%Y-%m-%d %H:%M:%S UTC")

                    # Wyliczamy ile dni pozostało do wygaśnięcia
                    teraz = datetime.now(timezone.utc)
                    pozostalo = (data_konca - teraz).days
                    wynik["pozostalo_dni"] = pozostalo

                if data_poczatku_napis:
                    data_poczatku = datetime.strptime(data_poczatku_napis, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
                    wynik["wazny_od"] = data_poczatku.strftime("%Y-%m-%d %H:%M:%S UTC")

                # Odczytujemy wystawcę certyfikatu (np. Let's Encrypt, DigiCert)
                slownik_wystawcy = dict(x[0] for x in certyfikat.get("issuer", ()))
                wynik["wystawca"] = slownik_wystawcy.get("organizationName") or slownik_wystawcy.get("commonName") or "Nieznany"

                # Odczytujemy listę domen objętych certyfikatem (SAN)
                alternatywne = [el[1] for el in certyfikat.get("subjectAltName", ()) if el[0] == "DNS"]
                wynik["alternatywne_nazwy_san"] = alternatywne
                wynik["status"] = "ok"

    except socket.gaierror:
        wynik["komunikat_bledu"] = "Błąd rozpoznawania nazwy DNS"
    except socket.timeout:
        wynik["komunikat_bledu"] = f"Przekroczono limit czasu połączenia ({limit_czasu}s)"
    except ssl.SSLCertVerificationError as e:
        wynik["status"] = "niewazny_certyfikat"
        wynik["komunikat_bledu"] = f"Błąd weryfikacji certyfikatu: {e.verify_message}"
    except Exception as e:
        wynik["komunikat_bledu"] = str(e)

    return wynik


def main():
    parser = argparse.ArgumentParser(
        description="Inspektor ważności i bezpieczeństwa certyfikatów SSL/TLS",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Przykłady użycia:
  %(prog)s google.com github.com kul.pl
  %(prog)s -f lista_domen.txt --warn-days 30
  %(prog)s przyklad.pl --json
        """
    )
    parser.add_argument("domeny", nargs="*", help="Lista domen oddzielonych spacjami")
    parser.add_argument("-f", "--file", help="Plik tekstowy zawierający listę domen (jedna na linię)")
    parser.add_argument("-w", "--warn-days", type=int, default=14, help="Próg ostrzeżenia w dniach (domyślnie: 14 dni)")
    parser.add_argument("-c", "--crit-days", type=int, default=7, help="Próg krytyczny w dniach (domyślnie: 7 dni)")
    parser.add_argument("-p", "--port", type=int, default=443, help="Port sieciowy do sprawdzenia (domyślnie: 443)")
    parser.add_argument("-j", "--json", action="store_true", help="Wypisz wynik w formacie maszynowym JSON")
    parser.add_argument("-v", "--version", action="version", version=f"%(prog)s {WERSJA}")

    args = parser.parse_args()

    # Zbieramy domeny z argumentów oraz opcjonalnie z pliku
    badane_domeny: List[str] = list(args.domeny)
    if args.file:
        try:
            with open(args.file, "r", encoding="utf-8") as f:
                for linia in f:
                    linia = linia.strip()
                    if linia and not linia.startswith("#"):
                        badane_domeny.append(linia)
        except Exception as e:
            print(f"{Kolory.CZERWONY}[BŁĄD] Nie udało się odczytać pliku '{args.file}': {e}{Kolory.RESET}", file=sys.stderr)
            sys.exit(1)

    if not badane_domeny:
        print(f"{Kolory.ZOLTY}[!] Nie podano żadnej domeny do sprawdzenia.{Kolory.RESET}", file=sys.stderr)
        parser.print_help()
        sys.exit(2)

    wyniki = []
    czy_jest_alarm = False

    for domena in badane_domeny:
        dane = zbadaj_certyfikat_ssl(domena, port=args.port)
        wyniki.append(dane)
        dni = dane.get("pozostalo_dni")
        if dni is not None and dni <= args.warn_days:
            czy_jest_alarm = True
        elif dane["status"] != "ok":
            czy_jest_alarm = True

    # Tryb JSON (np. pod webhooki do Discorda/Slacka czy API monitoringu)
    if args.json:
        dane_wyjsciowe = {
            "wersja": WERSJA,
            "sprawdzone_domeny": wyniki,
            "czy_wymaga_uwagi": czy_jest_alarm
        }
        print(json.dumps(dane_wyjsciowe, indent=2, ensure_ascii=False))
        sys.exit(1 if czy_jest_alarm else 0)

    # Czytelna tabela w konsoli
    print(f"{Kolory.POGRUBIENIE}========================================================================================{Kolory.RESET}")
    print(f"{Kolory.CYJAN}{Kolory.POGRUBIENIE}                    INSPEKTOR CERTYFIKATÓW SSL/TLS DLA DOMEN                            {Kolory.RESET}")
    print(f"{Kolory.POGRUBIENIE}========================================================================================{Kolory.RESET}")
    print(f"  {'DOMENA':<24} {'DNI DO KOŃCA':<14} {'STATUS':<12} {'WYSTAWCA (CA)':<20} {'WERSJA TLS'}")
    print("  " + "-" * 84)

    for w in wyniki:
        domena = w["domena"]
        if w["status"] == "ok":
            dni = w["pozostalo_dni"]
            if dni is not None:
                if dni <= args.crit_days:
                    dni_tekst = f"{Kolory.CZERWONY}{dni} d (KRYT){Kolory.RESET}"
                    status_tekst = f"{Kolory.CZERWONY}WYGASA ZARAZ{Kolory.RESET}"
                elif dni <= args.warn_days:
                    dni_tekst = f"{Kolory.ZOLTY}{dni} d (OSTRZ){Kolory.RESET}"
                    status_tekst = f"{Kolory.ZOLTY}WYGASA NIEDŁUGO{Kolory.RESET}"
                else:
                    dni_tekst = f"{Kolory.ZIELONY}{dni} dni{Kolory.RESET}"
                    status_tekst = f"{Kolory.ZIELONY}WAŻNY{Kolory.RESET}"
            else:
                dni_tekst = "Brak"
                status_tekst = f"{Kolory.ZIELONY}WAŻNY{Kolory.RESET}"

            wystawca = (w["wystawca"][:18] + "..") if len(w["wystawca"]) > 20 else w["wystawca"]
            wersja_tls = w.get("wersja_tls", "Brak")
            print(f"  {domena:<24} {dni_tekst:<23} {status_tekst:<21} {wystawca:<20} {wersja_tls}")
        else:
            blad = w.get("komunikat_bledu", "Błąd")
            if len(blad) > 35:
                blad = blad[:32] + "..."
            print(f"  {domena:<24} {Kolory.CZERWONY}Brak{Kolory.RESET:<14} {Kolory.CZERWONY}BŁĄD{Kolory.RESET:<21} {Kolory.SZARY}{blad}{Kolory.RESET}")

    print(f"{Kolory.POGRUBIENIE}========================================================================================{Kolory.RESET}")

    if czy_jest_alarm:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
