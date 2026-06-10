# Auto-download app updates (KIS-146)

## Problem

Suniye ships Sparkle 2.9.2 with automatic checks enabled but automatic download
disabled (`SUAutomaticallyUpdate: false`). Updates only land when the user
manually checks, or accepts Sparkle's pre-download prompt on the daily
scheduled check. Users should get new versions without manual checking.

## Design

Configuration-only change in `project.yml` (XcodeGen source of truth for
`Suniye/Info.plist`):

- `SUAutomaticallyUpdate: false` → `true` — Sparkle downloads updates silently
  in the background, then shows a single "Update ready — Install and Relaunch /
  Later" popup. If dismissed, the staged update installs on next app quit.
- `SUScheduledCheckInterval: 18000` — check every 5 hours instead of the
  24-hour default. Each check is one conditional GET of the appcast XML.

Run `xcodegen generate` to regenerate `Suniye/Info.plist`; commit both files.

No new UI, no settings toggle, no gentle-reminders delegate (YAGNI).

## Behavior notes

- Plist values are Sparkle *defaults*: once a user expresses a preference via
  Sparkle's own UI checkbox, the UserDefaults value wins. Fresh and untouched
  installs adopt the new behavior immediately.
- Suniye is an `LSUIElement` menu-bar app; the "ready to install" alert
  briefly activates the app when shown.

## Testing

Tests are hosted in Suniye.app (`TEST_HOST`), so `Bundle.main` is the real app
bundle.

- Unit: app bundle Info.plist carries `SUEnableAutomaticChecks: true`,
  `SUAutomaticallyUpdate: true`, `SUScheduledCheckInterval: 18000`.
- Integration: a real `SparkleUpdateController` (backed by `SPUUpdater`)
  resolves `automaticallyDownloadsUpdates == true` and
  `updateCheckInterval == 18000` from the plist, with the mirrored
  UserDefaults keys cleared for determinism (restored in teardown).

Real-world verification happens on the next tip release: install an older tip
build and confirm the popup arrives pre-downloaded.
