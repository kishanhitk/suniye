# Phase 7: live observation and launch parity

Date: 2026-08-09

Branch: `kis-169-computer-use-parity`

## Scope

This phase fixes two live observation failures found in the installed Preview:

1. Core Graphics and Accessibility can report different titles for the same window.
2. A newly launched application can return from `NSWorkspace` before its primary window exists.

It also adds privacy-bounded lifecycle diagnostics used to distinguish model, tool, and native
failures without logging task text, tool arguments, Accessibility content, screenshots, paths, or
credentials.

## Reference evidence

- `[Verified]` The mounted native service contains
  `ApplicationUIElement.awaitingLaunchCompletion()`,
  `ApplicationUIElement.waitUntilHasPrimaryWindow(timeout:pollingInterval:)`, and
  `NSRunningApplication.waitToFinishLaunching()` symbols.
- `[Verified]` With Calculator not running, one direct reference `get_app_state` call launched and
  observed Calculator in 791 milliseconds. It did not require a preceding `list_apps` retry.
- `[Unknown]` The exact launch-completion timeout, primary-window timeout, polling interval, and
  transient-error policy are not recoverable from those symbols or the live result.

## Root causes and implementation

### Dynamic titles

- `[Verified]` System Settings exposed the same Battery window as Core Graphics title `Battery`
  and Accessibility title `Battery – Charged to 80% Limit`, with matching bounds.
- `[Corrected]` When Accessibility bounds exist, window geometry is now authoritative. A title is
  used only when Accessibility does not expose bounds.
- `[Verified]` The regression test failed before the change and passes after it. Empty Core
  Graphics windows remain excluded.

### Cold launch

- `[Corrected]` Background launch still uses `NSWorkspace.OpenConfiguration` with activation and
  recent-item insertion disabled.
- `[Implemented]` The launcher waits for `NSRunningApplication.isFinishedLaunching`, then asks the
  window-discovery boundary to poll until the launched process has a matched primary window.
- `[Independent choice]` Suniye uses a five-second primary-window deadline and 50-millisecond
  polling interval. These values are cancellation-aware closest matches; they are not claimed as
  recovered constants.

### Diagnostics

- `[Implemented]` Run and tool lifecycle logs contain only step counts, tool names, application
  counts, Accessibility text character counts, screenshot presence, and error types.
- `[Verified]` The strict review found no logged instruction, tool arguments, tool-result content,
  screenshot data, file path, model credential, or endpoint.

## Installed Preview evidence

- `[Verified]` The installed Preview was configured to use `openai/gpt-5.6-luna` for these live
  tasks.
- `[Verified]` A Battery-health task completed after `list_apps` and one successful
  `get_app_state`; the model reported `Battery Health status: Normal`.
- `[Verified]` `Use Calculator to calculate 17 times 19 and tell me the result.` completed with
  `323`. The 23-call trace alternated each action with a new `get_app_state`, demonstrating live
  fresh-observation use through a multi-action run.
- `[Verified]` After Calculator was quit, `Open Calculator and tell me the number currently shown.`
  completed from a fresh Preview process with one successful `get_app_state` call and reported
  `323`. No `list_apps` recovery call was needed.
- `[Not exercised]` This phase did not run every action kind, physical-user intervention, denied
  permissions, or live microphone submission. Those remain in the final E2E matrix.

## Strict review and validation

- `[Corrected]` Primary-window polling belongs to `ComputerUseWindowDiscovering`; the launcher
  orchestrates launch state and error mapping only.
- `[Verified]` No changed production or test file exceeds 254 lines. No target lock,
  deterministic task/app matcher, forced-frontmost path, or raw payload logging was added.
- `[Verified]` The full suite executes 1,078 tests with 2 skipped and 0 failures.
- `[Verified]` Gated line coverage is 89.36% (13,083/14,641 lines), above the requested 80% floor.
- `[Verified]` E2E preflight and smoke both pass.
