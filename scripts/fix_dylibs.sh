#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS_DIR="${ROOT_DIR}/Suniye/Frameworks"

cd "${FRAMEWORKS_DIR}"

if [[ ! -f libsherpa-onnx-c-api.dylib || ! -f libonnxruntime.dylib ]]; then
  echo "Required dylibs are missing in ${FRAMEWORKS_DIR}" >&2
  exit 1
fi

# Some ONNX Runtime builds use a versioned install name
# (@rpath/libonnxruntime.<version>.dylib). Suniye embeds one unversioned copy,
# so sherpa-onnx must load it by the unversioned name.
ORT_DEPENDENCY="$(otool -L libsherpa-onnx-c-api.dylib | awk '$1 ~ /^@rpath\/libonnxruntime/ { print $1; exit }')"
if [[ -z "${ORT_DEPENDENCY}" ]]; then
  echo "libsherpa-onnx-c-api.dylib does not load ONNX Runtime through @rpath." >&2
  exit 1
fi

install_name_tool -id @rpath/libonnxruntime.dylib libonnxruntime.dylib
install_name_tool -id @rpath/libsherpa-onnx-c-api.dylib libsherpa-onnx-c-api.dylib
if [[ "${ORT_DEPENDENCY}" != "@rpath/libonnxruntime.dylib" ]]; then
  install_name_tool -change "${ORT_DEPENDENCY}" @rpath/libonnxruntime.dylib libsherpa-onnx-c-api.dylib
fi

# install_name_tool invalidates the signatures. Xcode re-signs the embedded
# copies, but anything that loads these files directly needs a valid one.
codesign --force --sign - libonnxruntime.dylib libsherpa-onnx-c-api.dylib

echo "Dylib install names updated successfully."
