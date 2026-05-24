#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
VERSION=""
BUILD_NUMBER=""

usage() {
  cat <<'USAGE'
Usage: scripts/package_release.sh --version vX.Y.Z [--build-number <number>] [--dist-dir <dir>]
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

if [[ -z "${VERSION}" ]]; then
  echo "--version is required so release artifacts and appcast.xml describe the same version." >&2
  usage >&2
  exit 1
fi

if [[ -z "${BUILD_NUMBER}" ]]; then
  BUILD_NUMBER="${SUNIYE_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
fi

if [[ -z "${BUILD_NUMBER}" ]]; then
  echo "Build number is required. Pass --build-number, set SUNIYE_BUILD_NUMBER, or run in GitHub Actions with GITHUB_RUN_NUMBER." >&2
  exit 1
fi

if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "Build number must be numeric, got: ${BUILD_NUMBER}" >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"
DERIVED_DATA="${ROOT_DIR}/.derivedData-release"

BUILD_ARGS=(Release --derived-data-path "${DERIVED_DATA}" --output-dir "${DIST_DIR}")
BUILD_ARGS+=(--version "${VERSION}")
BUILD_ARGS+=(--build-number "${BUILD_NUMBER}")
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

rm -f "${ZIP_PATH}" "${DMG_PATH}" "${CHECKSUMS_PATH}" "${APPCAST_PATH}"

# Create zip artifact
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

# Create DMG with app + Applications link
DMG_STAGING="${ROOT_DIR}/.dmg-staging"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
/usr/bin/ditto "${APP_PATH}" "${DMG_STAGING}/Suniye.app"
ln -s /Applications "${DMG_STAGING}/Applications"

/usr/bin/hdiutil create -volname "Suniye" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_PATH}" >/dev/null
rm -rf "${DMG_STAGING}"

(
  cd "${DIST_DIR}"
  shasum -a 256 "Suniye.dmg" "Suniye.app.zip" > "SHA256SUMS.txt"
)

"${ROOT_DIR}/scripts/generate_appcast.sh" --version "${VERSION}" --dist-dir "${DIST_DIR}"

echo "Packaged ${VERSION}"

echo "Artifacts created in: ${DIST_DIR}"
ls -lh "${DIST_DIR}/Suniye.dmg" "${DIST_DIR}/Suniye.app.zip" "${DIST_DIR}/SHA256SUMS.txt"
if [[ -f "${APPCAST_PATH}" ]]; then
  ls -lh "${APPCAST_PATH}"
fi
