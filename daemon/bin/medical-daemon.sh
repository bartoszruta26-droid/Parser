#!/usr/bin/env bash
set -Eeuo pipefail

# Medical Data Management Daemon
# Daemon do zarządzania podmiotowymi i przedmiotowymi danymi medycznymi pacjenta
# oraz danymi z czujników biosensor i biofeedback

CONFIG_FILE="${DAEMON_CONFIG:-/etc/medical-daemon/daemon.conf}"
FALLBACK_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/medical-daemon.conf.example"

if [[ -r "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
elif [[ -r "$FALLBACK_CONFIG" ]]; then
  source "$FALLBACK_CONFIG"
else
  echo "No daemon configuration found: $CONFIG_FILE" >&2
  exit 78
fi

APP_NAME="${APP_NAME:-medical-data-daemon}"
RUN_DIR="${RUN_DIR:-/tmp/medical-daemon}"
LOG_DIR="${LOG_DIR:-${RUN_DIR}/log}"
COMMAND_FIFO="${COMMAND_FIFO:-${RUN_DIR}/commands.fifo}"
RESPONSE_DIR="${RESPONSE_DIR:-${RUN_DIR}/responses}"
STATE_FILE="${STATE_FILE:-${RUN_DIR}/state.env}"
DAEMON_LOG="${DAEMON_LOG:-${LOG_DIR}/daemon.log}"
PROTOCOL_VERSION="${PROTOCOL_VERSION:-1}"

# Queue files for different data types
PATIENT_DATA_QUEUE="${PATIENT_DATA_QUEUE:-${RUN_DIR}/patient-data.jsonl}"
SENSOR_BIOSENSOR_QUEUE="${SENSOR_BIOSENSOR_QUEUE:-${RUN_DIR}/biosensor-events.jsonl}"
SENSOR_BIOFEEDBACK_QUEUE="${SENSOR_BIOFEEDBACK_QUEUE:-${RUN_DIR}/biofeedback-events.jsonl}"
MEDICAL_FHIR_QUEUE="${MEDICAL_FHIR_QUEUE:-${RUN_DIR}/fhir-messages.jsonl}"
MEDICAL_HL7_QUEUE="${MEDICAL_HL7_QUEUE:-${RUN_DIR}/hl7-messages.jsonl}"
SWARM_QUEUE="${SWARM_QUEUE:-${RUN_DIR}/swarm-events.jsonl}"

RPI_NODE_NAME="${RPI_NODE_NAME:-local}"
RPI_NODE_ROLE="${RPI_NODE_ROLE:-main}"

running="true"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
last_command="none"

# Logging function
log() {
  local level="$1"
  local message="$2"
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$message" | tee -a "$DAEMON_LOG" >&2
}

# Prepare runtime directories and files
prepare_runtime() {
  mkdir -p "$RUN_DIR" "$LOG_DIR" "$RESPONSE_DIR"
  chmod 0750 "$RUN_DIR" "$LOG_DIR" "$RESPONSE_DIR"
  
  # Create queue files
  touch "$PATIENT_DATA_QUEUE" "$SENSOR_BIOSENSOR_QUEUE" "$SENSOR_BIOFEEDBACK_QUEUE"
  touch "$MEDICAL_FHIR_QUEUE" "$MEDICAL_HL7_QUEUE" "$SWARM_QUEUE"
  
  chmod 0640 "$PATIENT_DATA_QUEUE" "$SENSOR_BIOSENSOR_QUEUE" "$SENSOR_BIOFEEDBACK_QUEUE"
  chmod 0640 "$MEDICAL_FHIR_QUEUE" "$MEDICAL_HL7_QUEUE" "$SWARM_QUEUE"

  if [[ -p "$COMMAND_FIFO" ]]; then
    return
  fi

  rm -f "$COMMAND_FIFO"
  mkfifo "$COMMAND_FIFO"
  chmod 0660 "$COMMAND_FIFO"
}

# Write daemon state to file
write_state() {
  cat > "$STATE_FILE" <<STATE
APP_NAME="$APP_NAME"
PROTOCOL_VERSION="$PROTOCOL_VERSION"
STARTED_AT="$started_at"
LAST_COMMAND="$last_command"
RUNNING="$running"
RPI_NODE_NAME="$RPI_NODE_NAME"
RPI_NODE_ROLE="$RPI_NODE_ROLE"
PATIENT_DATA_QUEUE="$PATIENT_DATA_QUEUE"
SENSOR_BIOSENSOR_QUEUE="$SENSOR_BIOSENSOR_QUEUE"
SENSOR_BIOFEEDBACK_QUEUE="$SENSOR_BIOFEEDBACK_QUEUE"
MEDICAL_FHIR_QUEUE="$MEDICAL_FHIR_QUEUE"
MEDICAL_HL7_QUEUE="$MEDICAL_HL7_QUEUE"
STATE
}

# JSON escape helper
json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

# Generate JSON response
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

# Send response to client
# Validates and sanitizes request ID to prevent path traversal attacks
# Returns 0 if valid, 1 if invalid
validate_request_id() {
  local req_id="$1"
  # Reject if empty, contains path separators, or contains traversal sequences
  if [[ -z "$req_id" ]] || [[ "$req_id" == *"/"* ]] || [[ "$req_id" == *".."* ]]; then
    log_error "Invalid request_id format: $req_id"
    return 1
  fi
  return 0
}

send_response() {
  local request_id="$1"
  local body="$2"
  
  # Security Check: Validate request_id before constructing path
  if ! validate_request_id "$request_id"; then
    log_error "Rejected response due to unsafe request_id"
    return 1
  fi

  local response_file="$RESPONSE_DIR/${request_id}.json"

  printf '%s\n' "$body" > "$response_file"
  chmod 0640 "$response_file"
}

# Handle ping command
handle_ping() {
  local request_id="$1"
  send_response "$request_id" "$(json_response "$request_id" "ok" "PONG" "pong")"
}

# Handle status command
handle_status() {
  local request_id="$1"
  local payload
  payload="{\"app\":\"$(json_escape "$APP_NAME")\",\"started_at\":\"$started_at\",\"last_command\":\"$(json_escape "$last_command")\",\"rpi_node\":\"$(json_escape "$RPI_NODE_NAME")\",\"rpi_role\":\"$(json_escape "$RPI_NODE_ROLE")\",\"queues\":{\"patient_data\":\"$(json_escape "$PATIENT_DATA_QUEUE")\",\"biosensor\":\"$(json_escape "$SENSOR_BIOSENSOR_QUEUE")\",\"biofeedback\":\"$(json_escape "$SENSOR_BIOFEEDBACK_QUEUE")\",\"fhir\":\"$(json_escape "$MEDICAL_FHIR_QUEUE")\",\"hl7\":\"$(json_escape "$MEDICAL_HL7_QUEUE")\"}}"
  send_response "$request_id" "$(json_response "$request_id" "ok" "STATUS" "Daemon is running" "$payload")"
}

# Validate JSON payload - returns 0 if valid, 1 if invalid
validate_json() {
  local json="$1"
  # Use jq to validate JSON syntax
  if echo "$json" | jq . >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Encrypt sensitive data using openssl (AES-256-CBC)
encrypt_payload() {
  local payload="$1"
  local key="${ENCRYPTION_KEY:-default_key_change_in_production}"
  
  echo -n "$payload" | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -pass pass:"$key" -base64 -A 2>/dev/null || echo -n "$payload"
}

# Append event to queue file with validation and optional encryption
append_event() {
  local event_file="$1"
  local source="$2"
  local command="$3"
  local payload="$4"
  local should_encrypt="${5:-false}"
  
  # Validate that payload is valid JSON before appending
  if ! validate_json "$payload"; then
    log "ERROR" "Invalid JSON payload for command=$command from source=$source"
    return 1
  fi
  
  # Apply encryption if required
  local final_payload="$payload"
  if [[ "$should_encrypt" == "true" ]]; then
    final_payload="\"$(encrypt_payload "$payload")\""
    log "DEBUG" "Encrypted payload for $command (encrypted_size=${#final_payload})"
  fi
  
  printf '{"timestamp_utc":"%s","node":"%s","role":"%s","source":"%s","command":"%s","payload":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(json_escape "$RPI_NODE_NAME")" "$(json_escape "$RPI_NODE_ROLE")" "$(json_escape "$source")" "$(json_escape "$command")" "$final_payload" >> "$event_file"
}

# Handle patient data (podmiotowe i przedmiotowe dane pacjenta)
handle_patient_data() {
  local request_id="$1"
  local source="$2"
  local payload="$3"
  
  # Honor encryption setting for sensitive patient data
  local encrypt_flag="false"
  if [[ "${PATIENT_DATA_ENCRYPTION:-false}" == "true" ]]; then
    encrypt_flag="true"
  fi
  
  if ! append_event "$PATIENT_DATA_QUEUE" "$source" "patient.data" "$payload" "$encrypt_flag"; then
    send_response "$request_id" "$(json_response "$request_id" "rejected" "PATIENT_DATA" "Invalid JSON payload" "{}")"
    return 1
  fi
  
  log "INFO" "Accepted patient data request_id=$request_id source=$source payload_bytes=${#payload} encrypted=$encrypt_flag"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "PATIENT_DATA" "Patient data accepted" "{\"queued\":true,\"event_file\":\"$(json_escape "$PATIENT_DATA_QUEUE")\",\"encrypted\":$encrypt_flag}")"
}

# Handle biosensor data (dane z czujników biosensor)
handle_biosensor_data() {
  local request_id="$1"
  local source="$2"
  local payload="$3"
  
  append_event "$SENSOR_BIOSENSOR_QUEUE" "$source" "biosensor.data" "$payload"
  log "INFO" "Accepted biosensor data request_id=$request_id source=$source payload_bytes=${#payload}"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "BIOSENSOR_DATA" "Biosensor data accepted" "{\"queued\":true,\"event_file\":\"$(json_escape "$SENSOR_BIOSENSOR_QUEUE")\"}")"
}

# Handle biofeedback data (dane z czujników biofeedback)
handle_biofeedback_data() {
  local request_id="$1"
  local source="$2"
  local payload="$3"
  
  append_event "$SENSOR_BIOFEEDBACK_QUEUE" "$source" "biofeedback.data" "$payload"
  log "INFO" "Accepted biofeedback data request_id=$request_id source=$source payload_bytes=${#payload}"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "BIOFEEDBACK_DATA" "Biofeedback data accepted" "{\"queued\":true,\"event_file\":\"$(json_escape "$SENSOR_BIOFEEDBACK_QUEUE")\"}")"
}

