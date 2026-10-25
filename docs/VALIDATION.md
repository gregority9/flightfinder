# Walidacja

Przeprowadzona 24 października 2026 r.

- 11 testów backendu zakończonych powodzeniem (Python 3.12, pytest).
- Prawdziwe wyszukiwanie Fli: GDN → HAM, 23 listopada 2026, 1 dorosły, PLN. Dostawca zwrócił m.in. bezpośredni lot Ryanair FR6119 o 06:55–08:20 za 219 PLN w chwili sprawdzenia. To dowód działania integracji w tej sesji, nie aktualna oferta ani gwarancja tej ceny.
- Prawdziwe wyszukiwanie RT: GDN → HAM 23 listopada i HAM → GDN 27 listopada 2026. Zwrócono 18 par połączeń; najtańszy wynik adaptera wynosił 387 PLN w chwili sprawdzenia.
- Testy obejmują uwierzytelnienie, walidację dat i lotnisk, limity, dopasowanie filtrów Fli, cenę RT, brak waluty, próg i deduplikację alertów, ponowne uruchomienie po wzroście ceny, zachowanie podczas błędu dostawcy, SQLite po ponownym otwarciu, wyłączenie przeterminowanych tras, interwał sprawdzania, usuwanie i rejestrację tokenu urządzenia.
- Testy alertów używają kontrolowanego dostawcy. Nie wysyłają prawdziwych powiadomień.
- Brak środowiska macOS/Xcode w sesji: kompilacja iOS, podpis, instalacja na iPhone i dostarczenie push pozostają do sprawdzenia. Workflow jest przygotowany, ale nie został wykonany.
- Nie uruchomiono hostowanego backendu ani kontenera Docker. Nie skonfigurowano domeny, sekretów, APNs lub ntfy.
- Repozytorium docelowe wskazane 25 października 2026: https://github.com/gregority9/flightfinder. Aktualny wynik testów i kompilacji jest dostępny w zakładce Actions tego repozytorium.
