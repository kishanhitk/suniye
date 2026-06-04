# Troubleshooting

## "App is damaged" / blocked by macOS
Suniye is currently self-signed but not notarized.
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

## Update check fails
- Check network access to `https://suniye.kishans.in/appcast.xml`.
- If you use the Tip channel, also check network access to `https://suniye.kishans.in/appcast-tip.xml`.
- If the appcast is unavailable, check that the latest GitHub release includes `appcast.xml`.

## Downloaded the wrong model during onboarding
- Open the app settings and go to `ASR Model`.
- Install the model you want, then click `Use Model`.
- The onboarding flow downloads whichever ASR model is currently selected. Fresh installs default to `Parakeet TDT 0.6B v3`.

## Local Model download failed during onboarding
- You can finish onboarding and keep dictating without Magic Format.
- Open `Magic Format`, select `Local Model`, and retry the download.
- The Local Model is optional and separate from the speech model used for transcription.

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

If this happened immediately after updating from an older ad hoc-signed build, grant the permissions once more. Suniye releases now use one stable self-signed identity so future updates should preserve those grants.

## Bluetooth audio drops to call quality while dictating
- Bluetooth headphones switch to their call-quality profile whenever their microphone is used. This is a Bluetooth limitation, not an audio-quality setting Suniye can override.
- To keep high-quality headphone playback, choose the built-in Mac microphone or a USB microphone while continuing to use the Bluetooth headphones for output. Suniye shows the current route and offers a recommended local microphone when one is available.
- Echo Cancellation uses Apple's Voice Processing only when both the input and output route support it. Suniye bypasses it for Bluetooth routes.

## Selected microphone is unavailable
- Suniye preserves an explicitly selected microphone when it is disconnected instead of silently recording from a different device.
- Reconnect the microphone or choose another input device in **General > Microphone**. The unavailable device remains visible in the picker until you make a different choice.

## Dictation stops after an audio-device change
- Suniye stops the current dictation if the active microphone changes, becomes unavailable, changes format, is muted, or Core Audio restarts.
- Check the current route in **General > Microphone**, then start the dictation again.
