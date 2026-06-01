#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${DAEMON_CONFIG:-/etc/parser-template/daemon.conf}"
FALLBACK_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/daemon.conf.example"

if [[ -r "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
else
  # shellcheck source=/dev/null
  source "$FALLBACK_CONFIG"
fi

RUN_DIR="${RUN_DIR:-/tmp/parser-template}"
COMMAND_FIFO="${COMMAND_FIFO:-${RUN_DIR}/commands.fifo}"
RESPONSE_DIR="${RESPONSE_DIR:-${RUN_DIR}/responses}"
REQUEST_TIMEOUT_SECONDS="${REQUEST_TIMEOUT_SECONDS:-10}"
TUI_REFRESH_SECONDS="${TUI_REFRESH_SECONDS:-2}"
NO_COLOR="${NO_COLOR:-0}"

last_response="Brak odpowiedzi. Wybierz akcję z menu."
last_status="nieznany"

usage() {
  cat <<USAGE
Usage: $0 [--once <ping|status|frontend.event|shutdown>] [--payload <json>] [--no-color]

Interactive Bash TUI for communicating with the daemon.
Use --once in scripts and tests to send a single command without opening the menu.
USAGE
}

color() {
  local code="$1"
  if [[ "$NO_COLOR" == "1" || ! -t 1 ]]; then
    return
  fi
  printf '\033[%sm' "$code"
}

reset_color() {
  color 0
}

new_request_id() {
  printf 'tui-%s-%s-%s' "$(date +%s%N)" "$$" "$RANDOM"
}

write_command_fifo() {
  local request_id="$1"
  local command="$2"
  local payload="$3"
  local deadline="$4"
  local writer_pid

  (printf '%s|tui|%s|%s\n' "$request_id" "$command" "$payload" > "$COMMAND_FIFO") &
  writer_pid=$!

  while kill -0 "$writer_pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      kill "$writer_pid" 2>/dev/null || true
      wait "$writer_pid" 2>/dev/null || true
      printf 'Timeout: brak czytnika FIFO daemona: %s\n' "$COMMAND_FIFO" >&2
      return 70
    fi
    sleep 0.1
  done

  if ! wait "$writer_pid"; then
    printf 'Nie można zapisać do FIFO daemona: %s\n' "$COMMAND_FIFO" >&2
    return 69
  fi
}

send_daemon_command() {
  local command="$1"
  local payload="${2:-}"
  local request_id response_file deadline

  request_id="$(new_request_id)"
  response_file="$RESPONSE_DIR/${request_id}.json"

  if [[ ! -p "$COMMAND_FIFO" ]]; then
    printf 'Daemon nie jest dostępny. Brak FIFO: %s\n' "$COMMAND_FIFO" >&2
    return 69
  fi

  deadline=$((SECONDS + REQUEST_TIMEOUT_SECONDS))
  write_command_fifo "$request_id" "$command" "$payload" "$deadline" || return $?

  while [[ ! -f "$response_file" ]]; do
    if (( SECONDS >= deadline )); then
      printf 'Timeout: brak odpowiedzi daemona w %ss\n' "$REQUEST_TIMEOUT_SECONDS" >&2
      return 70
    fi
    sleep 0.1
  done

  cat "$response_file"
}

refresh_status() {
  if last_status="$(send_daemon_command status 2>/dev/null)"; then
    return 0
  fi

  last_status="Daemon niedostępny"
  return 1
}

render_header() {
  clear
  color '1;36'
  printf '╔══════════════════════════════════════════════════════╗\n'
  printf '║              Parser Template - TUI                  ║\n'
  printf '╚══════════════════════════════════════════════════════╝\n'
  reset_color
  printf 'Konfiguracja: %s\n' "$CONFIG_FILE"
  printf 'FIFO:         %s\n' "$COMMAND_FIFO"
  printf 'Odświeżanie:  %ss\n\n' "$TUI_REFRESH_SECONDS"
}

render_status_panel() {
  color '1;33'
  printf 'Status daemona:\n'
  reset_color
  printf '%s\n\n' "$last_status"
}

render_response_panel() {
  color '1;32'
  printf 'Ostatnia odpowiedź:\n'
  reset_color
  printf '%s\n\n' "$last_response"
}

render_menu() {
  color '1;37'
  printf 'Menu:\n'
  reset_color
  cat <<MENU
  1) Ping daemona
  2) Pobierz status
  3) Wyślij zdarzenie frontend.event
  4) Odśwież ekran
  q) Wyjście
MENU
  printf '\nWybór: '
}

prompt_payload() {
  local payload
  printf 'Payload JSON dla zdarzenia frontend.event: '
  IFS= read -r payload
  printf '%s' "${payload:-{}}"
}

run_action() {
  local action="$1"
  local payload="${2:-}"

  if last_response="$(send_daemon_command "$action" "$payload")"; then
    refresh_status >/dev/null || true
    return 0
  fi

  last_response="Błąd komunikacji z daemonem dla akcji: $action"
  refresh_status >/dev/null || true
  return 1
}

run_once() {
  local command="$1"
  local payload="${2:-}"
  send_daemon_command "$command" "$payload"
}

run_tui() {
  local choice payload
  refresh_status >/dev/null || true

  while true; do
    render_header
    render_status_panel
    render_response_panel
    render_menu
    IFS= read -r choice

    case "$choice" in
      1)
        run_action ping || true
        ;;
      2)
        run_action status || true
        ;;
      3)
        payload="$(prompt_payload)"
        run_action frontend.event "$payload" || true
        ;;
      4|"")
        refresh_status >/dev/null || true
        ;;
      q|Q)
        break
        ;;
      *)
        last_response="Nieznana opcja menu: $choice"
        ;;
    esac
  done
}

once_command=""
once_payload=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)
      if [[ $# -lt 2 ]]; then
        printf 'Brak wartości dla --once\n' >&2
        exit 64
      fi
      once_command="$2"
      shift 2
      ;;
    --payload)
      if [[ $# -lt 2 ]]; then
        printf 'Brak wartości dla --payload\n' >&2
        exit 64
      fi
      once_payload="$2"
      shift 2
      ;;
    --no-color)
      NO_COLOR="1"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      printf 'Nieznany argument: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -n "$once_command" ]]; then
  case "$once_command" in
    ping|status|frontend.event|shutdown)
      run_once "$once_command" "$once_payload"
      ;;
    *)
      printf 'Nieobsługiwana komenda --once: %s\n' "$once_command" >&2
      exit 64
      ;;
  esac
  exit $?
fi

run_tui
