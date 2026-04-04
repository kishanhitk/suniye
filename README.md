# Suniye

Open-source, local-first dictation for macOS. Hold a key, speak, and your words appear as text — right where your cursor is. No audio leaves your machine. (*Suniye* is Hindi for "listen.")

> **Alpha** — Expect rough edges and breaking changes.

**[Website](https://suniye.kishans.in)** · **[Download](https://github.com/kishanhitk/suniye/releases/latest)** · **[Report Bug](https://github.com/kishanhitk/suniye/issues)**

## Why Suniye?

- **Private by default** — Local speech models run entirely on your Mac. Audio never leaves your machine, with no cloud processing or training data retention.
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
5. Suniye will help you install a local speech model on first launch. The onboarding flow defaults to **Parakeet TDT 0.6B v3**, and you can switch to another supported offline model later from the `ASR Model` page.
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
| **Model** | Compare local ASR models by speed, quality, size, and language support; install supported options, switch the active model, or remove unused ones |
| **Vocabulary** | Add domain-specific terms so the app gets your jargon right |
| **LLM** | Optional AI cleanup — choose a model, set an API key, customize the prompt |
| **General** | Preferred mic, auto-paste, launch at login, diagnostics |

## Supported speech models

Suniye ships a curated local model catalog instead of a single fixed recognizer:

- **Parakeet TDT 0.6B v3** — recommended default for everyday dictation
- **Parakeet TDT 0.6B v2** — strong English-focused Parakeet option
- **Moonshine Base** — fastest lightweight English option
- **SenseVoice** — multilingual option for Chinese, Japanese, Korean, English, and Cantonese
- **Whisper Tiny (English)** — smallest Whisper download
- **Whisper Base (English)** — lightweight Whisper English model
- **Whisper Small (English)** — more accurate English Whisper option
- **Whisper Large v3 Turbo** — faster large Whisper model
- **Whisper Distil Large v3** — distilled large Whisper model
- **Whisper Large v3** — broad multilingual fallback with the heaviest footprint

All supported models run offline on your Mac and are managed from the `ASR Model` page.

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
| **Speech engine** | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) with a curated local model catalog (Parakeet, Moonshine, SenseVoice, and multiple Whisper variants) |
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
