# Computer Use parity audit

Date: 2026-08-03

Reference: `/Users/kishan/Downloads/ChatGPT (1).dmg`

Mounted reference paths used in this audit:

- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/docs/sky-window2-api.md`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/docs/sky-window-api.md`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/skills/computer-use/SKILL.md`
- `/Users/kishan/.codex/worktrees/eaaa/suniye/docs/research/kis-169-computer-use/parity-audit-dmg-agent.md`

This is a behavior and boundary comparison. It does not copy source code from the reference.

## Result

Suniye has a working same-process desktop prototype. It has app discovery, internal native window
resolution, Accessibility state, screenshots, typed actions, automatic policy authorization, an
agent loop, a configured model client, cancellation, per-step app targeting, and target activation
before input. Historical implementation details elsewhere in this file are superseded by the
final cleanup entry.

Suniye does not have full reference parity. The reference has a separate native service and
client, versioned IPC, richer screenshot and Accessibility state handling, native service
permission/session errors, per-call app targeting, indexed actions with dynamic Accessibility
action names, and a separate browser adapter.

## Parity matrix

| Area | Suniye now | Reference evidence | Status |
|---|---|---|---|
| App discovery | Running `NSRunningApplication` records plus installed app candidates; async launch by bundle ID or display name | The macOS `list_apps`/`get_app_state` API accepts an app per call; `get_app_state` can launch a non-running app in the background. `launch_app` belongs to the documented Windows `Window2` API. | Partial |
| Window discovery | Internal on-screen layer-zero resolution from `CGWindowListCopyWindowInfo`; no user-facing window selection | The public macOS API is app-level; the native service resolves app windows. Explicit `Window` records and `list_windows` belong to the documented Windows `Window2` API. | Partial |
| Window activation | Internal per-observation/per-action target activation; no Bring Forward UX | Input methods activate their target; explicit `activate_window` belongs to the Windows-shaped API | Partial; Suniye self-target passes, cross-process TCC test pending |
| AX observation | Bounded tree, indexes, roles, values, bounds, enabled/focused/selected state, exposed actions | AX tree text, focused/selected/document state, refetchable tree, optional diff | Partial |
| Screenshot | Mandatory PNG from the resolved app window with MIME type and dimensions | Mac state returns a screenshot URL and text; screenshot IDs/origin/z-order are Windows-shaped fields | Partial |
| Coordinate actions | Window-relative click, click count, mouse button, drag, and positioned scroll | Window-relative coordinate click, drag, and scroll | Broad parity |
| Keyboard and text | Key chords, text insertion, AX set value, text selection | `press_key`, `type_text`, `set_value`, `select_text` | Broad parity |
| Accessibility actions | Indexed clicks, typed AX actions, and arbitrary exposed AX action names | Indexed click and arbitrary exposed `perform_secondary_action` | Broad desktop parity; self-target observation passes, cross-process behavior pending |
| Model loop | Observe, decide, automatic policy authorization, act, settle, re-observe; no local action/failure/time caps | State capture, one action, settle/refetch, and next decision | Broad conceptual parity |
| Approval and safety | Once/session/always policy scopes, revocation, redacted audit, and explicit stop | App policy, approval bridge, confirmation taxonomy, handoff rules | Partial; product taxonomies differ |
| Permissions | Accessibility and Screen Recording checks and request buttons | Native session permission states and helper-owned permission lifecycle | Partial |
| Process boundary | All current services run in Suniye | Node client plus separate native service/client bundles | Missing |
| IPC | No Computer Use helper transport | Framed JSON-RPC native pipe and an exposed XPC path | Missing |
| Browser control | No tabs, DOM, Playwright, extension, or CDP adapter | Separate browser plugin and browser session surfaces | Missing by design |

## Corrective implementation in this slice

The following list records the earlier corrective implementation state; the superseding cleanup entry
at the end of this document is authoritative for the current branch:

- `ComputerUseAction` now supports click metadata, positioned scroll, drag, AX value setting, and
  text selection. Coordinate actions can carry and validate the current screenshot ID.
- Indexed clicks and arbitrary exposed Accessibility action names are validated against the latest
  observation and require the same approval and generation checks as other actions.
- Coordinate validation and conversion use the selected window’s local origin.
- The target UI lists windows and has an explicit Bring Forward action.
- Agent startup uses the selected app/window as optional initial context. Later model target
  decisions can select another app/window without ending the run.
- Each input action activates its observed app/window immediately before posting input. This keeps
  coordinate and keyboard events directed at the requested target without requiring that target
  to remain frontmost between model turns.
- Policy authorization is automatic in the current testing mode. No approval prompt or
  always-allowed approval list is exposed in the Preview surface.
- The platform runner is isolated from the MainActor coordinator.
- Stale `application.isActive` data no longer marks a window as current. Current frontmost state
  comes from the live frontmost-process provider.

## Target-scope correction and implementation: 2026-08-03

The current Suniye session has a stricter target lock than the inspected macOS reference.

- `[Verified]` The previous Suniye implementation bound an agent task to one `applicationID` and
  one `windowID`.
- `[Verified]` The previous implementation stopped when the frontmost process changed or the
  selected window was no longer key. That intervention monitor was a Suniye restriction, not a
  required reference behavior.
- `[Verified]` The reference macOS `sky-window-api.md` has no session-wide target parameter. Each
  `get_app_state` and input action accepts an `app` value.
- `[Verified]` The reference Computer Use skill says `get_app_state` transparently launches an
  app when it is not running.
- `[Verified]` The reference applies app policy and approval per operation. This is the safety
  boundary that the Suniye prototype should preserve.
- `[Inferred]` The reference model can move from one app to another by making a new app-targeted
  call, subject to policy and approval. The complete host agent loop is not visible in the DMG.
- `[Corrected]` The one-app/window session lock was a Suniye safety and implementation choice. It
  was incorrectly treated as reference parity. It prevents a task such as “open Chrome” from
  changing apps.
- `[Implemented]` `ComputerUseModelDecision.target` changes the current app/window for the next
  observation. The model receives running and installed app names and bundle identifiers.
- `[Implemented]` The observation service resolves bundle IDs, dynamic process IDs, and display
  names. It launches a resolved non-running app before reading its state.
- `[Implemented]` The action service activates the observation target immediately before input.
  Approval, per-app policy, permission checks, and observation-generation checks remain active.
- `[Remaining]` Suniye still lacks the reference's separate native-helper architecture and browser
  adapter. The reference helper's public protocol and major native mechanisms are now recovered;
  see `native-algorithm-recovery-2026-08-09.md`.

## Findings by certainty

### Verified

- The reference `sky-window2-api.md` documents app/window records, `get_window_state`, window-
  relative input, `set_value`, `drag`, `perform_secondary_action`, and `activate_window`.
- The reference old window API documents `select_text` and Accessibility action names.
- The reference Computer Use skill requires confirmation immediately before consequential impact,
  treats third-party content as untrusted, supports stop/handoff behavior, and keeps browser
  control separate.
- Suniye’s current source and deterministic tests cover the corrective behaviors listed above.

### Inferred

- A separate helper is useful when Suniye needs crash isolation, independent TCC ownership, or a
  trusted IPC peer boundary. It is not required to keep the current Swift prototype testable.
- Observation generations and screenshot identifiers now gate screenshot-grounded coordinate
  actions. The screenshot cache is still one-shot, unlike the reference transient-capture cache.
- Indexed click and dynamic secondary Accessibility actions now use the same observation generation
  and policy checks as the other typed actions.

### Unknown

- Provider-private inference, hidden classifiers, exceptional reroute decisions, and
  post-receipt transformations. Client-side model selection, exact model slug transport, static
  prompts, and runtime request ordering are recovered.
- The exact native XPC endpoint and sender-authentication algorithm.
- The final multi-window comparator, exact AX diff equality/budget rules, screenshot-backend
  selection matrix, every AX-versus-synthesized-input branch, and intervention/cancellation timing
  for an already-posted native event.
- The reference’s full release permission and approval policy.
- Whether Suniye’s Core Graphics capture is equivalent to ScreenCaptureKit for all Retina,
  multi-display, and transient-window cases.
- Whether the current native activation path succeeds for every target app under real Accessibility
  permission.

## UX comparison

Suniye now exposes the main session controls in one Computer Use page: permission status, app and
window target selection, Bring Forward, optional local screenshot capture, task entry, model
status, Stop, and automatic action execution.

The reference also exposes Computer Use settings for control scope, any-app behavior, and always-
allowed app management. Suniye exposes an optional starting-context picker. The agent can switch
targets during a run. The model receives installed-app candidates, but the picker still lists
running apps only. Suniye does not yet provide a separate installed-app launcher or app allow-list
editor. These are known UX and behavior gaps, not unknown implementation details.

## Next parity work

1. Decide whether helper isolation is required. If yes, define and test one versioned Swift IPC
   contract before adding a helper target.
2. Run live macOS tests with Screen Recording and a safe cross-process target app.
3. Design browser control as a separate adapter after a separate browser audit.

## Automatic execution and target-selection cleanup: 2026-08-03

- `[Corrected]` The window catalog no longer reorders macOS's native front-to-back window list by
  area, title, or window ID. That heuristic was Suniye-specific and was not supported by the DMG
  evidence.
- `[Implemented]` The Preview agent executes actions automatically. The temporary manual action
  surface and interactive approval mode are removed; the coordinator no longer carries pending
  approval continuation or always-approval UI state.
- `[Retained]` Policy preparation, one-time grants, approval-store validation, Accessibility and
  Screen Recording checks, observation-generation checks, target activation, cancellation, and
  action/session limits remain in the lower action boundary. These are technical enforcement
  boundaries, not a user-facing approval prompt.
- `[Verified]` The focused Computer Use suite passes after this cleanup.
- `[Unknown]` The exact reference confirmation taxonomy and its model-side integration remain
  unknown beyond the inspected policy wrapper and Computer Use confirmation document. The current
  Preview default is intentionally automatic for testing.

## Manual action surface cleanup: 2026-08-03

- `[Verified]` The inspected macOS reference exposes app-scoped state and action methods through
  its model-facing client. It does not expose the temporary Suniye manual action panel.
- `[Implemented]` Suniye removes the manual action panel, direct coordinator action requests, and
  action-only coordinator phases. Actions now enter through the automatic agent loop.
- `[Retained]` The typed action contract, policy authorization, native action service, target
  activation, cancellation, and fresh observation loop remain.
- `[Verified]` The focused Computer Use test run reports 67 passed tests and 0 failures.
- `[Unknown]` The complete reference host UI remains outside the DMG evidence; this is parity
  cleanup of a verified-extra path, not a claim that the whole Suniye page matches ChatGPT UX.

## Reference-shaped action and screenshot cleanup: 2026-08-03

- `[Verified]` The DMG's public macOS action surface has one generic
  `perform_secondary_action` operation whose action name comes from the current Accessibility
  state. It does not expose a second hard-coded AX action enum.
- `[Implemented]` Suniye removes the redundant semantic-action enum. Dynamic secondary actions now
  carry the exact observed action label, including labels not known at compile time.
- `[Verified]` The DMG window-state API includes a screenshot by default when screenshot capture is
  requested; the inspected client has no separate upload-consent toggle.
- `[Implemented]` Suniye removes the separate remote screenshot-upload switch. The existing local
  `Include screenshot` control still determines whether a screenshot is captured and therefore
  whether one is available to the configured model endpoint.
- `[Retained]` Accessibility and Screen Recording permission checks, policy authorization,
  cancellation, target activation, and observation-generation checks remain active.

## Superseding removal of non-reference execution paths — 2026-08-03

- `[Verified]` The mounted Mac client exposes `list_apps`, app-scoped state, and app-scoped
  actions. Window picker/Bring Forward UX, a session-wide target lock, and a frontmost/window
  intervention monitor are not part of that Mac surface; Suniye removes them.
- `[Verified]` The mounted client forwards indexed clicks, scrolls, value changes, text selection,
  and arbitrary secondary Accessibility actions to the native service. Suniye removes cached
  element/action prevalidation and keeps only native-adapter shape checks.
- `[Verified]` The local agent no longer stops on action/failure/time counters. It continues until
  a model terminal decision, platform/model error, explicit cancellation, or provider timeout.
- `[Verified]` Every Suniye macOS observation captures a screenshot. The model prompt uses native
  Accessibility text and the screenshot, without a duplicate structured element dump.
- `[Verified]` The Preview page no longer exposes manual action controls, approval cards,
  screenshot-choice controls, or internal window/generation diagnostics.
- `[Unknown]` Native helper IPC, the server-side model loop/prompt, and browser control remain open
  parity work.

## Final validation correction — 2026-08-03

- `[Verified]` Full tests pass at 1,080 executed, 1 skipped, 0 failures; gated coverage is 95.02%
  (13,672/14,389 lines).
- `[Verified]` E2E preflight and smoke pass. A fresh installed Preview process no longer exposes
  the removed local-only controls.
- `[Verified]` A configured model completed a safe read-only Calculator task and reported `323`.
- `[Unknown]` Full native-helper parity, Screen Recording consent, cross-process input, the
  server-side model loop/prompt, and browser control remain unverified.

## Fresh-branch phase 3 status — 2026-08-09

This section supersedes prototype implementation claims above when evaluating
`kis-169-computer-use-parity`. See `fresh-implementation-baseline-2026-08-09.md`.

| Area | Fresh branch | Reference evidence | Status |
|---|---|---|---|
| Tool surface | Exact ten operation names, app argument per state/action call, public button/direction aliases | Shipped macOS client and native tools list | Verified observable match |
| State requirement | One successful app/window observation authorizes one action; failed refresh invalidates prior state | Recovered workflow requires updated state before the next decision; user requirement tightens this to every newly selected action | Implemented requirement; exact internal cache policy unknown |
| Indexed AX actions | Refetch by path/role/identifier; AX press, arbitrary action, value replacement, text/cursor selection; unique identifier recovery | Semantic-first native layer, refetchable tree, stale/ambiguous element handling | Broad match; exact branch conditions unknown |
| Synthesized input | Process-scoped click, drag, pixel scroll, key chord, and Unicode text events | Native synthesized-event layer and `postToPid` | Broad match; timing/calibration unknown |
| Coordinate conversion | Actual screenshot scale plus current window origin | Recovered scaling transform | Verified algorithm match |
| Background behavior | Observation and action boundaries do not require frontmost/key status or add activation | Live background observation and process-scoped input evidence | Intended match; cross-process live action pending |
| Settling | Cancellation-aware one-second wait after success | About one-second base plus loading-aware extension to about five seconds | Partial; loading extension remains |
| Intervention and focus | Cancellation checks around paired events | Native conditional focus, physical-input, lock-screen, and invalidation monitors | Partial |
| Model/agent loop | Not connected on this fresh branch | Request ordering, model selection, and prompt context recovered separately | Missing next phase |
| Permissions, voice, chat UX | Not connected on this fresh branch | Observable permission and host UX evidence recorded separately | Missing later phases |
| Browser control | No desktop-tool browser adapter | Separate browser surface | Correctly separate; extension path remains later work |

- `[Corrected]` The strict phase review removed duplicate AX cast/read code and prevented failed
  observations from preserving stale action authority.
- `[Independent choice]` Scroll calibration, Unicode event chunking, AX search limits,
  `AXScrollToVisible`, repeated semantic click behavior, and ScreenCaptureKit-only capture are not
  claimed as exact internal parity.
- `[Verified]` The post-review full suite executes 1,041 tests with 2 skipped and 0 failures; gated
  coverage is 95.38% (12,277/12,871 lines); E2E preflight and smoke pass.
- `[Live required]` Installed-Preview cross-process action results remain pending final E2E.

## Fresh-branch phase 7 live observation status — 2026-08-09

- `[Verified observable match]` A cold reference Calculator observation launches and waits for a
  primary window before returning. The fresh Suniye path now does the same without activating the
  target or adding it to recent items.
- `[Corrected]` Matching geometry takes precedence over different dynamic CG/AX titles. This fixes
  live System Settings observation without adding app-specific matching logic.
- `[Verified]` Installed live tasks read Battery Health, performed a multi-action Calculator task,
  and cold-launched Calculator. The multi-action trace required a new observation after every
  action.
- `[Independent choice]` Suniye's five-second primary-window timeout and 50-millisecond polling
  interval are not recovered reference constants.
- `[Verified]` Lifecycle diagnostics are metadata-only and exclude user/model/native payloads.
- `[Still required]` The final E2E matrix must exercise all action kinds, Stop, intervention,
  failure/permission paths, voice initiation, and final chat rendering.
