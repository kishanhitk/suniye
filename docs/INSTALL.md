# Install VibeStoke (GitHub Release DMG)

## 1) Download
1. Open the latest GitHub Release.
2. Download:
   - `VibeStoke.dmg`
   - `SHA256SUMS.txt`

## 2) Verify checksum
From your Downloads folder:
```bash
shasum -a 256 VibeStoke.dmg
```
Match the output against `SHA256SUMS.txt`.

## 3) Install
1. Open `VibeStoke.dmg`.
2. Drag `VibeStoke.app` into `~/Applications`.

## 4) First launch (unsigned app)
Because the app is not notarized, macOS may block first launch.

If blocked:
1. Try opening `VibeStoke.app` once.
2. Open `System Settings` > `Privacy & Security`.
3. Find the blocked app message and click `Open Anyway`.
4. Confirm launch.

## 5) Permissions
Grant permissions when prompted:
- Microphone
- Accessibility (for text insertion)
