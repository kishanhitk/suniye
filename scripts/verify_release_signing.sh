#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
EXPECTED_BUNDLE_ID="${2:-dev.suniye.app}"

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Usage: scripts/verify_release_signing.sh <path-to-Suniye.app> [bundle-id]" >&2
  exit 1
fi

SIGNING_DETAILS="$(/usr/bin/codesign -dvvv --entitlements :- "${APP_PATH}" 2>&1 || true)"
REQUIREMENT_DETAILS="$(/usr/bin/codesign -d -r- "${APP_PATH}" 2>&1 || true)"

if grep -q '^Signature=adhoc$' <<<"${SIGNING_DETAILS}"; then
  echo "Release app must not be ad hoc signed." >&2
  exit 1
fi

if ! grep -q "identifier \"${EXPECTED_BUNDLE_ID}\"" <<<"${REQUIREMENT_DETAILS}"; then
  echo "Release app designated requirement must include identifier \"${EXPECTED_BUNDLE_ID}\"." >&2
  echo "${REQUIREMENT_DETAILS}" >&2
  exit 1
fi

if grep -q 'designated => cdhash' <<<"${REQUIREMENT_DETAILS}"; then
  echo "Release app designated requirement must not be cdhash-only." >&2
  echo "${REQUIREMENT_DETAILS}" >&2
  exit 1
fi

if ! grep -q 'certificate ' <<<"${REQUIREMENT_DETAILS}"; then
  echo "Release app designated requirement must include a certificate condition." >&2
  echo "${REQUIREMENT_DETAILS}" >&2
  exit 1
fi

if grep -q 'com.apple.security.get-task-allow' <<<"${SIGNING_DETAILS}"; then
  echo "Release app must not include com.apple.security.get-task-allow." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

while IFS= read -r -d '' executable_path; do
  if file -b "${executable_path}" | grep -q 'Mach-O'; then
    EXEC_SIGNING_DETAILS="$(/usr/bin/codesign -dvv "${executable_path}" 2>&1 || true)"
    if grep -q '^Signature=adhoc$' <<<"${EXEC_SIGNING_DETAILS}"; then
      echo "Nested executable is ad hoc signed: ${executable_path}" >&2
      exit 1
    fi
  fi
done < <(find "${APP_PATH}/Contents" -type f -perm -111 -print0)

SPCTL_OUTPUT="$(/usr/sbin/spctl -a -vv "${APP_PATH}" 2>&1)" && SPCTL_STATUS=0 || SPCTL_STATUS=$?
if [[ "${SPCTL_STATUS}" -eq 0 ]]; then
  echo "spctl accepted release app:"
  echo "${SPCTL_OUTPUT}"
else
  echo "spctl informational result for self-signed release app:"
  echo "${SPCTL_OUTPUT}"
fi

echo "Release signing checks passed for: ${APP_PATH}"
