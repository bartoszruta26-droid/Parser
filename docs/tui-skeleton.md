# Szkielet aplikacji TUI

Ten plik opisuje schematyczny frontend TUI (`Text User Interface`) do komunikacji z daemonem projektu. TUI jest napisane w Bashu i nie wymaga dodatkowych bibliotek typu `dialog` lub `ncurses`, dlatego może działać na minimalnych instalacjach Linux/Raspberry Pi.

## Cel

TUI jest referencyjną aplikacją frontendową dla operatora lokalnego. Nie zawiera logiki biznesowej systemu — wysyła komendy do daemona i prezentuje odpowiedzi. Dzięki temu tę samą logikę mogą wykorzystywać inne frontendy, na przykład WebUI, GUI lub aplikacja Android.

## Plik startowy

```bash
./frontend/tui/parser-tui.sh
```

Skrypt korzysta z tej samej konfiguracji co daemon:

- `DAEMON_CONFIG` — opcjonalna ścieżka do pliku konfiguracji.
- `COMMAND_FIFO` — kanał poleceń daemona.
- `RESPONSE_DIR` — katalog odpowiedzi JSON.
- `REQUEST_TIMEOUT_SECONDS` — maksymalny czas oczekiwania na odpowiedź.
- `TUI_REFRESH_SECONDS` — opisowy interwał odświeżania widoczny w nagłówku TUI.

## Tryb interaktywny

W trybie interaktywnym operator otrzymuje menu:

- `Ping daemona` — sprawdzenie życia procesu.
- `Pobierz status` — pobranie podstawowego stanu daemona.
- `Wyślij zdarzenie frontend.event` — przykładowe zdarzenie operatorskie z payloadem JSON.
- `Odśwież ekran` — ponowne pobranie statusu.
- `Wyjście` — zamknięcie TUI bez zatrzymywania daemona.

## Tryb jednorazowy

Tryb jednorazowy jest przeznaczony do testów automatycznych i integracji z innymi narzędziami:

```bash
./frontend/tui/parser-tui.sh --once ping
./frontend/tui/parser-tui.sh --once status
./frontend/tui/parser-tui.sh --once frontend.event --payload '{"source":"tui"}'
```

## Granice odpowiedzialności

TUI powinno pozostać cienkim klientem. Docelowa logika walidacji, autoryzacji, kolejkowania, wykonania zadań i obsługi sprzętu powinna znajdować się po stronie daemona albo dedykowanych komponentów backendowych.
