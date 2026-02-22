#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${HOME}/Applications/VibeStoke.app"
LOG_DIR="${HOME}/Library/Application Support/VibeStoke/logs"
LOG_FILE="${LOG_DIR}/app.log"

mkdir -p "${LOG_DIR}"
touch "${LOG_FILE}"

echo "[1/4] Building and installing Debug app"
"${ROOT_DIR}/scripts/build_app.sh" Debug --install-user

echo "[2/4] Restarting app"
pkill -f '/VibeStoke.app/Contents/MacOS/VibeStoke' || true
sleep 1
open "${APP_PATH}"

echo "[3/4] Log file: ${LOG_FILE}"
echo "[4/4] Live tail (Ctrl+C to stop)"
tail -n 200 -f "${LOG_FILE}"
