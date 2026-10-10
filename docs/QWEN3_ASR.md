# Qwen3-ASR

Qwen3-ASR 1.7B is an opt-in speech model: an audio encoder feeding the Qwen3-1.7B language model. It detects 30 languages and 22 Chinese dialects on its own. Suniye runs it with the bundled `llama-server` helper (the same one as [Local Gemma](LOCAL_GEMMA.md)), so it is Apple Silicon-only.

## Model

- Repository: `ggml-org/Qwen3-ASR-1.7B-GGUF` (Apache-2.0, converted from `Qwen/Qwen3-ASR-1.7B`)
- Revision: `36a678687ba7d07a74ca70ccb0e36902e005fb80`
- Files, sizes, and SHA-256: `qwen3ASRFile` entries in `Suniye/ASRModelCatalog.swift`
  - `Qwen3-ASR-1.7B-Q8_0.gguf`: the language model and its vocabulary
  - `mmproj-Qwen3-ASR-1.7B-Q8_0.gguf`: the audio encoder and projector
- Installed path: `~/Library/Application Support/Suniye/models/qwen3-asr-1.7b-q8_0-gguf/`

## Runtime

Loading the model starts the helper and sends one second of silence, so the first dictation does not pay for loading the weights or compiling the audio encoder. The helper keeps about 3 GB of memory until another model is selected or Suniye quits. If it dies, the next dictation starts it again.

```bash
llama-server \
  --model <dir>/Qwen3-ASR-1.7B-Q8_0.gguf \
  --mmproj <dir>/mmproj-Qwen3-ASR-1.7B-Q8_0.gguf \
  --ctx-size 4096 \
  --parallel 1 \
  --cache-ram 0 \
  --host 127.0.0.1 --port <random-port> --api-key <random-key> \
  --no-webui --log-disable
```

`--cache-ram 0` turns off llama-server's prompt cache. Every request carries different audio, so a cached prompt is never reused, and by default each request would add about 110 KiB per token to memory.

Each dictation:

1. Resamples the capture to 16 kHz.
2. Runs Silero VAD (`Suniye/Resources/silero_vad_v5.onnx`). A clip without speech returns no text. Like Whisper, the model turns silence and room noise into fluent, invented sentences.
3. Splits audio longer than 90 s at the quietest point before each boundary.
4. Sends each chunk as one `/v1/chat/completions` request: an empty system turn, then a user turn whose only content is the chunk as a 16-bit WAV `input_audio` part. Temperature is 0, and the reply budget is 20 tokens per second of audio plus 32.
5. Parses the reply `language <Name><asr_text><transcript>` the way the reference `qwen-asr` toolkit does, including its collapse of decoding loops.

The model writes numbers as words ("four thirty p.m."). Magic Format can rewrite them. Live preview is off for this model.

## Tests

`Qwen3ASRTranscriptionServiceTests` runs the engine against a fake helper in CI. The opt-in real-model tests need the model and the helper:

```bash
TEST_RUNNER_SUNIYE_RUN_QWEN3_ASR_TESTS=1 \
TEST_RUNNER_SUNIYE_QWEN3_ASR_MODEL_DIR=/path/to/gguf-dir \
TEST_RUNNER_SUNIYE_LLAMA_SERVER_PATH=/path/to/llama-server \
xcodebuild test -project Suniye.xcodeproj -scheme Suniye \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .derivedData \
  -only-testing:SuniyeTests/Qwen3ASRTranscriptionServiceRealModelTests \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```
