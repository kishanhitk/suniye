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
LLM="0"; LLM_ENDPOINT=""; LLM_MODEL="local"; LLM_KEY=""; SITE=""
LLAMA_SERVER="${SUNIYE_LLAMA_SERVER:-$ROOT/Suniye/LocalLLM/llama-server}"
LLM_MODEL_PATH="${SUNIYE_LLM_MODEL_PATH:-$HOME/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --llm)      LLM="1"; shift ;;
    # --flipkart: also run the LIVE-Flipkart tier (real site, the user's logged-in
    # Chrome session). Implies --llm for the orders-navigation flow.
    --flipkart) SITE="flipkart"; LLM="1"; shift ;;
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

# Preferred test brain: a remote smart model via OpenRouter, keyed from the
# environment or a 0600 credential file (never hardcoded/committed). Override the
# model with SUNIYE_TEST_LLM_MODEL.
KEY_FILE="$HOME/.config/suniye/test-llm-key"
if [[ -z "${SUNIYE_TEST_LLM_KEY:-}" && -f "$KEY_FILE" ]]; then
  SUNIYE_TEST_LLM_KEY="$(cat "$KEY_FILE")"
fi
if [[ "$LLM" == "1" && -z "$LLM_ENDPOINT" && -n "${SUNIYE_TEST_LLM_KEY:-}" ]]; then
  LLM_ENDPOINT="${SUNIYE_TEST_LLM_ENDPOINT:-https://openrouter.ai/api}"
  LLM_MODEL="${SUNIYE_TEST_LLM_MODEL:-anthropic/claude-sonnet-4.6}"
  LLM_KEY="$SUNIYE_TEST_LLM_KEY"
  echo "Using remote test model: $LLM_MODEL"
fi

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

python3 - "$GATE" "$LLM_ENDPOINT" "$LLM_MODEL" "$LLM_KEY" "$SITE" <<'PY'
import json, sys
path, url, model, key, site = sys.argv[1:6]
cfg = {"enabled": True}
if url:
    cfg["llm_url"] = url
    cfg["llm_model"] = model
    if key:
        cfg["llm_key"] = key
if site:
    cfg["site"] = site
with open(path, "w") as f:
    json.dump(cfg, f)
PY

ONLY_TESTS=(-only-testing:SuniyeTests/BrowserFixtureE2ETests)
[[ -n "$SITE" ]] && ONLY_TESTS+=(-only-testing:SuniyeTests/BrowserLiveSiteE2ETests)

echo "Running browser E2E (real extension + fixture page${SITE:+ + live $SITE})…"
set +e
xcodebuild test \
  -scheme Suniye \
  -destination 'platform=macOS,arch=arm64' \
  "${ONLY_TESTS[@]}" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO 2>&1 \
  | grep -E "Test Case '.*(started|passed|failed)|error:|XCTSkip|skipped|Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)|page never|FLIPKART|WIKI|EXAMPLE|failed -"
STATUS="${PIPESTATUS[0]}"
set -e

echo "browser e2e exit: $STATUS"
exit "$STATUS"
