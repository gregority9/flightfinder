# FlightDeck

Osobista, natywna wyszukiwarka lotów na iPhone (SwiftUI, iOS 17+) z serwerem Fli / Google Flights, obserwowaniem tras i alertami cenowymi.

## Co zawiera projekt

- Wyszukiwanie w jedną i obie strony, lotniska IATA, daty, 1–9 dorosłych, klasa, przesiadki i waluty PLN/EUR/TRY/USD/GBP.
- Karty lotów z czasami lokalnymi, szczegółami przesiadek, sortowaniem i linkiem do konkretnego połączenia w Google Flights.
- Ostatnie wyszukiwania na telefonie, zapisane progi cenowe na serwerze, wstrzymywanie i usuwanie alertów, historia cen i lista okazji.
- Sprawdzanie cen domyślnie co 30 minut, również gdy aplikacja jest zamknięta. SQLite przechowuje dane po restarcie serwera.
- Opcjonalne powiadomienia APNs albo ntfy. Bez konfiguracji kanału okazje są dostępne w zakładce Alerty po odświeżeniu.
- Klucz API w pęku kluczy iPhone'a, połączenie HTTPS, limity zapytań, pięciominutowy cache.
- GitHub Actions: testy serwera i kompilacja niepodpisanego IPA na macOS.

## Stan i ograniczenia

To kod pierwszej wersji, a nie uruchomiona usługa. Do działania trzeba wystawić serwer HTTPS, ustawić klucz i zainstalować aplikację. Samo umieszczenie kodu na GitHubie nie uruchamia serwera ani alertów.

