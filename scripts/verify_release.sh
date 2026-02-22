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

DMG_PATH="${DIST_DIR}/VibeStoke.dmg"
ZIP_PATH="${DIST_DIR}/VibeStoke.app.zip"
CHECKSUMS_PATH="${DIST_DIR}/SHA256SUMS.txt"

for f in "${DMG_PATH}" "${ZIP_PATH}" "${CHECKSUMS_PATH}"; do
  [[ -f "${f}" ]] || { echo "Missing artifact: ${f}" >&2; exit 1; }
done

(
  cd "${DIST_DIR}"
  shasum -a 256 -c SHA256SUMS.txt
)

MOUNT_POINT="$(mktemp -d /tmp/vibestroke-dmg-XXXXXX)"
/usr/bin/hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_POINT}" -nobrowse -readonly >/dev/null
trap '/usr/bin/hdiutil detach "${MOUNT_POINT}" -quiet >/dev/null 2>&1 || true; rm -rf "${MOUNT_POINT}"' EXIT

[[ -d "${MOUNT_POINT}/VibeStoke.app" ]] || { echo "DMG missing VibeStoke.app" >&2; exit 1; }
[[ -L "${MOUNT_POINT}/Applications" ]] || { echo "DMG missing Applications symlink" >&2; exit 1; }

/usr/bin/hdiutil detach "${MOUNT_POINT}" -quiet >/dev/null
rm -rf "${MOUNT_POINT}"
trap - EXIT

if [[ -n "${VERSION}" ]]; then
  echo "Verified ${VERSION}"
fi

echo "Release artifacts verified successfully."
