#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_NAME="sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${MODEL_NAME}.tar.bz2"
MODEL_BASE_DIR="${HOME}/Library/Application Support/VibeStoke/models"
MODEL_DIR="${MODEL_BASE_DIR}/${MODEL_NAME}"
ARCHIVE_PATH="${TMPDIR:-/tmp}/${MODEL_NAME}.tar.bz2"

mkdir -p "${MODEL_BASE_DIR}"

if [[ -f "${MODEL_DIR}/encoder.int8.onnx" && -f "${MODEL_DIR}/decoder.int8.onnx" && -f "${MODEL_DIR}/joiner.int8.onnx" && -f "${MODEL_DIR}/tokens.txt" ]]; then
  echo "Model already present at: ${MODEL_DIR}"
  exit 0
fi

echo "Downloading model archive..."
curl -L "${MODEL_URL}" -o "${ARCHIVE_PATH}"

echo "Extracting model..."
/usr/bin/tar -xjf "${ARCHIVE_PATH}" -C "${MODEL_BASE_DIR}"

rm -f "${ARCHIVE_PATH}"

echo "Model ready at: ${MODEL_DIR}"
