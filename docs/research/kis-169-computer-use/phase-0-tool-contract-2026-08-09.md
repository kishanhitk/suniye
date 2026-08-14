# Phase 0: desktop tool contract

Date: 2026-08-09

Branch: `kis-169-computer-use-parity`

## Scope

This phase establishes only the Swift domain contract and dispatch seam for desktop Computer Use.
It intentionally does not implement native macOS behavior, model integration, orchestration, or UI.

## Evidence labels

- `[Verified]` is directly established by recovered reference evidence or a passing test.
- `[Implemented]` exists in the fresh Suniye branch.
- `[Planned]` has not been implemented yet.

## Contract

- `[Verified]` The reference desktop capability exposes exactly `list_apps`, `get_app_state`,
  `click`, `perform_secondary_action`, `set_value`, `select_text`, `scroll`, `drag`, `press_key`,
  and `type_text`.
- `[Implemented]` `ComputerUseToolName` preserves those exact operation names.
- `[Implemented]` `ComputerUseToolCall` gives each operation a typed Swift representation.
- `[Implemented]` Clicks require either an AX element index or screenshot coordinates. Invalid
  combinations are not representable in the normalized domain model.
- `[Implemented]` `ComputerUseToolServing` is the async boundary that later native macOS services
  must implement.
- `[Implemented]` `ComputerUseSession` serializes and dispatches calls through that boundary.

## Target behavior

- `[Verified]` Every observation and action in the recovered public API carries its own `app`
  argument. There is no public session-wide target lock.
- `[Implemented]` The dispatcher neither infers a target nor requires an exact app string to match
  an earlier call. Display names, paths, and bundle identifiers remain backend concerns.
- `[Planned]` The agent loop will require a successful current observation before asking the model
  for an action batch. After that batch, it will observe again before another model decision.

## Wire compatibility boundary

The recovered JavaScript API uses optional fields, defaults, snake-case names, and short aliases.
The Swift types in this phase are normalized domain types, not the JSON wire DTOs.

- `[Planned]` A model-tool decoder will accept the recovered wire shape and defaults.
- `[Planned]` The decoder will normalize direction and mouse-button aliases.
- `[Planned]` It will reject missing or conflicting click targets before calling the dispatcher.

This split keeps malformed model output outside native action code without changing the public tool
contract presented to the model.

## Quality review corrections

The strict maintainability review produced three corrections:

1. Removed actor state that existed only for test inspection.
2. Replaced the optional click field bag with a typed target.
3. Removed a cancellation check after backend completion because an action may already have occurred.

A subsequent parity check removed a fourth issue: the dispatcher no longer keeps an exact-string
active-app set, because that would create an unrecovered target restriction.

## Tests

`ComputerUseProtocolTests` verifies:

- the exact ten operation names;
- every call-to-operation-name mapping;
- app discovery without target selection;
- no exact app-identifier target lock;
- routing and normalized arguments for all eight actions.

Focused result: `[Verified]` 5 passed, 0 failed.

Repository result: `[Verified]` 989 tests executed, 1 skipped, and 0 failed. Gated line coverage is
95.20% (11,177/11,741 lines) at the requested 95% threshold. The existing E2E preflight and smoke
checks pass.

## Explicitly absent

- `[Planned]` running and recent application catalog;
- `[Planned]` app identity resolution and background launch;
- `[Planned]` window discovery and background capture;
- `[Planned]` AX rendering, revisions, diffs, and element lookup;
- `[Planned]` native semantic and synthesized input actions;
- `[Planned]` model request construction and agent loop;
- `[Planned]` permission, approval, cancellation, and intervention UX;
- `[Planned]` chat UI and end-to-end testing.
