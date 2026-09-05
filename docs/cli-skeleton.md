# Medical Daemon CLI - Dokumentacja

## Przegląd

`medical-cli.sh` to kompletny klient wiersza poleceń (CLI) do komunikacji z daemonem medycznym. Umożliwia wysyłanie wszystkich komend obsługiwanych przez protokół daemona oraz odbieranie odpowiedzi w czytelnej formie.

## Struktura

```
cli/
├── bin/
│   └── medical-cli.sh      # Główny skrypt CLI
├── lib/
│   └── cli-helpers.sh      # Biblioteka funkcji pomocniczych
└── config/
    └── cli.conf.example    # Przykładowa konfiguracja
```

## Instalacja

1. Skopiuj plik konfiguracyjny:
```bash
sudo cp cli/config/cli.conf.example /etc/medical-daemon/cli.conf
```

2. Dostosuj konfigurację jeśli konieczne (ścieżki muszą pasować do konfiguracji daemona).

3. Upewnij się, że skrypt jest wykonywalny:
```bash
chmod +x cli/bin/medical-cli.sh
```

## Użycie

### Podstawowe komendy

```bash
# Sprawdzenie dostępności daemona
./cli/bin/medical-cli.sh ping

# Pobranie statusu daemona
./cli/bin/medical-cli.sh status

# Zatrzymanie daemona
./cli/bin/medical-cli.sh shutdown
```

### Dane medyczne

```bash
# Dane pacjenta (podmiotowe i przedmiotowe)
./cli/bin/medical-cli.sh patient.data '{"patient_id":"123","name":"Jan Kowalski"}'

# Dane z czujników biosensor
./cli/bin/medical-cli.sh biosensor.data '{"heart_rate":72,"spo2":98,"temperature":36.6}'

# Dane z czujników biofeedback
./cli/bin/medical-cli.sh biofeedback.data '{"stress_level":0.3,"focus":0.8}'

# Wiadomość FHIR
./cli/bin/medical-cli.sh medical.fhir '{"resourceType":"Patient","id":"example"}'

# Wiadomość HL7v2
./cli/bin/medical-cli.sh medical.hl7 'MSH|^~\&|SENDING_APP|...'

# Ogólna wiadomość medyczna (auto-detekcja typu)
./cli/bin/medical-cli.sh medical.message '{"resourceType":"Observation",...}'
```

### Swarm Raspberry Pi

```bash
# Dane sensorów
./cli/bin/medical-cli.sh swarm.sensor '{"temperature":22.5,"humidity":45}'

# Komendy efektorów
./cli/bin/medical-cli.sh swarm.effector '{"relay":"on","fan_speed":50}'

# Przekazywanie między daemonami
./cli/bin/medical-cli.sh swarm.forward '{"target":"rpi-worker-01","message":{...}}'
```

### Backend

```bash
# Zadanie z backendu
./cli/bin/medical-cli.sh backend.job '{"task":"sync","priority":"high"}'
```

## Opcje

### Globalne opcje

- `-h, --help` - Wyświetlenie pomocy
- `-v, --verbose` - Tryb szczegółowy (pokazuje szczegóły transmisji)
- `--no-color` - Wyłączenie kolorów w outputcie
- `-q, --quiet` - Tylko JSON response (bez formatowania)
- `-t, --timeout SECONDS` - Timeout na odpowiedź (domyślnie 10s)
- `-f, --file FILE` - Wczytaj dane z pliku JSON
- `-s, --source SOURCE` - Źródło danych (domyślnie: cli)

### Przykłady użycia opcji

```bash
# Tryb cichy - tylko JSON
./cli/bin/medical-cli.sh status --quiet

# Tryb verbose - szczegóły transmisji
./cli/bin/medical-cli.sh patient.data '{"id":"123"}' --verbose

# Wczytanie danych z pliku
./cli/bin/medical-cli.sh patient.data -f patient.json

# Określenie źródła danych
./cli/bin/medical-cli.sh biosensor.data -s sensor-01 '{"hr":72}'

# Dłuższy timeout
./cli/bin/medical-cli.sh medical.fhir -f large_fhir.json --timeout 30
```

## Zmienne środowiskowe

- `DAEMON_CONFIG` - Ścieżka do pliku konfiguracyjnego daemona
- `RUN_DIR` - Katalog runtime (domyślnie: /tmp/medical-daemon)
- `REQUEST_TIMEOUT_SECONDS` - Timeout na odpowiedź
- `USE_COLOR` - Kolory w outputcie (true/false)

