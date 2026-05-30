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
GUI_DIALOG_TOOL="${GUI_DIALOG_TOOL:-auto}"

dialog_tool=""
last_response="Brak odpowiedzi. Wybierz akcję w oknie GUI."

usage() {
  cat <<USAGE
Usage: $0 [--once <ping|status|frontend.event|shutdown>] [--payload <json>] [--tool <auto|zenity|kdialog>]

Desktop GUI skeleton for communicating with the daemon.
Interactive mode requires zenity or kdialog. Use --once for tests and scripts.
USAGE
}

select_dialog_tool() {
  case "$GUI_DIALOG_TOOL" in
    zenity|kdialog)
      if command -v "$GUI_DIALOG_TOOL" >/dev/null 2>&1; then
        dialog_tool="$GUI_DIALOG_TOOL"
        return 0
      fi
      printf 'Wybrane narzędzie GUI nie jest dostępne: %s\n' "$GUI_DIALOG_TOOL" >&2
      return 69
      ;;
    auto)
      if command -v zenity >/dev/null 2>&1; then
        dialog_tool="zenity"
        return 0
      fi
      if command -v kdialog >/dev/null 2>&1; then
        dialog_tool="kdialog"
        return 0
      fi
      printf 'Brak narzędzia GUI. Zainstaluj zenity albo kdialog.\n' >&2
      return 69
      ;;
    *)
      printf 'Nieobsługiwane narzędzie GUI: %s\n' "$GUI_DIALOG_TOOL" >&2
      return 64
      ;;
  esac
}

new_request_id() {
  printf 'gui-%s-%s' "$(date +%s)" "$$"
}

send_daemon_command() {
  local command="$1"
  local payload="${2:-}"
  local request_id response_file deadline

  request_id="$(new_request_id)"
  response_file="$RESPONSE_DIR/${request_id}.json"

  if [[ ! -p "$COMMAND_FIFO" ]]; then
    printf 'Daemon nie jest dostępny. Brak FIFO: %s\n' "$COMMAND_FIFO" >&2
    return 69
  fi

  printf '%s|gui|%s|%s\n' "$request_id" "$command" "$payload" > "$COMMAND_FIFO"

  deadline=$((SECONDS + REQUEST_TIMEOUT_SECONDS))
  while [[ ! -f "$response_file" ]]; do
    if (( SECONDS >= deadline )); then
      printf 'Timeout: brak odpowiedzi daemona w %ss\n' "$REQUEST_TIMEOUT_SECONDS" >&2
      return 70
    fi
    sleep 0.1
  done

  cat "$response_file"
}

gui_message() {
  local title="$1"
  local message="$2"

  case "$dialog_tool" in
    zenity)
      zenity --info --title="$title" --width=700 --height=320 --text="$message"
      ;;
    kdialog)
      kdialog --title "$title" --msgbox "$message"
      ;;
  esac
}

gui_error() {
  local title="$1"
  local message="$2"

  case "$dialog_tool" in
    zenity)
      zenity --error --title="$title" --width=700 --height=240 --text="$message"
      ;;
    kdialog)
      kdialog --title "$title" --error "$message"
      ;;
  esac
}

gui_menu() {
  case "$dialog_tool" in
    zenity)
      zenity --list \
        --title="Parser Template - GUI" \
        --width=760 \
        --height=420 \
        --column="Akcja" \
        --column="Opis" \
        "ping" "Sprawdź, czy daemon odpowiada" \
        "status" "Pobierz aktualny status daemona" \
        "frontend.event" "Wyślij przykładowe zdarzenie z GUI" \
        "show.last" "Pokaż ostatnią odpowiedź" \
        "exit" "Zamknij GUI"
      ;;
    kdialog)
      kdialog --title "Parser Template - GUI" --menu "Wybierz akcję" \
        "ping" "Sprawdź, czy daemon odpowiada" \
        "status" "Pobierz aktualny status daemona" \
        "frontend.event" "Wyślij przykładowe zdarzenie z GUI" \
        "show.last" "Pokaż ostatnią odpowiedź" \
        "exit" "Zamknij GUI"
      ;;
  esac
}

gui_payload_prompt() {
  case "$dialog_tool" in
    zenity)
      zenity --entry \
        --title="Zdarzenie GUI" \
        --width=700 \
        --text="Payload JSON dla komendy frontend.event" \
        --entry-text='{"source":"gui"}'
      ;;
    kdialog)
      kdialog --title "Zdarzenie GUI" --inputbox "Payload JSON dla komendy frontend.event" '{"source":"gui"}'
      ;;
  esac
}

run_gui_action() {
  local command="$1"
  local payload="${2:-}"

  if last_response="$(send_daemon_command "$command" "$payload")"; then
    gui_message "Odpowiedź daemona" "$last_response"
    return 0
  fi

  last_response="Błąd komunikacji z daemonem dla akcji: $command"
  gui_error "Błąd komunikacji" "$last_response"
  return 1
}

run_once() {
  local command="$1"
  local payload="${2:-}"
  send_daemon_command "$command" "$payload"
}

run_gui() {
  local choice payload

  select_dialog_tool
  while true; do
    choice="$(gui_menu || true)"
    case "$choice" in
      ping|status)
        run_gui_action "$choice" || true
        ;;
      frontend.event)
        payload="$(gui_payload_prompt || true)"
        [[ -z "$payload" ]] && payload='{}'
        run_gui_action frontend.event "$payload" || true
        ;;
      show.last)
        gui_message "Ostatnia odpowiedź" "$last_response"
        ;;
      exit|"")
        break
        ;;
      *)
        gui_error "Nieznana akcja" "Nieobsługiwana akcja GUI: $choice"
        ;;
    esac
  done
}

once_command=""
once_payload=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)
      if [[ $# -lt 2 ]]; then
        printf 'Brak wartości dla --once\n' >&2
        exit 64
      fi
      once_command="$2"
      shift 2
      ;;
    --payload)
      if [[ $# -lt 2 ]]; then
        printf 'Brak wartości dla --payload\n' >&2
        exit 64
      fi
      once_payload="$2"
      shift 2
      ;;
    --tool)
      if [[ $# -lt 2 ]]; then
        printf 'Brak wartości dla --tool\n' >&2
        exit 64
      fi
      GUI_DIALOG_TOOL="$2"
      shift 2
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      printf 'Nieznany argument: %s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -n "$once_command" ]]; then
  case "$once_command" in
    ping|status|frontend.event|shutdown)
      run_once "$once_command" "$once_payload"
      ;;
    *)
      printf 'Nieobsługiwana komenda --once: %s\n' "$once_command" >&2
      exit 64
      ;;
  esac
  exit $?
fi

run_gui
