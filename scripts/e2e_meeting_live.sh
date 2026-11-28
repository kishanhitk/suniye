#!/usr/bin/env bash
# Records a real meeting in an installed app and checks the live transcript.
# The app plays nothing itself: this script plays a recorded meeting on the
# speakers, so the call-audio tap and the microphone hear it as in a call.
# The app needs Microphone and System Audio Recording access.
#
# Usage: scripts/e2e_meeting_live.sh <app path> <meeting audio file> [seconds]
set -euo pipefail

APP_PATH="${1:?app path}"
AUDIO_PATH="${2:?meeting audio file}"
MEETING_SECONDS="${3:-120}"
BIN_PATH="${APP_PATH}/Contents/MacOS/$(/usr/bin/defaults read "${APP_PATH}/Contents/Info" CFBundleExecutable)"
LOG_FILE="${HOME}/Library/Application Support/Suniye/logs/app.log"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "App executable not found at ${BIN_PATH}." >&2
  exit 1
fi
if [[ ! -f "${AUDIO_PATH}" ]]; then
  echo "Audio file not found: ${AUDIO_PATH}" >&2
  exit 1
fi

mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"
start_marker="E2E_MEETING_LIVE_START_$(date +%s)"
echo "${start_marker}" >> "${LOG_FILE}"

log_since_start() {
  awk -v marker="${start_marker}" 'seen { print } $0 ~ marker { seen=1 }' "${LOG_FILE}"
}

app_pid=""
player_pid=""
cleanup() {
  [[ -n "${player_pid}" ]] && kill "${player_pid}" >/dev/null 2>&1 || true
  [[ -n "${app_pid}" ]] && kill "${app_pid}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${BIN_PATH}" "--e2e-meeting-live=${MEETING_SECONDS}" >/dev/null 2>&1 &
app_pid=$!
echo "app pid ${app_pid}"

/usr/bin/afplay -t "$((MEETING_SECONDS + 60))" "${AUDIO_PATH}" &
player_pid=$!

finished=0
for _ in $(seq 1 $((MEETING_SECONDS + 600))); do
  if log_since_start | grep "e2e meeting live finished" >/dev/null; then
    finished=1
    break
  fi
  if ! ps -p "${app_pid}" >/dev/null 2>&1; then
    echo "The app ended before the meeting finished." >&2
    break
  fi
  sleep 1
done

log_since_start | grep -E "e2e meeting live|meeting (started|stopped|transcript)" || true

if [[ "${finished}" != "1" ]]; then
  echo "The meeting did not finish." >&2
  exit 1
fi
if ! log_since_start | grep -E "e2e meeting live lines=[1-9]" >/dev/null; then
  echo "No line showed during the meeting." >&2
  exit 1
fi
if ! log_since_start | grep -E "e2e meeting live finished .* final=[1-9]" >/dev/null; then
  echo "The final transcript has no line." >&2
  exit 1
fi
if log_since_start | grep -E "e2e meeting live finished .* status=interrupted" >/dev/null; then
  echo "The final transcript did not finish." >&2
  exit 1
fi
echo "E2E meeting live passed."
