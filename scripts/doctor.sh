#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${HOME}/Library/Application Support/VibeStoke/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"

need_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing command: ${cmd}" >&2
    return 1
  fi
}

echo "[1/5] Checking required commands"
need_cmd xcodebuild
need_cmd xcodegen
need_cmd tar
need_cmd curl
need_cmd hdiutil
need_cmd shasum

echo "[2/5] Checking active Xcode"
xcodebuild -version >/dev/null

echo "[3/5] Checking runtime dylibs"
[[ -f "${ROOT_DIR}/VibeStoke/Frameworks/libsherpa-onnx-c-api.dylib" ]]
[[ -f "${ROOT_DIR}/VibeStoke/Frameworks/libonnxruntime.dylib" ]]

echo "[4/5] Checking ASR model files"
for f in encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt; do
  [[ -f "${MODEL_DIR}/${f}" ]] || { echo "Missing model file: ${MODEL_DIR}/${f}" >&2; exit 1; }
done

echo "[5/5] Checking project generation"
xcodegen generate --spec "${ROOT_DIR}/project.yml" >/dev/null

echo "Doctor check passed."
