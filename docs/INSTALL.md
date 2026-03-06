# Install Suniye (GitHub Release DMG)

## 1) Download
1. Open the latest GitHub Release.
2. Download:
   - `Suniye.dmg`
   - `SHA256SUMS.txt`

## 2) Verify checksum
From your Downloads folder:
```bash
shasum -a 256 Suniye.dmg
```
Match the output against `SHA256SUMS.txt`.

## 3) Install
1. Open `Suniye.dmg`.
2. Drag `Suniye.app` into `~/Applications`.

## 4) First launch (unsigned app)
Because the app is not notarized, macOS may block first launch.

If blocked:
1. Try opening `Suniye.app` once.
2. Open `System Settings` > `Privacy & Security`.
3. Find the blocked app message and click `Open Anyway`.
4. Confirm launch.

## 5) Permissions
Grant permissions when prompted:
- Microphone
- Accessibility (for text insertion)

## 6) Update flow (manual install)
On each app launch, Suniye checks GitHub Releases in the background.

If a newer version is found:
1. Open the menu bar menu.
2. Click `Download Update...`.
3. The app downloads and verifies the archive checksum against `SHA256SUMS.txt`.
4. The installer/archive is opened; replace the app in `~/Applications` manually.
