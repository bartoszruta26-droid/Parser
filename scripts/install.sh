#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="${PREFIX:-/opt/parser-template}"
CONFIG_DIR="${CONFIG_DIR:-/etc/parser-template}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
APACHE_HTTP_DIR="${APACHE_HTTP_DIR:-/var/www/html/parser-template}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] %q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

run mkdir -p "$PREFIX" "$CONFIG_DIR" "$APACHE_HTTP_DIR"
run cp -R "$PROJECT_ROOT/daemon" "$PROJECT_ROOT/frontend" "$PROJECT_ROOT/backend" "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/protocol" "$PREFIX/"
run cp -R "$PROJECT_ROOT/frontend/webui/." "$APACHE_HTTP_DIR/"
run cp "$PROJECT_ROOT/config/daemon.conf.example" "$CONFIG_DIR/daemon.conf"
run cp "$PROJECT_ROOT/systemd/parser-template-daemon.service" "$SYSTEMD_DIR/parser-template-daemon.service"

cat <<INFO
Installed parser-template skeleton.
WebUI target: $APACHE_HTTP_DIR
Next steps:
  sudo systemctl daemon-reload
  sudo systemctl enable --now parser-template-daemon.service
INFO
