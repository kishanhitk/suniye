#!/usr/bin/env bash
set -euo pipefail

# End-to-end Command Mode harness: the REAL agent loop + REAL brain (a live LLM) +
# REAL tools + REAL accessibility perception — only ASR is skipped (tasks are text).
# Drives SuniyeTests/CommandMode/CommandModeE2ETests.swift.
#
# By default it spawns a local llama-server (Gemma) as the brain. Point it at any
# OpenAI-compatible endpoint instead with --endpoint (e.g. to validate the pipeline
# with a smart remote model).
#
#   ./scripts/e2e_command_mode.sh                       # local Gemma, launch tier
#   ./scripts/e2e_command_mode.sh --ax                  # + click/type/navigate (needs grants)
#   ./scripts/e2e_command_mode.sh --endpoint https://openrouter.ai/api \
#        --model anthropic/claude-3.7-sonnet --key sk-... --ax
#
# The launch tier asserts on the frontmost app (no TCC). The AX tier (--ax) clicks,
# types, and reads the accessibility tree / Safari's URL, so the TEST RUNNER needs
# Accessibility (and Automation) granted — System Settings → Privacy & Security.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENDPOINT=""
MODEL="local"
KEY=""
AX="0"
SERVER="${SUNIYE_LLAMA_SERVER:-$ROOT/Suniye/LocalLLM/llama-server}"
MODEL_PATH="${SUNIYE_LLM_MODEL_PATH:-$HOME/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf}"

usage() { echo "Usage: $0 [--endpoint URL --model M [--key K]] [--ax]"; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint) ENDPOINT="$2"; shift 2 ;;
    --model)    MODEL="$2"; shift 2 ;;
    --key)      KEY="$2"; shift 2 ;;
    --ax)       AX="1"; shift ;;
    -h|--help)  usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

CONFIG_FILE="$HOME/.suniye-cmd-e2e.json"
SERVER_PID=""
cleanup() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
  rm -f "$CONFIG_FILE"
}
trap cleanup EXIT

if [[ -z "$ENDPOINT" ]]; then
  [[ -x "$SERVER" ]] || { echo "llama-server not found at $SERVER (run scripts/setup_llama_cpp.sh or set SUNIYE_LLAMA_SERVER)" >&2; exit 2; }
  [[ -f "$MODEL_PATH" ]] || { echo "model not found at $MODEL_PATH (set SUNIYE_LLM_MODEL_PATH)" >&2; exit 2; }
  PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  ENDPOINT="http://127.0.0.1:$PORT"
  echo "Starting llama-server on $ENDPOINT ..."
  "$SERVER" --model "$MODEL_PATH" --host 127.0.0.1 --port "$PORT" \
    --ctx-size 4096 --parallel 1 --reasoning off --no-webui --log-disable >/dev/null 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 90); do
    curl -sf "$ENDPOINT/health" >/dev/null 2>&1 && break
    kill -0 "$SERVER_PID" 2>/dev/null || { echo "llama-server exited early" >&2; exit 1; }
    sleep 1
  done
  echo "llama-server ready."
fi

# The macOS test host does NOT inherit this process's env, so hand config to the
# test through a file it reads from $HOME (env is also exported, for manual runs).
AX_BOOL="false"; [[ "$AX" == "1" ]] && AX_BOOL="true"
python3 - "$CONFIG_FILE" "$ENDPOINT" "$MODEL" "$KEY" "$AX_BOOL" <<'PY'
import json, sys
path, url, model, key, ax = sys.argv[1:6]
cfg = {"enabled": True, "url": url, "model": model, "ax": ax == "true"}
if key:
    cfg["key"] = key
with open(path, "w") as f:
    json.dump(cfg, f)
PY
export SUNIYE_CMD_E2E=1
export SUNIYE_E2E_LLM_URL="$ENDPOINT"
export SUNIYE_E2E_LLM_MODEL="$MODEL"
[[ -n "$KEY" ]] && export SUNIYE_E2E_LLM_KEY="$KEY"
[[ "$AX" == "1" ]] && export SUNIYE_CMD_E2E_AX=1

echo "Running Command Mode E2E (AX tier=$AX) against $ENDPOINT model=$MODEL ..."
set +e
xcodebuild test \
  -scheme Suniye \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SuniyeTests/CommandModeE2ETests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 \
  | grep -E "Test Case '.*(started|passed|failed)|error:|Executed [0-9]+ test|frontmost app was|Safari URL was|=> |XCTSkip| Skipped "
STATUS="${PIPESTATUS[0]}"
set -e
echo "e2e exit: $STATUS"
exit "$STATUS"
