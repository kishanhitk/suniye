# Third-Party Notices

Suniye depends on third-party software and model artifacts.

## Runtime dependencies
- sherpa-onnx v1.13.8
  - Source: https://github.com/k2-fsa/sherpa-onnx
  - Pinned by: `scripts/setup_sherpa.sh`
  - Used for: speech recognition C API runtime
  - Local files: `Suniye/Frameworks/libsherpa-onnx-c-api.dylib`, `Suniye/c-api.h`, `Suniye/SherpaOnnx.swift` (from `swift-api-examples`, unmodified)
- ONNX Runtime 1.28.2 (arm64 build from https://github.com/csukuangfj/onnxruntime-libs, the build sherpa-onnx v1.13.8 pins)
  - Source: https://github.com/microsoft/onnxruntime
  - Used for: model inference runtime; its C API is also called directly by the Cohere Transcribe engine
  - Local files: `Suniye/Frameworks/libonnxruntime.dylib`, `Suniye/onnxruntime_c_api.h`, `Suniye/onnxruntime_ep_c_api.h`, `Suniye/onnxruntime_error_code.h` (headers unmodified from the same build)
- llama.cpp
  - Source: https://github.com/ggml-org/llama.cpp
  - Pinned by: `scripts/setup_llama_cpp.sh`
  - Used for: the `llama-server` runtime for Local Gemma and Qwen3-ASR
  - Local file: `Suniye/LocalLLM/llama-server`, embedded as `Contents/Helpers/llama-server`

## Model artifacts
- Model: `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`
- Download source: sherpa-onnx releases
  - https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models
- Installed by: `scripts/setup_model.sh` and in-app downloader
- Model: `cohere-transcribe-03-2026-onnx-int8` (Cohere Transcribe, Apache-2.0)
- Download source: Hugging Face, community INT8 ONNX export of `CohereLabs/cohere-transcribe-03-2026`
  - https://huggingface.co/tristanripke/cohere-transcribe-onnx-int8 (pinned to commit `9ecc3a5e`)
- Installed by: in-app downloader (opt-in)
- Expected SHA-256: see `ASRModelCatalog.swift` (`cohereFile`), one per file
- Model: `qwen3-asr-1.7b-q8_0-gguf` (Qwen3-ASR 1.7B, Apache-2.0)
- Download source: Hugging Face, ggml-org's Q8_0 GGUF conversion of `Qwen/Qwen3-ASR-1.7B`
  - https://huggingface.co/ggml-org/Qwen3-ASR-1.7B-GGUF (pinned to commit `36a67868`)
- Installed by: in-app downloader (opt-in)
- Expected SHA-256: see `ASRModelCatalog.swift` (`qwen3ASRFile`), one per file
- Model: Silero VAD v5 (`silero_vad_v5.onnx`, MIT, Copyright (c) 2020-present Silero Team)
  - Source: https://github.com/snakers4/silero-vad, as published by sherpa-onnx at https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad_v5.onnx
  - Bundled as `Suniye/Resources/silero_vad_v5.onnx`; gates Qwen3-ASR so silence never reaches it
  - Expected SHA-256: `6b99cbfd39246b6706f98ec13c7c50c6b299181f2474fa05cbc8046acc274396`
- Model: `gemma-4-e2b-Q4_K_M.gguf`
- Download source: Hugging Face
  - https://huggingface.co/dahus/gemma-4-e2b-it-Q4_K_M-GGUF
- Installed by: in-app Local Gemma downloader
- Expected SHA-256: `d075ddeea9b056b6488af98e4c3776604c7c3196f1e55155c88a085027ab6d31`

## Maintainer action required
Before every public release, verify license and redistribution terms of:
- sherpa-onnx binaries
- onnxruntime binaries
- llama.cpp helper binary
- model files

If redistribution terms are incompatible, do not ship bundled binaries. Switch to runtime download/setup only.
