# Fake cursor evidence from `ChatGPT (1).dmg`

Date: 2026-08-11

Artifact: `<home>/Downloads/ChatGPT (1).dmg`

Current read-only mount: `/Volumes/ChatGPT Installer`
ASAR extraction used for line-level inspection: `/tmp/suniye-cua-app-asar.iL06DI`

This is a primary-artifact report. The evidence labels follow
[`README.md:95-99`](README.md:95-99). No production code was changed.

## Bottom line

- **[Verified]** The macOS Computer Use helper contains a dedicated software/virtual cursor
  subsystem, not just an incidental cursor icon. The helper has `ComputerUseCursor`,
  `SoftwareCursorStyle`, `AgentCursor`, `CursorView`, `CursorMotionPath`, a cursor window, cursor
  display/capture state, cursor-location notifications, and a feature flag named
  `feature/computerUseCursor` (`Enable the virtual cursor in Computer Use`).
- **[Verified]** The helper ships a compiled image asset named `SoftwareCursor` / rendition
  `Software Cursor.png` in `Package_ComputerUse.bundle/Contents/Resources/Assets.car`.
- **[Verified]** The host-side `sky.node` bridge carries cursor active state and location and has
  a remote-hosted PIP cursor-location handler. This is the native presentation path exposed to
  the ChatGPT host.
- **[Verified]** The ASAR contains a separate browser-only renderer overlay named
  `browser-agent-cursor-overlay`. It creates a pointer-events-disabled absolute layer, uses an
  embedded PNG, and animates browser cursor coordinates with Bezier/scoot motion and springs.
  Its `browser-use-cursor-arrived` event and `browser-agent-*` test IDs distinguish it from the
  native Mac Computer Use cursor.
- **[Inferred]** The fake cursor visible during desktop Computer Use is most likely the native
  helper's `SoftwareCursor`, composited in a dedicated overlay window and moved along an animated
  path to the action target. The native evidence supports this architecture, but does not expose
  the complete Swift implementation.
- **[Unknown]** The inspected artifact does not prove whether the native cursor is baked into the
  `skyshot` image sent to the model, drawn only over the user's desktop/PIP surface, or used in
  both places. It also does not prove whether the real system pointer is moved, or only a virtual
  cursor is rendered.

## Native Computer Use helper

Primary binary:

`/Volumes/ChatGPT Installer/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService`

`strings -a -t d` byte offsets in that binary provide these direct anchors:

| Evidence | Decimal file offset |
| --- | ---: |
| `ComputerUseCursor` | 14,402,512 |
| `SoftwareCursorStyle` | 14,402,736 |
| `CursorMotionPath` / `CursorMotionPathMeasurement` | 14,403,088 / 14,403,056 |
| `AgentCursor` / `CursorView` | 14,420,247 / 14,420,259 |
| `RecordAndReplayOverlayController` | 15,048,368 |
| `ComputerUse/ComputerUseCursor.swift` | 15,063,664 |
| `cursorWindow` | 15,065,107 |
| `cursorDisplayLayer` / `cursorCaptureStream` | 15,083,520 / 15,083,568 |
| `currentCursorLayerGeometry` | 15,083,728 |
| `feature/computerUseCursor` and `Enable the virtual cursor in Computer Use.` | 15,235,664 / 15,235,696 |
| `feature/detachComputerUseCursor` | 15,235,744 |
| `setComputerUseCursorLocationWithX:y:isActive:withReply:` | 15,972,367 |

The same binary names animation state for cursor motion and “scoot” deformation, including
`cursorMotionProgressAnimation`, `cursorScootPositionAnimation`, rotation/stretch state, and
`cursorMotionCompletionHandler` (around offsets 15,064,112-15,064,480 and
15,596,752-15,597,040). These names verify that the cursor has a native animated presentation
model; they do not recover the exact timing constants or rendering code.

The binary also contains `RecordAndReplayOverlayController`, `RecordAndReplayOverlayContentView`,
`RecordAndReplayOverlayPanel`, and `pressedOverlay` (15,048,368-15,049,203). **[Unknown]** whether
that recording/click overlay is part of the cursor seen by users; its name suggests a separate
record/replay or pressed-state surface, so it is not treated as cursor proof.

## Native host bridge and PIP path

Primary bridge:

`/Volumes/ChatGPT Installer/ChatGPT.app/Contents/Resources/native/sky.node`

Relevant `strings -a -t d` offsets:

- `_computerUseCursorActive` — 260,768;
- `_computerUseCursorLocation` — 260,793;
- `_hoverOverlayLayer` / `_positionLayer` — 262,116 / 262,962;
- `setComputerUseCursorLocation:isActive:` — 273,978;
- `setComputerUseCursorLocationWithX:y:isActive:withReply:` — 274,054;
- `remoteHostedPIPContentComputerUseCursorLocationHandler` — 278,281;
- `PIPStackProgrammaticMove` — 285,543.

