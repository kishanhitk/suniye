# AGENTS.md

## Scope
This repo builds VibeStoke: a local-first macOS dictation app.
Core flow: hold hotkey -> capture audio -> transcribe with sherpa-onnx -> paste into focused app.

## Tech stack
- Swift + SwiftUI + Observation
- macOS 14+
- XcodeGen project generation (`project.yml` is source of truth)
- sherpa-onnx C API via bundled dylibs in `VibeStoke/Frameworks`

## Architecture map
- `VibeStoke/AppState.swift`
  - Main state machine and orchestration (`@MainActor`).
  - Coordinates permissions, recording lifecycle, transcription, insertion, LLM post-processing.
- `VibeStoke/Services/AudioCaptureService.swift`
  - AVAudioEngine capture and sample buffering.
- `VibeStoke/Services/TranscriptionService.swift`
  - `actor` wrapping sherpa recognizer lifecycle and decode path.
- `VibeStoke/Services/TextInsertionService.swift`
  - Clipboard-preserving paste + submit-key event posting.
- `VibeStoke/Services/ModelManager.swift`
  - Model download/extract/validation and recognizer config paths.
- `VibeStoke/Views/*`
  - SwiftUI UI only; keep business logic in state/services.

## Hard constraints
- Keep audio/transcription local. Do not add remote audio processing.
- Keep model path contract stable unless intentionally migrating storage:
  - `~/Library/Application Support/VibeStoke/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`
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

# Unit tests (matches CI)
xcodegen generate --spec project.yml
xcodebuild \
  -project VibeStoke.xcodeproj \
  -scheme VibeStoke \
  -destination 'platform=macOS' \
  -derivedDataPath .derivedData \
  test
```

## Targeted E2E scripts
- LLM forced success/fallback and submit-command smoke tests run via launch args:
  - `--e2e-llm-success`, `--e2e-llm-fallback`, `--e2e-submit-command`
- Scripts under `scripts/e2e_*.sh` expect app installed at:
  - `~/Applications/VibeStoke.app`

## Logging and diagnostics
- App log file:
  - `~/Library/Application Support/VibeStoke/logs/app.log`
- For live debugging:
  - `./scripts/run_debug_live.sh`

## Change rules for agents
- Prefer minimal, surgical edits.
- Preserve actor/MainActor boundaries; do not introduce UI-thread blocking work.
- Keep service boundaries intact (do not collapse logic into views).
- Keep dependency-injected seams used by tests (`LLMPostProcessor`, settings store, keychain service).
- When behavior changes, update tests and relevant docs (`README.md`, `CHANGELOG.md`, `docs/*`).

## Commit messages
- Commit messages should follow commit lint conventions.

## Release notes
- Follow `docs/RELEASE.md`.
- Release artifacts and verification are script-driven:
  - `./scripts/package_release.sh --version vX.Y.Z`
  - `./scripts/verify_release.sh --version vX.Y.Z --dist-dir dist`
