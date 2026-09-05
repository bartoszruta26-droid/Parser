#!/bin/bash
#
# Medical System Daemon
# Główny daemon zbierający dane z sensorów (USB/Ethernet Arduino Nano, Raspberry Pi Pico)
# i udostępniający je przez CLI
#

set -euo pipefail

# Konfiguracja
DAEMON_NAME="medical-daemon"
PID_FILE="/workspace/medical-system/run/${DAEMON_NAME}.pid"
LOG_FILE="/workspace/medical-system/logs/${DAEMON_NAME}.log"
SOCKET_FILE="/workspace/medical-system/run/${DAEMON_NAME}.sock"
CONFIG_FILE="/workspace/medical-system/config/daemon.conf"
SENSOR_DIR="/workspace/medical-system/sensors"
DATA_DIR="/workspace/medical-system/data"

# Domyślne wartości konfiguracyjne
POLL_INTERVAL=5
MAX_SENSORS=32
BUFFER_SIZE=1000
LOG_LEVEL="INFO"

# Kolory dla logów
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Poziomy logowania
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["WARN"]=2
    ["ERROR"]=3
)

# ============================================================================
# Funkcje pomocnicze
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Sprawdź czy poziom logowania jest wystarczający
    local current_level=${LOG_LEVELS[$LOG_LEVEL]:-1}
    local msg_level=${LOG_LEVELS[$level]:-1}
    
    if [[ $msg_level -ge $current_level ]]; then
        local color=""
        case "$level" in
            DEBUG) color="$BLUE" ;;
            INFO)  color="$GREEN" ;;
            WARN)  color="$YELLOW" ;;
            ERROR) color="$RED" ;;
        esac
        
        echo -e "${timestamp} [${color}${level}${NC}] $message" >> "$LOG_FILE"
        
        # Jeśli nie jesteśmy w trybie daemon, wypisuj na stdout
        if [[ ! ${DAEMONIZE:-false} == "true" ]]; then
            echo -e "${timestamp} [${color}${level}${NC}] $message" >&2
        fi
    fi
}

log_debug() { log "DEBUG" "$@"; }
log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Wczytywanie konfiguracji z $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log_warn "Plik konfiguracyjny nie istnieje, używam domyślnych wartości"
    fi
}

check_pid() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

cleanup() {
    log_info "Oczyszczanie zasobów..."
    
    # Zamknij socket UNIX
    if [[ -S "$SOCKET_FILE" ]]; then
        rm -f "$SOCKET_FILE"
    fi
    
    # Usuń PID file
    rm -f "$PID_FILE"
    
    log_info "Daemon zatrzymany"
}

# ============================================================================
# Obsługa sensorów
# ============================================================================

# Struktura danych sensora (w tablicach asocjacyjnych)
declare -A SENSORS_ID
declare -A SENSORS_TYPE      # usb, ethernet
declare -A SENSORS_PORT      # /dev/ttyUSB0, 192.168.1.100
declare -A SENSORS_STATUS    # connected, disconnected, error
declare -A SENSORS_LAST_READ # timestamp ostatniego odczytu
declare -A SENSORS_DATA      # ostatnie dane z sensora

sensor_count=0

register_sensor() {
    local id="$1"
    local type="$2"
    local port="$3"
    
    if [[ $sensor_count -ge $MAX_SENSORS ]]; then
        log_error "Osiągnięto maksymalną liczbę sensorów ($MAX_SENSORS)"
        return 1
    fi
    
    SENSORS_ID[$id]="$id"
    SENSORS_TYPE[$id]="$type"
    SENSORS_PORT[$id]="$port"
    SENSORS_STATUS[$id]="connected"
    SENSORS_LAST_READ[$id]=$(date +%s)
    SENSORS_DATA[$id]=""
    
    ((sensor_count++))
    log_info "Zarejestrowano sensor: ID=$id, TYPE=$type, PORT=$port"
    return 0
}

unregister_sensor() {
    local id="$1"
    
    if [[ -v SENSORS_ID[$id] ]]; then
        unset SENSORS_ID[$id]
        unset SENSORS_TYPE[$id]
        unset SENSORS_PORT[$id]
        unset SENSORS_STATUS[$id]
        unset SENSORS_LAST_READ[$id]
        unset SENSORS_DATA[$id]
        
        ((sensor_count--))
        log_info "Wyrejestrowano sensor: ID=$id"
        return 0
    fi
    return 1
}