# Handle FHIR medical messages
handle_medical_fhir() {
  local request_id="$1"
  local source="$2"
  local payload="$3"
  
  append_event "$MEDICAL_FHIR_QUEUE" "$source" "medical.fhir" "$payload"
  log "INFO" "Accepted FHIR message request_id=$request_id source=$source payload_bytes=${#payload}"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "MEDICAL_FHIR" "FHIR message accepted" "{\"queued\":true,\"event_file\":\"$(json_escape "$MEDICAL_FHIR_QUEUE")\"}")"
}

# Handle HL7v2 medical messages
handle_medical_hl7() {
  local request_id="$1"
  local source="$2"
  local payload="$3"
  
  append_event "$MEDICAL_HL7_QUEUE" "$source" "medical.hl7" "$payload"
  log "INFO" "Accepted HL7v2 message request_id=$request_id source=$source payload_bytes=${#payload}"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "MEDICAL_HL7" "HL7v2 message accepted" "{\"queued\":true,\"event_file\":\"$(json_escape "$MEDICAL_HL7_QUEUE")\"}")"
}

# Handle generic medical message
handle_medical_message() {
  local request_id="$1"
  local source="$2"
  local payload="$3"
  
  # Auto-detect message type and route accordingly
  if echo "$payload" | grep -q '"resourceType"'; then
    handle_medical_fhir "$request_id" "$source" "$payload"
  elif echo "$payload" | grep -q '^MSH'; then
    handle_medical_hl7 "$request_id" "$source" "$payload"
  else
    append_event "$MEDICAL_FHIR_QUEUE" "$source" "medical.message" "$payload"
    log "INFO" "Accepted medical message request_id=$request_id source=$source payload=<masked> payload_bytes=${#payload}"
    send_response "$request_id" "$(json_response "$request_id" "accepted" "MEDICAL_MESSAGE" "Medical protocol message accepted" "{\"queued\":true,\"masked\":true}")"
  fi
}

