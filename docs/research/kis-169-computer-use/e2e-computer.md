# Live `@Computer` E2E record

Date: 2026-08-03

Build: Debug build installed at `/Users/kishan/Applications/Suniye.app` with
`./scripts/build_app.sh Debug --install-user --open`.

The test used the Computer Use skill's `node_repl` wrapper. It targeted the full installed app
path because the machine has many Suniye bundles with the same bundle identifier.

## Safe test scope

The test operated only on Suniye. It did not open or modify a third-party app, accept a macOS
permission prompt, send a model request, or allow a native input action.

## Results

- `[Verified]` The installed app exposes the `Computer Use` navigation row.
- `[Verified]` The Computer Use page renders without quitting.
- `[Verified]` The running-app picker opens and lists running applications. The selected target was
  Suniye.
- `[Verified]` The window picker opens and lists Suniye windows.
- `[Verified]` `Bring Forward` completes for the selected Suniye window and the app remains alive.
- `[Verified]` Accessibility shows `Granted`.
- `[Verified]` Screen Recording shows a warning. With screenshot inclusion on, observation is
  disabled. Turning screenshot inclusion off enables Accessibility-only capture.
- `[Verified]` Accessibility-only capture produces an observation with window metadata, AX text,
  indexed elements, typed action buttons, and dynamic AX actions.
- `[Verified]` A benign `Click center` request opens the approval card with `Allow Once`, `Deny`,
  and `Stop Session`. `Deny` returns to the observation state without posting the click.
- `[Verified]` The agent task editor accepts and clears text. The remote agent controls remain
  disabled because no model is configured.
- `[Verified]` The final run remained alive after navigation, activation, observation, approval,
  and denial.

## Failures found and corrected

The first navigation run exposed an `EXC_BREAKPOINT` in `NativePopupPicker.updateNSView` while the
native popup menu had fewer items than the SwiftUI model. The fix bounds synchronization and uses
the popup's `itemArray`. `NativePopupPickerTests` covers the mismatch boundary.

The first `Bring Forward` run exposed an `EXC_BREAKPOINT` when Suniye used
`AXUIElementPerformAction(..., kAXRaiseAction)` on its own process. The fix keeps AX raising for
other processes and skips the re-entrant call after `NSRunningApplication.activate` for Suniye's
own process. `ComputerUseWindowActivationTests` covers that policy.

## Remaining unknowns

- `[Unknown]` Actual Screen Recording capture remains untested because the permission is not
  granted. No prompt was accepted during this run.
- `[Unknown]` A live remote model response, screenshot upload, provider cancellation, and agent
  loop completion remain untested because no model is configured.
- `[Unknown]` Cross-process window activation and native input delivery remain untested. The test
  deliberately used Suniye as the safe same-process target.
- `[Deferred]` Browser control and helper IPC remain outside this E2E.
- `[Not exercised]` Installed-app launch is implemented behind the async application-catalog seam,
  but this safe UI run did not launch a third-party application.

## Superseding live safe-target check — 2026-08-03

The earlier run above is historical: it exercised the temporary window picker, approval card, and
screenshot toggle before the parity cleanup. The current installed Preview build was tested with
the Computer Use skill against Calculator only.

- `[Verified]` The current Computer Use page opens without the removed window picker, Bring
  Forward control, approval card, or screenshot-choice control.
- `[Verified]` A task that asks Calculator to evaluate `17 × 19` completes automatically and
  reports `323` without a manual approval step.
- `[Verified]` The app remains responsive after the task completes.
- `[Not exercised]` No third-party app, browser, purchase, login, external message, or destructive
  action was used.
- `[Unknown]` Live provider configuration, Screen Recording capture, cross-process input, helper
  IPC, and browser extension behavior remain unverified.

## Final installed Preview check — 2026-08-03

- `[Verified]` `./scripts/build_app.sh Debug --preview --install-user` installed a fresh build at
  `/Users/kishan/Applications/Suniye Preview.app`.
- `[Verified]` After quitting and reopening that path, the Computer Use page opened without the
  removed window picker, Bring Forward control, screenshot toggle, manual action controls, or
  approval card.
- `[Verified]` With Calculator selected and the observation captured, the task
  `Read the Calculator result and report it. Do not change the calculator.` completed
  automatically and the UI reported `Computer Use finished The Calculator result is 323`.
- `[Not exercised]` The task did not change Calculator state and did not touch a browser or any
  third-party/destructive workflow.
- `[Unknown]` This confirms one configured-provider path, not full provider parity. Helper IPC,
  Screen Recording consent, cross-process input, and browser extension behavior remain open.
