#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/notarize_artifact.sh <path-to-zip-or-dmg>

Submits one artifact to Apple's notary service, waits for the verdict, and
prints the notary log when Apple rejects it. Stapling is the caller's job.

Authentication (one of):
  SUNIYE_NOTARY_KEYCHAIN_PROFILE   notarytool keychain profile (local releases)
  SUNIYE_NOTARY_API_KEY_P8         App Store Connect API key (.p8 contents, CI)
  SUNIYE_NOTARY_API_KEY_ID         API key ID
  SUNIYE_NOTARY_API_ISSUER_ID      API key issuer ID
USAGE
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

ARTIFACT_PATH="$1"
if [[ ! -f "${ARTIFACT_PATH}" ]]; then
  echo "Artifact not found: ${ARTIFACT_PATH}" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/suniye-notary.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT

if [[ -n "${SUNIYE_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  AUTH_ARGS=(--keychain-profile "${SUNIYE_NOTARY_KEYCHAIN_PROFILE}")
elif [[ -n "${SUNIYE_NOTARY_API_KEY_P8:-}" ]]; then
  : "${SUNIYE_NOTARY_API_KEY_ID:?SUNIYE_NOTARY_API_KEY_ID is required with SUNIYE_NOTARY_API_KEY_P8}"
  : "${SUNIYE_NOTARY_API_ISSUER_ID:?SUNIYE_NOTARY_API_ISSUER_ID is required with SUNIYE_NOTARY_API_KEY_P8}"
  KEY_PATH="${WORK_DIR}/AuthKey_${SUNIYE_NOTARY_API_KEY_ID}.p8"
  (umask 077 && printf '%s\n' "${SUNIYE_NOTARY_API_KEY_P8}" > "${KEY_PATH}")
  AUTH_ARGS=(--key "${KEY_PATH}" --key-id "${SUNIYE_NOTARY_API_KEY_ID}" --issuer "${SUNIYE_NOTARY_API_ISSUER_ID}")
else
  echo "Notarization credentials are missing." >&2
  usage >&2
  exit 1
fi

RESULT_PATH="${WORK_DIR}/submit.json"
echo "Submitting for notarization: ${ARTIFACT_PATH}"
SUBMIT_STATUS=0
/usr/bin/xcrun notarytool submit "${ARTIFACT_PATH}" \
  "${AUTH_ARGS[@]}" \
  --wait \
  --timeout 45m \
  --output-format json > "${RESULT_PATH}" || SUBMIT_STATUS=$?

SUBMISSION_ID="$(/usr/bin/plutil -extract id raw -o - "${RESULT_PATH}" 2>/dev/null || true)"
VERDICT="$(/usr/bin/plutil -extract status raw -o - "${RESULT_PATH}" 2>/dev/null || true)"
echo "Notary submission ${SUBMISSION_ID:-<none>}: ${VERDICT:-<no verdict>}"

if [[ "${SUBMIT_STATUS}" -ne 0 || "${VERDICT}" != "Accepted" ]]; then
  cat "${RESULT_PATH}" >&2 || true
  if [[ -n "${SUBMISSION_ID}" ]]; then
    /usr/bin/xcrun notarytool log "${SUBMISSION_ID}" "${AUTH_ARGS[@]}" >&2 || true
  fi
  echo "Notarization failed for ${ARTIFACT_PATH}" >&2
  exit 1
fi