# Wykrywanie sensorów USB (Arduino Nano)
detect_usb_sensors() {
    log_debug "Skanowanie portów USB..."
    
    for device in /dev/ttyUSB* /dev/ttyACM*; do
        if [[ -e "$device" ]]; then
            local basename=$(basename "$device")
            local sensor_id="usb_${basename}"
            
            if [[ ! -v SENSORS_ID[$sensor_id] ]]; then
                log_info "Wykryto nowy sensor USB: $device"
                register_sensor "$sensor_id" "usb" "$device"
                
                # Inicjalizacja portu szeregowego
                stty -F "$device" 9600 cs8 -cstopb -parenb 2>/dev/null || true
            fi
        fi
    done
}

# Wykrywanie sensorów Ethernet (Raspberry Pi Pico W, Arduino z shieldem Ethernet)
detect_ethernet_sensors() {
    log_debug "Skanowanie sensorów Ethernet..."
    
    # Przykładowa lista IP do sprawdzenia (w produkcji można użyć discovery protocol)
    local -a known_ips=(
        "192.168.1.100"
        "192.168.1.101"
        "192.168.1.102"
    )
    
    for ip in "${known_ips[@]}"; do
        local sensor_id="eth_${ip//./_}"
        
        # Sprawdź czy sensor jest osiągalny
        if ping -c 1 -W 1 "$ip" &>/dev/null; then
            if [[ ! -v SENSORS_ID[$sensor_id] ]]; then
                log_info "Wykryto nowy sensor Ethernet: $ip"
                register_sensor "$sensor_id" "ethernet" "$ip"
            fi
            
            # Aktualizuj status
            SENSORS_STATUS[$sensor_id]="connected"
        else
            if [[ -v SENSORS_ID[$sensor_id] ]]; then
                SENSORS_STATUS[$sensor_id]="disconnected"
                log_warn "Sensor Ethernet niedostępny: $ip"
            fi
        fi
    done
}

# Odczyt danych z sensora USB
read_usb_sensor() {
    local sensor_id="$1"
    local port="${SENSORS_PORT[$sensor_id]}"
    
    if [[ ! -e "$port" ]]; then
        SENSORS_STATUS[$sensor_id]="error"
        log_error "Port niedostępny: $port"
        return 1
    fi
    
    # Odczytaj dane z portu szeregowego (timeout 2s)
    local data
    data=$(timeout 2 cat "$port" 2>/dev/null | head -n 1 || echo "")
    
    if [[ -n "$data" ]]; then
        SENSORS_DATA[$sensor_id]="$data"
        SENSORS_LAST_READ[$sensor_id]=$(date +%s)
        SENSORS_STATUS[$sensor_id]="connected"
        log_debug "Odczytano z $sensor_id: $data"
        return 0
    else
        log_warn "Brak danych z sensora USB: $sensor_id"
        return 1
    fi
}

# Odczyt danych z sensora Ethernet (HTTP GET lub TCP)
read_ethernet_sensor() {
    local sensor_id="$1"
    local ip="${SENSORS_PORT[$sensor_id]}"
    
    # Spróbuj pobrać dane przez HTTP (typowe dla Pico W)
    local data
    data=$(curl -s --connect-timeout 2 "http://$ip/data" 2>/dev/null || echo "")
    
    if [[ -z "$data" ]]; then
        # Spróbuj przez TCP socket
        data=$(timeout 2 bash -c "echo 'GET_DATA' | nc -w 1 $ip 8080 2>/dev/null" || echo "")
    fi
    
    if [[ -n "$data" ]]; then
        SENSORS_DATA[$sensor_id]="$data"
        SENSORS_LAST_READ[$sensor_id]=$(date +%s)
        SENSORS_STATUS[$sensor_id]="connected"
        log_debug "Odczytano z $sensor_id: $data"
        return 0
    else
        log_warn "Brak danych z sensora Ethernet: $sensor_id"
        return 1
    fi
}

# Główna pętla odczytu sensorów
poll_sensors() {
    log_debug "Polling sensorów..."
    
    for sensor_id in "${!SENSORS_ID[@]}"; do
        local type="${SENSORS_TYPE[$sensor_id]}"
        
        case "$type" in
            usb)
                read_usb_sensor "$sensor_id" || true
                ;;
            ethernet)
                read_ethernet_sensor "$sensor_id" || true
                ;;
        esac
    done
}

