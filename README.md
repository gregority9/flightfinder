# FlightDeck / flightfinder

Natywna aplikacja iPhone (iOS 17+) do wyszukiwania lotów przez Fli i wykrywania okazji. Wersja 1.1 wyszukuje **bezpośrednio na telefonie, bez własnego serwera i kluczy API**.

## Instalacja

1. Pobierz [zweryfikowane IPA wersji 1.1](https://github.com/gregority9/flightfinder/actions/runs/40215287061/artifacts/12607411118) albo otwórz [Actions → Build iPhone IPA](https://github.com/gregority9/flightfinder/actions/workflows/ios.yml).
2. W najnowszej udanej kompilacji pobierz artefakt `FlightDeck-unsigned-IPA` i rozpakuj ZIP.
3. Podpisz i zainstaluj znajdujący się w nim `FlightDeck-unsigned.ipa` narzędziem sideloadingowym, np. iLoader.
4. Otwórz aplikację i wyszukaj lot. Nie konfigurujesz serwera.
5. Przy wynikach wybierz „Obserwuj cenę tej trasy”. Domyślnie włączony jest próg automatyczny; można przełączyć na cenę ręczną.

Aktualizuj z tym samym bundle ID i podpisem, aby zachować historię. Odinstalowanie aplikacji usuwa lokalne dane.

## Kiedy i jak działają alerty

- Po wejściu do aplikacji sprawdzane są aktywne trasy, jeżeli od ostatniej kontroli minęło 15 minut. Przeciągnięcie listy Alerty w dół sprawdza je ręcznie. Wyszukiwania mają cache do 5 minut, więc odświeżenie nie zawsze oznacza nowe pobranie danych.
- **Przy zamkniętej aplikacji ceny nie są sprawdzane.** Powrót do aplikacji uruchamia kontrolę; zamknięcie/anulowanie przerywa trwające zapytania.
- Automatyczny próg to **15% poniżej mediany wcześniejszych cen** dla identycznych lotnisk, dat, klasy, liczby osób, waluty i limitu przesiadek.
- Potrzeba co najmniej **5 poprawnych pomiarów rozłożonych na minimum 24 godziny**. Do mediany liczy się najwyżej jeden pomiar z każdego 30-minutowego okna z ostatnich 30 dni. Podczas nauki aplikacja pokazuje „Zbieram historię”, zamiast wymyślać typową cenę. Aktualna cena jest oceniana względem wcześniejszych pomiarów, przed dodaniem jej do historii.
- To historia obserwacji z tego telefonu, a nie globalna średnia rynkowa. „Zwykle” nie jest porównaniem do wszystkich sezonów ani dat podróży.
- Osiągnięcie progu tworzy wpis w zakładce Alerty i, po udzieleniu zgody, lokalny baner iOS. Kolejny baner wymaga dalszego spadku o ponad 1% albo ponownego wejścia poniżej progu po wcześniejszym wzroście. Błędy i nieznana/inna waluta nie uruchamiają alertu.
- Limit 10 zapisanych tras, 200 ostatnich pomiarów na trasę i 100 okazji. Historia jest zapisywana atomowo w Application Support na telefonie.

## Wyszukiwanie

Loty w jedną i obie strony; lotniska IATA wyszukiwane lokalnie; 1–9 dorosłych; waluty PLN/EUR/TRY/USD/GBP; klasa i maksymalnie 0–2 przesiadki; sortowanie ceną/czasem; szczegóły lotów i linki do konkretnych połączeń w Google Flights. Kwoty są łączne dla wybranej liczby pasażerów. Godziny są lokalne dla lotnisk. Cena RT pochodzi z finalnego rekordu wybranej podróży, nie z sumy obu rekordów.

Google jest pobierane przez natywne URLSession, a wbudowany JavaScriptCore wykonuje wyłącznie dołączone do aplikacji kodery/dekodery Fli. HTML Google jest przetwarzany jako tekst; skrypty otrzymane od Google nie są wykonywane. Nie ma WebView ani zdalnego backendu w ścieżce aplikacji. Żądania i przekierowania są ograniczone do HTTPS `www.google.com/travel/flights`.

## Ograniczenia

Fli jest nieoficjalną integracją. Google może blokować zapytania lub zmienić format danych. Aplikacja pokazuje błędy i oznacza częściowe wyniki. Nie gwarantuje wszystkich ofert ani finalnej ceny. Bagaż i warunki wymagają sprawdzenia przed zakupem. RT rozwija pięć najtańszych kandydatów wylotu i pobiera powroty osobno, co może potrwać i zużywa kilka MB na stronę wyników. Nie ma multi-city, wyszukiwania „dokądkolwiek” ani elastycznych dat. Powiadomienia lokalne nie działają jako monitoring zamkniętej aplikacji.

Kod poprzedniego, opcjonalnego serwera jest zachowany w `backend/`, `compose.yaml` i `.env.example`; **aplikacja 1.1 go nie używa**. Alerty zapisane wcześniej na serwerze nie są automatycznie przenoszone na telefon.

## Kompilacja i testy

GitHub Actions instaluje Node, buduje dołączony silnik, uruchamia testy JavaScript w środowisku bez przeglądarki/Node globals, następnie testuje prawdziwe JavaScriptCore i politykę okazji w Swift na macOS, po czym kompiluje IPA.

Na Macu:

```sh
npm ci
npm run build:engine
npm run test:engine
brew install xcodegen
cd ios
xcodegen generate
open FlightDeck.xcodeproj
```

W Xcode wybierz swój zespół, podpis i urządzenie. Natywne testy logiki uruchamiane przez workflow znajdują się w `ios/EngineChecks/main.swift`. Stan weryfikacji: [docs/VALIDATION.md](docs/VALIDATION.md).

Silnik budowany jest z przypiętego commita Fli `881aee5ff4321e81ea2157cb44be94ce6a21dc1b` oraz zależności zapisanych w `package-lock.json`. Wymaga dostępu do GitHuba/npm podczas budowania, a po instalacji telefon potrzebuje tylko połączenia z Google Flights. Bundle ID: `com.gregority9.flightdeck`, wersja 1.1.0 (2).

## Źródła i licencje

[Fli](https://github.com/punitarani/fli), MIT, Copyright 2025 Punit Arani. Licencja w `engine/FLI-LICENSE.txt`, dołączana też do aplikacji. Fragment strony użyty w testach pochodzi z publicznego, pozbawionego danych konta fixture projektu Fli. Dodatkowy adapter i reguły okazji należą do tego projektu.
