# Phase 21: background voice resilience and installed E2E

Date: 2026-08-12

## Evidence boundary

- `[Verified]` The inspected desktop runtime supports starting a Computer Use task without making
  its conversation window the controlled target. Its app-scoped tool contract does not require
  the host conversation to be visible while the run continues.
- `[Unknown]` The artifact does not expose the host application's exact persistence format for a
  transcript that is waiting on permissions or model configuration.
- `[Independent choice]` Suniye persists one pending locally transcribed instruction in its own
  Application Support directory. This prevents a restart from dropping speech captured before
  the run can start.

## Final lifecycle corrections

- `[Implemented]` App bootstrap refreshes the Computer Use Accessibility and Screen Recording
  snapshot even when the Computer Use page has never been opened. This is a read-only TCC status
  check and does not display a permission prompt.
- `[Implemented]` A global voice transcript that is waiting for model configuration or macOS
  permissions is written atomically to a dedicated local file. Coordinator recreation restores
  it as the pending task and visible draft.
- `[Implemented]` The pending file is cleared only after the coordinator has accepted the task as
  an active run, or when the user explicitly stops, cancels, or starts a new conversation.
- `[User-directed]` Computer Use keeps independent provider, endpoint, and model settings, but
  OpenRouter has one shared credential across Magic Format and Computer Use. Saving or clearing it
  from either feature changes the same credential. OpenAI and Custom continue to use the separate
  Computer Use credential, and that credential is never selected for OpenRouter.
- `[Not added]` No instruction matcher, target lock, app-opening heuristic, approval gate,
  physical-input cancellation, or forced conversation navigation was introduced.

## Installed Preview E2E

Build: Debug Preview at `/Users/kishan/Applications/Suniye Preview.app` from
`kis-169-computer-use-parity`.

- `[Verified live]` A natural task, `Open Calculator, enter 7, and verify the display.`, completed
  through an OpenAI-compatible loopback provider. The model loop called `get_app_state`,
  `press_key`, and `get_app_state`, then returned `Done — Calculator now shows 7.` Debug session:
  `CU-6EE003523304`.
- `[Verified live]` An independent observation through the bundled Computer Use integration read
  Calculator's display value as `7`.
- `[Verified live]` The completed conversation, tool arguments, and raw collapsed tool output
  survived quitting and reopening Preview. New conversation cleared the stored session.
- `[Verified live]` A delayed run showed the generic shimmering `Working` surface with one stop
  affordance. Stop cancelled the provider request and appended `Stopped.` Debug session:
  `CU-031A4F2312E4`.
- `[Verified live]` A delayed task continued after the Suniye window was closed. The process stayed
  alive, did not reopen or focus its conversation window, completed three tool calls, and restored
  the completed conversation when reopened. Debug session: `CU-83846183223F`.
- `[Verified live]` Accessibility and Screen Recording were granted in the installed Preview.
- `[Verified live]` The dedicated Hold to Run Task shortcut was configured as
  `Control + Command + U` without changing the Magic Format model configuration.
- `[Verified live]` After OpenRouter credential sharing replaced the temporary fallback design,
  the installed Preview displayed `OpenRouter API key shared with Magic Format.` and enabled the
  model without a second Computer Use key.
- `[Verified live]` The natural task `Open Calculator, enter 42, and tell me what the display
  shows.` ran through the real OpenRouter `openai/gpt-5.6-luna` configuration. Session
  `CU-22D0FF4454A7` performed seven calls in the sequence observation, click, observation, click,
  observation, click, observation, then answered `The Calculator display shows **42**.`
- `[Verified live]` The bundled Computer Use driver independently observed Calculator after the
  run and reported `StandardInputView;value:42` and AX value `42`.

## Honest remaining live boundaries

- `[Not exercised]` The bundled Computer Use integration exposes app-scoped key presses, not a
  global hold/release shortcut. It therefore cannot itself perform a real microphone hold,
  speech, and release cycle. That final physical voice leg requires user participation or a
  purpose-built shortcut test driver.
- `[Verified partial live chain]` A user-operated installed run already recorded shortcut
  down/up, 1.82 seconds of production microphone capture, local transcription, and direct routing
  into Computer Use. The final installed General page independently confirms the configured
  `Control + Command + U` shortcut. This does not replace the required continuous voice-to-action
  rerun now that the shared provider credential is active.
- `[Superseded by final live run]` Sessions `CU-7E6BEA9FE8C8` and `CU-83CD69D173D9` now prove the
  continuous chain: global hold/release, real Bluetooth-mic capture, local transcription, raw
  transcript routing, Luna inference, fresh Calculator observation, terminal response, windowless
  background execution, and session restoration after restart.
- `[Verified]` Deterministic cancellation, persistence, and closed-window lifecycle checks used a
  temporary local protocol-compatible provider; its credential and server were removed. The final
  Calculator run used the user's existing shared OpenRouter credential without exposing or copying
  it into a second store.
- `[Not exercised]` The status-item New Computer Use Conversation action was not reachable through
  the bundled app-scoped accessibility driver. Its app-level action and enabled-state policy are
  covered by tests; the same reset was exercised from the conversation UI.

## Validation

- `[Verified]` Focused tests cover startup permission refresh, immediate pending-instruction save,
  restart restoration, run handoff, explicit clearing, app-owned model reconfiguration, shared
  shared OpenRouter reads/writes, and provider isolation.
- `[Verified]` The full suite passes 1,139 tests with 2 skipped and zero failures.
- `[Verified]` Gated coverage is 87.05% (14,389/16,530 lines), above the 80% floor.
- `[Verified]` E2E preflight and smoke pass when run sequentially. The smoke build reports an
  unrelated out-of-date iOS CoreSimulator warning; the macOS destination and build succeed.
