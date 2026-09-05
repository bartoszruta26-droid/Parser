#!/usr/bin/env bash
set -Eeuo pipefail

# Medical Daemon CLI Helper Library
# Biblioteka funkcji pomocniczych dla aplikacji CLI komunikujących się z daemonem

# Walidacja request_id (zabezpieczenie przed path traversal)
# Zwraca 0 jeśli poprawny, 1 jeśli niepoprawny
validate_request_id() {
  local req_id="$1"
  if [[ -z "$req_id" ]] || [[ "$req_id" == *"/"* ]] || [[ "$req_id" == *".."* ]]; then
    return 1
  fi
  return 0
}

# Generowanie unikalnego request_id
# Argument: prefix (domyślnie "cli")
new_request_id() {
  local prefix="${1:-cli}"
  printf '%s-%s-%s-%s' "$prefix" "$(date +%s%N)" "$$" "$RANDOM"
}

# Sprawdzenie czy daemon jest uruchomiony
# Zwraca 0 jeśli FIFO istnieje, 1 jeśli nie
check_daemon_running() {
  local command_fifo="${1:-}"
  
  if [[ -z "$command_fifo" ]]; then
    echo "COMMAND_FIFO not set" >&2
    return 1
  fi
  
  if [[ ! -p "$command_fifo" ]]; then
    echo "Daemon command FIFO does not exist: $command_fifo" >&2
    return 1
  fi
  
  return 0
}

# Zapisanie polecenia do FIFO z timeoutem
# Argumenty: request_id, command, payload, source, deadline
# Zwraca 0 jeśli sukces, 69/70 jeśli błąd
write_command_fifo() {
  local request_id="$1"
  local command="$2"
  local payload="$3"
  local source="$4"
  local deadline="$5"
  local command_fifo="$6"
  local writer_pid

  (printf '%s|%s|%s|%s\n' "$request_id" "$source" "$command" "$payload" > "$command_fifo") &
  writer_pid=$!

  while kill -0 "$writer_pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      kill "$writer_pid" 2>/dev/null || true
      wait "$writer_pid" 2>/dev/null || true
      echo "Timed out waiting for daemon FIFO reader: $command_fifo" >&2
      return 70
    fi
    sleep 0.1
  done

  if ! wait "$writer_pid"; then
    echo "Unable to write daemon command FIFO: $command_fifo" >&2
    return 69
  fi
  
  return 0
}

# Oczekiwanie na odpowiedź daemona
# Argumenty: response_file, deadline
# Zwraca 0 jeśli odpowiedź nadeszła, 70 jeśli timeout
wait_for_response() {
  local response_file="$1"
  local deadline="$2"

  while [[ ! -f "$response_file" ]]; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for daemon response: $response_file" >&2
      return 70
    fi
    sleep 0.1
  done
  
  return 0
}

# Odczyt i czyszczenie pliku odpowiedzi
# Argument: response_file
# Zwraca treść odpowiedzi na stdout
read_response() {
  local response_file="$1"
  
  if [[ ! -f "$response_file" ]]; then
    echo "Response file does not exist: $response_file" >&2
    return 1
  fi
  
  cat "$response_file"
  rm -f "$response_file"
}

# Walidacja JSON
# Argument: json_string
# Zwraca 0 jeśli poprawny JSON, 1 jeśli nie
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

# Formatowanie odpowiedzi JSON z kolorami
# Argument: json_response
format_response() {
  local response="$1"
  local use_color="${2:-true}"
  
  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[1;33m'
  local NC='\033[0m'
  
  if command -v jq &>/dev/null; then
    local status code message
    status=$(echo "$response" | jq -r '.status // "unknown"')
    code=$(echo "$response" | jq -r '.code // "UNKNOWN"')
    message=$(echo "$response" | jq -r '.message // ""')
    
    local status_color=""
    case "$status" in
      ok|accepted)
        status_color="$GREEN"
        ;;
      rejected)
        status_color="$YELLOW"
        ;;
      error|*)
        status_color="$RED"
        ;;
    esac
    
    if [[ "$use_color" == "true" ]] && [[ -t 1 ]]; then
      printf '\033[0;32m✓ Status: %s\033[0m | Code: %s | Message: %s\n' "$status" "$code" "$message"
      printf '\n%s\n' "$(echo "$response" | jq .)"
    else
      printf 'Status: %s | Code: %s | Message: %s\n' "$status" "$code" "$message"
      printf '\n%s\n' "$(echo "$response" | jq .)"
    fi
  else
    printf '%s\n' "$response"
  fi
}

# Parsowanie danych z pliku lub argumentu
# Argumenty: input, from_file (true/false)
get_payload() {
  local input="$1"
  local from_file="$2"
  
  if [[ "$from_file" == "true" ]]; then
    if [[ ! -r "$input" ]]; then
      echo "File not readable: $input" >&2
      return 66
    fi
    cat "$input"
  else
    printf '%s' "$input"
  fi
}

# Wysyłanie komendy do daemona z pełną obsługą
# Argumenty: command, payload, source, timeout, quiet, verbose, command_fifo, response_dir
send_daemon_command() {
  local command="$1"
  local payload="${2:-}"
  local source="${3:-cli}"
  local timeout="${4:-10}"
  local quiet="${5:-false}"
  local verbose="${6:-false}"
  local command_fifo="$7"
  local response_dir="$8"
  
  local request_id response_file deadline
  
  request_id="$(new_request_id "$command")"
  response_file="$response_dir/${request_id}.json"

  # Sprawdzenie FIFO
  if ! check_daemon_running "$command_fifo"; then
    exit 69
  fi

  # Cleanup starej odpowiedzi
  rm -f "$response_file"

  deadline=$((SECONDS + timeout))
  
  if [[ "$verbose" == "true" ]]; then
    echo "Sending command: $command" >&2
    echo "Request ID: $request_id" >&2
    echo "Source: $source" >&2
    echo "Payload: $payload" >&2
    echo "Response file: $response_file" >&2
  fi

  if ! write_command_fifo "$request_id" "$command" "$payload" "$source" "$deadline" "$command_fifo"; then
    exit $?
  fi

  if ! wait_for_response "$response_file" "$deadline"; then
    exit 70
  fi

  local response
  response="$(read_response "$response_file")"

  if [[ "$quiet" == "true" ]]; then
    printf '%s\n' "$response"
  else
    format_response "$response"
  fi
}