# ============================================================================
# Komunikacja przez socket UNIX (CLI <-> Daemon)
# ============================================================================

handle_client_request() {
    local request="$1"
    local response=""
    
    log_debug "Otrzymano żądanie: $request"
    
    # Parsowanie żądania
    local command=$(echo "$request" | jq -r '.command // empty' 2>/dev/null)
    
    case "$command" in
        ping)
            response='{"status":"ok","message":"pong","timestamp":'$(date +%s)'}'
            ;;
        
        status)
            local sensors_json="["
            local first=true
            for sensor_id in "${!SENSORS_ID[@]}"; do
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    sensors_json+=","
                fi
                sensors_json+=$(cat <<EOF
{
    "id": "$sensor_id",
    "type": "${SENSORS_TYPE[$sensor_id]}",
    "port": "${SENSORS_PORT[$sensor_id]}",
    "status": "${SENSORS_STATUS[$sensor_id]}",
    "last_read": ${SENSORS_LAST_READ[$sensor_id]},
    "data": "${SENSORS_DATA[$sensor_id]}"
}
EOF
)
            done
            sensors_json+="]"
            
            response=$(cat <<EOF
{
    "status": "ok",
    "daemon": "$DAEMON_NAME",
    "sensor_count": $sensor_count,
    "sensors": $sensors_json,
    "timestamp": $(date +%s)
}
EOF
)
            ;;
        
        sensor.read)
            local target_sensor=$(echo "$request" | jq -r '.sensor_id // empty' 2>/dev/null)
            if [[ -n "$target_sensor" && -v SENSORS_ID[$target_sensor] ]]; then
                # Wymuś odczyt
                local type="${SENSORS_TYPE[$target_sensor]}"
                case "$type" in
                    usb) read_usb_sensor "$target_sensor" || true ;;
                    ethernet) read_ethernet_sensor "$target_sensor" || true ;;
                esac
                
                response=$(cat <<EOF
{
    "status": "ok",
    "sensor_id": "$target_sensor",
    "data": "${SENSORS_DATA[$target_sensor]}",
    "timestamp": ${SENSORS_LAST_READ[$target_sensor]}
}
EOF
)
            else
                response='{"status":"error","message":"Sensor not found"}'
            fi
            ;;
        
        sensor.list)
            local ids=""
            for sensor_id in "${!SENSORS_ID[@]}"; do
                if [[ -n "$ids" ]]; then
                    ids+=","
                fi
                ids+="\"$sensor_id\""
            done
            response="{\"status\":\"ok\",\"sensors\":[$ids],\"count\":$sensor_count}"
            ;;
        
        sensor.add)
            local new_id=$(echo "$request" | jq -r '.sensor_id // empty' 2>/dev/null)
            local new_type=$(echo "$request" | jq -r '.type // empty' 2>/dev/null)
            local new_port=$(echo "$request" | jq -r '.port // empty' 2>/dev/null)
            
            if [[ -n "$new_id" && -n "$new_type" && -n "$new_port" ]]; then
                if register_sensor "$new_id" "$new_type" "$new_port"; then
                    response="{\"status\":\"ok\",\"message\":\"Sensor added\",\"sensor_id\":\"$new_id\"}"
                else
                    response="{\"status\":\"error\",\"message\":\"Failed to add sensor\"}"
                fi
            else
                response="{\"status\":\"error\",\"message\":\"Missing parameters\"}"
            fi
            ;;
        
        sensor.remove)
            local remove_id=$(echo "$request" | jq -r '.sensor_id // empty' 2>/dev/null)
            if [[ -n "$remove_id" ]]; then
                if unregister_sensor "$remove_id"; then
                    response="{\"status\":\"ok\",\"message\":\"Sensor removed\",\"sensor_id\":\"$remove_id\"}"
                else
                    response="{\"status\":\"error\",\"message\":\"Sensor not found\"}"
                fi
            else
                response="{\"status\":\"error\",\"message\":\"Missing sensor_id\"}"
            fi
            ;;
        
        data.get)
            local target_sensor=$(echo "$request" | jq -r '.sensor_id // empty' 2>/dev/null)
            if [[ -n "$target_sensor" && -v SENSORS_ID[$target_sensor] ]]; then
                response=$(cat <<EOF
{
    "status": "ok",
    "sensor_id": "$target_sensor",
    "data": "${SENSORS_DATA[$target_sensor]}",
    "timestamp": ${SENSORS_LAST_READ[$target_sensor]}
}
EOF
)
            else
                response='{"status":"error","message":"Sensor not found"}'
            fi
            ;;
        
        shutdown)
            log_info "Otrzymano żądanie zamknięcia"
            response='{"status":"ok","message":"Shutting down"}'
            echo "$response"
            cleanup
            exit 0
            ;;
        
        *)
            response="{\"status\":\"error\",\"message\":\"Unknown command: $command\"}"
            ;;
    esac
    
    echo "$response"
}

