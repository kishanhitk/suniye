#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH=""
DMG_PATH=""

usage() {
  cat <<'USAGE'
Usage: scripts/create_dmg.sh --app <path/to/Suniye.app> --output <path/to/Suniye.dmg>

Creates an unsigned DMG with the app, an Applications link, and the Finder
window layout in packaging/dmg/dmgbuild_settings.py.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --output)
      DMG_PATH="$2"
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

if [[ -z "${APP_PATH}" || -z "${DMG_PATH}" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App not found: ${APP_PATH}" >&2
  exit 1
fi

if [[ "${DMG_PATH}" != *.dmg ]]; then
  echo "Output must be a .dmg path: ${DMG_PATH}" >&2
  exit 1
fi

if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
  echo "dmgbuild needs Python 3.10 or later, found: $(python3 --version 2>&1)" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# dmgbuild writes the window layout straight into the volume's .DS_Store. It
# does not script Finder, so the DMG comes out the same on CI as on a desktop.
python3 -m venv "${WORK_DIR}/venv"
"${WORK_DIR}/venv/bin/python" -m pip install \
  --quiet \
  --disable-pip-version-check \
  --only-binary :all: \
  --require-hashes \
  -r "${ROOT_DIR}/packaging/dmg/requirements.txt"

/usr/bin/xcrun swift "${ROOT_DIR}/scripts/render_dmg_background.swift" "${WORK_DIR}/background" >/dev/null

"${WORK_DIR}/venv/bin/dmgbuild" \
  -s "${ROOT_DIR}/packaging/dmg/dmgbuild_settings.py" \
  -D app="${APP_PATH}" \
  -D background="${WORK_DIR}/background/background.png" \
  "Suniye" \
  "${DMG_PATH}"

echo "Created ${DMG_PATH}"
