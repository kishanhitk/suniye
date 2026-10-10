# Troubleshooting

## "App is damaged" / blocked by macOS
Suniye releases are signed with an Apple Developer ID and notarized, so macOS opens them without extra steps. If macOS still blocks the app, read the exact alert:
- "Apple could not verify…" or "is damaged": the copy is older than the first Developer ID release, or the download is incomplete. Download the latest release from GitHub and install it again.
- Any other alert: open **System Settings > Privacy & Security** and check the message in the Security section.

## Model download fails
- Run `./scripts/setup_model.sh` manually.
- Check network access to GitHub Releases.
- Ensure enough disk space in `~/Library/Application Support/Suniye/models`.

## Update check fails
- Check network access to `https://suniye.kishans.in/appcast.xml`.
- If you use the Tip channel, also check network access to `https://suniye.kishans.in/appcast-tip.xml`.
- If the appcast is unavailable, check that the latest GitHub release includes `appcast.xml`.

## Onboarding downloaded a speech model on macOS 26
- Suniye uses Apple's built-in speech engine only when it works on your Mac. If it does not (unsupported language, a setting from your organization, or the system speech files cannot be installed), Suniye downloads `Parakeet TDT 0.6B v3` instead.
- `~/Library/Application Support/Suniye/logs/app.log` names the reason on the line `system default model unavailable`.
- To use a different model, open `Speech Model`, install it, then click `Use Model`.

## Holding the dictation key did nothing after the microphone prompt
- If you let go of the key while macOS asks for Microphone access, Suniye does not start recording. The floating indicator shows `Hold again to dictate`. Hold the key again.

## Local Model download failed
- Dictation keeps working without Magic Format.
- Open `Magic Format`, select `Local Model`, and retry the download.
- The Local Model is optional and separate from the speech model used for transcription.

## Model is installed but won’t load
- Open `Speech Model` and try switching to another installed model.
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

If this happened right after the update to the first Developer ID release, grant the permissions once more. macOS ties the grants to the app's signing identity, and that identity changed once. If Accessibility shows Suniye as already on, select Suniye in the Accessibility list, remove it with the minus button, and add it again.

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
