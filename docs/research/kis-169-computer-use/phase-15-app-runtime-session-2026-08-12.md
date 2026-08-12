# Phase 15: app-level runtime and durable current session

Date: 2026-08-12

## Problem corrected

- `[Verified]` The coordinator previously belonged to `MainWindowView`. Closing that window
  destroyed the active Computer Use runtime and its in-memory conversation.
- `[Verified]` Direct voice routing previously depended on a weak page-owned callback. Leaving the
  Computer Use page removed the callback and canceled a queued transcript.
- `[Verified]` The conversation, including tool arguments and raw tool results, was not restored
  after process restart.

## Implementation

- `[Implemented]` `AppState` now owns one `ComputerUseCoordinator`. `MainWindowView` and
  `ComputerUsePage` observe that shared coordinator instead of constructing page-local runtime
  state.
- `[Implemented]` Page visibility now selects the destination of the existing dictation hotkey. It
  does not own or cancel the Computer Use task. A transcript already handed to the coordinator
  continues after the page or main window closes.
- `[Implemented]` The coordinator restores its current conversation on initialization and saves
  every conversation mutation through a `ComputerUseConversationStoring` boundary.
- `[Implemented]` The production store writes ordered JSON atomically on a serial background
  queue. It stores the complete local timeline, including exact tool arguments and raw tool
  output, and removes the file when New conversation clears the session.
- `[Implemented]` Preview and stable builds use separate storage directories derived from their
  bundle identifiers.
- `[Independent choice]` Suniye stores the current session at
  `Application Support/Suniye/computer-use/<bundle-id>/current-session.json`. The inspected
  reference establishes ordered thread context, but it does not prescribe a reusable Swift
  persistence format for Suniye.

## Scope boundary

- `[Retained temporarily]` This slice still initializes Computer Use from the existing remote
  model configuration. Dedicated Computer Use provider, endpoint, model, and credential settings
  are a separate next slice and this temporary coupling is not the intended final design.
- `[Not added]` No application matcher, target lock, forced window activation, automatic main
  window opening, new approval rule, or browser-specific branch was introduced.
- `[Not yet implemented]` The dedicated global Computer Use voice hotkey, 50-message normalized
  model context, active-run spoken intervention, and floating background task UX remain later
  slices.

## Validation

- `[Verified]` Focused storage, coordinator, and AppState voice-routing tests pass.
- `[Verified]` The full suite passes 1,098 tests with 2 skipped and zero failures.
- `[Verified]` Gated coverage is 88.35% (13,558/15,346 lines), above the 80% floor.
- `[Verified]` E2E preflight and smoke pass.
