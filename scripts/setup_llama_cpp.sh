#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CPP_REPO="${LLAMA_CPP_REPO:-https://github.com/ggml-org/llama.cpp.git}"
LLAMA_CPP_COMMIT="${LLAMA_CPP_COMMIT:-06938ac129e5feee1e731323e5c37dc973de5573}"
SOURCE_DIR="${ROOT_DIR}/.build/llama.cpp/source"
BUILD_DIR="${ROOT_DIR}/.build/llama.cpp/build"
OUTPUT_PATH="${SUNIYE_LLAMA_SERVER_OUTPUT:-${ROOT_DIR}/Suniye/LocalLLM/llama-server}"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Local Gemma llama-server is Apple Silicon-only for this build." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required." >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required. Install it with Homebrew or Xcode tooling before building llama.cpp." >&2
  exit 1
fi

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  rm -rf "${SOURCE_DIR}"
  git clone "${LLAMA_CPP_REPO}" "${SOURCE_DIR}"
fi

git -C "${SOURCE_DIR}" fetch --tags --prune origin
git -C "${SOURCE_DIR}" checkout --detach "${LLAMA_CPP_COMMIT}"

cmake \
  -S "${SOURCE_DIR}" \
  -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DLLAMA_CURL=OFF \
  -DLLAMA_OPENSSL=OFF

cmake --build "${BUILD_DIR}" --config Release --target llama-server -j"$(sysctl -n hw.ncpu)"

SERVER_CANDIDATES=(
  "${BUILD_DIR}/bin/llama-server"
  "${BUILD_DIR}/tools/server/llama-server"
)

SERVER_PATH=""
for candidate in "${SERVER_CANDIDATES[@]}"; do
  if [[ -x "${candidate}" ]]; then
    SERVER_PATH="${candidate}"
    break
  fi
done

if [[ -z "${SERVER_PATH}" ]]; then
  echo "Built llama-server was not found under ${BUILD_DIR}." >&2
  exit 1
fi

if /usr/bin/otool -L "${SERVER_PATH}" | grep -E '/opt/homebrew|/usr/local' >/dev/null; then
  echo "llama-server links against Homebrew/local dylibs; build must be static or bundle those dylibs before release." >&2
  /usr/bin/otool -L "${SERVER_PATH}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"
/usr/bin/ditto "${SERVER_PATH}" "${OUTPUT_PATH}"
/bin/chmod 755 "${OUTPUT_PATH}"

echo "Prepared llama-server helper at: ${OUTPUT_PATH}"
echo "Pinned llama.cpp commit: ${LLAMA_CPP_COMMIT}"
