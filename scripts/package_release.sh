#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
VERSION=""
BUILD_NUMBER=""
BUILD_CHANNEL="${SUNIYE_BUILD_CHANNEL:-stable}"
APPCAST_CHANNEL=""
DOWNLOAD_URL_PREFIX=""
RELEASE_NOTES_FILE=""

usage() {
  cat <<'USAGE'
Usage: scripts/package_release.sh --version vX.Y.Z [--build-number <number>] [--build-channel stable|tip] [--appcast-channel <name>] [--download-url-prefix <url>] [--dist-dir <dir>] [--release-notes-file <path>]
USAGE
}

channel_rank() {
  case "$1" in
    tip)
      echo "1"
      ;;
    stable)
      echo "8"
      ;;
    *)
      echo "Unknown build channel: $1" >&2
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --build-channel)
      BUILD_CHANNEL="$2"
      shift 2
      ;;
    --appcast-channel)
      APPCAST_CHANNEL="$2"
      shift 2
      ;;
    --download-url-prefix)
      DOWNLOAD_URL_PREFIX="$2"
      shift 2
      ;;
    --dist-dir)
      DIST_DIR="$2"
      shift 2
      ;;
    --release-notes-file)
      RELEASE_NOTES_FILE="$2"
      shift 2
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
done

if [[ -z "${VERSION}" ]]; then
  echo "--version is required so release artifacts and appcast.xml describe the same version." >&2
  usage >&2
  exit 1
fi

CHANNEL_RANK="$(channel_rank "${BUILD_CHANNEL}")"

if [[ -z "${BUILD_NUMBER}" ]]; then
  BUILD_NUMBER="${SUNIYE_BUILD_NUMBER:-}"
fi

if [[ -z "${BUILD_NUMBER}" ]] && git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  COMMIT_COUNT="$(git -C "${ROOT_DIR}" rev-list --count HEAD)"
  BUILD_NUMBER="$((COMMIT_COUNT * 10 + CHANNEL_RANK))"
fi

if [[ -z "${BUILD_NUMBER}" || ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "Build number must be numeric, got: ${BUILD_NUMBER}" >&2
  exit 1
fi

if [[ -n "${APPCAST_CHANNEL}" && ! "${APPCAST_CHANNEL}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Appcast channel may only contain letters, numbers, dots, underscores, and dashes: ${APPCAST_CHANNEL}" >&2
  exit 1
fi

if [[ -n "${RELEASE_NOTES_FILE}" && ! -s "${RELEASE_NOTES_FILE}" ]]; then
  echo "Release notes file is missing or empty: ${RELEASE_NOTES_FILE}" >&2
  exit 1
fi

if [[ -z "${SUNIYE_CODESIGN_IDENTITY:-}" ]]; then
  echo "SUNIYE_CODESIGN_IDENTITY is required for release packaging." >&2
  echo "Create/import the stable self-signed release identity before packaging." >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"
DERIVED_DATA="${ROOT_DIR}/.derivedData-release"
LLAMA_SERVER_HELPER="${SUNIYE_LLAMA_SERVER_PATH:-${ROOT_DIR}/Suniye/LocalLLM/llama-server}"

if [[ -n "${SUNIYE_LLAMA_SERVER_PATH:-}" && ! -x "${LLAMA_SERVER_HELPER}" ]]; then
  echo "SUNIYE_LLAMA_SERVER_PATH must point to an executable helper: ${LLAMA_SERVER_HELPER}" >&2
  exit 1
fi

if [[ -n "${SUNIYE_LLAMA_SERVER_PATH:-}" ]]; then
  echo "Using Local Gemma llama-server helper from SUNIYE_LLAMA_SERVER_PATH: ${LLAMA_SERVER_HELPER}"
elif [[ ! -x "${LLAMA_SERVER_HELPER}" ]]; then
  echo "Preparing Local Gemma llama-server helper..."
  "${ROOT_DIR}/scripts/setup_llama_cpp.sh"
fi

BUILD_ARGS=(Release --derived-data-path "${DERIVED_DATA}" --output-dir "${DIST_DIR}")
BUILD_ARGS+=(--version "${VERSION}")
BUILD_ARGS+=(--build-number "${BUILD_NUMBER}")
BUILD_ARGS+=(--build-channel "${BUILD_CHANNEL}")
BUILD_ARGS+=(--codesign-identity "${SUNIYE_CODESIGN_IDENTITY}")
BUILD_ARGS+=(--release-sign)
"${ROOT_DIR}/scripts/build_app.sh" "${BUILD_ARGS[@]}"

APP_PATH="${DIST_DIR}/Suniye.app"
ZIP_PATH="${DIST_DIR}/Suniye.app.zip"
DMG_PATH="${DIST_DIR}/Suniye.dmg"
CHECKSUMS_PATH="${DIST_DIR}/SHA256SUMS.txt"
APPCAST_PATH="${DIST_DIR}/appcast.xml"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected app not found at ${APP_PATH}" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
"${ROOT_DIR}/scripts/verify_release_signing.sh" "${APP_PATH}"

rm -f "${ZIP_PATH}" "${DMG_PATH}" "${CHECKSUMS_PATH}" "${APPCAST_PATH}"

# Create zip artifact
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

# Create DMG with app + Applications link
DMG_STAGING="${ROOT_DIR}/.dmg-staging"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
/usr/bin/ditto "${APP_PATH}" "${DMG_STAGING}/Suniye.app"
ln -s /Applications "${DMG_STAGING}/Applications"

/usr/bin/hdiutil create -volname "Suniye" -srcfolder "${DMG_STAGING}" -ov -format ULMO "${DMG_PATH}" >/dev/null
rm -rf "${DMG_STAGING}"

(
  cd "${DIST_DIR}"
  shasum -a 256 "Suniye.dmg" "Suniye.app.zip" > "SHA256SUMS.txt"
)

APPCAST_ARGS=(--version "${VERSION}" --dist-dir "${DIST_DIR}")
if [[ -n "${DOWNLOAD_URL_PREFIX}" ]]; then
  APPCAST_ARGS+=(--download-url-prefix "${DOWNLOAD_URL_PREFIX}")
fi
if [[ -n "${APPCAST_CHANNEL}" ]]; then
  APPCAST_ARGS+=(--channel "${APPCAST_CHANNEL}")
fi
if [[ -n "${RELEASE_NOTES_FILE}" ]]; then
  APPCAST_ARGS+=(--release-notes-file "${RELEASE_NOTES_FILE}")
fi
"${ROOT_DIR}/scripts/generate_appcast.sh" "${APPCAST_ARGS[@]}"

echo "Packaged ${VERSION} build ${BUILD_NUMBER} channel ${BUILD_CHANNEL}"

echo "Artifacts created in: ${DIST_DIR}"
ls -lh "${DIST_DIR}/Suniye.dmg" "${DIST_DIR}/Suniye.app.zip" "${DIST_DIR}/SHA256SUMS.txt"
if [[ -f "${APPCAST_PATH}" ]]; then
  ls -lh "${APPCAST_PATH}"
fi
