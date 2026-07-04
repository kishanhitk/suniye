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
- `Suniye/AppState.swift`
  - Main state machine and orchestration (`@MainActor`).
  - Coordinates permissions, recording lifecycle, transcription, insertion, LLM post-processing.
- `Suniye/Services/AudioCaptureService.swift`
  - AVAudioEngine capture and sample buffering.
- `Suniye/Services/TranscriptionService.swift`
  - `actor` wrapping sherpa recognizer lifecycle and decode path.
- `Suniye/Services/TextInsertionService.swift`
  - Clipboard-preserving paste + submit-key event posting.
- `Suniye/Services/ModelManager.swift`
  - Model download/extract/validation and recognizer config paths.
- `Suniye/Views/*`
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

# Unit tests (matches CI)
xcodegen generate --spec project.yml
xcodebuild \
  -project Suniye.xcodeproj \
  -scheme Suniye \
  -destination 'platform=macOS' \
  -derivedDataPath .derivedData \
  -enableCodeCoverage YES \
  -resultBundlePath .derivedData/coverage.xcresult \
  test

# Coverage report + gate (run after tests; CI fails below threshold)
./scripts/coverage_report.sh
```

## Coverage policy
- CI enforces a 95% line-coverage floor on the app target via `scripts/coverage_report.sh`
  (current level ~95.3%; the residue is documented-unreachable code: permission
  prompts, real-model decode, OS-state-dependent branches, race guards).
- Files that genuinely cannot run headless in CI (live AppKit/window-server,
  hardware audio, vendored code) are listed in `scripts/coverage_exclusions.txt`
  with a reason comment. Do not add a file there to dodge writing tests;
  prefer extracting logic into a testable unit.
- New code must ship with tests that keep the gate green.

## Targeted E2E scripts
- LLM forced success/fallback and submit-command smoke tests run via launch args:
  - `--e2e-llm-success`, `--e2e-llm-fallback`, `--e2e-submit-command`
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
- When behavior changes, update tests and relevant docs (`README.md`, `docs/*`).

## Commit messages
- Commit messages should follow commit lint conventions.

## Release notes
- Follow `docs/RELEASE.md`.
- Release artifacts and verification are script-driven:
  - `./scripts/package_release.sh --version vX.Y.Z`
  - `./scripts/verify_release.sh --version vX.Y.Z --dist-dir dist`
