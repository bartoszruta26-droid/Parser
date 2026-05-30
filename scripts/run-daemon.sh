#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DAEMON_CONFIG="${DAEMON_CONFIG:-${PROJECT_ROOT}/config/daemon.conf.example}"

exec "${PROJECT_ROOT}/daemon/bin/template-daemon.sh"
