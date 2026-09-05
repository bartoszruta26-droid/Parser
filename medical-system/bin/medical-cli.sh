#!/bin/bash
#
# Medical System CLI Client
# Interfejs linii poleceń do komunikacji z daemonem medycznym
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_SOCKET="/workspace/medical-system/run/medical-daemon.sock"
TIMEOUT=5
VERBOSE=false
NO_COLOR=false
QUIET=false

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Funkcje pomocnicze
# ============================================================================

print_color() {
    local color="$1"
    shift
    if [[ "$NO_COLOR" == "true" ]]; then
        echo "$*"
    else
        echo -e "${color}$*${NC}"
    fi
}

print_success() { print_color "$GREEN" "$@"; }
print_error()   { print_color "$RED" "$@" >&2; }
print_warn()    { print_color "$YELLOW" "$@"; }
print_info()    { print_color "$BLUE" "$@"; }
print_debug()   { [[ "$VERBOSE" == "true" ]] && print_color "$CYAN" "[DEBUG] $*" || true; }

log_json() {
    local json="$1"
    if command -v jq &>/dev/null; then
        echo "$json" | jq .
    else
        echo "$json"
    fi
}

check_daemon() {
    if [[ ! -S "$DAEMON_SOCKET" ]]; then
        print_error "Daemon nie działa lub socket niedostępny: $DAEMON_SOCKET"
        print_error "Uruchom daemon: medical-daemon.sh start"
        exit 69  # EX_UNAVAILABLE
    fi
}

send_command() {
    local command="$1"
    local extra_data="${2:-}"
    
    check_daemon
    
    # Zbuduj żądanie JSON
    local request
    if [[ -n "$extra_data" ]]; then
        request=$(jq -n --arg cmd "$command" --argjson data "$extra_data" \
            '{command: $cmd} + $data')
    else
        request=$(jq -n --arg cmd "$command" '{command: $cmd}')
    fi
    
    print_debug "Wysyłam żądanie: $request"
    
    # Wyślij żądanie i odbierz odpowiedź
    local response
    response=$(echo "$request" | timeout "$TIMEOUT" socat - UNIX-CONNECT:"$DAEMON_SOCKET" 2>/dev/null)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 && -n "$response" ]]; then
        # Sprawdź status odpowiedzi
        local status=$(echo "$response" | jq -r '.status // "unknown"' 2>/dev/null)
        
        if [[ "$status" == "ok" ]]; then
            if [[ "$QUIET" == "true" ]]; then
                # W trybie quiet wypisz tylko dane
                echo "$response" | jq -r '.data // empty' 2>/dev/null || echo "$response"
            else
                log_json "$response"
            fi
            return 0
        else
            print_error "Błąd: $(echo "$response" | jq -r '.message // "Nieznany błąd"')"
            return 1
        fi
    else
        print_error "Brak odpowiedzi od daemona (timeout: ${TIMEOUT}s)"
        exit 68  # EX_NOINPUT
    fi
}

# ============================================================================
# Komendy CLI
# ============================================================================

cmd_ping() {
    print_info "Testowanie połączenia z daemonem..."
    send_command "ping"
}

cmd_status() {
    print_info "Status systemu:"
    send_command "status"
}

cmd_sensor_list() {
    print_info "Zarejestrowane sensory:"
    send_command "sensor.list"
}

cmd_sensor_read() {
    local sensor_id="$1"
    
    if [[ -z "$sensor_id" ]]; then
        print_error "Podaj ID sensora: --id <sensor_id>"
        exit 64
    fi
    
    print_info "Odczyt danych z sensora: $sensor_id"
    send_command "sensor.read" "{\"sensor_id\": \"$sensor_id\"}"
}

cmd_sensor_add() {
    local sensor_id="$1"
    local sensor_type="$2"
    local sensor_port="$3"
    
    if [[ -z "$sensor_id" || -z "$sensor_type" || -z "$sensor_port" ]]; then
        print_error "Wymagane parametry: --id <id> --type <usb|ethernet> --port <port>"
        exit 64
    fi
    
    # Walidacja typu
    if [[ ! "$sensor_type" =~ ^(usb|ethernet)$ ]]; then
        print_error "Nieprawidłowy typ sensora: $sensor_type (oczekiwano: usb|ethernet)"
        exit 65  # EX_DATAERR
    fi
    
    print_info "Dodawanie sensora: ID=$sensor_id, TYPE=$sensor_type, PORT=$sensor_port"
    send_command "sensor.add" "{\"sensor_id\": \"$sensor_id\", \"type\": \"$sensor_type\", \"port\": \"$sensor_port\"}"
}

cmd_sensor_remove() {
    local sensor_id="$1"
    
    if [[ -z "$sensor_id" ]]; then
        print_error "Podaj ID sensora: --id <sensor_id>"
        exit 64
    fi
    
    print_warn "Usuwanie sensora: $sensor_id"
    send_command "sensor.remove" "{\"sensor_id\": \"$sensor_id\"}"
}

cmd_data_get() {
    local sensor_id="$1"
    
    if [[ -z "$sensor_id" ]]; then
        print_error "Podaj ID sensora: --id <sensor_id>"
        exit 64
    fi
    
    print_debug "Pobieranie danych z sensora: $sensor_id"
    send_command "data.get" "{\"sensor_id\": \"$sensor_id\"}"
}

cmd_shutdown() {
    print_warn "Wysyłanie polecenia zamknięcia daemona..."
    send_command "shutdown"
}

