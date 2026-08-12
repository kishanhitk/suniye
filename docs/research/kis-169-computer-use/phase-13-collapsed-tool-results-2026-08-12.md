# Phase 13: collapsed inline tool results

Date: 2026-08-12

## Outcome

- `[Implemented]` Each inline tool-call row is updated in place with the exact encoded result that
  Suniye sends back to the model.
- `[Implemented]` Completed tool calls become disclosure rows. The existing raw tool name and raw
  JSON parameters remain visible; the raw result starts collapsed beneath them.
- `[Implemented]` Expanding a row shows the full selectable monospaced result. This includes
  `null` for successful actions, encoded app lists and app states, and encoded error objects.
- `[Implemented]` The pending call and completed result share a private activity identifier, so
  completion updates one row instead of adding another timeline item.
- `[Retained]` Activity rows remain excluded from later model conversation context. The model
  already receives its tool result through the typed request sequence; the UI is only a view of
  that same payload.
- `[Retained]` The UI does not add lifecycle, provider, HTTP, request-count, result-summary,
  per-tool icon, or separate completion rows.

## Validation

- `[Verified]` Agent tests confirm that the activity sink receives one pending activity followed
  by a completed activity with the same identifier and exact encoded result.
- `[Verified]` Coordinator tests confirm that pending and completed events produce one inline row
  between the user and assistant messages.
- `[Verified]` A failed native call is published as the same encoded error object sent back to the
  model.
- `[Verified live]` The installed Preview rendered all completed calls as collapsed disclosure
  rows during session `CU-B4C2E8F64CFC`.
- `[Verified live]` Expanding the `set_value` row revealed its exact output, `null`; collapsing it
  hid the output again. A `get_app_state` row exposed the complete encoded app, screenshot URL, and
  Accessibility text when expanded.
- `[Verified]` The full suite executes 1,094 tests with 2 skipped and 0 failures. Gated coverage is
  88.24% (13,453/15,246), above the 80% floor. E2E preflight and smoke pass.

## Files

- `Suniye/Services/ComputerUseActivity.swift`
- `Suniye/Services/ComputerUseAgent.swift`
- `Suniye/Services/ComputerUseCoordinator.swift`
- `Suniye/Views/MainWindow/ComputerUseChatComponents.swift`
- `SuniyeTests/ComputerUseAgentTests.swift`
- `SuniyeTests/ComputerUseCoordinatorTests.swift`
