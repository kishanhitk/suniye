#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "Missing required file: ${path}" >&2
    return 1
  fi
}

echo "[1/3] Verifying sherpa dylibs"
require_file "${ROOT_DIR}/Suniye/Frameworks/libsherpa-onnx-c-api.dylib"
require_file "${ROOT_DIR}/Suniye/Frameworks/libonnxruntime.dylib"

echo "[2/3] Verifying source and bridge header presence"
require_file "${ROOT_DIR}/Suniye/Suniye-Bridging-Header.h"
if command -v rg >/dev/null 2>&1; then
  SWIFT_COUNT="$(rg --files Suniye -g '*.swift' | wc -l | tr -d ' ')"
else
  SWIFT_COUNT="$(find Suniye -type f -name '*.swift' | wc -l | tr -d ' ')"
fi
if [[ "${SWIFT_COUNT}" -eq 0 ]]; then
  echo "No Swift source files found under Suniye/" >&2
  exit 1
fi

echo "[3/3] Generating project spec"
xcodegen generate --spec "${ROOT_DIR}/project.yml" >/dev/null

echo "E2E preflight passed."
