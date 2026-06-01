#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
DAEMON_PID=""

cleanup() {
  if [[ -n "$DAEMON_PID" ]] && kill -0 "$DAEMON_PID" 2>/dev/null; then
    kill "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/daemon.conf" <<CONF
APP_NAME="parser-template-test"
RUN_DIR="$TMP_DIR/run"
LOG_DIR="$TMP_DIR/log"
COMMAND_FIFO="\${RUN_DIR}/commands.fifo"
RESPONSE_DIR="\${RUN_DIR}/responses"
STATE_FILE="\${RUN_DIR}/state.env"
DAEMON_LOG="\${LOG_DIR}/daemon.log"
PROTOCOL_VERSION="1"
REQUEST_TIMEOUT_SECONDS="3"
RPI_SWARM_ENABLED="true"
RPI_NODE_NAME="rpi-test-main"
RPI_NODE_ROLE="main"
SENSOR_QUEUE_FILE="\${RUN_DIR}/sensor-events.jsonl"
EFFECTOR_QUEUE_FILE="\${RUN_DIR}/effector-events.jsonl"
SWARM_QUEUE_FILE="\${RUN_DIR}/swarm-events.jsonl"
RPI_SENSOR_SOURCES="temperature=$TMP_DIR/sensors/temperature.value"
RPI_EFFECTOR_TARGETS="relay=$TMP_DIR/effectors/relay.state"
CONF

mkdir -p "$TMP_DIR/sensors"
printf '22.5\n' > "$TMP_DIR/sensors/temperature.value"

DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/daemon/bin/template-daemon.sh" &
DAEMON_PID="$!"

for _ in {1..30}; do
  [[ -p "$TMP_DIR/run/commands.fifo" ]] && break
  sleep 0.1
done

DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/frontend/cli/daemonctl.sh" ping | grep '"code":"PONG"' >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/frontend/cli/daemonctl.sh" status | grep '"code":"STATUS"' >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/frontend/tui/parser-tui.sh" --once status --no-color | grep '"code":"STATUS"' >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/frontend/tui/parser-tui.sh" --once frontend.event --payload '{"source":"tui-smoke"}' --no-color | grep '"code":"FRONTEND_EVENT"' >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/frontend/gui/parser-gui.sh" --once status | grep '"code":"STATUS"' >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/frontend/gui/parser-gui.sh" --once frontend.event --payload '{"source":"gui-smoke"}' | grep '"code":"FRONTEND_EVENT"' >/dev/null
if command -v php >/dev/null 2>&1; then
  DAEMON_CONFIG="$TMP_DIR/daemon.conf" WEBUI_COMMAND=status php "$PROJECT_ROOT/frontend/webui/api/daemon.php" | grep '"code":"STATUS"' >/dev/null
  DAEMON_CONFIG="$TMP_DIR/daemon.conf" WEBUI_COMMAND=frontend.event WEBUI_PAYLOAD='{"source":"webui-smoke"}' php "$PROJECT_ROOT/frontend/webui/api/daemon.php" | grep '"code":"FRONTEND_EVENT"' >/dev/null
else
  echo "php not installed; skipping WebUI smoke checks" >&2
fi
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/backend/adapter/backend-client.sh" '{"task":"smoke"}' | grep '"code":"BACKEND_JOB"' >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/protocol/bin/daemon-send.sh" --source medical --command medical.message --payload '{"profile":"fhir","masked":true}' | grep '"code":"MEDICAL_MESSAGE"' >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/swarm/bin/rpi-swarm.sh" sensor-read temperature | grep '"code":"SWARM_SENSOR"' >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/swarm/bin/rpi-swarm.sh" effector-send relay on | grep '"code":"SWARM_EFFECTOR"' >/dev/null
grep '"sensor":"temperature"' "$TMP_DIR/run/sensor-events.jsonl" >/dev/null
grep '"effector":"relay"' "$TMP_DIR/run/effector-events.jsonl" >/dev/null
grep '^on$' "$TMP_DIR/effectors/relay.state" >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/swarm/bin/rpi-swarm.sh" forward-main swarm.sensor '{"node":"rpi-worker-01","sensor":"remote","value":"1"}' | grep '"code":"SWARM_SENSOR"' >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/frontend/cli/daemonctl.sh" shutdown | grep '"code":"SHUTDOWN"' >/dev/null
wait "$DAEMON_PID"
DAEMON_PID=""
