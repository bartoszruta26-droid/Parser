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

payload="${1:-{}}"
request_id="backend-$(date +%s)-$$"
response_file="$RESPONSE_DIR/${request_id}.json"

if [[ ! -p "$COMMAND_FIFO" ]]; then
  echo "Daemon command FIFO does not exist: $COMMAND_FIFO" >&2
  exit 69
fi

printf '%s|backend|backend.job|%s\n' "$request_id" "$payload" > "$COMMAND_FIFO"

deadline=$((SECONDS + REQUEST_TIMEOUT_SECONDS))
while [[ ! -f "$response_file" ]]; do
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for daemon response: $response_file" >&2
    exit 70
  fi
  sleep 0.1
done

cat "$response_file"
printf '\n'
