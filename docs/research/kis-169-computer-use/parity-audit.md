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

Suniye has a working same-process desktop prototype. It has app and window discovery, bounded
Accessibility state, optional screenshots, typed actions, approval, an agent loop, a configured
model client, cancellation, per-step target selection, and target activation before input.

Suniye does not have full reference parity. The reference has a separate native service and
client, versioned IPC, richer screenshot and Accessibility state handling, native service
permission/session errors, per-call app targeting, indexed actions with dynamic Accessibility
action names, and a separate browser adapter.

## Parity matrix

| Area | Suniye now | Reference evidence | Status |
|---|---|---|---|
| App discovery | Running `NSRunningApplication` records plus installed app candidates; async launch by bundle ID or display name | The macOS `list_apps`/`get_app_state` API accepts an app per call; `get_app_state` can launch a non-running app in the background. `launch_app` belongs to the documented Windows `Window2` API. | Partial |
| Window discovery | On-screen layer-zero windows from `CGWindowListCopyWindowInfo`; user can select a window | The public macOS API is app-level; the native service resolves ordered app windows. Explicit `Window` records and `list_windows` belong to the documented Windows `Window2` API. | Partial |
| Window activation | Explicit “Bring Forward” UX and per-action target activation | `activate_window`; input methods also activate their target | Partial; Suniye self-target passes, cross-process TCC test pending |
| AX observation | Bounded tree, indexes, roles, values, bounds, enabled/focused/selected state, exposed actions | AX tree text, focused/selected/document state, refetchable tree, optional diff | Partial |
| Screenshot | Optional bounded PNG from the selected window with an id, dimensions, origin, and z-order | Stable screenshot ids, dimensions, origin, z-order, and related transient captures | Partial |
| Coordinate actions | Window-relative click, click count, mouse button, drag, and positioned scroll | Window-relative coordinate click, drag, and scroll | Broad parity |
| Keyboard and text | Key chords, text insertion, AX set value, text selection | `press_key`, `type_text`, `set_value`, `select_text` | Broad parity |
| Accessibility actions | Indexed clicks, typed AX actions, and arbitrary exposed AX action names | Indexed click and arbitrary exposed `perform_secondary_action` | Broad desktop parity; self-target observation passes, cross-process behavior pending |
| Model loop | Observe, decide, approve, act, settle, re-observe; bounded retries and limits | State capture, one action, settle/refetch, and next decision | Broad conceptual parity |
| Approval and safety | Once/session/always policy scopes, revocation, redacted audit, and explicit stop | App policy, approval bridge, confirmation taxonomy, handoff rules | Partial; product taxonomies differ |
| Permissions | Accessibility and Screen Recording checks and request buttons | Native session permission states and helper-owned permission lifecycle | Partial |
| Process boundary | All current services run in Suniye | Node client plus separate native service/client bundles | Missing |
| IPC | No Computer Use helper transport | Framed JSON-RPC native pipe and an exposed XPC path | Missing |
| Browser control | No tabs, DOM, Playwright, extension, or CDP adapter | Separate browser plugin and browser session surfaces | Missing by design |

## Corrective implementation in this slice

The current branch adds the verified desktop behaviors that fit Suniye’s existing boundaries:

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
- Always-allowed approvals have a visible list and revocation confirmation. The list refreshes
  after the approval is actually stored.
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
- `[Remaining]` The exact native helper orchestration and browser adapter remain outside this
  desktop slice.

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
  and approval checks as the typed semantic action model.

### Unknown

- The reference server-side model, prompt, exact model name, and complete agent orchestration.
- The exact native XPC endpoint and sender-authentication algorithm.
- The reference’s full permission matrix, lock-screen behavior, and cancellation timing for an
  already-posted native event.
- Whether Suniye’s Core Graphics capture is equivalent to ScreenCaptureKit for all Retina,
  multi-display, and transient-window cases.
- Whether the current native activation path succeeds for every target app under real Accessibility
  permission.

## UX comparison

Suniye now exposes the main session controls in one Computer Use page: permission status, app and
window target selection, Bring Forward, screenshot consent, task entry, model status, action
approval, Stop, and always-allowed revocation.

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