# Handle swarm sensor forwarding
handle_swarm_sensor() {
  local request_id="$1"
  local source="$2"
  local payload="$3"
  
  append_event "$SWARM_QUEUE" "$source" "swarm.sensor" "$payload"
  log "INFO" "Accepted RPi sensor data request_id=$request_id source=$source payload_bytes=${#payload}"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "SWARM_SENSOR" "RPi sensor data accepted" "{\"queued\":true,\"event_file\":\"$(json_escape "$SWARM_QUEUE")\"}")"
}

# Handle swarm effector commands
handle_swarm_effector() {
  local request_id="$1"
  local source="$2"
  local payload="$3"
  
  append_event "$SWARM_QUEUE" "$source" "swarm.effector" "$payload"
  log "INFO" "Accepted RPi effector command request_id=$request_id source=$source payload=$payload"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "SWARM_EFFECTOR" "RPi effector command accepted" "{\"queued\":true,\"event_file\":\"$(json_escape "$SWARM_QUEUE")\"}")"
}

# Handle swarm forwarding
handle_swarm_forward() {
  local request_id="$1"
  local source="$2"
  local payload="$3"
  
  append_event "$SWARM_QUEUE" "$source" "swarm.forward" "$payload"
  log "INFO" "Accepted RPi daemon forwarding request_id=$request_id source=$source payload=$payload"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "SWARM_FORWARD" "RPi daemon forwarding request accepted" "{\"queued\":true,\"event_file\":\"$(json_escape "$SWARM_QUEUE")\"}")"
}

