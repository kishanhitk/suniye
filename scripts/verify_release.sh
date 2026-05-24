#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
VERSION=""
DOWNLOAD_URL_PREFIX=""
APPCAST_CHANNEL=""
BUILD_CHANNEL=""

usage() {
  cat <<'USAGE'
Usage: scripts/verify_release.sh [--version vX.Y.Z] [--download-url-prefix <url>] [--channel <name>] [--build-channel stable|tip] [--dist-dir <dir>]
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
    --build-channel)
      BUILD_CHANNEL="$2"
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

case "${BUILD_CHANNEL}" in
  ""|stable|tip)
    ;;
  *)
    echo "Unknown build channel: ${BUILD_CHANNEL}" >&2
    exit 1
    ;;
esac

if [[ -n "${APPCAST_CHANNEL}" && ! "${APPCAST_CHANNEL}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Appcast channel may only contain letters, numbers, dots, underscores, and dashes: ${APPCAST_CHANNEL}" >&2
  exit 1
fi

if [[ -n "${DOWNLOAD_URL_PREFIX}" ]]; then
  DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX%/}/"
fi

DMG_PATH="${DIST_DIR}/Suniye.dmg"
ZIP_PATH="${DIST_DIR}/Suniye.app.zip"
CHECKSUMS_PATH="${DIST_DIR}/SHA256SUMS.txt"
APPCAST_PATH="${DIST_DIR}/appcast.xml"

for f in "${DMG_PATH}" "${ZIP_PATH}" "${CHECKSUMS_PATH}" "${APPCAST_PATH}"; do
  [[ -f "${f}" ]] || { echo "Missing artifact: ${f}" >&2; exit 1; }
done

(
  cd "${DIST_DIR}"
  shasum -a 256 -c SHA256SUMS.txt
)

MOUNT_POINT="$(mktemp -d /tmp/suniye-dmg-XXXXXX)"
/usr/bin/hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_POINT}" -nobrowse -readonly >/dev/null
trap '/usr/bin/hdiutil detach "${MOUNT_POINT}" -quiet >/dev/null 2>&1 || true; rm -rf "${MOUNT_POINT}"' EXIT

[[ -d "${MOUNT_POINT}/Suniye.app" ]] || { echo "DMG missing Suniye.app" >&2; exit 1; }
[[ -L "${MOUNT_POINT}/Applications" ]] || { echo "DMG missing Applications symlink" >&2; exit 1; }

if [[ -n "${BUILD_CHANNEL}" ]]; then
  APP_BUILD_CHANNEL="$(/usr/libexec/PlistBuddy -c "Print :SuniyeBuildChannel" "${MOUNT_POINT}/Suniye.app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "${APP_BUILD_CHANNEL}" != "${BUILD_CHANNEL}" ]]; then
    echo "App build channel ${APP_BUILD_CHANNEL:-<missing>} does not match ${BUILD_CHANNEL}" >&2
    exit 1
  fi
fi

/usr/bin/python3 - "${APPCAST_PATH}" "${VERSION}" "${DOWNLOAD_URL_PREFIX}" "${APPCAST_CHANNEL}" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
version = sys.argv[2]
download_url_prefix = sys.argv[3]
expected_channel = sys.argv[4]
root = ET.parse(path).getroot()

namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
items = root.findall("./channel/item")
if not items:
    raise SystemExit("Appcast has no update items")

item = items[0]
enclosure = item.find("enclosure")
if enclosure is None:
    raise SystemExit("Appcast item is missing enclosure")

if not enclosure.attrib.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"):
    raise SystemExit("Appcast enclosure is missing Sparkle EdDSA signature")

actual_channel = item.findtext("sparkle:channel", namespaces=namespace)
if expected_channel:
    if actual_channel != expected_channel:
        raise SystemExit(f"Appcast channel {actual_channel!r} does not match {expected_channel!r}")
elif actual_channel not in (None, ""):
    raise SystemExit(f"Stable appcast should not include a Sparkle channel, got {actual_channel!r}")

if version:
    if download_url_prefix:
        expected_url = f"{download_url_prefix}Suniye.dmg"
    else:
        expected_url = f"https://github.com/kishanhitk/suniye/releases/download/{version}/Suniye.dmg"
    enclosure_url = enclosure.attrib.get("url", "")
    if enclosure_url != expected_url:
        raise SystemExit(f"Appcast enclosure URL {enclosure_url!r} does not match {expected_url!r}")

    short_version = item.findtext("sparkle:shortVersionString", namespaces=namespace)
    normalized = version[1:] if version.startswith("v") else version
    if short_version != normalized:
        raise SystemExit(f"Appcast short version {short_version!r} does not match {normalized!r}")
elif not enclosure.attrib.get("url", "").endswith("/Suniye.dmg"):
    raise SystemExit("Appcast enclosure does not point to Suniye.dmg")
PY

/usr/bin/hdiutil detach "${MOUNT_POINT}" -quiet >/dev/null
rm -rf "${MOUNT_POINT}"
trap - EXIT

if [[ -n "${VERSION}" ]]; then
  echo "Verified ${VERSION}"
fi

echo "Release artifacts verified successfully."
