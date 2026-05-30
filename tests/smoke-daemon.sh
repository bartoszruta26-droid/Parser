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
CONF

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
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/backend/adapter/backend-client.sh" '{"task":"smoke"}' | grep '"code":"BACKEND_JOB"' >/dev/null
DAEMON_CONFIG="$TMP_DIR/daemon.conf" "$PROJECT_ROOT/frontend/cli/daemonctl.sh" shutdown | grep '"code":"SHUTDOWN"' >/dev/null
wait "$DAEMON_PID"
DAEMON_PID=""
