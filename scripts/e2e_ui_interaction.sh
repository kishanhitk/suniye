#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${HOME}/Applications/VibeStoke.app"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not installed at ${APP_PATH}. Run ./scripts/build_app.sh Release --install-user first." >&2
  exit 1
fi

pkill -f '/VibeStoke.app/Contents/MacOS/VibeStoke' || true
sleep 1
open "${APP_PATH}"

for _ in {1..40}; do
  if pgrep -f '/VibeStoke.app/Contents/MacOS/VibeStoke' >/dev/null; then
    break
  fi
  sleep 0.25
done

if ! pgrep -f '/VibeStoke.app/Contents/MacOS/VibeStoke' >/dev/null; then
  echo "App process did not start" >&2
  exit 1
fi

result="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  if not (exists process "VibeStoke") then return "NO_PROCESS"
  tell process "VibeStoke"
    set frontmost to true
    delay 0.3
    if (count of windows) < 1 then return "NO_WINDOW"
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
