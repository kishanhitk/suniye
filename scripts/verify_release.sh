#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
VERSION=""

usage() {
  cat <<'USAGE'
Usage: scripts/verify_release.sh [--version vX.Y.Z] [--dist-dir <dir>]
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

/usr/bin/python3 - "${APPCAST_PATH}" "${VERSION}" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
version = sys.argv[2]
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

if version:
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
