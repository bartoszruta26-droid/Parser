#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${DAEMON_CONFIG:-/etc/parser-template/daemon.conf}"
FALLBACK_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/daemon.conf.example"

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

APP_NAME="${APP_NAME:-parser-template}"
RUN_DIR="${RUN_DIR:-/tmp/parser-template}"
LOG_DIR="${LOG_DIR:-${RUN_DIR}/log}"
COMMAND_FIFO="${COMMAND_FIFO:-${RUN_DIR}/commands.fifo}"
RESPONSE_DIR="${RESPONSE_DIR:-${RUN_DIR}/responses}"
STATE_FILE="${STATE_FILE:-${RUN_DIR}/state.env}"
DAEMON_LOG="${DAEMON_LOG:-${LOG_DIR}/daemon.log}"
PROTOCOL_VERSION="${PROTOCOL_VERSION:-1}"

running="true"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
last_command="none"

log() {
  local level="$1"
  local message="$2"
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$message" | tee -a "$DAEMON_LOG" >&2
}

prepare_runtime() {
  mkdir -p "$RUN_DIR" "$LOG_DIR" "$RESPONSE_DIR"
  chmod 0750 "$RUN_DIR" "$LOG_DIR" "$RESPONSE_DIR"

  if [[ -p "$COMMAND_FIFO" ]]; then
    return
  fi

  rm -f "$COMMAND_FIFO"
  mkfifo "$COMMAND_FIFO"
  chmod 0660 "$COMMAND_FIFO"
}

write_state() {
  cat > "$STATE_FILE" <<STATE
APP_NAME="$APP_NAME"
PROTOCOL_VERSION="$PROTOCOL_VERSION"
STARTED_AT="$started_at"
LAST_COMMAND="$last_command"
RUNNING="$running"
STATE
}

json_response() {
  local request_id="$1"
  local status="$2"
  local code="$3"
  local message="$4"
  local payload="${5:-{}}"

  cat <<JSON
{"protocol":"$PROTOCOL_VERSION","request_id":"$request_id","status":"$status","code":"$code","message":"$message","payload":$payload}
JSON
}

send_response() {
  local request_id="$1"
  local body="$2"
  local response_file="$RESPONSE_DIR/${request_id}.json"

  printf '%s\n' "$body" > "$response_file"
  chmod 0640 "$response_file"
}

handle_status() {
  local request_id="$1"
  local payload
  payload="{\"app\":\"$APP_NAME\",\"started_at\":\"$started_at\",\"last_command\":\"$last_command\"}"
  send_response "$request_id" "$(json_response "$request_id" "ok" "STATUS" "Daemon is running" "$payload")"
}

handle_ping() {
  local request_id="$1"
  send_response "$request_id" "$(json_response "$request_id" "ok" "PONG" "pong")"
}

handle_backend_job() {
  local request_id="$1"
  local payload="$2"
  log "INFO" "Accepted backend job request_id=$request_id payload=$payload"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "BACKEND_JOB" "Backend job accepted" "{\"queued\":true}")"
}


handle_medical_message() {
  local request_id="$1"
  local payload="$2"
  log "INFO" "Accepted medical message request_id=$request_id payload=<masked> payload_bytes=${#payload}"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "MEDICAL_MESSAGE" "Medical protocol message accepted" "{\"queued\":true,\"masked\":true}")"
}

handle_frontend_event() {
  local request_id="$1"
  local payload="$2"
  log "INFO" "Accepted frontend event request_id=$request_id payload=$payload"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "FRONTEND_EVENT" "Frontend event accepted" "{\"handled\":true}")"
}

handle_shutdown() {
  local request_id="$1"
  running="false"
  send_response "$request_id" "$(json_response "$request_id" "ok" "SHUTDOWN" "Daemon shutdown requested")"
}

handle_command() {
  local raw_line="$1"
  local request_id command source payload

  IFS='|' read -r request_id source command payload <<< "$raw_line"
  request_id="${request_id:-missing}"
  source="${source:-unknown}"
  command="${command:-unknown}"
  payload="${payload:-}"
  last_command="$source:$command"

  case "$command" in
    ping)
      handle_ping "$request_id"
      ;;
    status)
      handle_status "$request_id"
      ;;
    frontend.event)
      handle_frontend_event "$request_id" "$payload"
      ;;
    backend.job)
      handle_backend_job "$request_id" "$payload"
      ;;
    medical.message)
      handle_medical_message "$request_id" "$payload"
      ;;
    shutdown)
      handle_shutdown "$request_id"
      ;;
    *)
      send_response "$request_id" "$(json_response "$request_id" "error" "UNKNOWN_COMMAND" "Unsupported command: $command")"
      ;;
  esac

  write_state
}

main_loop() {
  log "INFO" "Starting $APP_NAME daemon with protocol v$PROTOCOL_VERSION"
  write_state

  while [[ "$running" == "true" ]]; do
    if IFS= read -r line < "$COMMAND_FIFO"; then
      [[ -z "$line" ]] && continue
      handle_command "$line"
    fi
  done

  write_state
  log "INFO" "Stopped $APP_NAME daemon"
}

trap 'running="false"; write_state; log "INFO" "Signal received, stopping"; exit 0' INT TERM

prepare_runtime
main_loop
