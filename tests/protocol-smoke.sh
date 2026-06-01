#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not installed; skipping JSON protocol validation" >&2
  exit 0
fi

jq empty \
  "$PROJECT_ROOT/protocol/schemas/daemon-message.schema.json" \
  "$PROJECT_ROOT/protocol/examples/request.json" \
  "$PROJECT_ROOT/protocol/examples/response.json" \
  "$PROJECT_ROOT/protocol/examples/medical-fhir-message.json" \
  "$PROJECT_ROOT/protocol/examples/rpi-sensor-message.json" \
  "$PROJECT_ROOT/protocol/examples/rpi-effector-message.json"

awk -F',' 'NR == 1 { expected = "protocol,request_id,source,command,payload_json,timestamp_utc,correlation_id"; if ($0 != expected) exit 1 }' \
  "$PROJECT_ROOT/protocol/examples/request.csv"

grep '^MSH|' "$PROJECT_ROOT/protocol/examples/medical-hl7v2-message.hl7" >/dev/null
grep '^OBX|' "$PROJECT_ROOT/protocol/examples/medical-hl7v2-message.hl7" >/dev/null

if rg -n '^#!.*python|python3? ' \
  "$PROJECT_ROOT/daemon" \
  "$PROJECT_ROOT/backend" \
  "$PROJECT_ROOT/frontend" \
  "$PROJECT_ROOT/protocol" \
  "$PROJECT_ROOT/scripts" \
  "$PROJECT_ROOT/tests"; then
  echo "Python dependency found in runtime scripts" >&2
  exit 1
fi
