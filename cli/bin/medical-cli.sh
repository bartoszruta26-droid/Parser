#!/usr/bin/env bash
set -Eeuo pipefail

# Medical Daemon CLI - Klient wiersza poleceń do komunikacji z daemonem medycznym
# Obsługuje wszystkie komendy protokołu: ping, status, patient.data, biosensor.data,
# biofeedback.data, medical.fhir, medical.hl7, swarm.*, backend.job, shutdown

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CONFIG_FILE="${DAEMON_CONFIG:-/etc/medical-daemon/daemon.conf}"
FALLBACK_CONFIG="${PROJECT_ROOT}/config/medical-daemon.conf.example"

if [[ -r "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
elif [[ -r "$FALLBACK_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$FALLBACK_CONFIG"
else
  echo "No daemon configuration found: $CONFIG_FILE" >&2
  exit 78
fi

RUN_DIR="${RUN_DIR:-/tmp/medical-daemon}"
COMMAND_FIFO="${COMMAND_FIFO:-${RUN_DIR}/commands.fifo}"
RESPONSE_DIR="${RESPONSE_DIR:-${RUN_DIR}/responses}"
REQUEST_TIMEOUT_SECONDS="${REQUEST_TIMEOUT_SECONDS:-10}"
PROTOCOL_VERSION="${PROTOCOL_VERSION:-1}"

# Kolory dla outputu (można wyłączyć przez --no-color)
USE_COLOR="${USE_COLOR:-true}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

colorize() {
  if [[ "$USE_COLOR" == "true" ]] && [[ -t 1 ]]; then
    printf '%b%s%b' "$1" "$2" "$NC"
  else
    printf '%s' "$2"
  fi
}

usage() {
  cat <<USAGE
$(colorize "$BLUE" "Medical Daemon CLI") - Klient wiersza poleceń do komunikacji z daemonem medycznym

$(colorize "$GREEN" "UŻYCIE:")
  $0 <komenda> [opcje] [dane]

$(colorize "$GREEN" "KOMENDY:")
  $(colorize "$YELLOW" "ping")                     Sprawdzenie dostępności daemona
  $(colorize "$YELLOW" "status")                   Pobranie statusu daemona i kolejek
  $(colorize "$YELLOW" "patient.data")             Wysyłanie danych pacjenta (podmiotowe/przedmiotowe)
  $(colorize "$YELLOW" "biosensor.data")           Wysyłanie danych z czujników biosensor
  $(colorize "$YELLOW" "biofeedback.data")         Wysyłanie danych z czujników biofeedback
  $(colorize "$YELLOW" "medical.fhir")             Wysyłanie wiadomości FHIR
  $(colorize "$YELLOW" "medical.hl7")              Wysyłanie wiadomości HL7v2
  $(colorize "$YELLOW" "medical.message")          Wysyłanie ogólnej wiadomości medycznej
  $(colorize "$YELLOW" "swarm.sensor")             Przekazywanie danych sensorów RPi
  $(colorize "$YELLOW" "swarm.effector")           Przekazywanie komend efektorów RPi
  $(colorize "$YELLOW" "swarm.forward")            Przekazywanie między daemonami RPi
  $(colorize "$YELLOW" "backend.job")              Wysyłanie zadania z backendu
  $(colorize "$YELLOW" "shutdown")                 Zatrzymanie daemona

$(colorize "$GREEN" "OPCJE OGÓLNE:")
  -h, --help                 Wyświetlenie tego helpa
  -v, --verbose              Tryb verbose (szczegółowy output)
  --no-color                 Wyłączenie kolorów w outputcie
  -t, --timeout SECONDS      Timeout na odpowiedź (domyślnie: $REQUEST_TIMEOUT_SECONDS)
  -f, --file FILE            Wczytaj dane z pliku zamiast z argumentu
  -s, --source SOURCE        Źródło danych (domyślnie: cli)
  -q, --quiet                Tylko JSON response, bez formatowania

$(colorize "$GREEN" "PRZYKŁADY:")
  $(colorize "$BLUE" "# Sprawdzenie dostępności")
  $0 ping

  $(colorize "$BLUE" "# Status daemona")
  $0 status

  $(colorize "$BLUE" "# Dane pacjenta z JSON")
  $0 patient.data '{"patient_id":"123","name":"Jan Kowalski"}'

  $(colorize "$BLUE" "# Dane pacjenta z pliku")
  $0 patient.data -f patient_data.json

  $(colorize "$BLUE" "# Wiadomość FHIR")
  $0 medical.fhir '{"resourceType":"Patient","id":"example"}'

  $(colorize "$BLUE" "# Biosensor z określeniem źródła")
  $0 biosensor.data -s sensor-01 '{"heart_rate":72,"spo2":98}'

  $(colorize "$BLUE" "# Shutdown daemona")
  $0 shutdown

$(colorize "$GREEN" "ZMIENNE ŚRODOWISKOWE:")
  DAEMON_CONFIG              Ścieżka do pliku konfiguracyjnego
  RUN_DIR                    Katalog runtime (/tmp/medical-daemon)
  REQUEST_TIMEOUT_SECONDS    Timeout na odpowiedź (sekundy)
  USE_COLOR                  true/false - kolory w outputcie

USAGE
}

# Generowanie unikalnego request_id
new_request_id() {
  local prefix="${1:-cli}"
  printf '%s-%s-%s-%s' "$prefix" "$(date +%s%N)" "$$" "$RANDOM"
}

# Walidacja request_id (zabezpieczenie przed path traversal)
validate_request_id() {
  local req_id="$1"
  if [[ -z "$req_id" ]] || [[ "$req_id" == *"/"* ]] || [[ "$req_id" == *".."* ]]; then
    return 1
  fi
  return 0
}

# Zapisanie polecenia do FIFO z timeoutem
write_command_fifo() {
  local request_id="$1"
  local command="$2"
  local payload="$3"
  local source="$4"
  local deadline="$5"
  local writer_pid

  # Base64-encode payload to safely handle multiline JSON
  local encoded_payload
  encoded_payload=$(printf '%s' "$payload" | base64 -w 0)

  (printf '%s|%s|%s|%s\n' "$request_id" "$source" "$command" "$encoded_payload" > "$COMMAND_FIFO") &
  writer_pid=$!

  while kill -0 "$writer_pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      kill "$writer_pid" 2>/dev/null || true
      wait "$writer_pid" 2>/dev/null || true
      echo "Timed out waiting for daemon FIFO reader: $COMMAND_FIFO" >&2
      return 70
    fi
    sleep 0.1
  done

  if ! wait "$writer_pid"; then
    echo "Unable to write daemon command FIFO: $COMMAND_FIFO" >&2
    return 69
  fi
}

# Wysyłanie komendy i oczekiwanie na odpowiedź
send_command() {
  local command="$1"
  local payload="${2:-}"
  local source="${3:-cli}"
  local timeout="${4:-$REQUEST_TIMEOUT_SECONDS}"
  local quiet="${5:-false}"
  local verbose="${6:-false}"
  
  local request_id response_file deadline
  
  request_id="$(new_request_id "$command")"
  response_file="$RESPONSE_DIR/${request_id}.json"

  # Sprawdzenie istnienia FIFO
  if [[ ! -p "$COMMAND_FIFO" ]]; then
    echo "Daemon command FIFO does not exist: $COMMAND_FIFO" >&2
    echo "Uruchom daemon: ./daemon/bin/medical-daemon.sh" >&2
    exit 69
  fi

  # Cleanup starej odpowiedzi jeśli istnieje
  rm -f "$response_file"

  deadline=$((SECONDS + timeout))
  
  if [[ "$verbose" == "true" ]]; then
    echo "Sending command: $command" >&2
    echo "Request ID: $request_id" >&2
    echo "Source: $source" >&2
    echo "Payload: $payload" >&2
    echo "Response file: $response_file" >&2
  fi

  write_command_fifo "$request_id" "$command" "$payload" "$source" "$deadline" || exit $?

  # Oczekiwanie na odpowiedź
  while [[ ! -f "$response_file" ]]; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for daemon response: $response_file" >&2
      exit 70
    fi
    sleep 0.1
  done

  # Odczyt i przetworzenie odpowiedzi
  local response
  response="$(cat "$response_file")"
  
  # Cleanup odpowiedzi
  rm -f "$response_file"

  # Output
  if [[ "$quiet" == "true" ]]; then
    printf '%s\n' "$response"
  else
    # Formatowanie JSON z kolorami
    if command -v jq &>/dev/null; then
      local status code message
      status=$(echo "$response" | jq -r '.status // "unknown"')
      code=$(echo "$response" | jq -r '.code // "UNKNOWN"')
      message=$(echo "$response" | jq -r '.message // ""')
      
      case "$status" in
        ok|accepted)
          printf '%b' "$(colorize "$GREEN" "✓ Status: $status")"
          ;;
        rejected)
          printf '%b' "$(colorize "$YELLOW" "⚠ Status: $status")"
          ;;
        error|*)
          printf '%b' "$(colorize "$RED" "✗ Status: $status")"
          ;;
      esac
      
      printf ' | Code: %s | Message: %s\n' "$code" "$message"
      printf '\n%s\n' "$(echo "$response" | jq .)"
    else
      printf '%s\n' "$response"
    fi
  fi
}

# Parsowanie danych z pliku lub argumentu
get_payload() {
  local input="$1"
  local from_file="$2"
  
  if [[ "$from_file" == "true" ]]; then
    if [[ ! -r "$input" ]]; then
      echo "File not readable: $input" >&2
      exit 66
    fi
    cat "$input"
  else
    printf '%s' "$input"
  fi
}

# Walidacja JSON
validate_json() {
  local json="$1"
  if command -v jq &>/dev/null; then
    if echo "$json" | jq . >/dev/null 2>&1; then
      return 0
    else
      return 1
    fi
  else
    # Bez jq - podstawowa walidacja
    if [[ "$json" =~ ^\{.*\}$ ]] || [[ "$json" =~ ^\[.*\]$ ]]; then
      return 0
    fi
    return 1
  fi
}

# Główna logika
VERBOSE="false"
QUIET="false"
FROM_FILE="false"
SOURCE="cli"
TIMEOUT="$REQUEST_TIMEOUT_SECONDS"
COMMAND=""
PAYLOAD_FILE_ARG=""

# Parsowanie argumentów - obsługa opcji przed i po komendzie
# Najpierw znajdziemy komendę, potem parsujemy resztę
parse_arguments() {
  local found_command="false"
  
  while [[ $# -gt 0 ]]; do
    if [[ "$found_command" == "false" ]]; then
      case "$1" in
        -h|--help)
          usage
          exit 0
          ;;
        -v|--verbose)
          VERBOSE="true"
          shift
          ;;
        --no-color)
          USE_COLOR="false"
          shift
          ;;
        -q|--quiet)
          QUIET="true"
          shift
          ;;
        -t|--timeout)
          TIMEOUT="$2"
          shift 2
          ;;
        -f|--file)
          FROM_FILE="true"
          PAYLOAD_FILE_ARG="$2"
          shift 2
          ;;
        -s|--source)
          SOURCE="$2"
          shift 2
          ;;
        -*)
          # Nieznana opcja przed komendą - traktuj jako błąd
          echo "Unknown option before command: $1" >&2
          exit 64
          ;;
        *)
          # To jest komenda
          COMMAND="$1"
          found_command="true"
          shift
          ;;
      esac
    else
      # Po komendzie - parsuj opcje lub payload
      case "$1" in
        -v|--verbose)
          VERBOSE="true"
          shift
          ;;
        --no-color)
          USE_COLOR="false"
          shift
          ;;
        -q|--quiet)
          QUIET="true"
          shift
          ;;
        -t|--timeout)
          TIMEOUT="$2"
          shift 2
          ;;
        -f|--file)
          FROM_FILE="true"
          PAYLOAD_FILE_ARG="$2"
          shift 2
          ;;
        -s|--source)
          SOURCE="$2"
          shift 2
          ;;
        -*)
          # Nieznana opcja po komendzie
          echo "Unknown option: $1" >&2
          exit 64
          ;;
        *)
          # To jest payload (jeśli jeszcze nie ustawiony z -f)
          if [[ -z "$PAYLOAD_FILE_ARG" ]]; then
            PAYLOAD_FILE_ARG="$1"
          fi
          shift
          ;;
      esac
    fi
  done
}

