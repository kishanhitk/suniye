#!/usr/bin/env bash
set -euo pipefail

# Every bundled sherpa-onnx binary and header comes from this tag. When you bump
# it, also replace Suniye/SherpaOnnx.swift with the same tag's
# swift-api-examples/SherpaOnnx.swift.
SHERPA_ONNX_VERSION="v1.13.8"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="${ROOT_DIR}/third_party"
SHERPA_DIR="${THIRD_PARTY_DIR}/sherpa-onnx"
FRAMEWORKS_DIR="${ROOT_DIR}/Suniye/Frameworks"
BUILD_DIR="${SHERPA_DIR}/build-suniye-macos"
INSTALL_DIR="${BUILD_DIR}/install"

mkdir -p "${THIRD_PARTY_DIR}" "${FRAMEWORKS_DIR}"

if [[ ! -d "${SHERPA_DIR}/.git" ]]; then
  git clone --depth 1 --branch "${SHERPA_ONNX_VERSION}" https://github.com/k2-fsa/sherpa-onnx "${SHERPA_DIR}"
else
  git -C "${SHERPA_DIR}" fetch --depth 1 origin tag "${SHERPA_ONNX_VERSION}"
  git -C "${SHERPA_DIR}" checkout --detach "${SHERPA_ONNX_VERSION}"
fi

# A build directory configured for another tag keeps stale cache entries.
rm -rf "${BUILD_DIR}"

pushd "${SHERPA_DIR}" >/dev/null

# Build shared C API dylibs directly (no xcframework step required).
cmake -S . -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
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

# The Cohere Transcribe engine calls the ONNX Runtime C API directly, so its
# headers must come from the same ONNX Runtime build that sherpa-onnx links.
ONNXRUNTIME_INCLUDE_DIR="${BUILD_DIR}/_deps/onnxruntime-src/include"
for header in onnxruntime_c_api.h onnxruntime_ep_c_api.h onnxruntime_error_code.h; do
  cp "${ONNXRUNTIME_INCLUDE_DIR}/${header}" "${ROOT_DIR}/Suniye/${header}"
done

cp "${INSTALL_DIR}/lib/libsherpa-onnx-c-api.dylib" "${FRAMEWORKS_DIR}/libsherpa-onnx-c-api.dylib"
cp "${INSTALL_DIR}/lib/libonnxruntime.dylib" "${FRAMEWORKS_DIR}/libonnxruntime.dylib"

chmod 755 "${FRAMEWORKS_DIR}/libsherpa-onnx-c-api.dylib" "${FRAMEWORKS_DIR}/libonnxruntime.dylib"

"${ROOT_DIR}/scripts/fix_dylibs.sh"

echo "Sherpa setup complete (sherpa-onnx ${SHERPA_ONNX_VERSION}):"
echo "- ${FRAMEWORKS_DIR}/libsherpa-onnx-c-api.dylib"
echo "- ${FRAMEWORKS_DIR}/libonnxruntime.dylib"
