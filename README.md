# VibeStoke

VibeStoke is a local-first macOS dictation app built with SwiftUI and sherpa-onnx.

## Alpha warning
This project is in alpha (`v0.0.1`). Breaking changes, bugs, and rough edges are expected.

## What it does
- Captures microphone audio
- Runs local transcription with sherpa-onnx
- Inserts text into the active app
- Provides a menu bar UX with onboarding and status

## Main window pages
- Dashboard: key stats, quick actions, recent activity
- History: searchable local history (copy, delete, clear all)
- Hotkey: arbitrary shortcut capture with hold-to-talk behavior
- Model: install status, required files, disk usage, model actions
- Vocabulary: LLM glossary terms management
- LLM Polish: API key, model, and prompt configuration
- General: about, input device selection, launch-at-login, permissions

## UI typography
- Prefers `Google Sans` when installed on the machine
- Falls back automatically to system fonts when `Google Sans` is unavailable

## Privacy model
VibeStoke is designed to run transcription locally on your machine.
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
open ./dist/VibeStoke.app
```

## Releases
Public binaries are distributed through GitHub Releases as `VibeStoke.dmg` with `SHA256SUMS.txt`.

Install instructions are in `docs/INSTALL.md`.

## Release trust model
This project currently ships unsigned/ad-hoc binaries (no Apple Developer account).
Expect Gatekeeper prompts on first launch and follow the bypass instructions in `docs/INSTALL.md`.

## Development checks
```bash
./scripts/e2e_preflight.sh
./scripts/e2e_smoke.sh
```

## Model storage
`~/Library/Application Support/VibeStoke/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`
