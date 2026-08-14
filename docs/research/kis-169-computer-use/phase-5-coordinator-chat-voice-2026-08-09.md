# Phase 5: Coordinator, conversation, permissions, and direct voice

Date: 2026-08-09

This note records the fresh branch's connection from the Phase 4 provider-backed agent to Suniye's
main-window Computer Use experience. It separates recovered facts from independent host-product
choices.

## Reference boundary

- `[Verified]` The recovered model contract uses normal conversation context, tool calls, tool
  results, screenshots, and assistant text outcomes in one ordered loop.
- `[Verified]` The recovered native path requires Accessibility for AX/input work and Screen
  Recording for screenshot work.
- `[Verified]` Explicit cancellation is part of the model/action lifecycle.
- `[Verified]` The recovered desktop surface is app-scoped. It does not require a model-facing
  window picker or a frontmost-app target fallback.
- `[Unknown]` The artifact does not expose the complete host application's SwiftUI/AppKit
  conversation implementation, permission-pane deep links, or direct-dictation routing code.

## Implemented service boundaries

### `ComputerUseCoordinator`

- `[Implemented]` A `@MainActor`, observable coordinator owns UI-facing phase, permissions,
  composer draft, conversation history, errors, pending voice work, and one active run.
- `[Implemented]` The coordinator creates the actor-backed agent from the current user-selected API
  endpoint model configuration. A running agent captures its configuration; a later settings
  change applies to the next run.
- `[Implemented]` Each run receives prior conversation and the current instruction exactly once.
  The user message enters the transcript and the composer clears before execution.
- `[Implemented]` A generated run ID prevents a cancelled or superseded task from publishing a
  stale result. Stop cancels the task and appends `Stopped.` to the transcript.
- `[Implemented]` Empty tasks, missing model configuration, and missing permissions fail before
  agent creation.

### Permission services

- `[Implemented]` `SystemComputerUsePermissionService` wraps `AXIsProcessTrusted`,
  `AXIsProcessTrustedWithOptions`, `CGPreflightScreenCaptureAccess`, and
  `CGRequestScreenCaptureAccess`.
- `[Implemented]` Permission refresh and request operations use generation IDs so an older async
  result cannot replace newer state.
- `[Independent choice]` `SystemComputerUsePermissionSettingsOpener` tries the modern and legacy
  System Settings URLs for Accessibility and Screen Recording. This is a recovery convenience,
  not a recovered native-helper algorithm.

### Direct voice

- `[Implemented]` `ComputerUseVoiceTaskHandling` is a narrow bridge from `AppState` to the visible
  coordinator.
- `[Implemented]` While the Computer Use page is registered, the normal hold-to-talk lifecycle
  sends its raw local transcript to Computer Use. It skips Magic Format, clipboard output,
  focused-app insertion, submit-key handling, and dictation history.
- `[Implemented]` Voice work starts immediately when ready or queues while model configuration or
  permission preparation completes. A second pending/running voice task is rejected.
- `[Independent choice]` Visible-page routing and its queue behavior are Suniye product choices;
  exact equivalent host behavior is unknown.

## Conversation UX

- `[Implemented]` The main navigation includes a Computer Use page with transcript, fixed composer,
  and new-conversation action.
- `[Implemented]` User messages use a trailing bubble. Assistant messages use a leading mark and
  plain selectable text. Assistant output never writes into the composer.
- `[Implemented]` During execution, the composer control becomes the only Stop control and the
  transcript shows generic shimmering `Working` text.
- `[Implemented]` Model and permission setup are grouped into one collapsed disclosure below the
  conversation. There is no target picker, target lock, frontmost fallback, manual action panel,
  approval card, or observation/debug panel.
- `[Independent choice]` This is a close conversation-first macOS design, not a claim that hidden
  host view code was recovered.

## Strict review corrections

- `[Corrected]` A 390-line page was split into page, chat-components, and settings-disclosure
  files with narrow responsibilities.
- `[Corrected]` Model changes are retained for the next run instead of being discarded while an
  agent is active.
- `[Corrected]` Concurrent permission operations cannot publish stale snapshots.
- `[Corrected]` A voice task arriving during permission preparation queues instead of failing as
  generically busy.
- `[Corrected]` Denied permission states expose direct System Settings recovery.

## Validation

- `[Verified]` Focused coordinator and voice tests pass.
- `[Verified]` The full suite executes 1,064 tests with 2 skipped and 0 failures.
- `[Verified]` Gated coverage is 89.32% (12,938/14,485 lines), above the requested 80% floor.
- `[Verified]` `e2e_preflight.sh` and `e2e_smoke.sh` pass.
- `[Verified]` The new production files contain no user-facing or source-level mention of the
  inspected reference products.

## Remaining work

- `[Not implemented]` Physical-user intervention handling.
- `[Not implemented]` Lock-screen guarding and recovery.
- `[Not implemented]` Loading-aware extended settling.
- `[Live required]` Installed Preview permission identity, model routing, screenshot capture,
  cross-process input, Stop, direct voice, and visual interaction.
- `[Deferred]` Browser control remains a separate extension/DOM capability and is not added to the
  recovered ten-tool desktop contract.
