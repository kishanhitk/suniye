#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${HOME}/Applications/Suniye.app"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not installed at ${APP_PATH}. Run ./scripts/build_app.sh Release --install-user first." >&2
  exit 1
fi

pkill -f '/Suniye.app/Contents/MacOS/Suniye' || true
sleep 1

echo "[1/4] Launching app"
open "${APP_PATH}"

echo "[2/4] Waiting for process"
for _ in {1..20}; do
  if pgrep -f '/Suniye.app/Contents/MacOS/Suniye' >/dev/null; then
    break
  fi
  sleep 0.25
done

if ! pgrep -f '/Suniye.app/Contents/MacOS/Suniye' >/dev/null; then
  echo "App process did not start" >&2
  exit 1
fi

echo "[3/4] Verifying main window is present"
window_count=""
for _ in {1..30}; do
  window_count="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  if exists process "Suniye" then
    tell process "Suniye"
      return (count of windows) as text
    end tell
  end if
end tell
return "0"
APPLESCRIPT
)"
  if [[ "${window_count}" =~ ^[0-9]+$ ]] && [[ "${window_count}" -gt 0 ]]; then
    break
  fi
  sleep 0.25
done

if ! [[ "${window_count}" =~ ^[0-9]+$ ]] || [[ "${window_count}" -lt 1 ]]; then
  echo "No app window detected via System Events (count=${window_count:-unknown})" >&2
  exit 1
fi

echo "[4/4] Verifying relaunch does not create duplicate process"
open "${APP_PATH}"
sleep 1
process_count="$(pgrep -f '/Suniye.app/Contents/MacOS/Suniye' | wc -l | tr -d ' ')"
if [[ "${process_count}" != "1" ]]; then
  echo "Expected 1 running process, got ${process_count}" >&2
  exit 1
fi

echo "E2E UI launch passed."