# ============================================================================
# Pomoc i użycie
# ============================================================================

show_usage() {
    cat <<EOF
Medical System CLI - Klient dla daemona medycznego

Użycie: $(basename "$0") [opcje] <komenda> [argumenty]

KOMENDY:
  ping                      Test połączenia z daemonem
  status                    Pokaż status wszystkich sensorów
  sensor list               Lista zarejestrowanych sensorów
  sensor read --id <id>     Odczytaj dane z konkretnego sensora
  sensor add --id <id> --type <typ> --port <port>
                            Dodaj nowy sensor ręcznie
  sensor remove --id <id>   Usuń sensor z rejestru
  data get --id <id>        Pobierz ostatnie dane z sensora
  shutdown                  Zatrzymaj daemon zdalnie

OPCJE GLOBALNE:
  -t, --timeout <sec>       Timeout połączenia (domyślnie: 5)
  -v, --verbose             Tryb szczegółowy (debug)
  -q, --quiet               Tryb cichy (tylko dane)
  --no-color                Wyłącz kolory w outputcie
  -h, --help                Pokaż tę pomoc

PRZYKŁADY UŻYCIA:
  # Sprawdź czy daemon działa
  $(basename "$0") ping
  
  # Pokaż wszystkie sensory
  $(basename "$0") status
  
  # Lista sensorów
  $(basename "$0") sensor list
  
  # Odczytaj dane z sensora USB
  $(basename "$0") sensor read --id usb_ttyUSB0
  
  # Dodaj sensor Ethernet ręcznie
  $(basename "$0") sensor add --id eth_192_168_1_100 --type ethernet --port 192.168.1.100
  
  # Pobierz dane w formacie JSON (tryb cichy)
  $(basename "$0") -q data get --id usb_ttyUSB0
  
  # Zatrzymaj daemon
  $(basename "$0") shutdown

TYPY SENSORÓW:
  usb       - Arduino Nano podłączone przez USB (/dev/ttyUSB*, /dev/ttyACM*)
  ethernet  - Raspberry Pi Pico W lub Arduino z Ethernet (adres IP)

FORMAT DANYCH:
  Daemon oczekuje danych w formacie JSON od sensorów Ethernet:
  {"sensor":"temp","value":25.5,"unit":"C","timestamp":1234567890}
  
  Dla sensorów USB dane są odczytywane jako tekst linia po linii.

KODY WYJŚCIA:
  0   - Sukces
  64  - Błąd składni/użycia (EX_USAGE)
  65  - Błąd danych (EX_DATAERR)
  68  - Brak odpowiedzi (EX_NOINPUT)
  69  - Daemon niedostępny (EX_UNAVAILABLE)
  70  - Błąd wewnętrzny (EX_SOFTWARE)
EOF
}

# ============================================================================
# Main
# ============================================================================

SENSOR_ID=""
SENSOR_TYPE=""
SENSOR_PORT=""
COMMAND=""
SUBCOMMAND=""

# Parsowanie argumentów
while [[ $# -gt 0 ]]; do
    case "$1" in
        ping)
            COMMAND="ping"
            shift
            ;;
        status)
            COMMAND="status"
            shift
            ;;
        sensor)
            COMMAND="sensor"
            shift
            ;;
        list)
            SUBCOMMAND="list"
            shift
            ;;
        read)
            SUBCOMMAND="read"
            shift
            ;;
        add)
            SUBCOMMAND="add"
            shift
            ;;
        remove)
            SUBCOMMAND="remove"
            shift
            ;;
        data)
            COMMAND="data"
            shift
            ;;
        get)
            SUBCOMMAND="get"
            shift
            ;;
        shutdown)
            COMMAND="shutdown"
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        --no-color)
            NO_COLOR=true
            export NO_COLOR=1
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        --id)
            SENSOR_ID="$2"
            shift 2
            ;;
        --type)
            SENSOR_TYPE="$2"
            shift 2
            ;;
        --port)
            SENSOR_PORT="$2"
            shift 2
            ;;
        *)
            print_error "Nieznana opcja: $1"
            show_usage
            exit 64
            ;;
    esac
done

# Wykonaj komendę
case "$COMMAND" in
    ping)
        cmd_ping
        ;;
    status)
        cmd_status
        ;;
    sensor)
        case "$SUBCOMMAND" in
            list)
                cmd_sensor_list
                ;;
            read)
                cmd_sensor_read "$SENSOR_ID"
                ;;
            add)
                cmd_sensor_add "$SENSOR_ID" "$SENSOR_TYPE" "$SENSOR_PORT"
                ;;
            remove)
                cmd_sensor_remove "$SENSOR_ID"
                ;;
            "")
                print_error "Podaj podkomendę: list, read, add, remove"
                show_usage
                exit 64
                ;;
            *)
                print_error "Nieznana podkomenda sensor: $SUBCOMMAND"
                exit 64
                ;;
        esac
        ;;
    data)
        case "$SUBCOMMAND" in
            get)
                cmd_data_get "$SENSOR_ID"
                ;;
            "")
                print_error "Podaj podkomendę: get"
                show_usage
                exit 64
                ;;
            *)
                print_error "Nieznana podkomenda data: $SUBCOMMAND"
                exit 64
                ;;
        esac
        ;;
    shutdown)
        cmd_shutdown
        ;;
    "")
        show_usage
        exit 0
        ;;
    *)
        print_error "Nieznana komenda: $COMMAND"
        show_usage
        exit 64
        ;;
esac