**[Verified]** This connects cursor location and active state to the native host/PIP integration.
**[Inferred]** The cursor can be presented above a remote-hosted Computer Use/PIP surface, but
these Objective-C bridge names alone do not establish the exact window hierarchy or pixels being
captured.

## Compiled cursor artwork

Asset catalog:

`/Volumes/ChatGPT Installer/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/Resources/Package_ComputerUse.bundle/Contents/Resources/Assets.car`

`assetutil --info` reports an image record with:

- `Name`: `SoftwareCursor`;
- `RenditionName`: `Software Cursor.png`;
- `PixelWidth` / `PixelHeight`: `200` / `230`;
- `Opaque`: `false`;
- `Template Mode`: `automatic`.

The literal `SoftwareCursor` occurs in this `Assets.car` at byte offsets 5,160 and 9,248. No
regular cursor PNG was found beside the catalog. The `LensSequence/Lens_frame_00.png` through
`_44.png` files are 48x48 blue lens/logo frames, not cursor artwork.

## ASAR and JavaScript evidence

Main archive:

`/Volumes/ChatGPT Installer/ChatGPT.app/Contents/Resources/app.asar`

The extracted bundle
`/tmp/suniye-cua-app-asar.iL06DI/webview/assets/app-initial-iBPGfcXU.js` contains the
`AgentCursor` module at line 8913 (extracted byte offset 8,853,698; the raw `app.asar` occurrence
is at byte offset 30,622,960). The module:

- creates `data-testid="browser-agent-cursor-overlay"` as an absolute, `overflow:hidden`,
  `pointer-events:none`, z-index-20 layer;
- creates an image marked `data-browser-agent-cursor-asset`;
- consumes cursor `x`/`y`, visibility, `animateMovement`, viewport size, and `moveSequence`;
- uses Bezier-path and “scoot” motion branches with spring state; and
- dispatches `browser-use-cursor-arrived` when movement completes.

**[Verified]** This is a real fake-cursor renderer in the ASAR, but its naming and event contract
make it browser-agent UI, not evidence that the native Mac cursor is implemented in React/JS.
Searching the extracted ASAR for `setComputerUseCursorLocation`,
`computerUseCursorLocation`, `CursorMotionPath`, and `FogCursor` found no JS implementation of the
native cursor path.

The bundled Sky JS API reinforces that boundary:

- `.../@oai/sky/dist/project/cua/sky_js/src/types/full-desktop/Options.d.ts:5-6` documents
  `mouse_size_px` as a Linux-only screenshot pointer-size option; it is not a Mac cursor overlay
  API.
- `.../@oai/sky/dist/project/cua/sky_js/src/targets/mac/client.js:1` sends native Mac IPC
  requests, including `ComputerUseIPCAppGetSkyshotRequest`, but exposes no cursor-rendering
  option.
- `.../@oai/sky/dist/project/cua/sky_js/src/targets/mac/window_result.js:1` validates and returns
  the app, screenshot URL, and Accessibility text; there is no cursor field or cursor metadata.

## Live visual corroboration

This section is deliberately separated from the DMG-only evidence. The mounted DMG helper is
version `26.727.1000550`. The live check used the currently installed Sky helper, version
`26.804.1000633`, so it corroborates the architecture but does not prove that every pixel path is
identical in the older mounted build.

- **[Verified]** A pre-action `get_app_state` screenshot from the installed helper contained the
  Calculator window without a virtual cursor:
  `/var/folders/2q/wdx2yjfx31v4z42_pgh5rxxr0000gn/T/com.openai.sky.CUAService/Calculator Screenshot 2026-08-11 at 10.37.49 AM.jpeg`.
- **[Verified]** After a Sky `click` on Calculator button `7`, the returned screenshot contained
  a white cursor glyph and blue/teal highlight at the button:
  `/var/folders/2q/wdx2yjfx31v4z42_pgh5rxxr0000gn/T/com.openai.sky.CUAService/Calculator Screenshot 2026-08-11 at 10.37.57 AM.jpeg`.
- **[Verified]** After a second click on button `1`, a later returned screenshot moved the same
  visual cursor to button `1`:
  `/var/folders/2q/wdx2yjfx31v4z42_pgh5rxxr0000gn/T/com.openai.sky.CUAService/Calculator Screenshot 2026-08-11 at 10.39.57 AM.jpeg`.
- **[Inferred]** The action path updates the virtual cursor destination before or alongside the
  native action and returns a post-action skyshot that can contain the cursor presentation.
- **[Unknown]** Because the live helper is a different build, this does not establish whether the
  exact mounted DMG build composites the cursor into every model-facing skyshot, only into a
  desktop/PIP surface, or into both.

