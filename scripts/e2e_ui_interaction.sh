#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${HOME}/Applications/Suniye.app"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not installed at ${APP_PATH}. Run ./scripts/build_app.sh Release --install-user first." >&2
  exit 1
fi

pkill -f '/Suniye.app/Contents/MacOS/Suniye' || true
sleep 1
open "${APP_PATH}"

for _ in {1..40}; do
  if pgrep -f '/Suniye.app/Contents/MacOS/Suniye' >/dev/null; then
    break
  fi
  sleep 0.25
done

if ! pgrep -f '/Suniye.app/Contents/MacOS/Suniye' >/dev/null; then
  echo "App process did not start" >&2
  exit 1
fi

window_ready=0
for _ in {1..40}; do
  window_count="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  if not (exists process "Suniye") then return "NO_PROCESS"
  tell process "Suniye"
    return (count of windows) as text
  end tell
end tell
APPLESCRIPT
)"
  if [[ "${window_count}" =~ ^[0-9]+$ ]] && [[ "${window_count}" -gt 0 ]]; then
    window_ready=1
    break
  fi
  sleep 0.25
done

if [[ "${window_ready}" != "1" ]]; then
  echo "UI interaction failed (NO_WINDOW). Verify Accessibility permissions for Terminal/System Events if needed." >&2
  exit 1
fi

result="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  if not (exists process "Suniye") then return "NO_PROCESS"
  tell process "Suniye"
    set frontmost to true
    delay 0.3
    set buttonCount to count of buttons of window 1
    if buttonCount < 1 then return "NO_BUTTON"
    click button 1 of window 1
    return "OK:" & (buttonCount as text)
  end tell
end tell
APPLESCRIPT
)"

case "${result}" in
  OK:*)
    echo "E2E UI interaction passed (${result})."
    ;;
  *)
    echo "UI interaction failed (${result}). Verify Accessibility permissions for Terminal/System Events if needed." >&2
    exit 1
    ;;
esac
