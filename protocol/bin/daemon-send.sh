#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${DAEMON_CONFIG:-/etc/parser-template/daemon.conf}"
FALLBACK_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/daemon.conf.example"
SOURCE="protocol"
COMMAND="status"
PAYLOAD="{}"

usage() {
  cat <<USAGE
Usage: $0 [--config <path>] --source <name> --command <name> [--payload <data>]

Pure Bash/Linux helper for sending one canonical message to the daemon through
its FIFO transport. It does not require Python and is intended as the reference
transport primitive for scripts, importers and integration adapters.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { echo "Missing value for --config" >&2; exit 64; }
      CONFIG_FILE="$2"
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || { echo "Missing value for --source" >&2; exit 64; }
      SOURCE="$2"
      shift 2
      ;;
    --command)
      [[ $# -ge 2 ]] || { echo "Missing value for --command" >&2; exit 64; }
      COMMAND="$2"
      shift 2
      ;;
    --payload)
      [[ $# -ge 2 ]] || { echo "Missing value for --payload" >&2; exit 64; }
      PAYLOAD="$2"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

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

RUN_DIR="${RUN_DIR:-/tmp/parser-template}"
COMMAND_FIFO="${COMMAND_FIFO:-${RUN_DIR}/commands.fifo}"
RESPONSE_DIR="${RESPONSE_DIR:-${RUN_DIR}/responses}"
REQUEST_TIMEOUT_SECONDS="${REQUEST_TIMEOUT_SECONDS:-10}"

if [[ ! -p "$COMMAND_FIFO" ]]; then
  echo "Daemon command FIFO does not exist: $COMMAND_FIFO" >&2
  exit 69
fi

request_id="${SOURCE}-$(date +%s)-$$"
response_file="$RESPONSE_DIR/${request_id}.json"
printf '%s|%s|%s|%s\n' "$request_id" "$SOURCE" "$COMMAND" "$PAYLOAD" > "$COMMAND_FIFO"

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
