# Phase 16: global voice-to-task hotkey

Date: 2026-08-12

## Entry path

- `[Implemented]` General settings now offers an optional `Hold to Run Task` shortcut. It is
  disabled by default, can be recorded or cleared, and is monitored while Suniye runs in the
  background.
- `[Implemented]` Holding the shortcut starts the existing local microphone and ASR pipeline with
  an explicit Computer Use destination. Releasing it stops capture, transcribes locally, trims
  surrounding whitespace, and submits the raw transcript to the app-owned current conversation.
- `[Verified]` This path does not require the Computer Use page to be visible and does not open or
  focus Suniye's window.
- `[Verified]` It does not invoke Magic Format, write to the clipboard, insert into the focused
  application, or add a dictation-history record.
- `[Implemented]` Escape cancels an active Computer Use voice recording. The global and local
  Escape monitors exist only while the optional Run Task shortcut is configured, and they do not
  consume Escape when no task recording is active.

## Shortcut ownership

- `[Implemented]` `HotkeyService` has three independent Carbon slots: dictation, Edit Mode, and
  Computer Use. Each slot retains hold/release semantics and duplicate key-down suppression.
- `[Implemented]` General settings validates all three shortcuts. Run Task cannot reuse the
  dictation or Edit Mode shortcut; Edit Mode cannot reuse Run Task; changing the primary
  dictation shortcut clears a matching optional shortcut.
- `[Implemented]` Persisted legacy settings decode Run Task as disabled. Persisted collisions are
  normalized to disabled and immediately saved so an unavailable shortcut is not silently shown
  as active.
- `[Independent choice]` Run Task is optional and has no default shortcut. The inspected reference
  does not expose a reusable product default for Suniye, and silently claiming an existing global
  shortcut would create an avoidable conflict.

## Scope boundary

- `[Retained]` The existing page-visible dictation route remains available. The dedicated shortcut
  is destination-explicit and does not depend on page visibility.
- `[Not added]` No deterministic instruction router, app matcher, target lock, forced application
  activation, approval prompt, or browser-specific path was added.
- `[Next]` Computer Use still temporarily reads the existing remote model configuration. Separate
  provider, endpoint, model, and Keychain settings are the next slice.

## Validation

- `[Verified]` Focused settings, routing, cancellation, source-state, analytics, and existing
  hotkey regression tests pass.
- `[Verified]` The full suite passes 1,106 tests with 2 skipped and zero failures.
- `[Verified]` Gated coverage is 88.41% (13,663/15,454 lines), above the 80% floor.
- `[Verified]` E2E preflight and smoke pass.
