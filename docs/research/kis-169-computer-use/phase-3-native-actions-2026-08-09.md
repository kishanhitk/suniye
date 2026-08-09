# Fresh implementation phase 3: native actions and fresh-state execution

Date: 2026-08-09

Branch: `kis-169-computer-use-parity`

Primary implementation commit: `82b415f`

This note describes the fresh-branch implementation. Similar files and claims from the preserved
prototype branch are historical and are not evidence for the code described here.

## Reference evidence used

- `[Verified]` The macOS client exposes the same ten app-scoped tools recorded in
  `native-algorithm-recovery-2026-08-09.md` and the recovered Computer Use skill.
- `[Verified]` Click accepts either an Accessibility element index or screenshot-relative finite
  coordinates, plus left/right/middle buttons and a positive click count.
- `[Verified]` Mouse-button aliases `l`, `r`, and `m`, and scroll-direction aliases `u`, `d`, `l`,
  and `r`, are accepted by the shipped client.
- `[Verified]` Indexed interaction is semantic-first. The native layer can perform AX actions,
  replace values, select a source-text range, reposition an element for interaction, or fall back
  to synthesized input.
- `[Verified]` Synthesized click, drag, scroll, keyboard, and text events can be posted to a target
  process. Merely observing an app does not require making it frontmost.
- `[Verified]` Screenshot-relative coordinates are scaled and then translated by the captured
  window origin: `screenPoint = screenshotPoint * scalingFactor + windowOrigin`.
- `[Verified]` The runtime has automatic UI settling with an approximately one-second base wait.
  It can extend the wait to about five seconds when native state indicates loading or continued
  change.
- `[Verified]` The native implementation refetches AX elements, monitors AX invalidation, and has
  physical-input, focus, lock-screen, and cancellation paths.

## Implemented on the fresh branch

- `[Implemented]` `ComputerUseToolBackend` is the concrete ten-tool backend. It resolves the app
  for each call and does not retain a session target, deterministic task matcher, or frontmost-app
  fallback.
- `[Implemented]` A successful observation authorizes one action for the same app process and CG
  window. The observation is consumed before native execution, including when execution fails.
  A second action therefore requires another successful observation.
- `[Corrected]` A new observation attempt invalidates the previous cached observation before AX
  or screenshot work begins. A failed refresh cannot leave older state authorized.
- `[Implemented]` Action-time resolution verifies the current process and CG window ID and uses
  the newly correlated AX window ordinal. It does not require the target to be frontmost or key.
- `[Implemented]` Indexed left clicks prefer `AXPress`; unsupported semantic clicks fall back to a
  process-scoped click at the freshly resolved AX element center. Right and middle clicks preserve
  their requested mouse semantics and use the current element center.
- `[Implemented]` Dynamic secondary AX actions, value replacement, and UTF-16 text or cursor
  selection operate on a refetched AX element. Path, role, and identifier checks reject changed
  elements; a unique role-plus-identifier search can recover from a moved path.
- `[Implemented]` Coordinate clicks and drags use the captured image-to-window scale and window
  origin. The screenshot adapter now derives scale from actual image dimensions and excludes
  shadows so image coordinates align with the window frame.
- `[Implemented]` Scroll, drag, click, xdotool-style key chords, and Unicode text events use
  process-scoped `CGEvent` delivery. Down/up cleanup is attempted when cancellation occurs between
  paired events.
- `[Implemented]` Public mouse and direction aliases decode to canonical long values.
- `[Implemented]` A cancellation-aware one-second settle runs after every successful native
  action.
- `[Corrected]` The strict maintainability review consolidated repeated AX copy, type-check, array,
  geometry, and action-name reads into one platform adapter. Observation, discovery, and action
  services retain their separate responsibilities.

## Independent closest-match choices

- `[Independent choice]` A scroll page currently maps to 400 pixel units. The exact native page
  calibration, sign convention, momentum behavior, and app-specific scrollbar branch are not
  recoverable from the inspected artifact.
- `[Independent choice]` Unicode text is posted in chunks of at most 20 UTF-16 units without
  splitting a Swift `Character`. The exact native chunk size is not recovered.
- `[Independent choice]` AX identifier fallback is bounded to depth 30 and 1,500 elements. Those
  bounds match the observation budget but are not verified native constants.
- `[Independent choice]` `AXScrollToVisible` is attempted when exposed before interaction. Failure
  is best-effort because the exact native positioning algorithm is not recovered.
- `[Independent choice]` Repeated indexed left clicks issue repeated `AXPress` operations. The
  exact native distinction between semantic double-click and synthesized double-click remains
  unknown.
- `[Independent choice]` Suniye uses public ScreenCaptureKit JPEG capture without a window shadow
  and derives one uniform coordinate scale from the actual image width. The reference contains
  multiple capture backends and options; its complete backend-selection matrix is unknown.

## Still unknown or not yet implemented

- `[Unknown]` The complete role/app/action matrix that chooses AX semantics versus synthesized
  events.
- `[Not yet implemented]` Native loading/change detection that can extend the one-second settle to
  approximately five seconds.
- `[Not yet implemented]` Conditional focus enforcement, focus-steal prevention, physical-input
  intervention monitoring, and lock-screen guards.
- `[Unknown]` The exact rich-text source-range mapping used when visible AX text differs from the
  editable source value.
- `[Unknown]` Exact scroll calibration, mouse timing, drag interpolation, modifier timing, and
  cancellation behavior after an event has already been delivered.
- `[Unknown]` Live cross-process behavior under Suniye's final Accessibility and Screen Recording
  permission identity. Deterministic tests do not prove this OS-bound path.

## Validation

- `[Verified]` The focused post-review suite executes 35 tests with zero failures.
- `[Verified]` The post-review full suite executes 1,041 tests with 2 skipped and 0 failures.
- `[Verified]` Gated line coverage is 95.38% (12,277/12,871 lines) at the required 95% floor.
- `[Verified]` E2E preflight and E2E smoke both pass.
- `[Live required]` These deterministic and build checks do not prove cross-process native input
  under the installed Preview's TCC identity.
