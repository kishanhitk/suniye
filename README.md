# Suniye

Open-source, local-first dictation for macOS. Hold a key, speak, and your words appear as text — right where your cursor is. No audio leaves your machine. (*Suniye* is Hindi for "listen.")

> **Alpha** — Expect rough edges and breaking changes.

**[Website](https://suniye.kishans.in)** · **[Download](https://github.com/kishanhitk/suniye/releases/latest)** · **Report bugs from inside the app**

## Why Suniye?

- **Private by default** — Local speech models run entirely on your Mac. Audio never leaves your machine, with no cloud processing or training data retention.
- **Works everywhere** — Inserts text directly into whichever app you're using via macOS Accessibility APIs.
- **Instant** — No network round-trip. Your voice becomes text in milliseconds, not seconds.
- **One shortcut** — Hold a key (configurable), talk, release. That's it.
- **Optional Magic Format cleanup** — Use Apple Intelligence locally when available, run a local Gemma 4 Q4 formatter, or connect an OpenAI-compatible endpoint to polish transcriptions and preserve domain-specific vocabulary.

## Install

Requires **macOS 14 (Sonoma)** or later.

### Homebrew (recommended)

```bash
brew install --cask kishanhitk/tap/suniye
```

The cask taps [`kishanhitk/homebrew-tap`](https://github.com/kishanhitk/homebrew-tap) and installs the latest release. Suniye is self-signed (not yet notarized), so the cask clears the Gatekeeper quarantine for you on install — no manual `xattr` step. Run `brew upgrade --cask suniye` to update, though Suniye also updates itself in the background via Sparkle.

### Direct download

1. Download **Suniye.dmg** from the [latest GitHub Release](../../releases/latest).
2. Open the DMG and drag **Suniye.app** into `/Applications`.
3. If macOS blocks the app on first launch, remove quarantine and try again:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Suniye.app
   ```

### First launch (either method)

1. Grant the permissions Suniye asks for:
   - **Microphone** — to hear you
   - **Accessibility** — to type text into other apps
2. Suniye will help you install a local speech model on first launch. The onboarding flow defaults to **Parakeet TDT 0.6B v3**, and you can switch to another supported offline model later from the `ASR Model` page.
3. On first launch, Suniye walks you through welcome, required setup, an optional Magic Format choice, and a practice dictation. The recommended Local Model download is optional and continues in the background while you try dictation.

See [docs/INSTALL.md](docs/INSTALL.md) for checksum verification and detailed steps.

## How it works

1. A small icon appears in your **menu bar** — that's Suniye.
2. **Hold your hotkey** (default: Fn/Globe) and speak.
3. Release the key — your speech is transcribed and pasted at the cursor.

## Reporting issues

Use **Report a Problem** from the menu bar, the General page, or the Help menu. Suniye sends your description and an optional sanitized diagnostics bundle to the maintainer's private issue queue. Diagnostics include app logs and metadata only; audio, transcripts, clipboard contents, API keys, model files, and full system logs are not included.

## Features

| Feature | Description |
|---|---|
| **Dashboard** | Session stats, today's word count, total dictation time, recent activity |
| **History** | Searchable log of past transcriptions with copy and delete |
| **Hotkey** | Configurable hold-to-talk shortcut (Fn/Globe, modifier combos, etc.) |
| **Model** | Compare local ASR models by speed, quality, size, and language support; install supported options, switch the active model, or remove unused ones |
| **Vocabulary** | Add domain-specific terms so the app gets your jargon right |
| **Magic Format** | Optional AI cleanup — use Apple Intelligence locally when available, local Gemma 4 Q4 when installed, or an API model with your own key; customize prompts and vocabulary |
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

Suniye checks for updates automatically in the background. Stable releases are the default. To test the latest `main` branch build, open `General` settings and switch **Update Channel** from `Stable` to `Tip`.

When an update is available:

1. Open the menu bar icon.
2. Click **Check for Updates...** if you want to check manually.
3. Follow the native updater prompt to install and relaunch.

Switching from Tip back to Stable does not downgrade the app. Sparkle will offer the next stable release once it has a newer build number than the installed tip build.

### Sparkle signing key recovery

GitHub Actions secrets are write-only. You cannot read `SPARKLE_PRIVATE_KEY` back from GitHub after storing it.

The owner copy is kept in the local macOS Keychain under Sparkle account `suniye`. To export it from a Sparkle distribution:

```bash
./bin/generate_keys --account suniye -x ./suniye-sparkle-private-key
```

Keep that exported file in a password manager or other secret store, then delete the local export.

## Privacy

- All transcription happens **locally** on your Mac.
- The only network calls are model downloads, update checks, and issue reports you explicitly submit.
- If you enable Magic Format, Suniye uses Apple Intelligence locally when available, or local Gemma when configured. When you choose an API endpoint, transcribed text is sent to the provider you configure.

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
