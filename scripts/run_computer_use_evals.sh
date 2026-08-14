#!/bin/zsh
# Runs the scored Computer Use task evals against the real agent, model, and
# machine. Text-in (post-ASR handoff); results land in evals/runs/cu_eval_*.json.
#
# Requirements: a GUI session, Accessibility + Screen Recording granted to the
# test host, and a model key (SUNIYE_CU_EVAL_API_KEY or the app's stored key).
# Mutating tasks reset after themselves, but prefer a dedicated test user for
# full sweeps. This is a measurement, not a CI gate — never wire it into CI.
#
# Optional environment:
#   SUNIYE_CU_EVAL_ENDPOINT  chat-completions URL (default: OpenRouter)
#   SUNIYE_CU_EVAL_MODEL     model id (default: openai/gpt-5.6-luna)
#   SUNIYE_CU_EVAL_API_KEY   key override

set -euo pipefail
cd "$(dirname "$0")/.."

# xcodebuild forwards environment to the test process only through the
# TEST_RUNNER_ prefix (stripped on delivery).
export TEST_RUNNER_SUNIYE_CU_EVALS=1
for name in SUNIYE_CU_EVAL_ENDPOINT SUNIYE_CU_EVAL_MODEL SUNIYE_CU_EVAL_API_KEY; do
  if [[ -n "${(P)name:-}" ]]; then
    export "TEST_RUNNER_${name}"="${(P)name}"
  fi
done

# The ad-hoc-signed test host loses its TCC grants whenever it is rebuilt
# (the signature changes). Default to running the existing binary; pass
# --rebuild only when code changed, then re-grant Accessibility and Screen
# Recording to the fresh binary before the next sweep.
action="test-without-building"
if [[ "${1:-}" == "--rebuild" ]]; then
  action="test"
fi

output="$(mktemp)"
xcodebuild \
  -project Suniye.xcodeproj \
  -scheme Suniye \
  -destination 'platform=macOS' \
  -derivedDataPath .derivedData \
  -parallel-testing-enabled NO \
  "$action" \
  -only-testing:SuniyeTests/ComputerUseEvalTests \
  2>&1 | tee "$output" | grep -E "eval task=|eval summary|overall:|results written|Test Case|TEST EXECUTE"

# A skipped eval is a broken invocation, not a passed sweep.
if grep -q "skipped" "$output" || ! grep -q "results written" "$output"; then
  echo "ERROR: the eval did not actually run (skipped or produced no results)." >&2
  exit 1
fi
