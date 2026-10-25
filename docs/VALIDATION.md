# Walidacja

Przeprowadzona 24 października 2026 r.; publikacja i kompilacja zweryfikowane 25 października 2026 r.

- 11 testów backendu zakończonych powodzeniem (Python 3.12, pytest).
- Prawdziwe wyszukiwanie Fli: GDN → HAM, 23 listopada 2026, 1 dorosły, PLN. Dostawca zwrócił m.in. bezpośredni lot Ryanair FR6119 o 06:55–08:20 za 219 PLN w chwili sprawdzenia. To dowód działania integracji w tej sesji, nie aktualna oferta ani gwarancja tej ceny.
- Prawdziwe wyszukiwanie RT: GDN → HAM 23 listopada i HAM → GDN 27 listopada 2026. Zwrócono 18 par połączeń; najtańszy wynik adaptera wynosił 387 PLN w chwili sprawdzenia.
- Testy obejmują uwierzytelnienie, walidację dat i lotnisk, limity, dopasowanie filtrów Fli, cenę RT, brak waluty, próg i deduplikację alertów, ponowne uruchomienie po wzroście ceny, zachowanie podczas błędu dostawcy, SQLite po ponownym otwarciu, wyłączenie przeterminowanych tras, interwał sprawdzania, usuwanie i rejestrację tokenu urządzenia.
- Testy alertów używają kontrolowanego dostawcy. Nie wysyłają prawdziwych powiadomień.
- Kompilacja na macOS w GitHub Actions zakończona sukcesem: https://github.com/gregority9/flightfinder/actions/runs/40213451278. Wygenerowano artefakt `FlightDeck-unsigned-IPA`. Potwierdza to kompilację aplikacji dla fizycznego urządzenia iOS; podpis, instalacja na iPhone i dostarczenie push pozostają do sprawdzenia.
- Testy backendu na GitHub Actions zakończone sukcesem: https://github.com/gregority9/flightfinder/actions/runs/40213451315.
- Nie uruchomiono hostowanego backendu ani kontenera Docker. Nie skonfigurowano domeny, sekretów, APNs lub ntfy.
- Repozytorium docelowe wskazane 25 października 2026: https://github.com/gregority9/flightfinder. Aktualny wynik testów i kompilacji jest dostępny w zakładce Actions tego repozytorium.

## Wersja 1.1: bez serwera, 25 października 2026

- Commit aplikacji: `a93ebca016af433b2050bccada14a15509f349c7`.
- Udana kompilacja urządzenia iOS i artefakt IPA: https://github.com/gregority9/flightfinder/actions/runs/40215287061/artifacts/12607411118.
- 7 testów adaptera JavaScript przeszło lokalnie oraz na GitHub Actions. Sprawdzono także uruchomienie w innej strefie czasowej (`Pacific/Honolulu`).
- Testy używają izolowanego runtime bez fetch/Buffer/URL; odczytują prawdziwy, zanonimizowany fixture Google z przypiętej wersji Fli. Obejmują kodowanie requestów, dekodowanie, błędy zamiast pustych sukcesów, walidację, offline airport lookup, przypinanie wylotu oraz finalną cenę RT bez sumowania.
- Natywny test na macOS uruchomił prawdziwe JavaScriptCore, odczytał fixture i sprawdził kodowanie zapytania. Zweryfikował medianę, odporność na pojedynczą skrajną cenę, minimum 5 próbek i 24 godzin, niedopuszczanie wielokrotnego odświeżania do sztucznej nauki, wygaśnięcie starych próbek, regułę kolejnego powiadomienia i serializację alertu z historią.
- Prawdziwy test HTTP nowego adaptera (curl jako transport zamiast URLSession): GDN–HAM 24 listopada, HAM–GDN 28 listopada 2026, PLN. Odczytano 9 rekordów wylotu i 4 rekordy powrotu dla wybranego wylotu; przykładowa finalna cena RT wynosiła 862 PLN. To dowód integracji w chwili sprawdzenia, nie aktualna oferta.
- Log kompilacji potwierdza skopiowanie `fli-engine.js` i `FLI-LICENSE.txt` do `FlightDeck.app`.
- Backend zachowany historycznie nadal przechodzi testy; aplikacja 1.1 nie korzysta z niego, klucza API ani APNs.
- Nadal nie wykonano instalacji/testu na fizycznym iPhonie ani wyświetlenia lokalnego banera na urządzeniu. Rzeczywisty dostęp URLSession z sieci telefonu może zależeć od ograniczeń Google. Aplikacja sprawdza ceny tylko na pierwszym planie.
