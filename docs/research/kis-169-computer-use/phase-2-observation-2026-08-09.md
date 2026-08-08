# Phase 2: Accessibility observation and screenshots

Date: 2026-08-09

Branch: `kis-169-computer-use-parity`

Status: implemented, reviewed, and validated

## Reference-backed behavior

- `[Verified]` The native service renders a depth-indented preorder AX tree with sequential integer
  element IDs. Lines can include role/name, description, help, application-provided identifier,
  disabled state, and exposed secondary actions.
- `[Verified]` It retains AX tree revisions, maps integer IDs back to elements, inherits IDs for
  matched nodes, and renders depth-first insertion/removal changes. `disableDiff` requests a full
  tree, and an unchanged live request may also return the full tree.
- `[Verified]` State includes a window-scoped screenshot while the target remains in the
  background. The native service contains ScreenCaptureKit and SkyLight paths; the live response
  was JPEG.
- `[Verified]` Screenshot coordinates are transformed to screen coordinates using screenshot scale
  and the selected window origin.
- `[Unknown]` Exact node-equality keys, diff line markers/budgets, AX traversal caps, and the full
  screenshot-backend branch matrix remain unrecovered.

## Suniye implementation

- `[Implemented]` `ComputerUseAccessibilityRevisionStore` flattens AX snapshots depth first,
  assigns integer IDs, retains per-app-and-window revisions, maps IDs to root/child paths, inherits
  IDs, and emits full or insertion/removal-aware text.
- `[Implemented]` Secure text-field values render as `[redacted]`. Ordinary values, settable state,
  disabled state, descriptions, help, identifiers, and secondary actions are represented.
- `[Implemented]` `SystemComputerUseAccessibilitySnapshotProvider` reads the selected AX window and
  menu bar without activating the app. It uses bounded depth, element count, and value length.
- `[Implemented]` `SystemComputerUseScreenshotCapturer` uses ScreenCaptureKit's
  desktop-independent window filter, JPEG encoding, actual display scale, and one retained temp
  screenshot per window.
- `[Implemented]` `ComputerUseObservationService` resolves/launches the app, discovers its internal
  window, captures AX and screenshot concurrently, and returns the recovered public state shape
  plus internal revision and coordinate metadata for later actions.

## Independent closest-match choices

- `[Independent choice]` Stable application identifiers plus role are the first revision match
  key; role plus tree path is the fallback. The exact native equality algorithm is unknown.
- `[Independent choice]` Changed nodes render as paired `-` and `+` lines sorted by tree path. The
  exact native punctuation and diff budget are unknown.
- `[Independent choice]` AX traversal defaults to depth 30, 1,500 elements, and 1,000 characters per
  value. These are resource bounds, not recovered constants.
- `[Independent choice]` Suniye currently uses the public ScreenCaptureKit path only. The private
  SkyLight fallback is not copied.

## Review and tests

- `[Verified]` Nine deterministic Phase 2 tests pass. They cover preorder rendering, details,
  secure redaction, ID inheritance, additions/removals, unchanged/full fallback, `disableDiff`,
  observation composition, no-process failure, and no-window failure.
- `[Corrected]` The required strict review replaced hard-coded Retina scaling with actual display
  scale and keyed revision identity by app plus native window ID.
- `[Live blocked]` A read-only Calculator test reached the native discovery path but failed with AX
  error `-25211` because the XCTest host lacks Accessibility permission. It did not claim a live
  pass and did not proceed to screenshot capture.
- `[Verified]` The final full suite executes 1,012 tests with 2 skipped and 0 failures. One skip is
  the existing model-dependent test and one is the opt-in live observation test.
- `[Verified]` Gated coverage is 95.14% (11,685/12,282 lines), above the requested 95% threshold.
  The two new live platform adapters are documented exclusions; pure revision and observation
  logic remains gated.
- `[Verified]` E2E preflight and E2E smoke both pass.

## Not implemented in Phase 2

- Semantic AX actions, process-scoped synthesized events, settling, or intervention monitoring.
- Permission UI and installed-app live validation.
- Model request/decision loop, approvals, cancellation UX, or chat surface.
- Browser-extension control.
