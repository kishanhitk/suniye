#!/bin/zsh
# VM eval sweep (KIS-182): clone the golden image, push the eval runner + tasks,
# run the sweep inside the disposable guest, pull results, destroy the clone.
# The guest is throwaway, so tasks-vm.json can be aggressive (mutating,
# destructive, multi-app) — see evals/computer-use/tasks-vm.json.
#
# Prerequisite: scripts/setup_cu_eval_vm.sh (builds the golden image).
# Requires SUNIYE_CU_EVAL_API_KEY (no app keychain inside the guest).
#
# Environment:
#   SUNIYE_CU_EVAL_API_KEY   model key (required)
#   SUNIYE_CU_EVAL_MODEL     model id (default: openai/gpt-5.6-luna)
#   SUNIYE_CU_EVAL_TASKS     task file (default: tasks-vm.json)

set -euo pipefail
cd "$(dirname "$0")/.."

TART="${TART:-$(command -v tart || echo "$HOME/.local/bin/tart")}"
GOLDEN="suniye-cu-golden"
CLONE="suniye-cu-run-$$"
SSH_KEY="$HOME/.ssh/suniye-cu-eval"
TASKS="${SUNIYE_CU_EVAL_TASKS:-tasks-vm.json}"

: "${SUNIYE_CU_EVAL_API_KEY:?set SUNIYE_CU_EVAL_API_KEY (the guest has no app keychain)}"
"$TART" list | awk '{print $2}' | grep -qx "$GOLDEN" \
  || { echo "ERROR: golden image missing; run scripts/setup_cu_eval_vm.sh" >&2; exit 1; }

echo "Building the eval runner..."
xcodegen generate >/dev/null
xcodebuild -project Suniye.xcodeproj -scheme SuniyeEvalRunner \
  -destination 'platform=macOS' -derivedDataPath .derivedData -configuration Release build \
  >/dev/null
RUNNER=".derivedData/Build/Products/Release/SuniyeEvalRunner.app"
[[ -d "$RUNNER" ]] || { echo "ERROR: runner build missing at $RUNNER" >&2; exit 1; }

"$TART" clone "$GOLDEN" "$CLONE"
cleanup() { "$TART" stop "$CLONE" 2>/dev/null || true; "$TART" delete "$CLONE" 2>/dev/null || true; }
trap cleanup EXIT

"$TART" run --no-graphics "$CLONE" &
for _ in {1..60}; do
  IP="$("$TART" ip "$CLONE" 2>/dev/null || true)"
  [[ -n "${IP:-}" ]] && nc -z "$IP" 22 2>/dev/null && break
  sleep 5
done
[[ -n "${IP:-}" ]] || { echo "ERROR: clone never became reachable" >&2; exit 1; }

SSH=(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "admin@$IP")
SCP=(scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

echo "Pushing runner, tasks, and dylibs to the guest..."
"${SSH[@]}" 'rm -rf ~/suniye-eval && mkdir -p ~/suniye-eval/evals/computer-use ~/suniye-eval/evals/runs'
"${SCP[@]}" -r "$RUNNER" "admin@$IP:~/suniye-eval/SuniyeEvalRunner.app"
"${SCP[@]}" "evals/computer-use/$TASKS" "admin@$IP:~/suniye-eval/evals/computer-use/tasks-vm.json"

echo "Running the sweep in the guest..."
"${SSH[@]}" "cd ~/suniye-eval && \
  SUNIYE_CU_EVAL_REPO=\$HOME/suniye-eval \
  SUNIYE_CU_EVAL_TASKS=tasks-vm.json \
  SUNIYE_CU_EVAL_MODEL='${SUNIYE_CU_EVAL_MODEL:-openai/gpt-5.6-luna}' \
  SUNIYE_CU_EVAL_API_KEY='${SUNIYE_CU_EVAL_API_KEY}' \
  ./SuniyeEvalRunner.app/Contents/MacOS/SuniyeEvalRunner"

echo "Pulling results..."
mkdir -p evals/runs
"${SCP[@]}" -r "admin@$IP:~/suniye-eval/evals/runs/*" evals/runs/ 2>/dev/null || true
"${SSH[@]}" 'sudo shutdown -h now' 2>/dev/null || true

latest="$(ls -t evals/runs/cu_eval_*.json 2>/dev/null | head -1 || true)"
[[ -n "$latest" ]] || { echo "ERROR: no results pulled from the guest" >&2; exit 1; }
echo "VM sweep results: $latest"
