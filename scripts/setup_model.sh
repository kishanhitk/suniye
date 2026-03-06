#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_NAME="sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${MODEL_NAME}.tar.bz2"
MODEL_BASE_DIR="${HOME}/Library/Application Support/Suniye/models"
MODEL_DIR="${MODEL_BASE_DIR}/${MODEL_NAME}"
ARCHIVE_PATH="${TMPDIR:-/tmp}/${MODEL_NAME}.tar.bz2"

mkdir -p "${MODEL_BASE_DIR}"

if [[ -f "${MODEL_DIR}/encoder.int8.onnx" && -f "${MODEL_DIR}/decoder.int8.onnx" && -f "${MODEL_DIR}/joiner.int8.onnx" && -f "${MODEL_DIR}/tokens.txt" ]]; then
  echo "Model already present at: ${MODEL_DIR}"
  exit 0
fi

download_archive() {
  local attempt=1
  local max_attempts=5
  while [[ "${attempt}" -le "${max_attempts}" ]]; do
    echo "Downloading model archive (attempt ${attempt}/${max_attempts})..."
    rm -f "${ARCHIVE_PATH}"

    if curl -fL --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 "${MODEL_URL}" -o "${ARCHIVE_PATH}"; then
      if /usr/bin/tar -tjf "${ARCHIVE_PATH}" >/dev/null 2>&1; then
        return 0
      fi

      local archive_size
      archive_size="$(wc -c < "${ARCHIVE_PATH}" | tr -d ' ')"
      echo "Downloaded file is not a valid tar.bz2 archive (size=${archive_size} bytes)." >&2
    else
      echo "Download failed on attempt ${attempt}." >&2
    fi

    sleep $((attempt * 2))
    attempt=$((attempt + 1))
  done

  return 1
}

if ! download_archive; then
  echo "Failed to download a valid model archive from ${MODEL_URL}" >&2
  exit 1
fi

echo "Extracting model..."
/usr/bin/tar -xjf "${ARCHIVE_PATH}" -C "${MODEL_BASE_DIR}"

rm -f "${ARCHIVE_PATH}"

echo "Model ready at: ${MODEL_DIR}"
