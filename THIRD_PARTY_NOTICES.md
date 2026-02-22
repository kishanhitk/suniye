# Third-Party Notices

VibeStoke depends on third-party software and model artifacts.

## Runtime dependencies
- sherpa-onnx
  - Source: https://github.com/k2-fsa/sherpa-onnx
  - Used for: speech recognition C API runtime
  - Local files: `VibeStoke/Frameworks/libsherpa-onnx-c-api.dylib`, `VibeStoke/c-api.h`
- ONNX Runtime (via sherpa-onnx build/install)
  - Source: https://github.com/microsoft/onnxruntime
  - Used for: model inference runtime
  - Local file: `VibeStoke/Frameworks/libonnxruntime.dylib`

## Model artifacts
- Model: `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`
- Download source: sherpa-onnx releases
  - https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models
- Installed by: `scripts/setup_model.sh` and in-app downloader

## Maintainer action required
Before every public release, verify license and redistribution terms of:
- sherpa-onnx binaries
- onnxruntime binaries
- model files

If redistribution terms are incompatible, do not ship bundled binaries. Switch to runtime download/setup only.
