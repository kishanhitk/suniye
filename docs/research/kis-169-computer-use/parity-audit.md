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
model client, cancellation, and intervention checks.

Suniye does not have full reference parity. The reference has a separate native service and
client, versioned IPC, richer screenshot and Accessibility state handling, native service
permission/session errors, app launch, indexed actions with dynamic Accessibility action names,
and a separate browser adapter.

## Parity matrix

| Area | Suniye now | Reference evidence | Status |
|---|---|---|---|
| App discovery | Running `NSRunningApplication` records with process identity | `list_apps` returns app records and targetable windows; `launch_app` is public | Partial |
| Window discovery | On-screen layer-zero windows from `CGWindowListCopyWindowInfo`; user can select a window | `list_windows`, app-owned window objects, and window rehydration by id | Partial |
| Window activation | Explicit “Bring Forward” UX and activation before an agent run | `activate_window`; input methods also activate their target | Partial; live TCC test pending |
| AX observation | Bounded tree, indexes, roles, values, bounds, enabled/focused/selected state, exposed actions | AX tree text, focused/selected/document state, refetchable tree, optional diff | Partial |
| Screenshot | Optional bounded PNG from the selected window with an id, dimensions, origin, and z-order | Stable screenshot ids, dimensions, origin, z-order, and related transient captures | Partial |
| Coordinate actions | Window-relative click, click count, mouse button, drag, and positioned scroll | Window-relative coordinate click, drag, and scroll | Broad parity |
| Keyboard and text | Key chords, text insertion, AX set value, text selection | `press_key`, `type_text`, `set_value`, `select_text` | Broad parity |
| Accessibility actions | Indexed clicks, typed AX actions, and arbitrary exposed AX action names | Indexed click and arbitrary exposed `perform_secondary_action` | Broad desktop parity; native behavior still needs live validation |
| Model loop | Observe, decide, approve, act, settle, re-observe; bounded retries and limits | State capture, one action, settle/refetch, and next decision | Broad conceptual parity |
| Approval and safety | Once/session/always policy scopes, revocation, redacted audit, stop, and intervention guard | App policy, approval bridge, confirmation taxonomy, handoff rules | Partial; product taxonomies differ |
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
- Agent startup activates the selected window before the first observation. Later frontmost/window
  changes still stop the run as user intervention.
- Always-allowed approvals have a visible list and revocation confirmation. The list refreshes
  after the approval is actually stored.
- The platform runner is isolated from the MainActor coordinator.
- Stale `application.isActive` data no longer marks a window as current. Current frontmost state
  comes from the live frontmost-process provider.

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
allowed app management. Suniye still limits the target list to eligible running apps and does not
yet provide an installed-app launcher or an app allow-list editor. This is a known UX gap, not an
unknown implementation detail.

## Next parity work

1. Add installed-app discovery and an explicit launch flow if Suniye should match the reference
   `list_apps`/`launch_app` surface.
2. Decide whether helper isolation is required. If yes, define and test one versioned Swift IPC
   contract before adding a helper target.
3. Run live macOS tests with Accessibility and Screen Recording on a deterministic target app.
4. Design browser control as a separate adapter after a separate browser audit.
