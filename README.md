# VibeStoke

Minimal local-only dictation app for macOS using SwiftUI and sherpa-onnx.

## Current status
- SwiftUI menu bar app scaffold is implemented.
- Audio capture, fn/globe hotkey, model download/extract, clipboard paste insertion, and app state flow are wired.
- sherpa-onnx transcription call is currently a placeholder in `VibeStoke/Services/TranscriptionService.swift`.

## Build
1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed.
2. Build from terminal:
   ```bash
   ./scripts/build_app.sh Release
   ```
3. Optional install targets:
   - Install to user Applications and open:
     ```bash
     ./scripts/build_app.sh Release --install-user --open
     ```
   - Install to system Applications and open:
     ```bash
     ./scripts/build_app.sh Release --install-system --open
     ```
4. One-time setup helpers:
   - Build sherpa dylibs: `./scripts/setup_sherpa.sh`
   - Download model: `./scripts/setup_model.sh`

## Model storage
`~/Library/Application Support/VibeStoke/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`
