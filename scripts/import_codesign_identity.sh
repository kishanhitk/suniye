#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-import}"
DEFAULT_IDENTITY="Suniye Self-Signed Release"

cleanup() {
  local keychain_path="${SUNIYE_CODESIGN_KEYCHAIN_PATH:-}"
  if [[ -z "${keychain_path}" ]]; then
    keychain_path="${RUNNER_TEMP:-/tmp}/suniye-codesign.keychain-db"
  fi

  if [[ -f "${keychain_path}" ]]; then
    security delete-keychain "${keychain_path}" >/dev/null 2>&1 || true
    echo "Deleted temporary codesign keychain: ${keychain_path}"
  fi
}

if [[ "${MODE}" == "cleanup" ]]; then
  cleanup
  exit 0
fi

if [[ "${MODE}" != "import" ]]; then
  echo "Usage: scripts/import_codesign_identity.sh [import|cleanup]" >&2
  exit 1
fi

: "${SUNIYE_CODESIGN_CERTIFICATE_P12_BASE64:?SUNIYE_CODESIGN_CERTIFICATE_P12_BASE64 is required}"
: "${SUNIYE_CODESIGN_CERTIFICATE_PASSWORD:?SUNIYE_CODESIGN_CERTIFICATE_PASSWORD is required}"

CODESIGN_IDENTITY="${SUNIYE_CODESIGN_IDENTITY:-${DEFAULT_IDENTITY}}"
KEYCHAIN_PATH="${RUNNER_TEMP:-/tmp}/suniye-codesign.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
CERT_PATH="$(mktemp "${RUNNER_TEMP:-/tmp}/suniye-codesign-cert.XXXXXX")"
trap 'rm -f "${CERT_PATH}"' EXIT

cleanup

if ! printf '%s' "${SUNIYE_CODESIGN_CERTIFICATE_P12_BASE64}" | base64 --decode > "${CERT_PATH}" 2>/dev/null; then
  printf '%s' "${SUNIYE_CODESIGN_CERTIFICATE_P12_BASE64}" | base64 -D > "${CERT_PATH}"
fi

security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security import "${CERT_PATH}" \
  -k "${KEYCHAIN_PATH}" \
  -P "${SUNIYE_CODESIGN_CERTIFICATE_PASSWORD}" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/xcodebuild

EXISTING_KEYCHAINS=()
while IFS= read -r existing_keychain; do
  if [[ -n "${existing_keychain}" ]]; then
    EXISTING_KEYCHAINS+=("${existing_keychain}")
  fi
done < <(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')
security list-keychains -d user -s "${KEYCHAIN_PATH}" "${EXISTING_KEYCHAINS[@]}"
security set-key-partition-list -S apple-tool:,apple: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"

if ! security find-identity -v -p codesigning "${KEYCHAIN_PATH}" | grep -F "\"${CODESIGN_IDENTITY}\"" >/dev/null; then
  echo "Imported keychain does not contain codesign identity: ${CODESIGN_IDENTITY}" >&2
  security find-identity -v -p codesigning "${KEYCHAIN_PATH}" >&2 || true
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "SUNIYE_CODESIGN_IDENTITY=${CODESIGN_IDENTITY}"
    echo "SUNIYE_CODESIGN_KEYCHAIN_PATH=${KEYCHAIN_PATH}"
  } >> "${GITHUB_ENV}"
fi

echo "Imported codesign identity into temporary keychain: ${CODESIGN_IDENTITY}"
