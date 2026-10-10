# Install Suniye

## Homebrew (recommended)

```bash
brew install --cask kishanhitk/tap/suniye
```

This taps [`kishanhitk/homebrew-tap`](https://github.com/kishanhitk/homebrew-tap) and installs the latest release. Updates are delivered in-app by Sparkle; `brew upgrade --cask suniye` works too.

Homebrew 6.0+ requires third-party taps to be trusted before their code runs. Using the fully-qualified name above grants trust to just this cask (you may be asked to confirm on first install). To pre-trust it — for example in scripted or CI installs — run `brew trust --cask kishanhitk/tap/suniye` first, or read the cask before trusting it with `brew cat kishanhitk/tap/suniye`.

To uninstall, including app data and downloaded models:

```bash
brew uninstall --zap --cask suniye
```

## Local preview build

To keep the official release installed while testing local work, build the preview variant:

```bash
./scripts/build_app.sh Debug --preview --install-user --open
```

Preview installs as `~/Applications/Suniye Preview.app` with bundle id `dev.suniye.app.preview`, so it does not replace `/Applications/Suniye.app` or `~/Applications/Suniye.app`. macOS treats it as a separate app, so grant Microphone and Accessibility permissions to Preview once. Preview builds disable Sparkle release updates, but they share the large ASR model cache at `~/Library/Application Support/Suniye/models`.

## Manual install (GitHub Release DMG)

### 1) Download
1. Open the latest GitHub Release.
2. Download:
   - `Suniye.dmg`
   - `SHA256SUMS.txt`

### 2) Verify checksum
From your Downloads folder:
```bash
shasum -a 256 Suniye.dmg
```
Match the output against `SHA256SUMS.txt`.

### 3) Install
1. Open `Suniye.dmg`.
2. Drag `Suniye.app` into `/Applications`.

### 4) First launch
Suniye is signed with an Apple Developer ID and notarized by Apple. macOS asks once to confirm that you want to open an app downloaded from the internet.

### 5) Permissions
Grant permissions when prompted:
- Microphone
- Accessibility (for text insertion)

If you are updating from a release older than the first Developer ID release, grant these permissions one more time. If Accessibility shows Suniye as already on but dictation still asks for it, select Suniye in the Accessibility list, remove it with the minus button, and add it again. Later updates keep the grants.

The first-run onboarding has four screens:
1. **Welcome** — click `Try your first dictation`. macOS asks for Microphone access here.
2. **Try your first dictation** — hold the dictation key (Globe by default), speak, and let go. Your words appear in the field.
3. **Dictate anywhere** — click `Allow Access` and drag Suniye into the Accessibility list. Closing the window on this screen finishes onboarding without Accessibility; Suniye then copies each dictation to the clipboard instead of pasting it.
4. **There's more when you need it** — names Magic Format, Speech Model, and Hold to edit selection. `Finish` opens the main window.

Speech model on a fresh install:
- On macOS 26, Suniye checks that Apple's built-in speech engine works on your Mac and uses it. Nothing is downloaded.
- If that check fails (macOS 14–15, an unsupported language, a setting from your organization, or the system speech files cannot be installed), Suniye downloads `Parakeet TDT 0.6B v3` and shows the progress on the second screen.
- After onboarding, open `Speech Model` to install or switch to another supported model.
- Magic Format is not part of onboarding. Turn it on later from `Magic Format`.

### 6) Update flow
Suniye checks for updates in the background. The default update channel is `Stable`.

To test the latest `main` branch build, open `General` settings and switch `Update Channel` to `Tip`. Switching back to `Stable` changes future checks, but Sparkle will not downgrade an installed tip build.

If a newer version is found:
1. Open the menu bar menu.
2. Click `Check for Updates...` if you want to check manually.
3. Follow the native updater prompt to install and relaunch.