# Handle backend job
handle_backend_job() {
  local request_id="$1"
  local payload="$2"
  
  log "INFO" "Accepted backend job request_id=$request_id payload=$payload"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "BACKEND_JOB" "Backend job accepted" "{\"queued\":true}")"
}

# Handle frontend event
handle_frontend_event() {
  local request_id="$1"
  local payload="$2"
  
  log "INFO" "Accepted frontend event request_id=$request_id payload=$payload"
  send_response "$request_id" "$(json_response "$request_id" "accepted" "FRONTEND_EVENT" "Frontend event accepted" "{\"handled\":true}")"
}

# Handle shutdown command
handle_shutdown() {
  local request_id="$1"
  running="false"
  send_response "$request_id" "$(json_response "$request_id" "ok" "SHUTDOWN" "Daemon shutdown requested")"
}

# Main command handler
handle_command() {
  local raw_line="$1"
  local request_id command source encoded_payload payload

  IFS='|' read -r request_id source command encoded_payload <<< "$raw_line"
  request_id="${request_id:-missing}"
  source="${source:-unknown}"
  command="${command:-unknown}"
  
  # Decode base64-encoded payload (sent by CLI to safely handle multiline JSON)
  if [[ -n "$encoded_payload" ]]; then
    payload=$(printf '%s' "$encoded_payload" | base64 -d 2>/dev/null || echo "")
  else
    payload=""
  fi
  
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
    patient.data)
      handle_patient_data "$request_id" "$source" "$payload"
      ;;
    biosensor.data)
      handle_biosensor_data "$request_id" "$source" "$payload"
      ;;
    biofeedback.data)
      handle_biofeedback_data "$request_id" "$source" "$payload"
      ;;
    medical.message)
      handle_medical_message "$request_id" "$source" "$payload"
      ;;
    medical.fhir)
      handle_medical_fhir "$request_id" "$source" "$payload"
      ;;
    medical.hl7)
      handle_medical_hl7 "$request_id" "$source" "$payload"
      ;;
    swarm.sensor)
      handle_swarm_sensor "$request_id" "$source" "$payload"
      ;;
    swarm.effector)
      handle_swarm_effector "$request_id" "$source" "$payload"
      ;;
    swarm.forward)
      handle_swarm_forward "$request_id" "$source" "$payload"
      ;;
    backend.job)
      handle_backend_job "$request_id" "$payload"
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

