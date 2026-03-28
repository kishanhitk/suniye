#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${ROOT_DIR}"
PROJECT_FILE="${PROJECT_DIR}/Suniye.xcodeproj"
CONFIGURATION="Release"
INSTALL_TARGET=""
SHOULD_OPEN="0"
DERIVED_DATA_PATH="${PROJECT_DIR}/.derivedData"
OUTPUT_DIR=""
BUILD_DESTINATION=""
BUILD_ARCH=""
VERSION=""
LOCAL_CODESIGN_IDENTITY=""

usage() {
  cat <<'USAGE'
Usage: scripts/build_app.sh [Debug|Release] [--install-user] [--install-system] [--open]

Options:
  --install-user    Copy app to ~/Applications/Suniye.app
  --install-system  Copy app to /Applications/Suniye.app
  --derived-data-path <path>  Override derived data path
  --output-dir <dir>          Copy built app to a deterministic output directory
  --version <vX.Y.Z>          Override MARKETING_VERSION in the build
  --open            Open the resulting app after build/install
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    Debug|Release)
      CONFIGURATION="$1"
      ;;
    --install-user)
      INSTALL_TARGET="${HOME}/Applications"
      ;;
    --install-system)
      INSTALL_TARGET="/Applications"
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="$2"
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift
      ;;
    --version)
      VERSION="$2"
      shift
      ;;
    --open)
      SHOULD_OPEN="1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -z "${BUILD_DESTINATION}" ]]; then
  case "$(uname -m)" in
    arm64)
      BUILD_DESTINATION="platform=macOS,arch=arm64"
      BUILD_ARCH="arm64"
      ;;
    x86_64)
      BUILD_DESTINATION="platform=macOS,arch=x86_64"
      BUILD_ARCH="x86_64"
      ;;
    *)
      BUILD_DESTINATION="platform=macOS"
      ;;
  esac
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required. Install full Xcode and run xcode-select --switch /Applications/Xcode.app" >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is not active. Run: sudo xcode-select --switch /Applications/Xcode.app" >&2
  exit 1
fi

if [[ -z "${LOCAL_CODESIGN_IDENTITY}" ]]; then
  LOCAL_CODESIGN_IDENTITY="${SUNIYE_CODESIGN_IDENTITY:-}"
fi

if [[ -z "${LOCAL_CODESIGN_IDENTITY}" ]] && command -v security >/dev/null 2>&1; then
  LOCAL_CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"Suniye Local Dev"/ { print $2; exit }')"
fi

xcodegen generate --spec "${PROJECT_DIR}/project.yml"

xcodebuild_args=(
  -project "${PROJECT_FILE}"
  -scheme "Suniye"
  -configuration "${CONFIGURATION}"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  -destination "${BUILD_DESTINATION}"
  build
)

if [[ -n "${BUILD_ARCH}" ]]; then
  xcodebuild_args+=(ARCHS="${BUILD_ARCH}" ONLY_ACTIVE_ARCH=YES)
fi

if [[ -n "${VERSION}" ]]; then
  # Strip leading 'v' prefix (v0.0.5 -> 0.0.5)
  MARKETING="${VERSION#v}"
  xcodebuild_args+=(MARKETING_VERSION="${MARKETING}")
fi

if [[ -n "${LOCAL_CODESIGN_IDENTITY}" ]]; then
  echo "Using local signing identity: ${LOCAL_CODESIGN_IDENTITY}"
  xcodebuild_args+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="${LOCAL_CODESIGN_IDENTITY}"
  )
fi

xcodebuild "${xcodebuild_args[@]}"

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/Suniye.app"
FINAL_APP_PATH="${APP_PATH}"

if [[ -n "${INSTALL_TARGET}" ]]; then
  mkdir -p "${INSTALL_TARGET}"
  DEST_APP_PATH="${INSTALL_TARGET}/Suniye.app"
  rm -rf "${DEST_APP_PATH}"
  ditto "${APP_PATH}" "${DEST_APP_PATH}"
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
  if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -u "${APP_PATH}" >/dev/null 2>&1 || true
    "${LSREGISTER}" -f -R -trusted "${DEST_APP_PATH}" >/dev/null 2>&1 || true
  fi
  rm -rf \
    "${DERIVED_DATA_PATH}/Build/Products/Debug/Suniye.app" \
    "${DERIVED_DATA_PATH}/Build/Products/Release/Suniye.app"
  FINAL_APP_PATH="${DEST_APP_PATH}"
  echo "Installed app to: ${DEST_APP_PATH}"
fi

if [[ -n "${OUTPUT_DIR}" ]]; then
  mkdir -p "${OUTPUT_DIR}"
  OUTPUT_APP_PATH="${OUTPUT_DIR}/Suniye.app"
  rm -rf "${OUTPUT_APP_PATH}"
  ditto "${APP_PATH}" "${OUTPUT_APP_PATH}"
  FINAL_APP_PATH="${OUTPUT_APP_PATH}"
  echo "Copied app to output directory: ${OUTPUT_APP_PATH}"
fi

if [[ "${SHOULD_OPEN}" == "1" ]]; then
  open "${FINAL_APP_PATH}"
fi

echo "Build complete: ${FINAL_APP_PATH}"
