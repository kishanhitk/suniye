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

## Runtime

Suniye bundles a signed `llama-server` helper in `Contents/Helpers/llama-server`. The app starts it on demand with a random localhost port and a per-launch API key:

```bash
llama-server \
  --model <installed-model-path> \
  --host 127.0.0.1 \
  --port <random-port> \
  --ctx-size 4096 \
  --parallel 1 \
  --reasoning off \
  --api-key <random-key> \
  --no-webui \
  --log-disable
```

Completion requests use `Authorization: Bearer <random-key>`. The server is reused while warm and shuts down after an idle timeout.

## Preparing The Helper

Build the pinned Apple Silicon helper before Release packaging:

```bash
./scripts/setup_llama_cpp.sh
```

This stages `Suniye/LocalLLM/llama-server`. Debug builds skip the helper when it is missing; Release builds fail if it is missing. Release signing signs the helper before the outer app bundle.
