# AGENTS.md

## Scope
This repo builds Suniye: a local-first macOS dictation app.
Core flow: hold hotkey -> capture audio -> transcribe with sherpa-onnx -> paste into focused app.

## Tech stack
- Swift + SwiftUI + Observation
- macOS 14+
- XcodeGen project generation (`project.yml` is source of truth)
- sherpa-onnx C API via bundled dylibs in `Suniye/Frameworks`

## Architecture map
- One folder per feature under `Suniye/`. Non-view code is flat in the feature folder; views are in `<Feature>/Views/`. Code that several features use and no feature owns is in `Shared/`, `Audio/` or `LLM/`.
- `Suniye/App/AppState.swift`
  - Main state machine and orchestration (`@MainActor`).
  - Coordinates permissions, recording lifecycle, transcription, insertion, LLM post-processing.
- `Suniye/Audio/AudioCaptureService.swift`
  - AVAudioEngine capture and sample buffering.
- `Suniye/SpeechModels/Engines/TranscriptionService.swift`
  - `actor` wrapping sherpa recognizer lifecycle and decode path.
- `Suniye/Dictation/TextInsertionService.swift`
  - Clipboard-preserving paste + submit-key event posting.
- `Suniye/SpeechModels/ModelManager.swift`
  - Model download/extract/validation and recognizer config paths.
- `Suniye/<Feature>/Views/*`
  - SwiftUI UI only; keep business logic in state/services.

## Hard constraints
- Keep audio/transcription local. Do not add remote audio processing.
- Keep model path contract stable unless intentionally migrating storage:
  - `~/Library/Application Support/Suniye/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`
- Required model files must remain:
  - `encoder.int8.onnx`, `decoder.int8.onnx`, `joiner.int8.onnx`, `tokens.txt`
- Text insertion depends on accessibility + unsandboxed CGEvent posting.
- If changing project structure/build settings, edit `project.yml` first, then regenerate project.

## Build and test commands
Run from repo root.

```bash
# Environment + dependencies
./scripts/setup_sherpa.sh
./scripts/setup_model.sh
./scripts/doctor.sh

# Build
./scripts/build_app.sh Debug
./scripts/build_app.sh Release --output-dir dist

# CI-equivalent checks
./scripts/e2e_preflight.sh
./scripts/e2e_smoke.sh

# Flow tests (matches CI; the dictation flow needs ./scripts/setup_model.sh)
xcodegen generate --spec project.yml
xcodebuild \
  -project Suniye.xcodeproj \
  -scheme Suniye \
  -destination 'platform=macOS' \
  -derivedDataPath .derivedData \
  test
```

## Test policy
- No coverage target. Do not add a test to raise a number.
- Tests are flow tests in the XCTest host. A flow test starts at a user entry point (hotkey, menu or settings action), runs the real app code, and stubs only the outside world: network, OS permission prompts, hardware (microphone, accessibility and key events, hotkey taps), the login Keychain, Sparkle.
- Do not add unit tests for helpers, formatters or single services. Add a flow test for a new user flow, or for a bug that a flow test can reproduce.
- A test must never touch real user data: no default stores, no real App Support folder, no `UserDefaults.standard`, no login Keychain. Start the app with `FlowApp` in `SuniyeTests/Support`.

## Targeted E2E scripts
- LLM forced success/fallback smoke tests run via launch args:
  - `--e2e-llm-success`, `--e2e-llm-fallback`
- Scripts under `scripts/e2e_*.sh` expect app installed at:
  - `~/Applications/Suniye.app`

## Logging and diagnostics
- App log file:
  - `~/Library/Application Support/Suniye/logs/app.log`
- For live debugging:
  - `./scripts/run_debug_live.sh`

## Change rules for agents
- Prefer minimal, surgical edits.
- Preserve actor/MainActor boundaries; do not introduce UI-thread blocking work.
- Keep service boundaries intact (do not collapse logic into views).
- Keep dependency-injected seams used by tests (`LLMPostProcessor`, settings store, keychain service).
- When behavior changes, update the flow tests and relevant docs (`README.md`, `docs/*`).

## Commit messages
- Commit messages should follow commit lint conventions.

## Release notes
- Follow `docs/RELEASE.md`.
- Release artifacts and verification are script-driven:
  - `./scripts/package_release.sh --version vX.Y.Z`
  - `./scripts/verify_release.sh --version vX.Y.Z --dist-dir dist`
