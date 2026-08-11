# Deep code parity audit

Date: 2026-08-12

Scope: three independent code-level audits of the inspected DMG and the current Suniye branch:
model/runtime composition, native app/window/action mechanics, and desktop cursor/UX lifecycle.

## Contract and model loop

- `[Verified]` Both implementations expose the same ten app-scoped operations: `list_apps`,
  `get_app_state`, `click`, `type_text`, `scroll`, `press_key`, `drag`, `set_value`,
  `select_text`, and `perform_secondary_action`.
- `[Verified]` The inspected runtime exposes those operations through persistent `node_repl` state
  backed by `@oai/sky`. Its active model path uses the Responses API, streams the response, disables
  parallel tool calls, and preserves ordered response items and encrypted reasoning across turns.
- `[Verified]` Suniye currently exposes the same operation shapes as direct Chat Completions
  function tools. It permits one tool call per model decision and rejects a response containing
  multiple tool calls.
- `[Verified]` The inspected operating instructions begin with `get_app_state` when the target app
  is known, use `list_apps` only when the app cannot be identified or a bundle-ID retry is needed,
  prefer AX element indices, use screenshots when AX is incomplete, and reobserve after one or
  more actions before deciding what to do next.
- `[Verified]` Suniye's prompt now carries the same behavioral rules where its transport permits
  them. Since each Suniye model decision can contain only one tool call, every action consumes its
  observation and the next action requires a new `get_app_state` decision.
- `[Verified]` Suniye attaches a captured screenshot directly to the next provider request. The
  inspected persistent JavaScript runtime instead makes screenshot emission explicit through
  `nodeRepl.emitImage`.
- `[Verified gap]` Suniye flattens earlier user/assistant conversation turns to text and does not
  retain the inspected runtime's complete ordered tool, image, and reasoning-item history.
- `[Verified gap]` Suniye uses a provider-portable Chat Completions endpoint rather than the
  inspected Responses API plus persistent JavaScript execution boundary. The tool semantics are
  aligned, but the transport and context representation are not identical.
- `[Unknown]` Provider-private routing, inference, and server-side transformations are not present
  in the client artifact.

## Native app, window, observation, and action behavior

- `[Verified]` The inspected API targets an application by display name, bundle identifier, or
  path. It does not expose a window picker or a caller-selected window ID.
- `[Verified]` The inspected helper enumerates on-screen non-desktop CG windows, correlates them
  with AX windows, waits for a primary window after a background launch, and has window-created,
  main-window-changed, focused-window-changed, and bounds-change observation machinery.
- `[Verified live]` After System Settings changed panes/windows, the inspected runtime reacquired
  the replacement window in the same process and returned a fresh AX tree and screenshot.
- `[Verified defect fixed]` Suniye previously treated a transient no-window result for a running
  app as a reason to reopen it. That produced a false `launchFailed` result. Suniye now waits for a
  replacement on-screen window in the same process, then observes again. If none appears, it
  reports `noWindow`; it reserves `launchFailed` for actual launch failures.
- `[Verified]` Suniye retains the stale-window action guard. An action authorized by the old
  window is rejected and cannot silently execute against its replacement; the next model step
  must observe again.
- `[Verified correction]` The temporary all-window/off-screen discovery and screenshot fallback
  was removed. The recovered normal path uses on-screen, non-desktop windows. The exact private
  SkyLight fallback matrix remains unknown.
- `[Verified]` Both implementations prefer semantic Accessibility operations and have
  process-scoped synthesized input fallbacks. Suniye posts click, drag, scroll, typing, and key
  events to the selected process without forcing that app to the front.
- `[Unknown]` The exact native comparator for every multi-window edge case, every AX observer
  wake-up ordering detail, and the complete private screenshot backend selection matrix are not
  recoverable from the public JavaScript contract.

## Cursor and conversation UX

- `[Verified]` The inspected desktop helper owns cursor-active and cursor-location state, a
  dedicated cursor window, a compiled software cursor asset, and host bridge state. The browser
  `AgentCursor` is a separate implementation and is not evidence for the native desktop cursor.
- `[Verified live]` Once the inspected desktop cursor has performed a pointer action, it remains
  at that location while the model reasons. The next pointer action animates from the retained
  position instead of making the cursor disappear and reappear.
- `[Implemented]` Suniye now follows that run-scoped lifecycle. Its overlay has no action-local
  hide timer; the last cursor point remains visible between model calls and observations. Stop,
  completion, failure, and New Conversation end the cursor session and clear the retained point.
- `[Verified]` Before the first pointer action, neither observed implementation invents a cursor
  location.
- `[Verified gap]` Suniye uses an independent transparent `NSPanel` and does not composite the
  virtual cursor into its captured screenshot. The inspected helper has host/PIP and cursor-state
  plumbing, but the exact mounted-build screenshot-compositing branch is unknown.
- `[Unknown]` Exact animation duration/easing and cursor behavior during Spaces/display topology
  changes are not recoverable. Suniye uses restrained independent constants and does not claim
  numerical identity.

## Result

The ten-tool public capability and the observable native action loop are aligned. The latest
evidence-backed corrections are persistent run-scoped cursor state, process-scoped input, strict
fresh observation per Suniye model decision, and same-process replacement-window reacquisition.
The remaining known differences are architectural: Responses/persistent JavaScript versus direct
Chat Completions tools, richer ordered turn history, helper IPC/private capture internals, and
cursor compositing. They must not be described as exact parity unless Suniye adopts and validates
equivalent architecture.
