# Phase 12: background-Space observation parity

Date: 2026-08-12

Reference evidence: the mounted DMG native service, targeted symbol recovery, direct live runs
through the bundled Computer Use runtime, and installed Suniye Preview sessions.

## Outcome

- `[Implemented]` Window discovery first uses on-screen, non-desktop Core Graphics windows. If
  that produces no matched window for the requested process, it retries against the complete
  Core Graphics window list. It does not activate the target application.
- `[Implemented]` If an application's `AXWindows` result succeeds but is empty, Suniye uses its
  deduplicated `AXMainWindow` and `AXFocusedWindow` values. Discovery, Accessibility snapshots,
  and Accessibility actions share this ordering so a window ordinal has one meaning throughout
  the action loop.
- `[Implemented]` Screenshot capture includes non-on-screen `SCWindow` records. ScreenCaptureKit
  remains the first capture backend. If capture of the resolved window fails, Suniye invokes the
  dynamically resolved SkyLight/WindowServer window-image function used by the inspected native
  implementation.
- `[Retained]` The model-facing contract remains the same ten tools. No application-name matcher,
  target lock, forced activation, browser-specific rule, or new tool was added.

## Reference evidence

- `[Verified live]` Helium was running on another macOS Space. The normal on-screen Core Graphics
  query returned no Helium window, while the complete query returned its browser window and
  auxiliary surfaces.
- `[Verified live]` Helium returned an empty `AXWindows` array while in the background, but both
  `AXMainWindow` and `AXFocusedWindow` returned the real browser window with its complete
  Accessibility tree.
- `[Verified live]` For this Helium process, `AXManualAccessibility` was unsupported and
  `AXEnhancedUserInterface` was already true. Trying to set the latter returned an Accessibility
  error. The direct evidence rejected the earlier AX-enablement hypothesis, so Suniye does not
  retain a speculative Chromium or web-shaped enablement branch.
- `[Verified live]` The bundled Computer Use runtime observed that background Helium window,
  including its screenshot and full Accessibility tree, while Suniye remained frontmost.
- `[Verified]` The inspected native binary contains
  `SystemSoftware.WindowServerSPI.captureWindowImagesInRect` and
  `SlimCore.ScreenshotImplementation.captureScreenshotWithSkyLight` paths and dynamically resolves
  `SLSHWCaptureWindowListInRect` from SkyLight.
- `[Verified live]` Calling the recovered SkyLight function for Helium window 356 returned a
  3420-by-2148 `CGImage` of the correct background browser window without activating Helium.
- `[Verified live]` ScreenCaptureKit could enumerate the background `SCWindow` after changing
  `onScreenWindowsOnly` to false, but capture failed with `SCStreamErrorDomain -3811`. The
  SkyLight/WindowServer fallback is therefore required for this verified off-Space case.
- `[Unknown]` The artifact does not establish that every reference screenshot failure uses this
  fallback, nor does it expose every option bit or future macOS compatibility guarantee for the
  private function. Suniye uses it only after the public capture path fails and preserves the
  public error when the private function is unavailable.

## Failure sequence and correction

- `[Observed]` Sessions `CU-AB6FA2F7BEB0`, `CU-A523EFFD9B29`, and `CU-A70F015D0D2A` failed before
  observation because only on-screen windows were considered.
- `[Observed]` Session `CU-B3024820A12A` resolved the background window after the discovery and AX
  corrections but could not find it in an on-screen-only ScreenCaptureKit inventory.
- `[Observed]` Session `CU-1852F08AC741` found the background `SCWindow` but ScreenCaptureKit could
  not start capture. This isolated the remaining failure to the screenshot backend.
- `[Verified live]` After adding the recovered fallback, session `CU-87E929416B23` answered the
  natural question `How many tabs are open in Helium browser right now?` with `There are 2 tabs
  open in Helium.` It used exactly one `get_app_state` tool call.
- `[Verified live]` Session `CU-1294CF91EBB9` observed Helium, opened a new tab, observed fresh
  state, closed the new tab, observed again, and completed. An independent final observation
  confirmed that Helium had returned to its original two tabs.

## Validation

- `[Verified]` The focused window-discovery suite executes 10 tests with 0 failures.
- `[Verified]` The full suite executes 1,093 tests with 2 skipped and 0 failures.
- `[Verified]` Gated line coverage is 88.46% (13,411/15,160), above the 80% floor.
- `[Verified]` E2E preflight and smoke pass.
- `[Verified]` The final installed build is `<home>/Applications/Suniye Preview.app`.

## Files

- `Suniye/Services/ComputerUseWindowDiscovery.swift`
- `Suniye/Services/SystemComputerUseWindowInventory.swift`
- `Suniye/Services/SystemComputerUseAccessibilityAPI.swift`
- `Suniye/Services/SystemComputerUseAccessibilitySnapshotProvider.swift`
- `Suniye/Services/SystemComputerUseAccessibilityActions.swift`
- `Suniye/Services/SystemComputerUseScreenshotCapturer.swift`
- `Suniye/SuniyeNativeBridge.h`
- `Suniye/SuniyeNativeBridge.mm`
- `SuniyeTests/ComputerUseWindowDiscoveryTests.swift`
