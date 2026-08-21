# Third-Party Notices

Suniye depends on third-party software and model artifacts.

## Runtime dependencies
- sherpa-onnx
  - Source: https://github.com/k2-fsa/sherpa-onnx
  - Used for: speech recognition C API runtime
  - Local files: `Suniye/Frameworks/libsherpa-onnx-c-api.dylib`, `Suniye/c-api.h`
- ONNX Runtime (via sherpa-onnx build/install)
  - Source: https://github.com/microsoft/onnxruntime
  - Used for: model inference runtime; its C API is also called directly by the Cohere Transcribe engine
  - Local files: `Suniye/Frameworks/libonnxruntime.dylib`, `Suniye/onnxruntime_c_api.h`, `Suniye/onnxruntime_ep_c_api.h` (headers vendored unmodified from the v1.23.2 tag)
- llama.cpp
  - Source: https://github.com/ggml-org/llama.cpp
  - Pinned by: `scripts/setup_llama_cpp.sh`
  - Used for: Local Gemma `llama-server` runtime
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