## Protokół komunikacji

CLI komunikuje się z daemonem poprzez:

1. **COMMAND_FIFO** - Named pipe do wysyłania poleceń
2. **RESPONSE_DIR** - Katalog z plikami odpowiedzi

Format polecenia:
```
request_id|source|command|payload
```

Format odpowiedzi (JSON):
```json
{
  "protocol": "1",
  "request_id": "cli-1234567890-1234-5678",
  "status": "accepted",
  "code": "PATIENT_DATA",
  "message": "Patient data accepted",
  "payload": {...}
}
```

## Kody wyjścia

- `0` - Sukces
- `64` - Błąd argumentów/nieznana komenda
- `65` - Niepoprawny JSON
- `66` - Błąd odczytu pliku
- `69` - Brak połączenia z daemonem (FIFO nie istnieje)
- `70` - Timeout odpowiedzi
- `78` - Brak konfiguracji

## Przykłady skryptów

### Batchowe wysyłanie danych

```bash
#!/usr/bin/env bash
# Wysyłanie danych z wielu sensorów

for sensor in sensor-01 sensor-02 sensor-03; do
  ./cli/bin/medical-cli.sh biosensor.data \
    -s "$sensor" \
    -f "${sensor}_data.json"
done
```

### Monitorowanie statusu

```bash
#!/usr/bin/env bash
# Pętla monitorująca status daemona

while true; do
  clear
  ./cli/bin/medical-cli.sh status --no-color --quiet | jq .
  sleep 5
done
```

### Walidacja przed wysłaniem

```bash
#!/usr/bin/env bash
# Walidacja danych przed wysłaniem

validate_and_send() {
  local file="$1"
  
  if ! jq . "$file" >/dev/null 2>&1; then
    echo "Invalid JSON in $file" >&2
    return 1
  fi
  
  ./cli/bin/medical-cli.sh patient.data -f "$file" --verbose
}

validate_and_send "new_patient.json"
```

## Integracja z innymi komponentami

### Z frontendem TUI

```bash
# TUI może wywoływać CLI do konkretnych operacji
tui_command="status"
./cli/bin/medical-cli.sh "$tui_command" --quiet | tui_process_response
```

### Z backendem

```bash
# Backend może używać CLI jako klienta
backend_job='{"task":"process_queue"}'
./cli/bin/medical-cli.sh backend.job "$backend_job" --quiet
```

### Ze skryptami Bash

```bash
# Source biblioteki helperów
source cli/lib/cli-helpers.sh

# Użycie funkcji bezpośrednio
send_daemon_command "ping" "" "script" 10 false false "$COMMAND_FIFO" "$RESPONSE_DIR"
```

## Rozwiązywanie problemów

### Daemon nie odpowiada

1. Sprawdź czy daemon jest uruchomiony:
```bash
ps aux | grep medical-daemon
ls -la /tmp/medical-daemon/commands.fifo
```

2. Uruchom daemon:
```bash
./daemon/bin/medical-daemon.sh
```

### Timeout odpowiedzi

- Zwiększ timeout: `--timeout 30`
- Sprawdź obciążenie systemu
- Sprawdź uprawnienia do RESPONSE_DIR

### Błędy JSON

- Użyj `jq` do walidacji: `echo "$json" | jq .`
- Sprawdź escapowanie znaków specjalnych
- Upewnij się że payload jest poprawnym JSON

## Bezpieczeństwo

- Request ID jest walidowane (blokada path traversal)
- Payload JSON jest walidowany przed wysłaniem
- Pliki odpowiedzi są usuwane po odczycie
- Uprawnienia do FIFO i plików odpowiedzi są restrykcyjne (0640/0660)

## Rozszerzanie

Aby dodać nową komendę:

1. Dodaj case w głównym switchu w `medical-cli.sh`
2. Zaimplementuj handler jeśli potrzebna specjalna logika
3. Zaktualizuj dokumentację i help
4. Dodaj testy

## Testowanie

```bash
# Test podstawowy
./cli/bin/medical-cli.sh --help

# Test połączenia
./cli/bin/medical-cli.sh ping

# Test pełny z daemonem
./scripts/run-daemon.sh &
sleep 2
./cli/bin/medical-cli.sh status
./cli/bin/medical-cli.sh shutdown
```
