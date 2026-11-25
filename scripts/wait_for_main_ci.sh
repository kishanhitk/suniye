#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-}"
SHA=""
TIMEOUT_MINUTES=75
POLL_SECONDS=30

usage() {
  cat <<'USAGE'
Usage: scripts/wait_for_main_ci.sh --sha <commit> [--repo owner/name] [--timeout-minutes <n>] [--poll-seconds <n>]

Waits for the build-test job of the ci.yml push run on main for <commit>.
Exits 0 when that job passed, or was skipped after the changes job found no app changes.
Exits 1 when it failed, or when it did not pass before the timeout.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sha)
      SHA="$2"
      shift 2
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --timeout-minutes)
      TIMEOUT_MINUTES="$2"
      shift 2
      ;;
    --poll-seconds)
      POLL_SECONDS="$2"
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

if [[ -z "${SHA}" || -z "${REPO}" ]]; then
  usage >&2
  exit 1
fi

# Prints one word per ci.yml run for SHA: passed, failed or pending.
build_test_states() {
  local run_ids run_id
  run_ids="$(gh api "repos/${REPO}/actions/workflows/ci.yml/runs?head_sha=${SHA}&branch=main&event=push" \
    --jq '.workflow_runs[].id')" || return 1
  for run_id in ${run_ids}; do
    echo "Main CI run: https://github.com/${REPO}/actions/runs/${run_id}" >&2
    gh api "repos/${REPO}/actions/runs/${run_id}/jobs" --jq '
      [.jobs[] | select(.name == "build-test")] as $jobs
      | [.jobs[] | select(.name == "changes")] as $changes
      | if ($jobs | length) == 0 then "pending"
        elif $jobs[0].status != "completed" then "pending"
        elif $jobs[0].conclusion == "success" then "passed"
        elif $jobs[0].conclusion == "skipped" and $changes[0].conclusion == "success" then "passed"
        else "failed" end' || return 1
  done
}

DEADLINE=$(( $(date +%s) + TIMEOUT_MINUTES * 60 ))

while true; do
  if STATES="$(build_test_states)"; then
    case "${STATES}" in
      *passed*)
        echo "Main CI build-test passed for ${SHA}."
        exit 0
        ;;
      *pending*)
        echo "Main CI build-test for ${SHA} is still running."
        ;;
      *failed*)
        echo "Main CI build-test failed for ${SHA}. Fix main, then re-run this release." >&2
        exit 1
        ;;
      *)
        echo "No main CI run for ${SHA} yet."
        ;;
    esac
  else
    echo "GitHub API call failed."
  fi

  if (( $(date +%s) >= DEADLINE )); then
    echo "Main CI build-test did not pass for ${SHA} within ${TIMEOUT_MINUTES} min. Tag only a commit on main." >&2
    exit 1
  fi
  echo "Next check in ${POLL_SECONDS} s."
  sleep "${POLL_SECONDS}"
done
