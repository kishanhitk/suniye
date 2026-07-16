# Permiso (vendored)

These files are vendored verbatim from [zats/permiso](https://github.com/zats/permiso),
copied because upstream has **no tagged releases** (only a moving `main`) and the code is
small, self-contained, and reverse-engineered against macOS System Settings — i.e. something
we want to be able to audit and patch ourselves when macOS shifts.

- **Upstream:** https://github.com/zats/permiso
- **Pinned commit:** `3012871b741f68b1b6f46e2e1936c422df703968`
- **Source path upstream:** `Sources/Permiso/`

## Vendored files

`PermisoAssistant.swift`, `OverlayWindowController.swift`, `AppDragSourceView.swift`,
`PermisoPanel.swift`, `PermisoHostApp.swift`, `SettingsWindowLocator.swift`

## Local modifications

One deliberate delta (re-apply after any upstream re-sync):

- `PermisoAssistant.swift`: added a `public var onDismiss: (() -> Void)?` hook, fired at the
  end of `dismiss()` when an active overlay was torn down. The overlay's back chevron calls
  `PermisoAssistant.dismiss()` directly, so without this hook the owning wrapper
  (`AccessibilityOnboarding.swift`) could not observe user dismissals — its `isPresenting`
  latch stayed set and the Enable button silently no-opped until the 300s safety timeout.

Everything else is copied unchanged. Prefer the wrapper in
`Suniye/Services/AccessibilityOnboarding.swift` for any further fixes, so re-syncing
upstream stays close to a clean copy.

## How it's used

Only `PermisoPanel.accessibility` is used, behind the
`AccessibilityOnboardingPresenting` seam (`Suniye/Services/AccessibilityOnboarding.swift`).
Permiso is presentation-only; grant detection / auto-dismiss lives in that wrapper.

## Re-syncing

```sh
SHA=<new-commit>
base="https://raw.githubusercontent.com/zats/permiso/$SHA/Sources/Permiso"
for f in PermisoAssistant OverlayWindowController AppDragSourceView PermisoPanel PermisoHostApp SettingsWindowLocator; do
  curl -fsSL "$base/$f.swift" -o "Suniye/Vendor/Permiso/$f.swift"
done
```

Then update the pinned commit above. Watch for new files added upstream (e.g. additional
panel types) and add them to this list.

## Fragility note

`SettingsWindowLocator` finds the System Settings window via `CGWindowListCopyWindowInfo`
matched on bundle id `com.apple.systempreferences`, and `OverlayWindowController` repositions
on a 0.15s timer. A macOS System Settings redesign can break the overlay silently. The
`GeneralSettings.accessibilityDragHelperEnabled` flag is the kill switch; the "Open Settings"
deep-link in onboarding/settings is the always-available fallback.