# Retention policy enforcement - removes old events from queue files
enforce_retention() {
  local queue_file="$1"
  local retention_days="$2"
  
  if [[ ! -f "$queue_file" ]]; then
    return 0
  fi
  
  local cutoff_date=$(date -u -d "$retention_days days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  local temp_file="${queue_file}.tmp"
  local removed_count=0
  
  # Filter out entries older than retention period
  while IFS= read -r line; do
    local entry_timestamp=$(echo "$line" | jq -r '.timestamp_utc' 2>/dev/null)
    if [[ -n "$entry_timestamp" ]] && [[ "$entry_timestamp" > "$cutoff_date" ]]; then
      echo "$line" >> "$temp_file"
    else
      ((removed_count++))
    fi
  done < "$queue_file"
  
  if [[ -f "$temp_file" ]]; then
    mv "$temp_file" "$queue_file"
    log "INFO" "Retention enforced on $queue_file: removed $removed_count entries older than $retention_days days"
  else
    # If all entries were removed, create empty file
    > "$queue_file"
    log "INFO" "Retention enforced on $queue_file: removed all $removed_count entries (all older than $retention_days days)"
  fi
}

# Main daemon loop
main_loop() {
  log "INFO" "Starting $APP_NAME daemon with protocol v$PROTOCOL_VERSION"
  log "INFO" "Patient data queue: $PATIENT_DATA_QUEUE"
  log "INFO" "Biosensor queue: $SENSOR_BIOSENSOR_QUEUE"
  log "INFO" "Biofeedback queue: $SENSOR_BIOFEEDBACK_QUEUE"
  log "INFO" "FHIR queue: $MEDICAL_FHIR_QUEUE"
  log "INFO" "HL7 queue: $MEDICAL_HL7_QUEUE"
  log "INFO" "Patient data retention: ${PATIENT_DATA_RETENTION_DAYS:-disabled} days"
  write_state
  
  local last_retention_run=0
  local retention_interval=3600  # Run retention check every hour

  while [[ "$running" == "true" ]]; do
    # Enforce retention policy periodically
    local current_time=$(date +%s)
    if [[ $((current_time - last_retention_run)) -ge $retention_interval ]]; then
      if [[ -n "${PATIENT_DATA_RETENTION_DAYS:-}" ]] && [[ "${PATIENT_DATA_RETENTION_DAYS:-0}" -gt 0 ]]; then
        enforce_retention "$PATIENT_DATA_QUEUE" "$PATIENT_DATA_RETENTION_DAYS"
      fi
      last_retention_run=$current_time
    fi
    
    if IFS= read -r line < "$COMMAND_FIFO"; then
      [[ -z "$line" ]] && continue
      handle_command "$line"
    fi
  done

  write_state
  log "INFO" "Stopped $APP_NAME daemon"
}

# Signal handling
trap 'running="false"; write_state; log "INFO" "Signal received, stopping"; exit 0' INT TERM

prepare_runtime
main_loop
