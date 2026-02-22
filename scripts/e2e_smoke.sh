#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${HOME}/Library/Application Support/VibeStoke/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "Missing required file: ${path}" >&2
    return 1
  fi
}

echo "[1/4] Checking sherpa dylibs"
require_file "${ROOT_DIR}/VibeStoke/Frameworks/libsherpa-onnx-c-api.dylib"
require_file "${ROOT_DIR}/VibeStoke/Frameworks/libonnxruntime.dylib"

echo "[2/4] Checking model files"
require_file "${MODEL_DIR}/encoder.int8.onnx"
require_file "${MODEL_DIR}/decoder.int8.onnx"
require_file "${MODEL_DIR}/joiner.int8.onnx"
require_file "${MODEL_DIR}/tokens.txt"

echo "[3/4] Generating project"
xcodegen generate --spec "${ROOT_DIR}/project.yml" >/dev/null

echo "[4/4] Building app"
"${ROOT_DIR}/scripts/build_app.sh" Debug >/dev/null

echo "E2E smoke passed."
