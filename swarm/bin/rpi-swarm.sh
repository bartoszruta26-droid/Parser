#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="${DAEMON_CONFIG:-/etc/parser-template/daemon.conf}"
FALLBACK_CONFIG="$PROJECT_ROOT/config/daemon.conf.example"
DAEMON_SEND="$PROJECT_ROOT/protocol/bin/daemon-send.sh"

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

RPI_NODE_NAME="${RPI_NODE_NAME:-$(hostname -s 2>/dev/null || printf 'rpi-node')}"
RPI_NODE_ROLE="${RPI_NODE_ROLE:-worker}"
RPI_MAIN_DAEMON_HOST="${RPI_MAIN_DAEMON_HOST:-127.0.0.1}"
RPI_MAIN_DAEMON_PORT="${RPI_MAIN_DAEMON_PORT:-8701}"
RPI_SENSOR_SOURCES="${RPI_SENSOR_SOURCES:-}"
RPI_EFFECTOR_TARGETS="${RPI_EFFECTOR_TARGETS:-}"
RPI_ENABLE_TCP_FORWARD="${RPI_ENABLE_TCP_FORWARD:-false}"

usage() {
  cat <<USAGE
Usage: $0 <command> [arguments]

Commands:
  sensor-read <sensor> [value]
      Read a sensor value from the configured source, or use the provided value,
      then send it to the local daemon as swarm.sensor.

  effector-send <effector> <state>
      Send an effector command to the local daemon as swarm.effector and apply it
      to the configured local target when possible.

  forward-main <command> <payload>
      Forward an already prepared daemon command/payload to the main RPi daemon.
      Uses TCP only when RPI_ENABLE_TCP_FORWARD=true; otherwise records the
      forwarding request in the local daemon.

  receive-line <request_id|source|command|payload>
      Accept one daemon protocol line from another RPi and pass it to the local
      daemon FIFO. This is intended for nc/socat wrappers.

Configuration maps use comma-separated name=target pairs, for example:
  RPI_SENSOR_SOURCES="temperature=/sys/bus/w1/devices/28-xxx/w1_slave,humidity=/opt/parser/read-humidity.sh"
  RPI_EFFECTOR_TARGETS="relay=/tmp/parser-template/relay.state,fan=/opt/parser/set-fan.sh"
USAGE
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

utc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

map_lookup() {
  local map="$1"
  local key="$2"
  local entry name value
  local -a entries

  IFS=',' read -ra entries <<< "$map"
  for entry in "${entries[@]}"; do
    name="${entry%%=*}"
    value="${entry#*=}"
    if [[ "$name" == "$key" && "$entry" == *=* ]]; then
      printf '%s' "$value"
      return 0
    fi
  done

  return 1
}

send_local_daemon() {
  local source="$1"
  local command="$2"
  local payload="$3"
  "$DAEMON_SEND" --config "$CONFIG_FILE" --source "$source" --command "$command" --payload "$payload"
}

read_sensor_value() {
  local sensor="$1"
  local provided="${2:-}"
  local target

  if [[ -n "$provided" ]]; then
    printf '%s' "$provided"
    return 0
  fi

  if target="$(map_lookup "$RPI_SENSOR_SOURCES" "$sensor")"; then
    if [[ -r "$target" && ! -d "$target" ]]; then
      head -n 1 "$target"
      return 0
    fi
    if [[ -x "$target" && ! -d "$target" ]]; then
      "$target"
      return 0
    fi
    echo "Sensor source for '$sensor' is not readable or executable: $target" >&2
    return 66
  fi

  echo "Unknown sensor '$sensor'. Configure RPI_SENSOR_SOURCES or pass a value." >&2
  return 66
}

apply_effector_target() {
  local effector="$1"
  local state="$2"
  local target

  if ! target="$(map_lookup "$RPI_EFFECTOR_TARGETS" "$effector")"; then
    return 0
  fi

  if [[ -x "$target" && ! -d "$target" ]]; then
    "$target" "$state"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  printf '%s\n' "$state" > "$target"
}

sensor_read() {
  local sensor="${1:-}"
  local value="${2:-}"
  local payload

  [[ -n "$sensor" ]] || { echo "Missing sensor name" >&2; exit 64; }
  value="$(read_sensor_value "$sensor" "$value")"
  payload="{\"node\":\"$(json_escape "$RPI_NODE_NAME")\",\"role\":\"$(json_escape "$RPI_NODE_ROLE")\",\"sensor\":\"$(json_escape "$sensor")\",\"value\":\"$(json_escape "$value")\",\"timestamp_utc\":\"$(utc_now)\"}"
  send_local_daemon "rpi-sensor" "swarm.sensor" "$payload"
}

effector_send() {
  local effector="${1:-}"
  local state="${2:-}"
  local payload

  [[ -n "$effector" ]] || { echo "Missing effector name" >&2; exit 64; }
  [[ -n "$state" ]] || { echo "Missing effector state" >&2; exit 64; }
  payload="{\"node\":\"$(json_escape "$RPI_NODE_NAME")\",\"role\":\"$(json_escape "$RPI_NODE_ROLE")\",\"effector\":\"$(json_escape "$effector")\",\"state\":\"$(json_escape "$state")\",\"timestamp_utc\":\"$(utc_now)\"}"
  send_local_daemon "rpi-effector" "swarm.effector" "$payload"
  apply_effector_target "$effector" "$state"
}

forward_main() {
  local command="${1:-}"
  local payload="${2:-{}}"
  local request_id line

  [[ -n "$command" ]] || { echo "Missing command" >&2; exit 64; }
  request_id="${RPI_NODE_NAME}-$(date +%s)-$$"
  line="$request_id|$RPI_NODE_NAME|$command|$payload"

  if [[ "$RPI_NODE_ROLE" == "main" ]]; then
    send_local_daemon "$RPI_NODE_NAME" "$command" "$payload"
    return
  fi

  if [[ "$RPI_ENABLE_TCP_FORWARD" == "true" ]]; then
    if command -v nc >/dev/null 2>&1; then
      printf '%s\n' "$line" | nc -w "${REQUEST_TIMEOUT_SECONDS:-10}" "$RPI_MAIN_DAEMON_HOST" "$RPI_MAIN_DAEMON_PORT"
      return
    fi

    if exec 3<>"/dev/tcp/$RPI_MAIN_DAEMON_HOST/$RPI_MAIN_DAEMON_PORT"; then
      printf '%s\n' "$line" >&3
      exec 3<&-
      exec 3>&-
      return
    fi

    echo "TCP forwarding is enabled, but no TCP transport is available" >&2
    exit 69
  fi

  payload="{\"target\":\"main\",\"host\":\"$(json_escape "$RPI_MAIN_DAEMON_HOST")\",\"port\":\"$(json_escape "$RPI_MAIN_DAEMON_PORT")\",\"command\":\"$(json_escape "$command")\",\"payload\":$(printf '%s' "$payload"),\"timestamp_utc\":\"$(utc_now)\"}"
  send_local_daemon "rpi-forward" "swarm.forward" "$payload"
}

receive_line() {
  local line="${1:-}"
  local request_id source command payload

  [[ -n "$line" ]] || IFS= read -r line
  IFS='|' read -r request_id source command payload <<< "$line"
  [[ -n "${request_id:-}" && -n "${source:-}" && -n "${command:-}" ]] || {
    echo "Invalid daemon protocol line" >&2
    exit 64
  }
  send_local_daemon "remote-$source" "$command" "${payload:-{}}"
}

case "${1:-}" in
  sensor-read)
    shift
    sensor_read "$@"
    ;;
  effector-send)
    shift
    effector_send "$@"
    ;;
  forward-main)
    shift
    forward_main "$@"
    ;;
  receive-line)
    shift
    receive_line "${1:-}"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unsupported RPi swarm command: $1" >&2
    usage >&2
    exit 64
    ;;
esac
