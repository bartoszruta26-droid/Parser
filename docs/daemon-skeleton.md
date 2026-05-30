# Szkielet aplikacji daemon

Ten katalog pokazuje schematyczny szkielet daemona dla projektu wieloaplikacyjnego. Daemon jest centralnym procesem utrzymującym stan systemu i przyjmującym polecenia z aplikacji frontendowych oraz backendowych.

## Komponenty

- `daemon/bin/template-daemon.sh` — proces działający w tle, obsługujący protokół poleceń.
- `frontend/cli/daemonctl.sh` — referencyjny frontend CLI wysyłający polecenia użytkownika.
- `frontend/tui/parser-tui.sh` — referencyjny frontend TUI z menu operatorskim.
- `frontend/gui/parser-gui.sh` — referencyjny frontend GUI oparty o zenity/kdialog.
- `backend/adapter/backend-client.sh` — referencyjny klient backendowy wysyłający zadania systemowe.
- `config/daemon.conf.example` — przykładowa konfiguracja ścieżek, timeoutów i wersji protokołu.
- `systemd/parser-template-daemon.service` — przykładowa jednostka systemd.
- `scripts/run-daemon.sh` — lokalny starter developerski.
- `scripts/install.sh` — schematyczny instalator z trybem `DRY_RUN=1`.

## Protokół komunikacji

Szkielet używa prostego protokołu tekstowego opartego o FIFO, ponieważ działa bez dodatkowych zależności i jest czytelny w środowiskach Linux/Raspberry Pi.

Format żądania:

```text
request_id|source|command|payload
```

Format odpowiedzi:

```json
{"protocol":"1","request_id":"...","status":"ok","code":"STATUS","message":"...","payload":{}}
```

Obsługiwane polecenia startowe:

- `ping` — test życia daemona.
- `status` — zwrot podstawowego stanu procesu.
- `frontend.event` — przykład zdarzenia z frontendu.
- `backend.job` — przykład zadania z backendu.
- `shutdown` — kontrolowane zatrzymanie daemona.

## Uruchomienie lokalne

W pierwszym terminalu:

```bash
./scripts/run-daemon.sh
```

W drugim terminalu:

```bash
./frontend/cli/daemonctl.sh ping
./frontend/cli/daemonctl.sh status
./frontend/tui/parser-tui.sh --once status
./frontend/gui/parser-gui.sh --once status
./frontend/cli/daemonctl.sh frontend.event '{"button":"start"}'
./backend/adapter/backend-client.sh '{"task":"sync"}'
```

## Kierunki rozbudowy

- Zamiana FIFO na Unix socket, TCP, HTTP lub WebSocket, jeśli wymaga tego docelowa architektura.
- Dodanie autoryzacji aplikacji klienckich.
- Dodanie walidacji JSON dla payloadów.
- Rozdzielenie handlerów komend na osobne moduły.
- Dodanie kolejek zadań, retry i trwałego storage.
- Dodanie testów integracyjnych uruchamiających daemona w izolowanym katalogu tymczasowym.
