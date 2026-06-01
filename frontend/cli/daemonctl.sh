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

usage() {
  cat <<USAGE
Usage: $0 <ping|status|frontend.event|shutdown> [payload]

Sends a command to the local daemon through the command FIFO and prints
its response file. This is a reference CLI frontend for the template.
USAGE
}

new_request_id() {
  printf 'frontend-%s-%s-%s' "$(date +%s%N)" "$$" "$RANDOM"
}

write_command_fifo() {
  local request_id="$1"
  local command="$2"
  local payload="$3"
  local deadline="$4"
  local writer_pid

  (printf '%s|frontend|%s|%s\n' "$request_id" "$command" "$payload" > "$COMMAND_FIFO") &
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

send_command() {
  local command="$1"
  local payload="${2:-}"
  local request_id response_file deadline

  request_id="$(new_request_id)"
  response_file="$RESPONSE_DIR/${request_id}.json"

  if [[ ! -p "$COMMAND_FIFO" ]]; then
    echo "Daemon command FIFO does not exist: $COMMAND_FIFO" >&2
    exit 69
  fi

  deadline=$((SECONDS + REQUEST_TIMEOUT_SECONDS))
  write_command_fifo "$request_id" "$command" "$payload" "$deadline" || exit $?

  while [[ ! -f "$response_file" ]]; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for daemon response: $response_file" >&2
      exit 70
    fi
    sleep 0.1
  done

  cat "$response_file"
  printf '\n'
}

if [[ $# -lt 1 ]]; then
  usage
  exit 64
fi

case "$1" in
  ping|status|frontend.event|shutdown)
    send_command "$1" "${2:-}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unsupported frontend command: $1" >&2
    usage >&2
    exit 64
    ;;
esac
