# Local Gemma Runtime

Local Gemma is Suniye's local Magic Format fallback after Apple Intelligence and before API providers in Automatic mode. It is Apple Silicon-only in v1.

## Model

- Provider: Hugging Face
- Repository: `dahus/gemma-4-e2b-it-Q4_K_M-GGUF`
- Revision: `4f3551c3ccd2cb0c06bd09ac57ad0539392a0d5c`
- File: `gemma-4-e2b-Q4_K_M.gguf`
- Size: `3427873408` bytes
- SHA-256: `d075ddeea9b056b6488af98e4c3776604c7c3196f1e55155c88a085027ab6d31`
- Installed path: `~/Library/Application Support/Suniye/llm/gemma-4-e2b-Q4_K_M.gguf`

The app downloads the model on demand, validates HTTP status, byte size, and SHA-256, then atomically installs it.

## Drafter

A small drafter model proposes the next 3 tokens, and Gemma checks them in one pass (llama.cpp multi-token prediction, `--spec-type draft-mtp`). Greedy output stays the same and decoding gets faster.

- Repository: `ggml-org/gemma-4-E2B-it-GGUF`
- Revision: `2a8538c2e2d4687953a86c422c7c623cfd022880`
- File: `mtp-gemma-4-E2B-it-Q4_0.gguf`
- Size: `59235872` bytes
- SHA-256: `718d3a44057924d5840c65a0aeedf7929366adeeda92a2006955ccabaf645ef4`
- Installed path: `~/Library/Application Support/Suniye/llm/mtp-gemma-4-E2B-it-Q4_0.gguf`

The app downloads the drafter after the model, with the same checks. At launch it downloads the drafter for an installed model that does not have it. The model runs without the drafter, so a failed download only waits for the next launch. Deleting the model deletes the drafter.

## Runtime

Suniye bundles a signed `llama-server` helper in `Contents/Helpers/llama-server`. The app starts it on demand with a random localhost port and a per-launch API key:

```bash
llama-server \
  --model <installed-model-path> \
  --host 127.0.0.1 \
  --port <random-port> \
  --ctx-size 16384 \
  --parallel 1 \
  --reasoning off \
  --spec-type draft-mtp \
  --spec-draft-model <installed-drafter-path> \
  --api-key <random-key> \
  --no-webui \
  --log-disable
```

The two `--spec` arguments are present only when the drafter file is installed. llama-server has no request field that turns the drafter off, so Magic Format, Edit Mode and meeting summaries all decode with it.

Completion requests use `Authorization: Bearer <random-key>`. The server is reused while warm and shuts down after an idle timeout. Quitting Suniye stops it; a helper left running by a crash is stopped at the next launch. The same helper also runs the Qwen3-ASR speech model ([QWEN3_ASR.md](QWEN3_ASR.md)).

## Preparing The Helper

Build the pinned Apple Silicon helper (llama.cpp commit `7e960f40fb0bd2eede76406f807d6bc3f7aa339c`) before Release packaging:

```bash
./scripts/setup_llama_cpp.sh
```

This stages `Suniye/LocalLLM/llama-server`. Debug builds skip the helper when it is missing; Release builds fail if it is missing. Release signing signs the helper before the outer app bundle.
