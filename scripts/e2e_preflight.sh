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
require_file "${ROOT_DIR}/VibeStoke/Frameworks/libsherpa-onnx-c-api.dylib"
require_file "${ROOT_DIR}/VibeStoke/Frameworks/libonnxruntime.dylib"

echo "[2/3] Typechecking app sources with C API bridge"
cd "${ROOT_DIR}"
if command -v rg >/dev/null 2>&1; then
  SWIFT_FILE_CMD=(rg --files VibeStoke -g '*.swift')
else
  SWIFT_FILE_CMD=(find VibeStoke -type f -name '*.swift')
fi
SWIFT_FILES=()
while IFS= read -r file; do
  SWIFT_FILES+=("${file}")
done < <("${SWIFT_FILE_CMD[@]}" | sort)
swiftc -import-objc-header VibeStoke/VibeStoke-Bridging-Header.h -typecheck "${SWIFT_FILES[@]}"

echo "[3/3] Generating project spec"
xcodegen generate --spec "${ROOT_DIR}/project.yml" >/dev/null

echo "E2E preflight passed."
