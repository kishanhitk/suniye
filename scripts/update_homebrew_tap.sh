#!/usr/bin/env bash
set -euo pipefail

# Render the Suniye Homebrew Cask from packaging/homebrew/suniye.rb.tmpl and push
# it to the custom tap (default: kishanhitk/homebrew-tap) as Casks/suniye.rb.
#
# Designed to run as a release step after the GitHub release is published, and to
# be runnable locally (use --no-push to render to stdout without cloning).
#
# The DMG sha256 is read from <dist-dir>/SHA256SUMS.txt unless --sha256 is given.
# If HOMEBREW_TAP_TOKEN is empty the script prints a warning and exits 0, so a
# release never fails just because the tap secret has not been configured yet.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""
DIST_DIR="${ROOT_DIR}/dist"
SHA256_OVERRIDE=""
TAP_REPO="kishanhitk/homebrew-tap"
TEMPLATE="${ROOT_DIR}/packaging/homebrew/suniye.rb.tmpl"
CASK_PATH="Casks/suniye.rb"
PUSH="true"

usage() {
  cat <<'USAGE'
Usage: scripts/update_homebrew_tap.sh --version vX.Y.Z [options]

  --version vX.Y.Z      Release tag (leading "v" is stripped for the cask version). Required.
  --dist-dir <dir>      Directory containing SHA256SUMS.txt (default: ./dist).
  --sha256 <hex>        DMG sha256 override (default: read Suniye.dmg from SHA256SUMS.txt).
  --tap-repo <o/r>      Tap repository (default: kishanhitk/homebrew-tap).
  --template <path>     Cask template (default: packaging/homebrew/suniye.rb.tmpl).
  --cask-path <path>    Destination path inside the tap (default: Casks/suniye.rb).
  --no-push             Render the cask to stdout and exit; do not clone or push.
  -h, --help            Show this help.

Environment:
  HOMEBREW_TAP_TOKEN    Token with push access to the tap repo (required unless --no-push).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --dist-dir) DIST_DIR="$2"; shift 2 ;;
    --sha256) SHA256_OVERRIDE="$2"; shift 2 ;;
    --tap-repo) TAP_REPO="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --cask-path) CASK_PATH="$2"; shift 2 ;;
    --no-push) PUSH="false"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "${VERSION}" ]]; then
  echo "--version is required." >&2
  usage >&2
  exit 1
fi

# Strip a single leading "v" so the cask version is bare (e.g. v0.0.41 -> 0.0.41).
CASK_VERSION="${VERSION#v}"
if [[ ! "${CASK_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Version does not look like a release version: ${VERSION}" >&2
  exit 1
fi

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Cask template not found: ${TEMPLATE}" >&2
  exit 1
fi

# Resolve the DMG sha256.
if [[ -n "${SHA256_OVERRIDE}" ]]; then
  DMG_SHA256="${SHA256_OVERRIDE}"
else
  SUMS_FILE="${DIST_DIR}/SHA256SUMS.txt"
  if [[ ! -f "${SUMS_FILE}" ]]; then
    echo "Checksums file not found: ${SUMS_FILE} (pass --sha256 to override)." >&2
    exit 1
  fi
  DMG_SHA256="$(awk '$2 == "Suniye.dmg" { print $1 }' "${SUMS_FILE}")"
fi

if [[ ! "${DMG_SHA256}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not resolve a valid Suniye.dmg sha256 (got: '${DMG_SHA256}')." >&2
  exit 1
fi

# Render the cask. Both substituted values are constrained above, so they are
# safe to use directly in a sed replacement.
render_cask() {
  sed -e "s/__VERSION__/${CASK_VERSION}/g" -e "s/__SHA256__/${DMG_SHA256}/g" "${TEMPLATE}"
}

if [[ "${PUSH}" != "true" ]]; then
  render_cask
  exit 0
fi

if [[ -z "${HOMEBREW_TAP_TOKEN:-}" ]]; then
  echo "HOMEBREW_TAP_TOKEN is not set; skipping Homebrew tap update for ${CASK_VERSION}." >&2
  echo "Configure the secret to enable automatic cask bumps (see docs/INSTALL.md)." >&2
  exit 0
fi

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

# Keep the token out of logs.
CLONE_URL="https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP_REPO}.git"
if ! git clone --depth 1 --quiet "${CLONE_URL}" "${WORK_DIR}/tap" 2>/dev/null; then
  echo "Failed to clone tap repository ${TAP_REPO}. Does it exist and does the token grant access?" >&2
  exit 1
fi

DEST="${WORK_DIR}/tap/${CASK_PATH}"
mkdir -p "$(dirname "${DEST}")"
render_cask > "${DEST}"

git -C "${WORK_DIR}/tap" add "${CASK_PATH}"
if git -C "${WORK_DIR}/tap" diff --cached --quiet; then
  echo "Cask already up to date at ${CASK_VERSION}; nothing to push."
  exit 0
fi

git -C "${WORK_DIR}/tap" \
  -c user.name="github-actions[bot]" \
  -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit --quiet -m "suniye ${CASK_VERSION}"
git -C "${WORK_DIR}/tap" push --quiet origin HEAD

echo "Pushed suniye ${CASK_VERSION} (sha256 ${DMG_SHA256}) to ${TAP_REPO}/${CASK_PATH}."
