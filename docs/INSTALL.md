# Install Suniye

## Homebrew (recommended)

```bash
brew install --cask kishanhitk/tap/suniye
```

This taps [`kishanhitk/homebrew-tap`](https://github.com/kishanhitk/homebrew-tap) and installs the latest release. Because Suniye is self-signed but not notarized, the cask clears the Gatekeeper quarantine automatically on install, so you can skip the manual `xattr` step. Updates are delivered in-app by Sparkle; `brew upgrade --cask suniye` works too.

To uninstall, including app data and downloaded models:

```bash
brew uninstall --zap --cask suniye
```

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

### 4) First launch (self-signed app)
Suniye is self-signed but not notarized, so macOS may block first launch.

If that happens, remove quarantine and try again:

```bash
xattr -dr com.apple.quarantine /Applications/Suniye.app
```

### 5) Permissions
Grant permissions when prompted:
- Microphone
- Accessibility (for text insertion)

If you are updating from an older ad hoc-signed Suniye release, macOS may ask for these permissions one more time. Future self-signed updates should preserve the grants.

After that, Suniye shows a short first-run onboarding flow that covers setup, an optional Magic Format choice, and a practice dictation.

During setup:
- Suniye downloads the currently selected speech model.
- Fresh installs default to `Parakeet TDT 0.6B v3`.
- After required setup, you can optionally enable Magic Format with Apple Intelligence or download the recommended Local Model.
- The Local Model download is optional and continues while you try dictation; it never blocks finishing onboarding.
- After onboarding, you can open `ASR Model` in settings to install or switch to another supported local model.

### 6) Update flow
Suniye checks for updates in the background. The default update channel is `Stable`.

To test the latest `main` branch build, open `General` settings and switch `Update Channel` to `Tip`. Switching back to `Stable` changes future checks, but Sparkle will not downgrade an installed tip build.

If a newer version is found:
1. Open the menu bar menu.
2. Click `Check for Updates...` if you want to check manually.
3. Follow the native updater prompt to install and relaunch.
