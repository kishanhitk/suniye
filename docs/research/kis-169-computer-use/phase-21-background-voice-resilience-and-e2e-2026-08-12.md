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
- `[User-directed]` Computer Use keeps independent provider, endpoint, and model settings. When
  its provider is OpenRouter and no dedicated Computer Use credential exists, it reuses the saved
  Magic Format key only if Magic Format is also configured for OpenRouter. A dedicated Computer
  Use key takes precedence; other providers never receive the shared key.
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

## Honest remaining live boundaries

- `[Not exercised]` The bundled Computer Use integration exposes app-scoped key presses, not a
  global hold/release shortcut. It therefore cannot itself perform a real microphone hold,
  speech, and release cycle. That final physical voice leg requires user participation or a
  purpose-built shortcut test driver.
- `[Not exercised]` The final installed run used a local protocol-compatible provider so request,
  tool, cancellation, persistence, and background lifecycle could be controlled deterministically.
  The temporary credential and server were removed afterward. A real provider credential remains
  user-owned and was not copied from another feature.
- `[Not exercised]` The status-item New Computer Use Conversation action was not reachable through
  the bundled app-scoped accessibility driver. Its app-level action and enabled-state policy are
  covered by tests; the same reset was exercised from the conversation UI.

## Validation

- `[Verified]` Focused tests cover startup permission refresh, immediate pending-instruction save,
  restart restoration, run handoff, explicit clearing, app-owned model reconfiguration, shared
  OpenRouter fallback, dedicated-key precedence, and provider isolation.
- `[Verified]` The full suite passes 1,139 tests with 2 skipped and zero failures.
- `[Verified]` Gated coverage is 87.03% (14,372/16,514 lines), above the 80% floor.
- `[Verified]` E2E preflight and smoke pass when run sequentially. The smoke build reports an
  unrelated out-of-date iOS CoreSimulator warning; the macOS destination and build succeed.