start_socket_server() {
    log_info "Uruchamianie serwera socket na $SOCKET_FILE"
    
    # Usuń stary socket jeśli istnieje
    rm -f "$SOCKET_FILE"
    
    # Utwórz socket UNIX
    exec 3<>"$SOCKET_FILE"
    chmod 660 "$SOCKET_FILE"
    
    log_info "Serwer socket gotowy"
}

process_socket_requests() {
    while true; do
        # Sprawdź czy są połączenia do obsługi (prosta implementacja)
        if read -t 1 -r request <&3 2>/dev/null; then
            local response
            response=$(handle_client_request "$request")
            echo "$response" >&3
        fi
        
        # Polling sensorów
        poll_sensors
        
        # Sprawdzaj co POLL_INTERVAL sekund
        sleep "$POLL_INTERVAL"
    done
}

# ============================================================================
# Zarządzanie daemonem
# ============================================================================

start_daemon() {
    if check_pid; then
        echo "Daemon już działa (PID: $(cat "$PID_FILE"))"
        exit 1
    fi
    
    log_info "Uruchamianie daemona..."
    
    # Zapisz PID
    echo $$ > "$PID_FILE"
    
    # Załaduj konfigurację
    load_config
    
    # Utwórz socket
    start_socket_server
    
    # Wykryj sensory na starcie
    detect_usb_sensors
    detect_ethernet_sensors
    
    log_info "Daemon uruchomiony (PID: $$)"
    
    # Puść w tło jeśli daemonize
    if [[ ${DAEMONIZE:-false} == "true" ]]; then
        exec >/dev/null 2>&1 </dev/null
    fi
    
    # Główna pętla
    trap cleanup EXIT INT TERM
    process_socket_requests
}

stop_daemon() {
    if check_pid; then
        local pid=$(cat "$PID_FILE")
        log_info "Zatrzymywanie daemona (PID: $pid)"
        kill "$pid"
        
        # Czekaj na zakończenie
        local timeout=10
        while kill -0 "$pid" 2>/dev/null && [[ $timeout -gt 0 ]]; do
            sleep 1
            ((timeout--))
        done
        
        if kill -0 "$pid" 2>/dev/null; then
            log_warn "Daemon nie zatrzymał się łagodnie, wysyłam SIGKILL"
            kill -9 "$pid"
        fi
        
        rm -f "$PID_FILE"
        echo "Daemon zatrzymany"
    else
        echo "Daemon nie działa"
        exit 1
    fi
}

restart_daemon() {
    stop_daemon || true
    sleep 1
    start_daemon
}

daemon_status() {
    if check_pid; then
        local pid=$(cat "$PID_FILE")
        echo "Daemon działa (PID: $pid)"
        echo "Socket: $SOCKET_FILE"
        echo "Logi: $LOG_FILE"
        echo "Sensory: $sensor_count"
        exit 0
    else
        echo "Daemon nie działa"
        exit 1
    fi
}

# ============================================================================
# Interfejs CLI dla daemona
# ============================================================================

