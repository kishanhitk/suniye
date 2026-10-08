#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/sign_release_app.sh <path-to-Suniye.app> <codesign-identity>

Signs Suniye's release bundle inside-out with the Developer ID identity, the
hardened runtime, and a secure timestamp, as notarization requires.
USAGE
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$1"
CODESIGN_IDENTITY="$2"
APP_ENTITLEMENTS_PATH="${ROOT_DIR}/Suniye/Suniye.entitlements"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App bundle not found: ${APP_PATH}" >&2
  exit 1
fi

if [[ -z "${CODESIGN_IDENTITY}" ]]; then
  echo "A codesign identity is required for release signing." >&2
  exit 1
fi

if [[ ! -f "${APP_ENTITLEMENTS_PATH}" ]]; then
  echo "App entitlements not found: ${APP_ENTITLEMENTS_PATH}" >&2
  exit 1
fi

codesign_cmd() {
  local target="$1"
  shift
  local args=(--force --sign "${CODESIGN_IDENTITY}" --timestamp --options runtime "$@")

  if [[ -n "${SUNIYE_CODESIGN_KEYCHAIN_PATH:-}" ]]; then
    args+=(--keychain "${SUNIYE_CODESIGN_KEYCHAIN_PATH}")
  fi

  echo "Signing: ${target}"
  /usr/bin/codesign "${args[@]}" "${target}"
}

sign_nested_if_exists() {
  local target="$1"
  shift
  if [[ -e "${target}" ]]; then
    codesign_cmd "${target}" --preserve-metadata=identifier "$@"
  fi
}

FRAMEWORKS_PATH="${APP_PATH}/Contents/Frameworks"
HELPERS_PATH="${APP_PATH}/Contents/Helpers"
SPARKLE_FRAMEWORK_PATH="${FRAMEWORKS_PATH}/Sparkle.framework"

if [[ -d "${HELPERS_PATH}" ]]; then
  while IFS= read -r -d '' helper_path; do
    sign_nested_if_exists "${helper_path}"
  done < <(find "${HELPERS_PATH}" -maxdepth 1 -type f -perm -111 -print0 | sort -z)
fi

if [[ -d "${SPARKLE_FRAMEWORK_PATH}" ]]; then
  SPARKLE_FRAMEWORK_VERSION="$(readlink "${SPARKLE_FRAMEWORK_PATH}/Versions/Current" 2>/dev/null || true)"
  if [[ -z "${SPARKLE_FRAMEWORK_VERSION}" || "${SPARKLE_FRAMEWORK_VERSION}" == /* || "${SPARKLE_FRAMEWORK_VERSION}" == *".."* ]]; then
    SPARKLE_FRAMEWORK_VERSION="B"
  fi
  SPARKLE_VERSION_PATH="${SPARKLE_FRAMEWORK_PATH}/Versions/${SPARKLE_FRAMEWORK_VERSION}"

  # Sparkle's Developer ID recipe: only Downloader.xpc keeps its entitlements.
  # The prebuilt Autoupdate carries com.apple.application-identifier, a
  # restricted entitlement that a Developer ID signature must not keep.
  sign_nested_if_exists "${SPARKLE_VERSION_PATH}/XPCServices/Installer.xpc"
  sign_nested_if_exists "${SPARKLE_VERSION_PATH}/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
  sign_nested_if_exists "${SPARKLE_VERSION_PATH}/Autoupdate"
  sign_nested_if_exists "${SPARKLE_VERSION_PATH}/Updater.app"
fi

if [[ -d "${FRAMEWORKS_PATH}" ]]; then
  while IFS= read -r -d '' dylib_path; do
    sign_nested_if_exists "${dylib_path}"
  done < <(find "${FRAMEWORKS_PATH}" -maxdepth 1 -type f -name '*.dylib' -print0 | sort -z)
fi

sign_nested_if_exists "${SPARKLE_FRAMEWORK_PATH}"

codesign_cmd "${APP_PATH}" --entitlements "${APP_ENTITLEMENTS_PATH}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
