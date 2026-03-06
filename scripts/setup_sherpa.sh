#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="${ROOT_DIR}/third_party"
SHERPA_DIR="${THIRD_PARTY_DIR}/sherpa-onnx"
FRAMEWORKS_DIR="${ROOT_DIR}/Suniye/Frameworks"
BUILD_DIR="${SHERPA_DIR}/build-suniye-macos"
INSTALL_DIR="${BUILD_DIR}/install"

mkdir -p "${THIRD_PARTY_DIR}" "${FRAMEWORKS_DIR}"

if [[ ! -d "${SHERPA_DIR}" ]]; then
  git clone --depth 1 https://github.com/k2-fsa/sherpa-onnx "${SHERPA_DIR}"
else
  git -C "${SHERPA_DIR}" pull --ff-only
fi

pushd "${SHERPA_DIR}" >/dev/null

# Build shared C API dylibs directly (no xcframework step required).
cmake -S . -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBUILD_SHARED_LIBS=ON \
  -DSHERPA_ONNX_ENABLE_BINARY=OFF \
  -DSHERPA_ONNX_BUILD_C_API_EXAMPLES=OFF \
  -DSHERPA_ONNX_ENABLE_C_API=ON \
  -DSHERPA_ONNX_ENABLE_TTS=OFF \
  -DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF \
  -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
  -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
  -DSHERPA_ONNX_ENABLE_TESTS=OFF \
  -DSHERPA_ONNX_ENABLE_CHECK=OFF \
  -DSHERPA_ONNX_ENABLE_JNI=OFF \
  -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF

cmake --build "${BUILD_DIR}" --config Release -j"$(sysctl -n hw.ncpu)"
cmake --install "${BUILD_DIR}" --config Release

popd >/dev/null

cp "${SHERPA_DIR}/sherpa-onnx/c-api/c-api.h" "${ROOT_DIR}/Suniye/c-api.h"

cp "${INSTALL_DIR}/lib/libsherpa-onnx-c-api.dylib" "${FRAMEWORKS_DIR}/libsherpa-onnx-c-api.dylib"
cp "${INSTALL_DIR}/lib/libonnxruntime.dylib" "${FRAMEWORKS_DIR}/libonnxruntime.dylib"

chmod 755 "${FRAMEWORKS_DIR}/libsherpa-onnx-c-api.dylib" "${FRAMEWORKS_DIR}/libonnxruntime.dylib"

echo "Sherpa setup complete:"
echo "- ${FRAMEWORKS_DIR}/libsherpa-onnx-c-api.dylib"
echo "- ${FRAMEWORKS_DIR}/libonnxruntime.dylib"
