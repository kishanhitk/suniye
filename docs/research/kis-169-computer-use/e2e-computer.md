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

## Direct voice integration check — 2026-08-03

- `[Verified]` The source-level route is connected from the existing AppState dictation lifecycle
  to the visible Computer Use coordinator.
- `[Verified]` Signed focused tests confirm that a transcribed voice task bypasses normal text
  insertion and starts or queues the Computer Use agent through the coordinator seam.
- `[Not exercised]` A live microphone task was not run in this pass.
- `[Unknown]` Live ASR output, model request timing, Screen Recording capture, and the behavior of
  a voice task while a provider is unavailable still need manual validation.

### Manual voice test

1. Open `/Users/kishan/Applications/Suniye Preview.app`.
2. Configure `Model → API Endpoint` and save a supported model/key.
3. Open `Computer Use`, grant the displayed Accessibility and Screen Recording permissions, and
   select a harmless read-only desktop task.
4. Hold the normal Suniye dictation hotkey, speak the task, and release.
5. Confirm that the transcript is not inserted into the focused app and that the agent starts
   automatically or shows a clear queued/preparation state.
6. Leave Computer Use and repeat ordinary dictation to confirm the normal insertion route.

Browser tasks should use the browser extension path and are not evidence for this desktop voice
route.

## App-owned session and background lifecycle E2E — 2026-08-12

Build: Debug Preview installed at `/Users/kishan/Applications/Suniye Preview.app` from
`kis-169-computer-use-parity`.

- `[Verified]` Natural task `Open Calculator, enter 7, and verify the display.` completed through
  a deterministic OpenAI-compatible loopback provider. The observed sequence was
  `get_app_state` → `press_key` → `get_app_state`; the final response reported that Calculator
  showed 7. Debug session: `CU-6EE003523304`.
- `[Verified]` The bundled Computer Use integration independently observed Calculator and read
  the display value as 7.
- `[Verified]` Quit/reopen restored the user turn, tool calls, collapsed raw output, and assistant
  result. New conversation removed the persisted session.
- `[Verified]` Stop cancelled a deliberately delayed provider response and appended `Stopped.`
  while showing one generic floating Working/Stop surface. Debug session: `CU-031A4F2312E4`.
- `[Verified]` A deliberately delayed task continued after the Suniye window was closed. The app
  remained running, did not reopen or focus the conversation, completed in the background, and
  restored the result when manually reopened. Debug session: `CU-83846183223F`.
- `[Verified]` Accessibility and Screen Recording were granted, and the dedicated shortcut was
  configured as `Control + Command + U`.
- `[Not exercised]` The bundled driver cannot hold and release a global shortcut, so it cannot
  produce a real microphone recording. The source route and failure/restart boundaries are
  covered by tests, but the final speech-to-action leg needs user participation.
- `[Not exercised]` A real remote provider credential was not copied from Magic Format. The local
  loopback credential was cleared and the temporary server removed after the run.

### Shared OpenRouter real-provider run — 2026-08-12

- `[Verified]` The final installed Preview showed provider `OpenRouter`, model
  `openai/gpt-5.6-luna`, and `OpenRouter API key shared with Magic Format.` No dedicated Computer
  Use key was required.
- `[Verified]` Natural task `Open Calculator, enter 42, and tell me what the display shows.`
  completed as session `CU-22D0FF4454A7` through the real provider.
- `[Verified]` The run made seven calls: `get_app_state`, `click`, `get_app_state`, `click`,
  `get_app_state`, `click`, `get_app_state`. It returned `The Calculator display shows **42**.`
- `[Verified]` A separate bundled Computer Use observation read Calculator's
  `StandardInputView;value:42` and AX display value `42`.

### Physical voice boundary — 2026-08-12

- `[Verified]` The bundled Computer Use driver inspected the final installed General page and
  confirmed `Hold to Run Task` is configured as `Control + Command + U`. The selected system input
  resolves to the WH-1000XM4 Bluetooth microphone.
- `[Verified live, earlier process]` App logs from a user-operated shortcut run record the global
  hotkey down/up callbacks, production audio capture, 1.82 seconds of usable audio, local
  transcription, and a 13-character transcript. The Computer Use page then showed the captured
  task waiting for configuration instead of inserting it into another app.
- `[Verified separately]` After the credential correction, the same app-owned coordinator and real
  Luna provider completed the Calculator action E2E described above.
- `[Not yet one continuous E2E]` The bundled driver explicitly supports only app-scoped key input;
  it cannot hold/release Suniye's global shortcut or generate microphone speech. A final
  user-operated hold–speak–release run is required to prove the complete chain in one session.

### Refreshed Preview UI smoke — 2026-08-03

- `[Verified]` After reinstalling and relaunching `/Users/kishan/Applications/Suniye Preview.app`,
  the Computer Use page exposes the direct voice instruction: “Hold your dictation hotkey, speak
  a task, and release. The agent starts automatically after transcription.”
- `[Verified]` The refreshed page still shows the configured model and Computer Use permission
  rows, and does not expose the removed manual action or approval controls.
- `[Not exercised]` This UI smoke did not record microphone audio, submit a voice task, or send a
  model request.

## Fresh-branch live provider and launch checks — 2026-08-09

Build: Debug Preview installed at `/Users/kishan/Applications/Suniye Preview.app` from
`kis-169-computer-use-parity`.

- `[Verified]` The configured `openai/gpt-5.6-luna` model completed a System Settings Battery task
  and reported Battery Health as `Normal` after one app listing and one state observation.
- `[Verified]` `Use Calculator to calculate 17 times 19 and tell me the result.` completed with
  `323`. Its 23 model-tool calls alternated each action with a fresh `get_app_state`.
- `[Verified]` After Calculator was quit, `Open Calculator and tell me the number currently shown.`
  cold-launched and observed it using one successful `get_app_state` tool call, with no app-list
  recovery call.
- `[Verified]` The current page renders user tasks and assistant results in the transcript; model
  output does not populate the composer.
- `[Not exercised]` Every individual action type, physical intervention, permission denial,
  provider/native error recovery, Stop, and live microphone initiation remain for the final E2E
  matrix.
