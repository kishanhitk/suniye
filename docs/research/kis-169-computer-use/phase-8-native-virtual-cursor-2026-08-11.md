# Phase 8: native virtual cursor

Date: 2026-08-11

Reference evidence: `fake-cursor-dmg-agent-report.md`

## Outcome

- `[Implemented]` Suniye now presents a software cursor for desktop click, drag, and scroll
  actions. The cursor is an internal action-presentation sidecar; the model-facing ten-tool
  contract is unchanged.
- `[Implemented]` The action service sends the cursor presenter the same resolved screen point
  used by the native action. Indexed clicks use the Accessibility element center when available.
  Coordinate clicks and drags use the existing screenshot-to-screen transform.
- `[Implemented]` The presenter owns a passive, borderless, nonactivating `NSPanel`. It cannot
  become key or main, ignores mouse input, joins all Spaces, and does not activate Suniye.
- `[Implemented]` Cursor travel follows a curved path with critically damped progress and a small
  stretch/tilt treatment. Clicks pulse at the destination. Reduced Motion removes travel and
  deformation animation.
- `[Implemented]` New cursor requests cancel superseded animation work, and run cancellation is
  propagated. A failed optional Accessibility-center lookup does not prevent the semantic click.
- `[Verified]` Production wiring uses `SystemComputerUseCursorPresenter`; dependency-injected
  action-service tests retain a no-op default.

## Boundaries

- `[Verified]` No new model tool, target matcher, application routing heuristic, approval rule, or
  provider prompt was added.
- `[Verified]` Suniye's existing process-scoped input path remains responsible for the actual
  event. The cursor overlay only presents the intended action location.
- `[Unknown]` The mounted reference build's exact spring constants, fade delay, cursor artwork,
  style-selection gate, and physical-pointer behavior were not recoverable. Suniye therefore uses
  independent, restrained presentation values rather than claiming pixel parity.
- `[Unknown]` Suniye does not yet composite the software cursor into its captured screenshot or a
  PIP surface. The reference evidence proves such host/PIP plumbing exists, but not the exact
  mounted-build composition branch.

## Validation

- `[Verified]` The full macOS suite executed 1,089 tests with 2 skipped and 0 failures.
- `[Verified]` Gated line coverage is 88.95% (13,380/15,043), above the 80% floor. Cursor
  presentation is 100% covered and the AppKit overlay controller is 83.3% covered.
- `[Verified]` E2E preflight and smoke pass.
- `[Verified]` The installed Preview at `<home>/Applications/Suniye Preview.app` accepted
  the natural task `Open Calculator and click the 7 button.` It discovered Calculator, recovered
  from initial observation failures, clicked `7`, re-observed the Calculator value as `71`, and
  completed with `Done.`
- `[Verified]` The live AppKit test confirms the software-cursor panel is visible during
  presentation, cannot become key or main, and hides on request.

## Superseding lifecycle correction — 2026-08-12

- `[Verified live]` The reference cursor remains at its last action point while the model reasons
  and then moves from that retained point for the next pointer action.
- `[Corrected]` Suniye removed the post-action fade timer. The cursor now remains visible for the
  complete run and is reset only on completion, failure, Stop, or a new conversation.
- `[Verified]` A regression test waits 1.6 seconds after presentation and confirms that the cursor
  panel is still visible before explicit session teardown.
- `[Unknown]` Exact reference animation constants and screenshot/PIP compositing remain
  unrecovered.

## Files

- `Suniye/Services/ComputerUseCursorPresentation.swift`
- `Suniye/Services/ComputerUseCursorOverlayController.swift`
- `Suniye/Services/ComputerUseActionService.swift`
- `Suniye/Services/ComputerUseToolBackend.swift`
- `SuniyeTests/ComputerUseCursorPresenterTests.swift`
- `SuniyeTests/ComputerUseActionServiceTests.swift`
