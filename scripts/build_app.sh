#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${ROOT_DIR}"
PROJECT_FILE="${PROJECT_DIR}/VibeStoke.xcodeproj"
CONFIGURATION="${1:-Release}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required. Install full Xcode and run xcode-select --switch /Applications/Xcode.app" >&2
  exit 1
fi

xcodegen generate --spec "${PROJECT_DIR}/project.yml"

xcodebuild \
  -project "${PROJECT_FILE}" \
  -scheme "VibeStoke" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${PROJECT_DIR}/.derivedData" \
  build

APP_PATH="${PROJECT_DIR}/.derivedData/Build/Products/${CONFIGURATION}/VibeStoke.app"

echo "Build complete: ${APP_PATH}"
