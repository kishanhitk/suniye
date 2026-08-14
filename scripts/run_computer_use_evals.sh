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

SUNIYE_CU_EVALS=1 xcodebuild \
  -project Suniye.xcodeproj \
  -scheme Suniye \
  -destination 'platform=macOS' \
  -derivedDataPath .derivedData \
  -parallel-testing-enabled NO \
  test \
  -only-testing:SuniyeTests/ComputerUseEvalTests \
  2>&1 | grep -E "^eval |^===|^  |results written|Test Case|TEST EXECUTE"
