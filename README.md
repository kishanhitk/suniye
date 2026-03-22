# Suniye

A local-first dictation app for macOS. Hold a key, speak, and your words appear as text — right where your cursor is. (*Suniye* is Hindi for "listen.")

> **Alpha** — Expect rough edges and breaking changes.

## Why Suniye?

- **Private by default** — Speech recognition runs entirely on your Mac. No audio leaves your machine.
- **Works everywhere** — Inserts text directly into whichever app you're using.
- **One shortcut** — Hold a key (configurable), talk, release. That's it.
- **Optional LLM cleanup** — Connect an LLM to polish transcriptions, fix grammar, or apply custom vocabulary.

## Install

Requires **macOS 14 (Sonoma)** or later.

1. Download **Suniye.dmg** from the [latest GitHub Release](../../releases/latest).
2. Open the DMG and drag **Suniye.app** into your Applications folder.
3. On first launch, macOS will block the app (it's unsigned).
   Go to **System Settings > Privacy & Security**, find the blocked-app message, and click **Open Anyway**.
4. Grant the permissions Suniye asks for:
   - **Microphone** — to hear you
   - **Accessibility** — to type text into other apps
5. Suniye will download a ~600 MB speech model on first launch. This is a one-time setup.

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
