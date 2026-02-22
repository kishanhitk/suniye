# VibeStoke

Minimal local-only dictation app for macOS using SwiftUI and sherpa-onnx.

## Current status
- SwiftUI menu bar app scaffold is implemented.
- Audio capture, fn/globe hotkey, model download/extract, clipboard paste insertion, and app state flow are wired.
- sherpa-onnx transcription call is currently a placeholder in `VibeStoke/Services/TranscriptionService.swift`.

## Build
1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed.
2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
3. Open `VibeStoke.xcodeproj` in Xcode.
4. Add these files from sherpa-onnx build artifacts:
   - `VibeStoke/Frameworks/libsherpa-onnx-c-api.dylib`
   - `VibeStoke/Frameworks/libonnxruntime.dylib`
   - Replace `VibeStoke/SherpaOnnx.swift`
   - Replace `VibeStoke/c-api.h` and uncomment import in `VibeStoke/VibeStoke-Bridging-Header.h`

## Model storage
`~/Library/Application Support/VibeStoke/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`
