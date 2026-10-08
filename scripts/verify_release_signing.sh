#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
EXPECTED_BUNDLE_ID="${2:-dev.suniye.app}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_ENTITLEMENTS_PATH="${ROOT_DIR}/Suniye/Suniye.entitlements"

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Usage: scripts/verify_release_signing.sh <path-to-Suniye.app> [bundle-id]" >&2
  exit 1
fi

fail() {
  echo "$1" >&2
  if [[ $# -gt 1 ]]; then
    echo "$2" >&2
  fi
  exit 1
}

SIGNING_DETAILS="$(/usr/bin/codesign -dvvv "${APP_PATH}" 2>&1 || true)"
REQUIREMENT_DETAILS="$(/usr/bin/codesign -d -r- "${APP_PATH}" 2>&1 || true)"

if ! grep -q '^Authority=Developer ID Application: ' <<<"${SIGNING_DETAILS}"; then
  fail "Release app must be signed with a Developer ID Application identity." "${SIGNING_DETAILS}"
fi

TEAM_ID="$(sed -n 's/^TeamIdentifier=//p' <<<"${SIGNING_DETAILS}")"
if [[ ! "${TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]]; then
  fail "Release app has no Team ID (got: ${TEAM_ID:-<missing>})." "${SIGNING_DETAILS}"
fi

if ! grep -q "identifier \"${EXPECTED_BUNDLE_ID}\"" <<<"${REQUIREMENT_DETAILS}"; then
  fail "Release app designated requirement must include identifier \"${EXPECTED_BUNDLE_ID}\"." "${REQUIREMENT_DETAILS}"
fi

if ! grep -q 'anchor apple generic' <<<"${REQUIREMENT_DETAILS}" \
  || ! grep -Eq "certificate leaf\[subject\.OU\] = \"?${TEAM_ID}\"?" <<<"${REQUIREMENT_DETAILS}"; then
  fail "Release app designated requirement must anchor to Apple and Team ID ${TEAM_ID}." "${REQUIREMENT_DETAILS}"
fi

ACTUAL_ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements - --xml "${APP_PATH}" 2>/dev/null | /usr/bin/plutil -convert json -o - - 2>/dev/null || true)"
EXPECTED_ENTITLEMENTS="$(/usr/bin/plutil -convert json -o - "${EXPECTED_ENTITLEMENTS_PATH}")"
if [[ "${ACTUAL_ENTITLEMENTS}" != "${EXPECTED_ENTITLEMENTS}" ]]; then
  fail "Release app entitlements must match ${EXPECTED_ENTITLEMENTS_PATH}." "expected: ${EXPECTED_ENTITLEMENTS}
actual:   ${ACTUAL_ENTITLEMENTS:-<none>}"
fi

LLAMA_SERVER_PATH="${APP_PATH}/Contents/Helpers/llama-server"
if [[ ! -x "${LLAMA_SERVER_PATH}" ]]; then
  fail "Release app is missing executable local LLM helper: ${LLAMA_SERVER_PATH}"
fi

LLAMA_SERVER_LINKS="$(/usr/bin/otool -L "${LLAMA_SERVER_PATH}" 2>&1 || true)"
if grep -E '/opt/homebrew|/usr/local' <<<"${LLAMA_SERVER_LINKS}" >/dev/null; then
  fail "llama-server must not depend on Homebrew/local dylibs in release artifacts." "${LLAMA_SERVER_LINKS}"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

# Notarization rejects any Mach-O that lacks the Developer ID signature, the
# hardened runtime, or a secure timestamp, so check every one of them here
# instead of waiting for Apple's verdict.
MACHO_COUNT=0
while IFS= read -r -d '' file_path; do
  if ! file -b "${file_path}" | grep -q 'Mach-O'; then
    continue
  fi
  MACHO_COUNT=$((MACHO_COUNT + 1))

  DETAILS="$(/usr/bin/codesign -dvvv "${file_path}" 2>&1 || true)"
  if [[ "$(sed -n 's/^TeamIdentifier=//p' <<<"${DETAILS}")" != "${TEAM_ID}" ]]; then
    fail "Nested code is not signed by Team ID ${TEAM_ID}: ${file_path}" "${DETAILS}"
  fi
  if ! grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime[^)]*\)' <<<"${DETAILS}"; then
    fail "Nested code lacks the hardened runtime: ${file_path}" "${DETAILS}"
  fi
  if ! grep -q '^Timestamp=' <<<"${DETAILS}"; then
    fail "Nested code lacks a secure timestamp: ${file_path}" "${DETAILS}"
  fi
  if /usr/bin/codesign -d --entitlements - --xml "${file_path}" 2>/dev/null | grep -q 'com.apple.security.get-task-allow'; then
    fail "Nested code must not include com.apple.security.get-task-allow: ${file_path}"
  fi
done < <(find "${APP_PATH}/Contents" -type f -print0)

if [[ "${MACHO_COUNT}" -eq 0 ]]; then
  fail "Found no Mach-O files to verify in ${APP_PATH}."
fi

echo "Release signing checks passed for ${MACHO_COUNT} Mach-O files in: ${APP_PATH}"
