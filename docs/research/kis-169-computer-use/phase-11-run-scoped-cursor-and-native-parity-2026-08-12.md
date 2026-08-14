# Phase 11: run-scoped cursor and native parity corrections

Date: 2026-08-12

Reference evidence: `native-algorithm-recovery-2026-08-09.md`,
`fake-cursor-dmg-agent-report.md`, the mounted ChatGPT DMG, and live `@Computer` runs against the
installed Suniye Preview.

## Outcome

- `[Implemented]` The software cursor now belongs to the complete Computer Use run. It remains
  visible at its last action point while the model reasons and while a fresh observation is being
  captured. A later pointer action animates from that retained point.
- `[Extended by Phase 23]` The retained cursor's blue halo now has a subtle, reduced-motion-aware
  breathing animation while visible. The cursor icon itself remains stationary between actions.
- `[Implemented]` The coordinator hides and resets the software cursor only when the run completes,
  fails, is stopped, or the user starts a new conversation. The overlay no longer has a
  post-action fade timer.
- `[Implemented]` Primary clicks prefer the element's settable `AXSelected` attribute for a
  single-click selection. Otherwise they perform the element's press action with the requested
  click count and retain the existing process-scoped pointer fallback.
- `[Implemented]` Synthesized click, drag, and scroll events are posted to the target process. They
  do not activate the target application or move it in front of Suniye.
- `[Corrected]` Suniye's current model transport returns one tool call per model decision. Each
  action therefore consumes its observation and the model must call `get_app_state` before its
  next action. The reference may group actions inside one persistent `node_repl` execution, but
  Suniye does not expose that execution boundary and must not reuse state across model decisions.
- `[Corrected by Phase 22]` A transient no-window result for a running application first waits for
  an on-screen replacement window in the same process and observes again. If the bounded wait
  expires, Suniye now requests one background reopen and observes the returned application before
  the model may act. A real Chrome session showed that waiting alone could leave the run spinning
  for minutes when the process remained alive without any observable window.
- `[Corrected]` The temporary non-on-screen CG-window and ScreenCaptureKit fallback was removed.
  Normal discovery again uses the verified on-screen, non-desktop window path. The reference
  helper contains a private SkyLight/WindowServer capture path, but its exact branch matrix is
  `[Unknown]`; Suniye does not invent a public-API substitute.
- `[Implemented]` Tool-failure logs now include the localized error next to the error type and the
  existing debug session ID. The conversation still shows only raw tool names and parameters.

## Reference boundary

- `[Verified]` The reference native service has cursor-active and cursor-location state, a
  dedicated cursor window, a compiled software-cursor asset, and a host bridge for cursor state.
- `[Verified]` The reference tool contract is app-scoped and its native helper contains
  process-scoped input paths. Suniye does not add a public target lock, window picker, forced app
  activation, or task-specific application routing.
- `[Verified]` The reference helper discovers on-screen non-desktop CG windows, joins them to AX
  windows, and contains both ScreenCaptureKit and SkyLight/WindowServer screenshot paths.
- `[Unknown]` The mounted build does not expose the exact cursor animation constants, every
  cursor-compositing branch, the complete private screenshot fallback matrix, or the exact
  multi-window comparator. Suniye does not claim those details are identical.

## Validation

- `[Verified]` The cursor overlay test waits 1.6 seconds after presentation and confirms that the
  panel remains visible. Ending the cursor session then hides it.
- `[Verified]` Coordinator tests confirm cursor-session teardown on normal completion and Stop.
- `[Verified]` The final focused app/window/backend suite executes 32 tests with 0 failures.
- `[Verified]` The final full suite executes 1,093 tests with 2 skipped and 0 failures.
- `[Verified]` Gated line coverage is 88.45% (13,397/15,146), above the 80% floor.
- `[Verified]` E2E preflight and smoke pass after the final correction.
- `[Verified live]` `<home>/Applications/Suniye Preview.app` ran the natural instruction
  `Check my battery health percentage.` with model `openai/gpt-5.6-luna`. Session
  `CU-6B4B5D149C26` observed System Settings in the background with a screenshot and executed
  click, set-value, key, and secondary-action tools without bringing System Settings forward.
- `[Verified live]` That run did not complete the requested battery lookup. After a System
  Settings window transition, Suniye rejected an action against the replaced window, then could
  not reacquire the new window. The model returned an explicit failure. This run identified the
  same-process reacquisition defect fixed in this phase.
- `[Verified live]` After the correction and Preview reinstall, session `CU-463FE693F46D` completed
  the natural task `Check my Mac's battery health percentage and tell me the result.` It observed
  System Settings, clicked the Battery Health control, reacquired the resulting sheet, and reported
  `100%` and `Normal`. A separate observation through the reference runtime verified the sheet's
  `Normal 100%` Accessibility value.
- `[Verified live]` Session `CU-DACA4C3C5CD5` completed a 13-step Calculator loop with strict
  action/observation alternation. The model itself selected `17 × 9` instead of the requested
  `17 × 19` and reported `153`; an independent Calculator observation verified the mismatch. This
  is a remaining model-planning/context-quality issue, not a native action or window failure.

## Files

- `Suniye/Services/ComputerUseCursorPresentation.swift`
- `Suniye/Services/ComputerUseCursorOverlayController.swift`
- `Suniye/Services/ComputerUseCoordinator.swift`
- `Suniye/Services/ComputerUseActionService.swift`
- `Suniye/Services/SystemComputerUseAccessibilityActions.swift`
- `Suniye/Services/SystemComputerUseInputEvents.swift`
- `Suniye/Services/ComputerUseToolBackend.swift`
- `Suniye/Services/ComputerUseWindowDiscovery.swift`
- `Suniye/Services/SystemComputerUseScreenshotCapturer.swift`
- `Suniye/Services/SystemComputerUseWindowInventory.swift`
- `Suniye/SuniyeNativeBridge.h`
- `Suniye/SuniyeNativeBridge.mm`
- `SuniyeTests/ComputerUseCursorPresenterTests.swift`
- `SuniyeTests/ComputerUseCoordinatorTests.swift`
- `SuniyeTests/ComputerUseToolBackendTests.swift`
- `SuniyeTests/ComputerUseWindowDiscoveryTests.swift`
