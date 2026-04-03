# Suniye

Open-source, local-first dictation for macOS. Hold a key, speak, and your words appear as text — right where your cursor is. No audio leaves your machine. (*Suniye* is Hindi for "listen.")

> **Alpha** — Expect rough edges and breaking changes.

**[Website](https://suniye.kishans.in)** · **[Download](https://github.com/kishanhitk/suniye/releases/latest)** · **[Report Bug](https://github.com/kishanhitk/suniye/issues)**

## Why Suniye?

- **Private by default** — A 600 MB speech model runs entirely on your Mac. No audio leaves your machine. No cloud. No training data.
- **Works everywhere** — Inserts text directly into whichever app you're using via macOS Accessibility APIs.
- **Instant** — No network round-trip. Your voice becomes text in milliseconds, not seconds.
- **One shortcut** — Hold a key (configurable), talk, release. That's it.
- **Optional LLM cleanup** — Connect any OpenAI-compatible endpoint to polish transcriptions, fix grammar, or apply domain-specific vocabulary.

## Install

Requires **macOS 14 (Sonoma)** or later.

1. Download **Suniye.dmg** from the [latest GitHub Release](../../releases/latest).
2. Open the DMG and drag **Suniye.app** into `/Applications`.
3. If macOS blocks the app on first launch, remove quarantine and try again:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Suniye.app
   ```
4. Grant the permissions Suniye asks for:
   - **Microphone** — to hear you
   - **Accessibility** — to type text into other apps
5. Suniye will download a ~600 MB speech model on first launch. This is a one-time setup.
6. On first launch, Suniye walks you through a short onboarding flow: welcome, setup, and an optional practice dictation.

See [docs/INSTALL.md](docs/INSTALL.md) for checksum verification and detailed steps.

## How it works

1. A small icon appears in your **menu bar** — that's Suniye.
2. **Hold your hotkey** (default: Fn/Globe) and speak.
3. Release the key — your speech is transcribed and pasted at the cursor.

## Features

| Feature | Description |
|---|---|
| **Dashboard** | Session stats, today's word count, total dictation time, recent activity |
| **History** | Searchable log of past transcriptions with copy and delete |
| **Hotkey** | Configurable hold-to-talk shortcut (Fn/Globe, modifier combos, etc.) |
| **Model** | Manage the offline speech model — download, update, or delete |
| **Vocabulary** | Add domain-specific terms so the app gets your jargon right |
| **LLM** | Optional AI cleanup — choose a model, set an API key, customize the prompt |
| **General** | Preferred mic, auto-paste, launch at login, diagnostics |

## Updating

Suniye checks for updates automatically on launch (no popups). When an update is available:

1. Open the menu bar icon.
2. Click **Download Update...** — the app downloads and verifies the new version.
3. Replace the old app with the new one.

## Privacy

- All transcription happens **locally** on your Mac.
- The only network calls are model downloads and update checks against GitHub Releases.
- If you enable the optional LLM feature, transcribed text is sent to the LLM provider you configure.

## Technical details

| | |
|---|---|
| **Platform** | macOS 14+ |
| **UI** | SwiftUI |
| **Speech engine** | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (NVIDIA NeMo Parakeet TDT 0.6B, int8) |
| **License** | [MIT](LICENSE) |

### Build from source

```bash
# Prerequisites: Xcode, XcodeGen (brew install xcodegen)
./scripts/setup_sherpa.sh
./scripts/setup_model.sh
./scripts/doctor.sh          # verify environment
./scripts/build_app.sh Release --output-dir ./dist
open ./dist/Suniye.app
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines and [CHANGELOG.md](CHANGELOG.md) for what's changed.

To run tests: `./scripts/e2e_preflight.sh && ./scripts/e2e_smoke.sh`
