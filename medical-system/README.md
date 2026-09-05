# Medical System - Szkielet Aplikacji CLI i Daemon

## Struktura Projektu

```
medical-system/
├── bin/
│   ├── medical-daemon.sh    # Główny daemon zbierający dane z sensorów
│   └── medical-cli.sh       # Klient CLI do komunikacji z daemonem
├── config/
│   └── daemon.conf.example  # Przykładowa konfiguracja daemona
├── sensors/
│   ├── arduino-nano-usb.ino     # Kod dla Arduino Nano (USB)
│   └── pico-w-ethernet.ino      # Kod dla Raspberry Pi Pico W (Ethernet)
├── logs/                    # Logi daemona
├── run/                     # PID file i socket UNIX
└── data/                    # Buforowane dane z sensorów
```

## Instalacja

### Wymagania

```bash
# Wymagane pakiety
sudo apt-get install jq socat netcat-openbsd curl

# Opcjonalnie: screen lub tmux do uruchamiania w tle
sudo apt-get install screen
```

### Konfiguracja

```bash
# Skopiuj przykładową konfigurację
cp config/daemon.conf.example config/daemon.conf

# Edytuj konfigurację według potrzeb
nano config/daemon.conf
```

## Uruchamianie

### Start daemona

```bash
# Uruchom w trybie foreground (do testów)
./bin/medical-daemon.sh start

# Uruchom w tle jako daemon
./bin/medical-daemon.sh start --daemonize

# Sprawdź status
./bin/medical-daemon.sh status
```

### Zatrzymywanie

```bash
# Łagodne zatrzymanie
./bin/medical-daemon.sh stop

# Restart
./bin/medical-daemon.sh restart
```

## Użycie CLI

### Podstawowe komendy

```bash
# Test połączenia
./bin/medical-cli.sh ping

# Status wszystkich sensorów
./bin/medical-cli.sh status

# Lista zarejestrowanych sensorów
./bin/medical-cli.sh sensor list
```

### Zarządzanie sensorami

```bash
# Dodaj sensor Ethernet ręcznie
./bin/medical-cli.sh sensor add \
  --id eth_192_168_1_100 \
  --type ethernet \
  --port 192.168.1.100

# Odczytaj dane z konkretnego sensora
./bin/medical-cli.sh sensor read --id usb_ttyUSB0

# Pobierz ostatnie dane (tryb cichy, tylko JSON)
./bin/medical-cli.sh -q data get --id usb_ttyUSB0

# Usuń sensor z rejestru
./bin/medical-cli.sh sensor remove --id eth_192_168_1_100
```

### Opcje CLI

```bash
# Tryb szczegółowy (debug)
./bin/medical-cli.sh -v status

# Tryb cichy (tylko dane)
./bin/medical-cli.sh -q data get --id usb_ttyUSB0

# Zwiększony timeout (10 sekund)
./bin/medical-cli.sh -t 10 sensor read --id eth_192_168_1_100

# Wyłącz kolory
./bin/medical-cli.sh --no-color status
```

## Typy Sensorów

### USB (Arduino Nano)

- **Automatyczne wykrywanie**: Daemon automatycznie wykrywa urządzenia `/dev/ttyUSB*` i `/dev/ttyACM*`
- **Baudrate**: Domyślnie 9600
- **Format danych**: Tekst linia po linii (JSON zalecany)

### Ethernet (Raspberry Pi Pico W, Arduino z Ethernet Shield)

- **Wykrywanie**: Przez ping znanych adresów IP
- **Protokoły**: HTTP GET lub TCP socket
- **Endpoint danych**: `http://<ip>/data` lub TCP port 8080
- **Format danych**: JSON

## Przykładowe Dane z Sensorów

### Arduino Nano (USB)
```json
{"temp":25.5,"humidity":60.2,"timestamp":1234567890}
```

### Raspberry Pi Pico W (Ethernet)
```json
{
  "sensor": "dht11",
  "temp": 25.5,
  "humidity": 60.2,
  "unit_temp": "C",
  "unit_humidity": "%",
  "timestamp": 1234567890,
  "ip": "192.168.1.100"
}
```

## Protokół Komunikacji (Socket UNIX)

### Żądanie (CLI → Daemon)
```json
{
  "command": "sensor.read",
  "sensor_id": "usb_ttyUSB0"
}
```

### Odpowiedź (Daemon → CLI)
```json
{
  "status": "ok",
  "sensor_id": "usb_ttyUSB0",
  "data": "{\"temp\":25.5,\"humidity\":60.2}",
  "timestamp": 1234567890
}
```

### Dostępne Komendy

