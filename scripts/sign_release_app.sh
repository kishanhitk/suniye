#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/sign_release_app.sh <path-to-Suniye.app> <codesign-identity>

Signs Suniye's release bundle inside-out with one stable release identity.
USAGE
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 1
fi

APP_PATH="$1"
CODESIGN_IDENTITY="$2"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App bundle not found: ${APP_PATH}" >&2
  exit 1
fi

if [[ -z "${CODESIGN_IDENTITY}" ]]; then
  echo "A codesign identity is required for release signing." >&2
  exit 1
fi

codesign_cmd() {
  local preserve_metadata="$1"
  local target="$2"
  local args=(--force --sign "${CODESIGN_IDENTITY}" --timestamp=none)

  if [[ -n "${SUNIYE_CODESIGN_KEYCHAIN_PATH:-}" ]]; then
    args+=(--keychain "${SUNIYE_CODESIGN_KEYCHAIN_PATH}")
  fi

  if [[ "${preserve_metadata}" == "1" ]]; then
    args+=(--preserve-metadata=identifier,entitlements,flags)
  fi

  /usr/bin/codesign "${args[@]}" "${target}"
}

sign_if_exists() {
  local target="$1"
  if [[ -e "${target}" ]]; then
    echo "Signing nested code: ${target}"
    codesign_cmd 1 "${target}"
  fi
}

FRAMEWORKS_PATH="${APP_PATH}/Contents/Frameworks"
SPARKLE_FRAMEWORK_PATH="${FRAMEWORKS_PATH}/Sparkle.framework"

if [[ -d "${SPARKLE_FRAMEWORK_PATH}" ]]; then
  SPARKLE_FRAMEWORK_VERSION="$(readlink "${SPARKLE_FRAMEWORK_PATH}/Versions/Current" 2>/dev/null || true)"
  if [[ -z "${SPARKLE_FRAMEWORK_VERSION}" || "${SPARKLE_FRAMEWORK_VERSION}" == /* || "${SPARKLE_FRAMEWORK_VERSION}" == *".."* ]]; then
    SPARKLE_FRAMEWORK_VERSION="B"
  fi
  SPARKLE_VERSION_PATH="${SPARKLE_FRAMEWORK_PATH}/Versions/${SPARKLE_FRAMEWORK_VERSION}"

  if [[ -d "${SPARKLE_VERSION_PATH}/XPCServices" ]]; then
    while IFS= read -r -d '' xpc_path; do
      sign_if_exists "${xpc_path}"
    done < <(find "${SPARKLE_VERSION_PATH}/XPCServices" -maxdepth 1 -type d -name '*.xpc' -print0 | sort -z)
  fi

  sign_if_exists "${SPARKLE_VERSION_PATH}/Updater.app"
  sign_if_exists "${SPARKLE_VERSION_PATH}/Autoupdate"
fi

if [[ -d "${FRAMEWORKS_PATH}" ]]; then
  while IFS= read -r -d '' dylib_path; do
    sign_if_exists "${dylib_path}"
  done < <(find "${FRAMEWORKS_PATH}" -maxdepth 1 -type f -name '*.dylib' -print0 | sort -z)
fi

sign_if_exists "${SPARKLE_FRAMEWORK_PATH}"

echo "Signing app bundle: ${APP_PATH}"
codesign_cmd 0 "${APP_PATH}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
