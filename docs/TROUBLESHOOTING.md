# Troubleshooting

## "App is damaged" / blocked by macOS
This project currently publishes unsigned binaries.
Use `System Settings` > `Privacy & Security` > `Open Anyway` after first blocked launch.

## Quarantine issues
If needed, remove quarantine from the installed app:
```bash
xattr -dr com.apple.quarantine ~/Applications/VibeStoke.app
```

## Model download fails
- Run `./scripts/setup_model.sh` manually.
- Check network access to GitHub Releases.
- Ensure enough disk space in `~/Library/Application Support/VibeStoke/models`.

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
