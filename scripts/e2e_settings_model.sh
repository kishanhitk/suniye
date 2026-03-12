#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${HOME}/Applications/Suniye.app"
BIN_PATH="${APP_PATH}/Contents/MacOS/Suniye"
LOG_FILE="${HOME}/Library/Application Support/Suniye/logs/app.log"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "App executable not found at ${BIN_PATH}. Run ./scripts/build_app.sh Release --install-user first." >&2
  exit 1
fi

mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"

start_marker="E2E_SETTINGS_START_$(date +%s)"
echo "${start_marker}" >> "${LOG_FILE}"

pkill -f '/Suniye.app/Contents/MacOS/Suniye' || true
sleep 1

"${BIN_PATH}" --open-model >/dev/null 2>&1 &
app_pid=$!

cleanup() {
  kill "${app_pid}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in {1..40}; do
  if ps -p "${app_pid}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

if ! ps -p "${app_pid}" >/dev/null 2>&1; then
  echo "App process did not start in model mode" >&2
  exit 1
fi

found=0
for _ in {1..80}; do
  if awk -v marker="${start_marker}" '
      seen { print }
      $0 ~ marker { seen=1 }
    ' "${LOG_FILE}" | rg -q "main window section rendered section=model"; then
    found=1
    break
  fi
  sleep 0.25
done

if [[ "${found}" != "1" ]]; then
  echo "Model section marker not found. Last logs:" >&2
  tail -n 80 "${LOG_FILE}" >&2
  exit 1
fi

echo "E2E settings model passed."
