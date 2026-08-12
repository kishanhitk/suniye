# Phase 17: independent Computer Use model settings

Date: 2026-08-12

## Reference boundary

- `[Verified]` The inspected client selects the model for each turn and includes that selection in
  the runtime request. The client-side model choice is distinct from provider-private inference
  and routing behavior.
- `[Verified]` Suniye previously constructed Computer Use configuration from Magic Format's
  endpoint, model, timeout, token limit, and API key. Changing Magic Format therefore silently
  reconfigured Computer Use.
- `[Unknown]` The reference does not provide a reusable Suniye provider-account settings schema or
  dictate how an independent Swift app should persist custom provider choices.

## Implementation

- `[Implemented]` Computer Use now owns a separate settings model and store containing provider,
  endpoint, model ID, request timeout, and output-token limit.
- `[Implemented]` The available provider choices are OpenAI, OpenRouter, and Custom. OpenAI and
  OpenRouter supply their known Chat Completions endpoints; Custom exposes an editable HTTP/HTTPS
  endpoint. Model ID remains editable for every provider.
- `[Implemented]` Computer Use uses a separate generic-password item in macOS Keychain, scoped to
  the app bundle identifier and the `computer-use-api-key` account.
- `[Implemented]` Settings mutations persist immediately and reconfigure the app-owned
  coordinator. Saving or clearing the Computer Use key does the same. Magic Format settings and
  key mutations no longer call the Computer Use coordinator.
- `[Implemented]` The Computer Use screen's bottom settings disclosure now contains the provider,
  model ID, API endpoint, API key Save/Clear controls, and a connection test. Accessibility and
  Screen Recording controls remain in the same disclosure.
- `[Independent choice]` New settings default to OpenAI and `gpt-5.6-luna`, following the model
  selected for this development effort. The user can replace both provider and model. No existing
  Magic Format credential is migrated because that would violate the requested independence.
- `[Superseded by Phase 21]` By explicit product direction, OpenRouter Computer Use may read the
  saved Magic Format key as a fallback when Magic Format also uses OpenRouter and no dedicated
  Computer Use key exists. It never copies, migrates, or deletes that shared key.

## Scope boundary

- `[Retained]` The existing model transport still uses the current OpenAI-compatible Chat
  Completions wire contract. Responses-style context normalization and compaction are a later
  parity slice.
- `[Not added]` No provider-specific task routing, model-name matcher, hidden endpoint, target
  restriction, or approval rule was introduced.

## Validation

- `[Verified]` Focused tests cover provider endpoints, custom endpoint/model trimming, settings
  persistence, credential save/clear, coordinator updates, connection testing, and isolation from
  Magic Format mutations.
- `[Verified]` The full suite passes 1,111 tests with 2 skipped and zero failures.
- `[Verified]` Gated coverage is 86.82% (13,789/15,882 lines), above the 80% floor.
- `[Verified]` E2E preflight and smoke pass.
