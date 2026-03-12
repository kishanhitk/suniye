# Suniye

Suniye is a local-first macOS dictation app built with SwiftUI and sherpa-onnx.

## Alpha warning
This project is in alpha (`v0.0.1`). Breaking changes, bugs, and rough edges are expected.

## What it does
- Captures microphone audio
- Runs local transcription with sherpa-onnx
- Inserts text into the active app
- Provides a menu bar UX with onboarding and status
- Includes a main window with `Dashboard`, `History`, `Hotkey`, `Model`, `Vocabulary`, `LLM`, and `General`

## Main window
- `Dashboard`: session totals, today count, words, total dictation time, and recent activity
- `History`: persisted transcript log with relative time, duration, copy, and delete
- `Hotkey`: configurable hold-to-talk shortcut, including Fn/Globe and standard key combos
- `Model`: offline ASR model status, disk usage, and delete/re-download controls
- `Vocabulary`: domain-term list used to bias LLM cleanup toward your terminology
- `LLM`: toggle, model selection, API key, system prompt, and advanced runtime controls
- `General`: preferred microphone, auto-submit after paste, launch-at-login, and runtime diagnostics

## Privacy model
Suniye is designed to run transcription locally on your machine.
Model downloads come from upstream release artifacts, but audio processing is local.

## Requirements
- macOS 14+
- Full Xcode (`xcodebuild` available)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Quick start (build from source)
```bash
./scripts/setup_sherpa.sh
./scripts/setup_model.sh
./scripts/doctor.sh
./scripts/build_app.sh Release --output-dir ./dist
open ./dist/Suniye.app
```

## Releases
Public binaries are distributed through GitHub Releases as `Suniye.dmg` with `SHA256SUMS.txt`.

Install instructions are in `docs/INSTALL.md`.

## Updates
- App performs a background update check on every launch (silent; no popup).
- You can manually run `Check for Updates...` from the menu bar.
- When an update is available, use `Download Update...` from the menu bar.
- Downloaded update archives are checksum-verified (`SHA256SUMS.txt`) before opening.
- Launch at login is best-effort and may require approval in macOS `Login Items`; unsigned/ad-hoc builds may not support it.

## Release trust model
This project currently ships unsigned/ad-hoc binaries (no Apple Developer account).
Expect Gatekeeper prompts on first launch and follow the bypass instructions in `docs/INSTALL.md`.

## Development checks
```bash
./scripts/e2e_preflight.sh
./scripts/e2e_smoke.sh
```

## Model storage
`~/Library/Application Support/Suniye/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`
