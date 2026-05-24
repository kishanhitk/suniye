#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
VERSION=""
DOWNLOAD_URL_PREFIX=""
APPCAST_CHANNEL=""
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-suniye}"
PRIVATE_KEY_FILE=""
CREATED_PRIVATE_KEY_FILE=0

usage() {
  cat <<'USAGE'
Usage: scripts/generate_appcast.sh --version vX.Y.Z [--dist-dir <dir>] [--download-url-prefix <url>] [--channel <name>] [--private-key-file <path>]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --dist-dir)
      DIST_DIR="$2"
      shift 2
      ;;
    --download-url-prefix)
      DOWNLOAD_URL_PREFIX="$2"
      shift 2
      ;;
    --channel)
      APPCAST_CHANNEL="$2"
      shift 2
      ;;
    --private-key-file)
      PRIVATE_KEY_FILE="$2"
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
  echo "--version is required" >&2
  usage >&2
  exit 1
fi

if [[ -n "${APPCAST_CHANNEL}" && ! "${APPCAST_CHANNEL}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Appcast channel may only contain letters, numbers, dots, underscores, and dashes: ${APPCAST_CHANNEL}" >&2
  exit 1
fi

if [[ -z "${DOWNLOAD_URL_PREFIX}" ]]; then
  DOWNLOAD_URL_PREFIX="https://github.com/kishanhitk/suniye/releases/download/${VERSION}/"
else
  DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX%/}/"
fi

DMG_PATH="${DIST_DIR}/Suniye.dmg"
APPCAST_PATH="${DIST_DIR}/appcast.xml"

[[ -f "${DMG_PATH}" ]] || { echo "Missing artifact: ${DMG_PATH}" >&2; exit 1; }

SPARKLE_TOOL_ROOTS=(
  "${ROOT_DIR}/.derivedData-release/SourcePackages/artifacts/sparkle/Sparkle/bin"
  "${ROOT_DIR}/.derivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
  "${HOME}/Library/Developer/Xcode/DerivedData"
)

GENERATE_APPCAST=""
for root in "${SPARKLE_TOOL_ROOTS[@]}"; do
  if [[ -x "${root}/generate_appcast" ]]; then
    GENERATE_APPCAST="${root}/generate_appcast"
    break
  fi
done

if [[ -z "${GENERATE_APPCAST}" ]]; then
  GENERATE_APPCAST="$(find "${HOME}/Library/Developer/Xcode/DerivedData" "${ROOT_DIR}" -path '*/artifacts/sparkle/Sparkle/bin/generate_appcast' -type f -perm -111 2>/dev/null | head -1 || true)"
fi

if [[ -z "${GENERATE_APPCAST}" ]]; then
  echo "Unable to find Sparkle generate_appcast. Build the app once so SwiftPM resolves Sparkle." >&2
  exit 1
fi

if [[ -z "${PRIVATE_KEY_FILE}" ]]; then
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    PRIVATE_KEY_FILE="$(mktemp)"
    CREATED_PRIVATE_KEY_FILE=1
    printf '%s' "${SPARKLE_PRIVATE_KEY}" > "${PRIVATE_KEY_FILE}"
  else
    PRIVATE_KEY_FILE="keychain:${SPARKLE_ACCOUNT}"
  fi
fi

rm -f "${APPCAST_PATH}"
APPCAST_WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${APPCAST_WORK_DIR}"
  if [[ "${CREATED_PRIVATE_KEY_FILE}" == "1" ]]; then
    rm -f "${PRIVATE_KEY_FILE}"
  fi
}
trap cleanup EXIT
cp "${DMG_PATH}" "${APPCAST_WORK_DIR}/Suniye.dmg"

generate_args=(
  --download-url-prefix "${DOWNLOAD_URL_PREFIX}"
  --maximum-versions 1
  -o "${APPCAST_PATH}"
)

if [[ -n "${APPCAST_CHANNEL}" ]]; then
  generate_args+=(--channel "${APPCAST_CHANNEL}")
fi

if [[ "${PRIVATE_KEY_FILE}" == keychain:* ]]; then
  "${GENERATE_APPCAST}" \
    --account "${SPARKLE_ACCOUNT}" \
    "${generate_args[@]}" \
    "${APPCAST_WORK_DIR}"
else
  "${GENERATE_APPCAST}" \
    --ed-key-file "${PRIVATE_KEY_FILE}" \
    "${generate_args[@]}" \
    "${APPCAST_WORK_DIR}"
fi

[[ -f "${APPCAST_PATH}" ]] || { echo "Sparkle appcast was not created." >&2; exit 1; }
echo "Generated Sparkle appcast: ${APPCAST_PATH}"
