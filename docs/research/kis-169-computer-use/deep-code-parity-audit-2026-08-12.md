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
- `[Verified correction]` Suniye now reconstructs completed activity as ordered function-call and
  result pairs, retains the latest observation and recent screenshot messages, and compacts the
  provider payload under message and token budgets. It still cannot retain encrypted reasoning
  items because its transport does not expose them.
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

## App lifecycle, voice entry, and configuration

- `[Verified]` Computer Use in Suniye is now owned by `AppState`, not by the page. Closing the
  window does not cancel a run, switch its target to the host app, or reopen the conversation.
- `[Verified]` The installed Preview completed a delayed three-tool run while its main window was
  closed. The process remained alive and restored the completed conversation when reopened.
- `[Implemented]` The dedicated optional global shortcut owns its hold/release recording path and
  routes locally transcribed text directly to the app-owned coordinator. It does not invoke Magic
  Format, clipboard insertion, normal dictation history, or page navigation.
- `[Implemented]` A transcript received during a run enters the same session as a user
  intervention. The agent discards stale model output or completes the current atomic native
  action, then obtains a fresh app observation before requesting another decision.
- `[Implemented]` Provider, endpoint, model ID, timeout, token limit, and connection test are
  independently configurable. By explicit product direction, OpenRouter has one shared credential
  across Magic Format and Computer Use. The separate Computer Use credential applies to OpenAI and
  Custom only and is never selected for OpenRouter.
- `[Unknown]` The artifact does not expose a host global-shortcut default, voice-intervention
  queue, pending-transcript persistence format, or exact microphone-to-task UX. Suniye's shortcut,
  one-pending-task file, and floating indicator are independent choices constrained by the
  recovered run lifecycle.
- `[Verified]` Startup reads the Computer Use TCC permission snapshot without prompting. A queued
  local transcript is persisted before configuration/permission checks and survives coordinator
  recreation; it is cleared only after run acceptance or explicit reset/cancellation.

## Durable conversation and model hygiene

- `[Implemented]` Suniye keeps one durable current conversation until New conversation. The local
  record preserves complete tool arguments and raw results for the collapsed UI.
- `[Implemented]` Provider context is separately normalized to at most 50 messages. Function
  call/result pairs stay grouped; the current instruction and latest observation are retained;
  missing local images are dropped; only recent useful screenshots are attached.
- `[Implemented]` Model-visible app-state output removes local screenshot URLs and preserves the
  screenshot as an image part. Success results remain minimal, AX diffs remain available, and
  oversized tool output uses the recovered model-aware truncation policy.
- `[Verified gap]` Suniye cannot reproduce encrypted reasoning retention, server-generated
  compaction items, or provider-private context mutation through its portable Chat Completions
  transport.

## Final validation state

- `[Verified live]` Installed session `CU-6EE003523304` completed a natural Calculator task with
  `get_app_state`, `press_key`, and a fresh `get_app_state`; an independent observation confirmed
  the display value. Persistence/reset, delayed-request Stop, and closed-window continuation were
  also exercised in the installed Preview.
- `[Verified]` The final full suite passes 1,139 tests with 2 skipped; gated line coverage is
  87.05%, and sequential E2E preflight/smoke pass.
- `[Not exercised]` The bundled app-scoped Computer Use driver cannot hold and release Suniye's
  global shortcut or supply live microphone speech. The physical voice-to-action leg therefore
  still needs a user-operated run; code-level routing, queuing, cancellation, and restart cases
  are covered by focused tests.

## Result

The ten-tool public capability, observable native action loop, app-level run lifecycle, durable
session, independent model configuration, and direct local voice routing are implemented. The
remaining known differences are architectural or unrecoverable: Responses/persistent JavaScript
versus direct Chat Completions tools, encrypted reasoning and server compaction items, helper
IPC/private capture internals, cursor compositing, and exact host voice UX. The physical global
hotkey/microphone leg also remains a live validation boundary. These must not be described as exact
parity without stronger evidence and matching validation.