Testy backendu i kompilacja iOS zostały pomyślnie wykonane na GitHub Actions 25 października 2026. [Pobierz artefakt FlightDeck-unsigned-IPA z udanej kompilacji](https://github.com/gregority9/flightfinder/actions/runs/40213451278). Plik wymaga podpisania narzędziem sideloadingowym przed instalacją. Nie przeprowadzono testu na fizycznym iPhonie ani dostarczenia zdalnego powiadomienia. Szczegóły: [docs/VALIDATION.md](docs/VALIDATION.md).

Fli jest nieoficjalną integracją. Aktualny upstream używa strony wyników Google Flights, a nie publicznego, gwarantowanego API. Wyniki mogą być niepełne lub czasowo niedostępne. Puste wyniki i błędy są rozróżniane. Nie ma zakupu biletu w aplikacji. Filtry bagażu i multi-city nie są oferowane. RT rozwija pięć kandydatów lotu wylotowego, więc nie jest gwarantowanym przeglądem wszystkich możliwych par połączeń. Domyślna częstotliwość nie gwarantuje wykrycia krótkotrwałych okazji.

Alert wysyła powiadomienie przy pierwszej cenie <= progu oraz dalszym spadku; po wzroście ponad próg może zostać uruchomiony ponownie. Błąd dostawcy nie usuwa ostatniej poprawnej ceny. Nieznana/inna waluta nigdy nie jest porównywana z progiem. Dla RT całkowitą cenę pobieramy z rekordu wylotu, zgodnie z serializerem przypiętej wersji Fli. Ceny są łączne dla wszystkich wybranych pasażerów, a nie za osobę. Cena i bagaż wymagają ponownego potwierdzenia przed zakupem.

## Serwer

1. Skopiuj `.env.example` jako `.env`.
2. Wygeneruj sekret: `python -c 'import secrets; print(secrets.token_urlsafe(32))'` i wpisz go jako `API_TOKEN`.
3. Uruchom `docker compose up -d --build`.
4. Skieruj domenę HTTPS przez reverse proxy na `127.0.0.1:8000`. Nie wystawiaj portu bez TLS. Przykład Caddy: `loty.twojadomena.pl { reverse_proxy 127.0.0.1:8000 }`.
5. W aplikacji → Ustawienia wpisz URL i ten sam klucz. Zapisz i sprawdź połączenie.

Uruchamiaj dokładnie jeden proces API / jedną replikę: harmonogram działa wewnątrz procesu. Backend jest przeznaczony dla jednej osoby lub zaufanej grupy korzystającej z tego samego klucza. Wszystkie urządzenia z tym kluczem widzą te same alerty. Nie jest serwisem wielokontowym. Utrzymuj kopię wolumenu `flightdeck-data`. Limit: 30 zapisanych tras, 10 wyszukiwań/min, minimum 15 minut między kontrolami pojedynczej trasy. Historyczne daty są automatycznie wyłączane według daty UTC.

Lokalnie:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r backend/requirements.txt pytest
export API_TOKEN="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
cd backend
python -m pytest -q
uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8000
```

Na prawdziwym telefonie API musi być dostępne przez HTTPS. Aplikacja celowo nie dopuszcza nieszyfrowanego HTTP. Upstream Fli jest przypięty do commita `881aee5ff4321e81ea2157cb44be94ce6a21dc1b`, bo wersja `0.10.0` z tego drzewa nie była dostępna w PyPI podczas przygotowania projektu. Aktualizację przypięcia należy poprzedzić testem adaptera i rzeczywistym wyszukiwaniem. Zależności pośrednie nie są w pełni zablokowane.

## IPA bez własnego Maca

Wgraj zawartość tego katalogu do głównego katalogu repozytorium GitHub, łącznie z `.github`.

1. Otwórz **Actions → Build iPhone IPA → Run workflow** albo wypchnij zmianę w `ios/`.
2. Po udanej kompilacji pobierz artefakt **FlightDeck-unsigned-IPA** i rozpakuj ZIP.
3. Plik `FlightDeck-unsigned.ipa` wymaga podpisania przez narzędzie sideloadingowe. Zainstaluj go np. używanym przez Ciebie narzędziem, które potrafi podpisywać IPA. Niepodpisany IPA nie jest samodzielnym instalatorem.
4. Skonfiguruj URL serwera i klucz w aplikacji.

Workflow nie zawiera kluczy Apple i nie wysyła aplikacji do App Store. Dostępność i koszt runnerów macOS zależą od planu i limitów konta GitHub. Utrzymanie serwera i instalacja pozostają oddzielnymi czynnościami.

Na Macu: `brew install xcodegen`, następnie `cd ios && xcodegen generate`; otwórz `FlightDeck.xcodeproj`, wybierz swój zespół i podpis oraz urządzenie. Domyślny bundle ID: `com.gregority9.flightdeck`.

## Powiadomienia przy sideloadingu: ntfy

Na serwerze ustaw `NTFY_TOPIC` (długa losowa nazwa) oraz opcjonalnie `NTFY_SERVER` i `NTFY_TOKEN`. Zrestartuj usługę. W aplikacji ntfy na iPhone zasubskrybuj identyczny serwer i temat oraz włącz powiadomienia. Dla prywatności używaj tematu z kontrolą dostępu; publiczny temat bez uwierzytelnienia może zostać odczytany przez każdego, kto zna jego nazwę.

To powiadomienia aplikacji **ntfy**, nie FlightDeck. Samodzielny serwer ntfy na iOS wymaga dodatkowej konfiguracji upstream relay; opisuje ją dokumentacja ntfy. FlightDeck nadal zapisuje wszystkie okazje we własnej zakładce Alerty.

## Natywne powiadomienia FlightDeck: APNs

Wymagają profilu podpisującego zawierającego Push Notifications dla Twojego bundle ID oraz odpowiedniej konfiguracji Apple Developer. Zwykły niepodpisany/sideloadowany build nie zapewnia tego uprawnienia.

1. W Apple Developer włącz Push Notifications dla identyfikatora aplikacji, przygotuj właściwy profil i klucz APNs `.p8`.
2. Zmień bundle ID w `ios/project.yml` i identycznie `APNS_BUNDLE_ID` na serwerze, jeśli używasz własnego.
3. Skopiuj `ios/FlightDeck-Push.entitlements.example` do `ios/FlightDeck/FlightDeck.entitlements`; dodaj do `settings.base` targetu `CODE_SIGN_ENTITLEMENTS: FlightDeck/FlightDeck.entitlements`. Wygeneruj projekt i podpisz odpowiednim profilem. Dla dystrybucji ustaw `aps-environment` na `production` i `APNS_PRODUCTION=true`; dla development pozostaw `development` i `false`.
4. Zamontuj `.p8` tylko do odczytu na serwerze; ustaw `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`. Nie commituj kluczy ani profili.
5. Po zapisaniu połączenia w aplikacji włącz powiadomienia. Telefon zarejestruje token na serwerze. Serwer pokazuje stan konfiguracji, ale dopiero prawdziwe dostarczenie potwierdzi konfigurację całej ścieżki.

Powiadomienia są best effort. Niepowodzenie jest zapisywane i ponawiane; po zaakceptowaniu przez choć jeden kanał wydarzenie nie jest ponawiane w drugim. APNs nie gwarantuje faktycznego wyświetlenia. Awaria po wysłaniu, ale przed zapisem potwierdzenia, może spowodować powtórne powiadomienie.

## Struktura

```text
ios/FlightDeck/        modele, SwiftUI, Keychain, klient API i rejestracja APNs
ios/project.yml       generowanie projektu Xcode
backend/app/          FastAPI, adapter Fli, SQLite, harmonogram i powiadomienia
backend/tests/        testy API, cen, walut, alertów i trwałości danych
.github/workflows/    kompilacja IPA i testy
compose.yaml          uruchamianie serwera z trwałym wolumenem
```

## Źródła

- Fli (MIT): https://github.com/punitarani/fli
- Wykorzystany serializer cen RT: https://github.com/punitarani/fli/blob/881aee5ff4321e81ea2157cb44be94ce6a21dc1b/fli/cli/utils.py
- ntfy iOS: https://docs.ntfy.sh/subscribe/phone/
- APNs: https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns
- XcodeGen: https://github.com/yonaskolb/XcodeGen

Nie ma dostępu do danych osobistych ani kluczy kont Apple w tym repozytorium. Do integracji z Fli używana jest bezpośrednio jego biblioteka Python; serwer MCP nie jest potrzebny w ścieżce aplikacji mobilnej.
