# Troubleshooting

## "App is damaged" / blocked by macOS
This project currently publishes unsigned binaries.
If macOS blocks the app on first launch, remove quarantine from the installed app:

```bash
xattr -dr com.apple.quarantine /Applications/Suniye.app
```

## Quarantine issues
If needed, remove quarantine from the installed app:
```bash
xattr -dr com.apple.quarantine /Applications/Suniye.app
```

## Model download fails
- Run `./scripts/setup_model.sh` manually.
- Check network access to GitHub Releases.
- Ensure enough disk space in `~/Library/Application Support/Suniye/models`.

## Downloaded the wrong model during onboarding
- Open the app settings and go to `ASR Model`.
- Install the model you want, then click `Use Model`.
- The onboarding flow downloads whichever ASR model is currently selected. Fresh installs default to `Parakeet TDT 0.6B v3`.

## Model is installed but won’t load
- Open `ASR Model` and try switching to another installed model.
- If the current model still fails, delete it from the model library and download it again.
- Check `~/Library/Application Support/Suniye/logs/app.log` for the failing model name and validation error.

## Missing dylibs
Rebuild and copy runtime libs:
```bash
./scripts/setup_sherpa.sh
./scripts/fix_dylibs.sh
```

## Permission errors while dictating
Grant and re-check:
- Microphone access
- Accessibility permissions

## Bluetooth audio drops to call quality while dictating
- Leave **Echo Cancellation** off unless you need speaker/audio playback removal from the mic signal.
- When Echo Cancellation is off, Suniye now captures from the selected microphone via an input-only Core Audio path so Bluetooth headphone playback can stay on the high-quality output profile.
