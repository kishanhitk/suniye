# Troubleshooting

## "App is damaged" / blocked by macOS
This project currently publishes unsigned binaries.
Use `System Settings` > `Privacy & Security` > `Open Anyway` after first blocked launch.

## Quarantine issues
If needed, remove quarantine from the installed app:
```bash
xattr -dr com.apple.quarantine ~/Applications/Suniye.app
```

## Model download fails
- Run `./scripts/setup_model.sh` manually.
- Check network access to GitHub Releases.
- Ensure enough disk space in `~/Library/Application Support/Suniye/models`.

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