cli_send_command() {
    local command="$1"
    local extra_data="${2:-}"
    
    if [[ ! -S "$SOCKET_FILE" ]]; then
        echo '{"status":"error","message":"Daemon nie działa lub socket niedostępny"}' >&2
        exit 69  # EX_UNAVAILABLE
    fi
    
    # Zbuduj żądanie JSON
    local request
    if [[ -n "$extra_data" ]]; then
        request=$(jq -n --arg cmd "$command" --argjson data "$extra_data" \
            '{command: $cmd} + $data')
    else
        request=$(jq -n --arg cmd "$command" '{command: $cmd}')
    fi
    
    # Wyślij żądanie i odbierz odpowiedź
    local response
    response=$(echo "$request" | timeout 5 socat - UNIX-CONNECT:"$SOCKET_FILE" 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$response" ]]; then
        echo "$response" | jq .
    else
        echo '{"status":"error","message":"Brak odpowiedzi od daemona"}' >&2
        exit 68  # EX_NOINPUT
    fi
}

# ============================================================================
# Main
# ============================================================================

show_usage() {
    cat <<EOF
Użycie: $0 {start|stop|restart|status|command} [opcje]

Komendy zarządzania:
  start           Uruchom daemon
  stop            Zatrzymaj daemon
  restart         Restartuj daemon
  status          Pokaż status daemona

Komendy CLI (wymagają działającego daemona):
  command ping              Test połączenia
  command status            Pokaż status wszystkich sensorów
  command sensor.list       Lista zarejestrowanych sensorów
  command sensor.read --id <sensor_id>  Odczytaj dane z sensora
  command sensor.add --id <id> --type <usb|ethernet> --port <port>
  command sensor.remove --id <sensor_id>
  command data.get --id <sensor_id>     Pobierz ostatnie dane
  command shutdown          Zatrzymaj daemon zdalnie

Opcje globalne:
  -c, --config <file>   Plik konfiguracyjny
  -l, --log-level <lvl> Poziom logowania (DEBUG|INFO|WARN|ERROR)
  -d, --daemonize       Uruchom w tle jako daemon
  -h, --help            Pokaż tę pomoc

Przykłady:
  $0 start --daemonize
  $0 command ping
  $0 command sensor.list
  $0 command sensor.read --id usb_ttyUSB0
  $0 command sensor.add --id eth_192_168_1_100 --type ethernet --port 192.168.1.100
EOF
}

# Parsowanie argumentów
ACTION=""
declare -A CMD_ARGS

while [[ $# -gt 0 ]]; do
    case "$1" in
        start|stop|restart|status|command)
            ACTION="$1"
            shift
            ;;
        --daemonize|-d)
            DAEMONIZE=true
            shift
            ;;
        --config|-c)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --log-level|-l)
            LOG_LEVEL="$2"
            shift 2
            ;;
        --id)
            CMD_ARGS[id]="$2"
            shift 2
            ;;
        --type)
            CMD_ARGS[type]="$2"
            shift 2
            ;;
        --port)
            CMD_ARGS[port]="$2"
            shift 2
            ;;
        ping|status|sensor.list|sensor.read|sensor.add|sensor.remove|data.get|shutdown)
            SUBCOMMAND="$1"
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo "Nieznana opcja: $1" >&2
            show_usage
            exit 64  # EX_USAGE
            ;;
    esac
done

# Wykonaj akcję
case "$ACTION" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        restart_daemon
        ;;
    status)
        daemon_status
        ;;
    command)
        if [[ -z "${SUBCOMMAND:-}" ]]; then
            echo "Brak podkomendy" >&2
            exit 64
        fi
        
        # Zbuduj dodatkowe dane JSON
        extra_data="{}"
        case "$SUBCOMMAND" in
            sensor.read|sensor.remove|data.get)
                if [[ -n "${CMD_ARGS[id]:-}" ]]; then
                    extra_data=$(jq -n --arg id "${CMD_ARGS[id]}" '{sensor_id: $id}')
                fi
                ;;
            sensor.add)
                if [[ -n "${CMD_ARGS[id]:-}" && -n "${CMD_ARGS[type]:-}" && -n "${CMD_ARGS[port]:-}" ]]; then
                    extra_data=$(jq -n \
                        --arg id "${CMD_ARGS[id]}" \
                        --arg type "${CMD_ARGS[type]}" \
                        --arg port "${CMD_ARGS[port]}" \
                        '{sensor_id: $id, type: $type, port: $port}')
                else
                    echo "Błąd: sensor.add wymaga --id, --type i --port" >&2
                    exit 64
                fi
                ;;
        esac
        
        cli_send_command "$SUBCOMMAND" "$extra_data"
        ;;
    "")
        show_usage
        exit 64
        ;;
    *)
        echo "Nieznana akcja: $ACTION" >&2
        show_usage
        exit 64
        ;;
esac