## Execution model reconstructed from the evidence

The narrowest supported sequence is:

1. The native app controller resolves an observed AX element or screenshot coordinate to a screen
   point. The controller stores `virtualCursor`, `targetWindowID`, the corresponding application
   process, and the cursor position in scaled coordinates.
2. `ComputerUseCursor` owns a separate cursor window. Its nested `Window` tracks the target window,
   screen changes, occlusion, active Space, and overlay window-level reasons.
3. The cursor style renders either the native SwiftUI-backed `FogCursorStyle`/`CursorView` or the
   `SoftwareCursorStyle` image view. The binary contains both styles; the selected runtime style
   and feature-gate branch are **[Unknown]**.
4. A motion path animates the cursor to the destination. The preserved configuration names show
   spring response, damping, arc/straight-path selection, and “scoot” position, tilt, stretch,
   squash, and rotation state. Exact timing values are **[Unknown]**.
5. The native action proceeds through Accessibility or synthesized input. The helper exposes
   cursor hide/location/finish notifications, and the host bridge receives cursor active state and
   location. A remote-hosted PIP renderer has a separate cursor display layer and cursor capture
   stream.
6. The cursor may fade or hide after movement. The exact delay, pressed-state choreography, and
   whether the physical system pointer is moved are **[Unknown]**.

The cursor is therefore a presentation sidecar to the action loop. It is not one of the ten public
Computer Use tools, is not represented as a cursor field in the public macOS state response, and
does not require adding another model-facing tool to Suniye.

## Suniye comparison

- **[Verified]** `Suniye/Services/ComputerUseObservationService.swift` returns AX text and a
  screenshot, but has no virtual-cursor state or cursor compositing step.
- **[Verified]** `Suniye/Services/ComputerUseActionService.swift` uses AX actions and
  process-scoped input events. It has no cursor window, cursor style, cursor destination
  notification, or host/PIP bridge.
- **[Verified]** `Suniye/Views/MainWindow/ComputerUsePage.swift` renders the chat transcript and
  settings disclosure, but no desktop overlay or live target presentation.
- **[Inferred]** The smallest parity seam is an internal presentation service driven by the same
  resolved screen point used for an action. It should not change the ten-tool contract or add
  deterministic target-selection logic.
- **[Implemented]** Suniye now has an internal native virtual-cursor presenter for click, drag, and
  scroll actions. It uses the resolved action coordinates and does not change the ten-tool
  contract. See `phase-8-native-virtual-cursor-2026-08-11.md` for implementation and validation.
- **[Unknown]** Suniye does not yet reproduce the unrecovered screenshot/PIP composition branch,
  exact cursor artwork, or exact native timing constants.

## False positives excluded

- `ChatGPT.app/Contents/Resources/native/avatar-overlay.node` contains avatar/pet-fog symbols,
  not the Computer Use cursor subsystem.
- `app.asar/webview/apps/cursor.png` is a 64x64 dark rounded app/icon image, not a pointer; its
  filename alone is not cursor evidence.
- `RecordAndReplayOverlayController` and `ComputerUseIPCAppStartCaptureAnimation*` are verified
  native overlay/capture names, but their relationship to the visible cursor remains **[Unknown]**.

## What the existing repo research confirms

- `parity-audit-dmg-agent.md:486-493` already verified native scaling, visible-rectangle,
  window-ordering, cursor/focus-enforcer symbols and left the screenshot backend open.
- `parity-audit-dmg-agent.md:676-681` verified native cursor movement among the helper's broader
  app, AX, input, window, and capture responsibilities.
- `native-algorithm-recovery-2026-08-09.md:285-300` recovers the screenshot-to-screen transform:
  `screenPoint = (screenshotPoint * scalingFactor) + optionalWindowOrigin`. This supports the
  target-coordinate part of cursor movement, but does not prove cursor rendering or screenshot
  inclusion.
- `source-inventory.md:112-135` records the helper executable and `Package_ComputerUse.bundle` as
  the primary native sources and distinguishes verified native findings from remaining branch
  unknowns.

## Final classification

**[Verified]** There is native Mac software-cursor code, a compiled `SoftwareCursor` asset, an
animated cursor state model, a cursor-location IPC bridge, and a separate browser-agent cursor
overlay in JavaScript.

**[Inferred]** The desktop fake cursor is a helper-owned virtual overlay, likely rendered in a
dedicated window and synchronized with model action coordinates and/or a PIP surface.

**[Unknown]** For the exact mounted DMG build, the cursor view hierarchy, default/gated states,
runtime style selection, click/pressed animation, whether it follows or replaces the system
pointer, and whether it is included in every model-facing screenshot remain unrecovered. The later
installed helper's post-action skyshot proves that screenshot inclusion exists in at least one
helper build.