parse_arguments "$@"

# Sprawdzenie komendy
if [[ -z "$COMMAND" ]]; then
  usage
  exit 64
fi

# Pobranie payloadu
PAYLOAD=""
if [[ -n "$PAYLOAD_FILE_ARG" ]]; then
  PAYLOAD="$(get_payload "$PAYLOAD_FILE_ARG" "$FROM_FILE")"
fi

# Walidacja JSON dla komend z danymi
case "$COMMAND" in
  patient.data|biosensor.data|biofeedback.data|medical.fhir|medical.hl7|medical.message|swarm.*|backend.job)
    if [[ -n "$PAYLOAD" ]] && ! validate_json "$PAYLOAD"; then
      echo "Invalid JSON payload" >&2
      echo "$PAYLOAD" >&2
      exit 65
    fi
    ;;
esac

# Obsługa komend
case "$COMMAND" in
  ping)
    send_command "ping" "" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  status)
    send_command "status" "" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  patient.data)
    send_command "patient.data" "$PAYLOAD" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  biosensor.data)
    send_command "biosensor.data" "$PAYLOAD" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  biofeedback.data)
    send_command "biofeedback.data" "$PAYLOAD" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  medical.fhir)
    send_command "medical.fhir" "$PAYLOAD" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  medical.hl7)
    send_command "medical.hl7" "$PAYLOAD" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  medical.message)
    send_command "medical.message" "$PAYLOAD" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  swarm.sensor)
    send_command "swarm.sensor" "$PAYLOAD" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  swarm.effector)
    send_command "swarm.effector" "$PAYLOAD" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  swarm.forward)
    send_command "swarm.forward" "$PAYLOAD" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  backend.job)
    send_command "backend.job" "$PAYLOAD" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  shutdown)
    send_command "shutdown" "" "$SOURCE" "$TIMEOUT" "$QUIET" "$VERBOSE"
    ;;
  *)
    echo "Unsupported command: $COMMAND" >&2
    echo "Użyj '$0 --help' aby zobaczyć listę dostępnych komend." >&2
    exit 64
    ;;
esac
