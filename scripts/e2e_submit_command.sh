#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${HOME}/Applications/VibeStoke.app"
BIN_PATH="${APP_PATH}/Contents/MacOS/VibeStoke"
LOG_FILE="${HOME}/Library/Application Support/VibeStoke/logs/app.log"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "App executable not found at ${BIN_PATH}. Run ./scripts/build_app.sh Release --install-user first." >&2
  exit 1
fi

mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"

start_marker="E2E_SUBMIT_COMMAND_START_$(date +%s)"
echo "${start_marker}" >> "${LOG_FILE}"

pkill -f '/VibeStoke.app/Contents/MacOS/VibeStoke' || true
sleep 1

"${BIN_PATH}" --e2e-submit-command >/dev/null 2>&1 &
app_pid=$!

exited=0
for _ in {1..180}; do
  if ! ps -p "${app_pid}" >/dev/null 2>&1; then
    exited=1
    break
  fi
  sleep 0.1
done

if [[ "${exited}" != "1" ]]; then
  echo "Submit command smoke did not terminate in time" >&2
  kill "${app_pid}" >/dev/null 2>&1 || true
  exit 1
fi

after_marker="$(awk -v marker="${start_marker}" '
  seen { print }
  $0 ~ marker { seen=1 }
' "${LOG_FILE}")"

require_log() {
  local pattern="$1"
  if ! printf '%s\n' "${after_marker}" | rg -q "${pattern}"; then
    echo "Missing expected log pattern: ${pattern}" >&2
    printf '%s\n' "${after_marker}" | tail -n 80 >&2
    exit 1
  fi
}

require_log "e2e submit smoke start"
require_log "e2e submit smoke done passed=true"

echo "E2E submit command passed."
