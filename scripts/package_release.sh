#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
VERSION=""
BUILD_NUMBER=""

usage() {
  cat <<'USAGE'
Usage: scripts/package_release.sh [--version vX.Y.Z] [--build-number <number>] [--dist-dir <dir>]
USAGE
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
    --dist-dir)
      DIST_DIR="$2"
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

if [[ -z "${BUILD_NUMBER}" ]]; then
  BUILD_NUMBER="${GITHUB_RUN_NUMBER:-}"
fi

mkdir -p "${DIST_DIR}"
DERIVED_DATA="${ROOT_DIR}/.derivedData-release"

BUILD_ARGS=(Release --derived-data-path "${DERIVED_DATA}" --output-dir "${DIST_DIR}")
if [[ -n "${VERSION}" ]]; then
  BUILD_ARGS+=(--version "${VERSION}")
fi
if [[ -n "${BUILD_NUMBER}" ]]; then
  BUILD_ARGS+=(--build-number "${BUILD_NUMBER}")
fi
"${ROOT_DIR}/scripts/build_app.sh" "${BUILD_ARGS[@]}"

APP_PATH="${DIST_DIR}/Suniye.app"
ZIP_PATH="${DIST_DIR}/Suniye.app.zip"
DMG_PATH="${DIST_DIR}/Suniye.dmg"
CHECKSUMS_PATH="${DIST_DIR}/SHA256SUMS.txt"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected app not found at ${APP_PATH}" >&2
  exit 1
fi

rm -f "${ZIP_PATH}" "${DMG_PATH}" "${CHECKSUMS_PATH}"

# Create zip artifact
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

# Create DMG with app + Applications link
DMG_STAGING="${ROOT_DIR}/.dmg-staging"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_PATH}" "${DMG_STAGING}/Suniye.app"
ln -s /Applications "${DMG_STAGING}/Applications"

/usr/bin/hdiutil create -volname "Suniye" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_PATH}" >/dev/null
rm -rf "${DMG_STAGING}"

(
  cd "${DIST_DIR}"
  shasum -a 256 "Suniye.dmg" "Suniye.app.zip" > "SHA256SUMS.txt"
)

if [[ -n "${VERSION}" ]]; then
  echo "Packaged ${VERSION}"
fi

echo "Artifacts created in: ${DIST_DIR}"
ls -lh "${DIST_DIR}/Suniye.dmg" "${DIST_DIR}/Suniye.app.zip" "${DIST_DIR}/SHA256SUMS.txt"
