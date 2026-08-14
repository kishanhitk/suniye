# Phase 10: Minimal inline tool activity

Date: 2026-08-11
Branch: `kis-169-computer-use-parity`

## Goal

Show the model's tool use in the normal conversation timeline without turning the chat into a
transport log or debug console.

## Implemented

- `[Implemented]` Each model-issued tool call appears in order between the user's task and the
  final assistant response.
- `[Implemented]` Each activity is one selectable monospaced text row containing only the raw tool
  name and the raw JSON argument string supplied by the model.
- `[Removed]` Model request and response payloads, HTTP metadata, lifecycle events, tool results,
  error payloads, expandable details, connector lines, and per-tool icons are not shown.
- `[Implemented]` Explicit Stop adds only the assistant response `Stopped.`; it does not add a
  separate lifecycle activity.
- `[Implemented]` Activity entries are presentation-only. They are excluded when conversation
  history is converted back into model messages.
- `[Unchanged]` Provider requests, tool results, screenshots, errors, and lifecycle events continue
  to participate in the agent loop and diagnostics where required. This change only limits what is
  rendered in chat.

## Verification

- `[Verified]` Focused agent, coordinator, and remote-model validation executes 19 tests with zero
  failures.
- `[Verified]` The full suite executes 1,090 tests with 2 skipped and 0 failures. Gated coverage is
  88.44% (13,420/15,174 lines) against the 80% floor.
- `[Verified]` Installed Preview session `CU-616B85F2116D` rendered the natural model-issued call
  `get_app_state  {"disableDiff":true,"app":"Preview"}` as one plain text row between the user
  task and final assistant message.
- `[Verified]` The live Accessibility tree and screenshot contain no activity icon, lifecycle row,
  model request or response, tool result, connector, disclosure, or separate completion row.
- `[Observed]` The model interpreted `Suniye Preview` as the separate app named `Preview`, so the
  task's answer was semantically wrong. That provider/app-name ambiguity is independent of this
  activity-presentation correction and was not masked with deterministic client logic.
