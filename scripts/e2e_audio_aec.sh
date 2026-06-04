#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${HOME}/Applications/Suniye.app"
BIN_PATH="${APP_PATH}/Contents/MacOS/Suniye"
LOG_FILE="${HOME}/Library/Application Support/Suniye/logs/app.log"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "App executable not found at ${BIN_PATH}. Run ./scripts/build_app.sh Debug --install-user first." >&2
  exit 1
fi

mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"

start_marker="E2E_AUDIO_AEC_START_$(date +%s)"
echo "${start_marker}" >> "${LOG_FILE}"

pkill -f '/Suniye.app/Contents/MacOS/Suniye' || true
sleep 2

"${BIN_PATH}" --e2e-audio-aec >/dev/null 2>&1 &
app_pid=$!

exited=0
for _ in {1..600}; do
  if ! ps -p "${app_pid}" >/dev/null 2>&1; then
    exited=1
    break
  fi
  sleep 0.1
done

if [[ "${exited}" != "1" ]]; then
  echo "Audio AEC smoke did not terminate in time" >&2
  kill "${app_pid}" >/dev/null 2>&1 || true
  exit 1
fi

after_marker="$(awk -v marker="${start_marker}" '
  seen { print }
  $0 ~ marker { seen=1 }
' "${LOG_FILE}")"

if ! printf '%s\n' "${after_marker}" | rg -q "e2e audio aec smoke done passed=true"; then
  echo "Audio AEC smoke failed" >&2
  printf '%s\n' "${after_marker}" | rg "e2e audio aec|audio capture|audio backend" | tail -n 100 >&2
  exit 1
fi

printf '%s\n' "${after_marker}" | rg "e2e audio aec attempt=.*passed=true" | tail -n 1
echo "E2E audio AEC passed."
