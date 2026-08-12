# Phase 22: running application window recovery

Date: 2026-08-12

Incident: `CU-C96C0E8AAC68`

## Observed failure

- `[Verified live]` The instruction was `check my email on google chrome`.
- `[Verified live]` Google Chrome was already running, but repeated observations reported
  `no observable window: com.google.Chrome`.
- `[Verified live]` The run eventually completed after 321 seconds and 59 tool calls. It made 34
  `get_app_state` calls, 16 `click` calls, 6 `press_key` calls, 2 `list_apps` calls, and 1
  `perform_secondary_action` call.
- `[Verified live]` Eight Chrome observations failed because no window was visible. The agent then
  spent 44 calls observing or operating Finder before Chrome finally exposed a window.
- `[Verified]` The action freshness guard rejected attempts to act on Chrome without a successful
  Chrome observation. That guard behaved correctly and was not removed.

## Root cause

- `[Verified]` Application resolution returned an already-running process immediately.
- `[Verified]` Observation recovery waited up to five seconds for a replacement window in that
  process and then returned `noWindow`.
- `[Verified]` No lifecycle path asked macOS to reopen an already-running application after the
  bounded replacement-window wait expired.
- `[Inferred]` Repeated model retries amplified this missing lifecycle recovery into the 59-call
  run. No deterministic application matcher or target lock was involved.

## Correction

- `[Implemented]` A running application that initially has no observable window still gets the
  existing bounded same-process replacement-window wait.
- `[Implemented]` If no replacement appears, the application catalog requests one background
  reopen through the existing native launcher.
- `[Implemented]` The backend observes the application record returned by that reopen before
  authorizing any action. It does not reuse stale Accessibility state.
- `[Implemented]` A reopen failure remains visible as `launchFailed`; it is not converted into a
  misleading observation error.
- `[Not added]` No target lock, task-specific routing, app-name matcher, browser adapter, arbitrary
  retry limit, or prompt restriction was added.

## Reference boundary

- `[Verified artifact]` The inspected desktop implementation has a background application-launch
  path and waits for a primary window before returning control to the agent.
- `[Unknown]` The artifact does not reveal the exact internal branch used when an application is
  already running but owns zero observable windows.
- `[Closest match]` Reusing Suniye's existing background launcher after the bounded same-process
  wait is the smallest native lifecycle recovery consistent with the observed architecture.

## Validation

- `[Verified]` A regression test first fails an observation, makes same-process window
  reacquisition expire, and proves the catalog is asked to reopen exactly once before observation
  succeeds.
- `[Verified]` A separate test proves a genuine reopen failure is returned to the agent.
- `[Verified]` Catalog coverage proves reopening a running record uses the background launcher.
- `[Verified]` Focused backend and application-catalog suites pass.
- `[Verified]` The complete XCTest suite passes 1,139 tests with 2 skipped and zero failures.
  Gated line coverage is 87.05% (14,398/16,539 lines), above the required 80% floor.
- `[Verified]` E2E preflight and smoke pass.
- `[Verified live]` Debug Preview was rebuilt and installed at
  `/Users/kishan/Applications/Suniye Preview.app`. The pre-existing Preview process had to be
  restarted before it loaded the new binary; its PID changed from 4573 to 9499.
- `[Verified live]` With Chrome still running without an observable window, the natural task
  `Open Google Chrome and tell me the title of its current window.` completed as session
  `CU-63BFC1495D24`. The fresh `get_app_state` call completed in about six seconds with a
  screenshot and the title `New Tab - Google Chrome`.
- `[Verified live]` Before that observation, the model attempted a `CMD+N` action based on prior
  conversation history. The freshness guard rejected it with `observationRequired`; no input was
  sent to Chrome until state was observed.
