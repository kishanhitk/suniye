#!/usr/bin/env bash
set -euo pipefail

# Autonomous end-to-end harness for Command Mode's BROWSER control: drives the
# REAL Chrome extension (already loaded + paired) against a local fixture page
# through the real BrowserBridge — no human interaction.
#
#   ./scripts/e2e_browser_command.sh
#
# Preconditions (one-time): Suniye Preview has run at least once (wrote the
# paired extension to ~/Library/Application Support/Suniye/BrowserExtension) and
# the user loaded that folder in Chrome (chrome://extensions → Load unpacked).
#
# What it does: quits Suniye Preview (frees the bridge port — the extension then
# reconnects to the TEST's bridge within seconds), writes the gate file that
# arms BrowserFixtureE2ETests, runs them, and restores everything after.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PAIRING="$HOME/Library/Application Support/Suniye/BrowserExtension/pairing.json"
GATE="$HOME/.suniye-browser-e2e.json"

# --llm: also run the full-pipeline tier with a REAL LLM brain (spawns a local
# llama-server on the Suniye Gemma model; override with --endpoint/--model/--key).
LLM="0"; LLM_ENDPOINT=""; LLM_MODEL="local"; LLM_KEY=""
LLAMA_SERVER="${SUNIYE_LLAMA_SERVER:-$ROOT/Suniye/LocalLLM/llama-server}"
LLM_MODEL_PATH="${SUNIYE_LLM_MODEL_PATH:-$HOME/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --llm)      LLM="1"; shift ;;
    --endpoint) LLM_ENDPOINT="$2"; LLM="1"; shift 2 ;;
    --model)    LLM_MODEL="$2"; shift 2 ;;
    --key)      LLM_KEY="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$PAIRING" ]]; then
  echo "No paired extension at $PAIRING" >&2
  echo "Launch Suniye Preview once, then load the folder in chrome://extensions." >&2
  exit 2
fi

PREVIEW_WAS_RUNNING=0
pgrep -f "Suniye Preview.app" >/dev/null 2>&1 && PREVIEW_WAS_RUNNING=1
LLAMA_PID=""

cleanup() {
  rm -f "$GATE"
  [[ -n "$LLAMA_PID" ]] && kill "$LLAMA_PID" 2>/dev/null || true
  if [[ "$PREVIEW_WAS_RUNNING" == "1" ]]; then
    open -a "Suniye Preview" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ "$LLM" == "1" && -z "$LLM_ENDPOINT" ]]; then
  [[ -x "$LLAMA_SERVER" ]] || { echo "llama-server not found at $LLAMA_SERVER" >&2; exit 2; }
  [[ -f "$LLM_MODEL_PATH" ]] || { echo "model not found at $LLM_MODEL_PATH" >&2; exit 2; }
  PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  LLM_ENDPOINT="http://127.0.0.1:$PORT"
  echo "Starting llama-server on $LLM_ENDPOINT …"
  "$LLAMA_SERVER" --model "$LLM_MODEL_PATH" --host 127.0.0.1 --port "$PORT" \
    --ctx-size 4096 --parallel 1 --reasoning off --no-webui --log-disable >/dev/null 2>&1 &
  LLAMA_PID=$!
  for _ in $(seq 1 90); do
    curl -sf "$LLM_ENDPOINT/health" >/dev/null 2>&1 && break
    kill -0 "$LLAMA_PID" 2>/dev/null || { echo "llama-server exited early" >&2; exit 1; }
    sleep 1
  done
  echo "llama-server ready."
fi

if [[ "$PREVIEW_WAS_RUNNING" == "1" ]]; then
  echo "Quitting Suniye Preview to free the bridge port (relaunched after)…"
  killall "Suniye Preview" 2>/dev/null || true
  sleep 1
fi

# Sync the repo's extension code into the paired copy (keeps pairing.json), and
# restart Chrome — unpacked service-worker code is only re-read on browser launch.
EXT_DIR="$HOME/Library/Application Support/Suniye/BrowserExtension"
echo "Syncing extension code into the paired copy…"
cp "$ROOT/Suniye/BrowserExtension/background.js" "$EXT_DIR/background.js"
cp "$ROOT/Suniye/BrowserExtension/manifest.json" "$EXT_DIR/manifest.json"
if pgrep -x "Google Chrome" >/dev/null 2>&1; then
  echo "Restarting Google Chrome to load the synced extension code…"
  osascript -e 'quit app "Google Chrome"' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do pgrep -x "Google Chrome" >/dev/null 2>&1 || break; sleep 0.5; done
fi

python3 - "$GATE" "$LLM_ENDPOINT" "$LLM_MODEL" "$LLM_KEY" <<'PY'
import json, sys
path, url, model, key = sys.argv[1:5]
cfg = {"enabled": True}
if url:
    cfg["llm_url"] = url
    cfg["llm_model"] = model
    if key:
        cfg["llm_key"] = key
with open(path, "w") as f:
    json.dump(cfg, f)
PY

echo "Running browser E2E (real extension + fixture page)…"
set +e
xcodebuild test \
  -scheme Suniye \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SuniyeTests/BrowserFixtureE2ETests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 \
  | grep -E "Test Case '.*(started|passed|failed)|error:|XCTSkip|Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)|page never|failed -"
STATUS="${PIPESTATUS[0]}"
set -e

echo "browser e2e exit: $STATUS"
exit "$STATUS"