| Komenda | Opis | Parametry |
|---------|------|-----------|
| `ping` | Test połączenia | - |
| `status` | Status wszystkich sensorów | - |
| `sensor.list` | Lista ID sensorów | - |
| `sensor.read` | Odczyt z sensora | `sensor_id` |
| `sensor.add` | Dodaj sensor | `sensor_id`, `type`, `port` |
| `sensor.remove` | Usuń sensor | `sensor_id` |
| `data.get` | Pobierz dane | `sensor_id` |
| `shutdown` | Zatrzymaj daemon | - |

## Kody Wyjścia

| Kod | Symbol | Znaczenie |
|-----|--------|-----------|
| 0 | - | Sukces |
| 64 | EX_USAGE | Błąd składni/użycia |
| 65 | EX_DATAERR | Błąd danych |
| 68 | EX_NOINPUT | Brak odpowiedzi |
| 69 | EX_UNAVAILABLE | Daemon niedostępny |
| 70 | EX_SOFTWARE | Błąd wewnętrzny |

## Logi

Logi są zapisywane w `/workspace/medical-system/logs/medical-daemon.log`

### Poziomy logowania

- **DEBUG**: Szczegółowe informacje diagnostyczne
- **INFO**: Normalne operacje (domyślny)
- **WARN**: Ostrzeżenia
- **ERROR**: Błędy

### Przykładowe logi

```
2024-01-15 10:30:00 [INFO] Uruchamianie daemona...
2024-01-15 10:30:01 [INFO] Wykryto nowy sensor USB: /dev/ttyUSB0
2024-01-15 10:30:01 [INFO] Zarejestrowano sensor: ID=usb_ttyUSB0, TYPE=usb, PORT=/dev/ttyUSB0
2024-01-15 10:30:05 [DEBUG] Odczytano z usb_ttyUSB0: {"temp":25.5,"humidity":60.2}
2024-01-15 10:30:10 [WARN] Sensor Ethernet niedostępny: 192.168.1.100
```

## Programowanie Sensorów

### Arduino Nano

1. Podłącz Arduino Nano przez USB
2. Otwórz `sensors/arduino-nano-usb.ino` w Arduino IDE
3. Zainstaluj bibliotekę DHT (jeśli używasz sensora DHT11/DHT22)
4. Wgraj kod na płytkę

### Raspberry Pi Pico W

1. Zainstaluj Arduino IDE z supportem dla RP2040
2. Otwórz `sensors/pico-w-ethernet.ino`
3. Edytuj `ssid` i `password` w kodzie
4. Zainstaluj biblioteki: `ArduinoJson`, `DHT sensor library`
5. Wgraj kod na Pico W
6. Zanotuj wyświetlony adres IP
7. Dodaj sensor do daemona:
   ```bash
   ./bin/medical-cli.sh sensor add \
     --id eth_192_168_1_100 \
     --type ethernet \
     --port 192.168.1.100
   ```

## Rozwiązywanie Problemów

### Daemon nie startuje

```bash
# Sprawdź czy port/socket nie jest zajęty
ls -la /workspace/medical-system/run/

# Sprawdź logi
tail -f /workspace/medical-system/logs/medical-daemon.log

# Sprawdź czy wymagane pakiety są zainstalowane
which jq socat nc curl
```

### Sensor USB nie wykryty

```bash
# Sprawdź dostępne urządzenia USB
ls -la /dev/ttyUSB* /dev/ttyACM*

# Sprawdź uprawnienia
sudo usermod -a -G dialout $USER
# Wyloguj się i zaloguj ponownie
```

### Sensor Ethernet nie odpowiada

```bash
# Sprawdź czy sensor jest osiągalny
ping 192.168.1.100

# Sprawdź endpoint HTTP
curl http://192.168.1.100/data

# Sprawdź port TCP
nc -zv 192.168.1.100 8080
```

### Brak danych z sensora

```bash
# Włącz tryb debug
./bin/medical-cli.sh -v sensor read --id usb_ttyUSB0

# Sprawdź logi daemona w czasie rzeczywistym
tail -f /workspace/medical-system/logs/medical-daemon.log
```

## Integracja z Backendem

Daemon można rozszerzyć o wysyłanie danych do backendu medycznego (FHIR, HL7):

1. Włącz w konfiguracji: `BACKEND_ENABLED=true`
2. Skonfiguruj endpoint: `BACKEND_URL="http://backend/api/v1/data"`
3. Daemon będzie wysyłał dane z każdego sensora po odczycie

## Bezpieczeństwo

- Socket UNIX ma uprawnienia `660` (tylko właściciel i grupa)
- Daemon powinien być uruchamiany jako dedykowany użytkownik
- W produkcji należy zabezpieczyć dostęp do sensorów Ethernet (VLAN, firewall)

## Licencja

MIT License
