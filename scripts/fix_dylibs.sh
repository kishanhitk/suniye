#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS_DIR="${ROOT_DIR}/Suniye/Frameworks"

cd "${FRAMEWORKS_DIR}"

if [[ ! -f libsherpa-onnx-c-api.dylib || ! -f libonnxruntime.dylib ]]; then
  echo "Required dylibs are missing in ${FRAMEWORKS_DIR}" >&2
  exit 1
fi

# Keep a compatibility symlink for the install-name expected by sherpa dylib.
ln -sf libonnxruntime.dylib libonnxruntime.1.23.2.dylib

install_name_tool -id @rpath/libonnxruntime.dylib libonnxruntime.dylib
install_name_tool -id @rpath/libsherpa-onnx-c-api.dylib libsherpa-onnx-c-api.dylib
install_name_tool -change @rpath/libonnxruntime.1.23.2.dylib @rpath/libonnxruntime.dylib libsherpa-onnx-c-api.dylib

echo "Dylib install names updated successfully."
