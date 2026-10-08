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

echo "Gatekeeper: $(/usr/sbin/spctl --status 2>&1)"

# Gatekeeper reports "source=Notarized Developer ID" only when the artifact is
# Developer ID signed and Apple's notary service has issued a ticket for it.
assess_gatekeeper() {
  local label="$1"
  shift
  local output
  output="$(/usr/sbin/spctl --assess -vv "$@" 2>&1)" || true
  if ! grep -q 'source=Notarized Developer ID' <<<"${output}"; then
    echo "${label} is not accepted by Gatekeeper as notarized Developer ID:" >&2
    echo "${output}" >&2
    exit 1
  fi
  echo "${label}: ${output}"
}

verify_notarized_app() {
  local app_path="$1"
  local label="$2"
  /usr/bin/xcrun stapler validate "${app_path}"
  assess_gatekeeper "${label}" --type execute "${app_path}"
}

/usr/bin/xcrun stapler validate "${DMG_PATH}"
assess_gatekeeper "DMG" --type open --context context:primary-signature "${DMG_PATH}"

MOUNT_POINT="$(mktemp -d /tmp/suniye-dmg-XXXXXX)"
ZIP_EXTRACT_DIR="$(mktemp -d /tmp/suniye-zip-XXXXXX)"
/usr/bin/hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_POINT}" -nobrowse -readonly >/dev/null
trap '/usr/bin/hdiutil detach "${MOUNT_POINT}" -quiet >/dev/null 2>&1 || true; rm -rf "${MOUNT_POINT}" "${ZIP_EXTRACT_DIR}"' EXIT

[[ -d "${MOUNT_POINT}/Suniye.app" ]] || { echo "DMG missing Suniye.app" >&2; exit 1; }
[[ -L "${MOUNT_POINT}/Applications" ]] || { echo "DMG missing Applications symlink" >&2; exit 1; }

verify_app_build_channel() {
  local app_path="$1"
  local label="$2"

  [[ -z "${BUILD_CHANNEL}" ]] && return 0

  local app_build_channel
  app_build_channel="$(/usr/libexec/PlistBuddy -c "Print :SuniyeBuildChannel" "${app_path}/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "${app_build_channel}" != "${BUILD_CHANNEL}" ]]; then
    echo "${label} build channel ${app_build_channel:-<missing>} does not match ${BUILD_CHANNEL}" >&2
    exit 1
  fi
}

verify_app_build_channel "${MOUNT_POINT}/Suniye.app" "DMG app"
"${ROOT_DIR}/scripts/verify_release_signing.sh" "${MOUNT_POINT}/Suniye.app"
verify_notarized_app "${MOUNT_POINT}/Suniye.app" "DMG app"
SPARKLE_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "${MOUNT_POINT}/Suniye.app/Contents/Info.plist")"

/usr/bin/ditto -x -k "${ZIP_PATH}" "${ZIP_EXTRACT_DIR}"
[[ -d "${ZIP_EXTRACT_DIR}/Suniye.app" ]] || { echo "ZIP missing Suniye.app" >&2; exit 1; }
verify_app_build_channel "${ZIP_EXTRACT_DIR}/Suniye.app" "ZIP app"
"${ROOT_DIR}/scripts/verify_release_signing.sh" "${ZIP_EXTRACT_DIR}/Suniye.app"
verify_notarized_app "${ZIP_EXTRACT_DIR}/Suniye.app" "ZIP app"

APPCAST_ENCLOSURE="$(/usr/bin/python3 - "${APPCAST_PATH}" "${VERSION}" "${DOWNLOAD_URL_PREFIX}" "${APPCAST_CHANNEL}" <<'PY'
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

description = item.findtext("description")
release_notes_link = item.findtext("sparkle:releaseNotesLink", namespaces=namespace)
if not (description and description.strip()) and not (release_notes_link and release_notes_link.strip()):
    raise SystemExit("Appcast item is missing Sparkle release notes")

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

print(enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"], enclosure.attrib.get("length", ""))
PY
)"
read -r ENCLOSURE_SIGNATURE ENCLOSURE_LENGTH <<<"${APPCAST_ENCLOSURE}"

DMG_SIZE="$(/usr/bin/stat -f %z "${DMG_PATH}")"
if [[ "${ENCLOSURE_LENGTH}" != "${DMG_SIZE}" ]]; then
  echo "Appcast enclosure length ${ENCLOSURE_LENGTH:-<missing>} does not match Suniye.dmg size ${DMG_SIZE}" >&2
  exit 1
fi

# Existing installs reject the update unless this signature matches the final,
# stapled DMG under the public key they embed.
/usr/bin/xcrun swift "${ROOT_DIR}/scripts/verify_sparkle_signature.swift" "${DMG_PATH}" "${SPARKLE_PUBLIC_KEY}" "${ENCLOSURE_SIGNATURE}"

/usr/bin/hdiutil detach "${MOUNT_POINT}" -quiet >/dev/null
rm -rf "${MOUNT_POINT}"
trap - EXIT

if [[ -n "${VERSION}" ]]; then
  echo "Verified ${VERSION}"
fi

echo "Release artifacts verified successfully."
