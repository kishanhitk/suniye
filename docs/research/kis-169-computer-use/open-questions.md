# KIS-169 open questions

## DMG questions

- What exact model and prompt produce Computer Use actions?
- Which service owns the complete agent loop?
- Which native API captures the target window in each state?
- How does the helper resolve an app name to one window?
- What exact signal means user intervention?
- What cancels an in-flight native action?
- Which actions require approval in the full production policy?
- How does browser control differ in its wire protocol?

## Suniye product questions

- Should the first model run locally, remotely, or through a user-selected provider?
- Does the local-first promise cover screenshots and AX text?
- `[Resolved for the current desktop prototype]` Suniye allows the agent to start from the active
  app or an optional picker selection, then switch apps during the run. Release policy remains
  open.
- Which action classes are safe without approval?
- Should persistent approvals exist in the first release?
- Should Suniye support locked-screen operation?
- Should the first release support browser-specific semantics?

## Implementation gates

- Do not choose a screenshot API until a macOS 14 test proves the required output.
- Do not add a helper process until the permission model proves that it is needed.
- Do not connect a model until the typed decision schema and safety policy are fixed.
- Do not enable persistent approval until audit and revocation behavior are specified.

## Phase 0 live validation

- Does `CGWindowListCreateImage` capture the selected window after Screen Recording grant?
- Does AX window geometry match CG window geometry for the target apps?
- Which target apps expose a complete enough AX tree for the first read-only preview?
- `[Resolved for the current desktop prototype]` The picker is optional starting context. The
  model can select another app during the run.
- Does running discovery and observation behind the Phase 1 actor boundary behave correctly for real AX targets?

## Phase 2 live validation

- Does the `CGEvent` event tap post click, key, and scroll events after the required macOS permissions are granted?
- Do AX window bounds and `CGEvent` screen coordinates use the same origin and display scale for each target app?
- Does a target remain safe to act on when its window moves, resizes, or changes key-window state after observation?
- Do target applications expose the observed element indexes consistently during semantic action resolution?
- Does the existing clipboard-preserving text insertion path protect clipboard state during an approved text action?
- Is a one-time approval card sufficient for the first local integration, or does the product need a separate persistent approval service later?

### Corrective parity status

- `[Resolved for the current desktop prototype]` The target UI can select a specific visible
  window, and the user can explicitly bring it forward before control.
- `[Resolved for the current desktop prototype]` The typed action boundary covers click metadata,
  positioned scroll, drag, set value, and text selection.
- `[Resolved for the current desktop prototype]` Always-allowed approvals have visible revocation
  UX and refresh after persistence.
- `[Unknown]` The selected-window activation path still needs a live Accessibility test across
  multiple target applications.
- `[Resolved for the current desktop prototype]` Indexed clicks, dynamic secondary AX actions,
  and screenshot IDs are part of the typed action and policy contracts.
- `[Resolved for the current desktop prototype]` The model receives running and installed app
  candidates. A non-running resolved app launches through the application catalog before state
  capture.
- `[Unknown]` Reference-level transient screenshot caching and state diffs are not yet implemented
  in Suniye.

## Phase 3 integration gates

- Which model provider may receive screenshots, AX text, action results, and failure messages?
- Does the local-first promise require a fully local Computer Use model, or can the user choose a remote provider with explicit disclosure?
- What request timeout and provider cancellation contract enforces the agent duration limit while a model request is in flight?
- How should `ComputerUseAgentResult` events connect to the main-actor coordinator without allowing the model to mutate views?
- Which model response schema and prompt produce reliable typed actions for each supported target app?
- Should action failures be shown to the user before the agent retries, or should the first release stop after one failure?

## Phase 4 integration gates

- Which action risks may receive session or always approval in the product default policy?
- Which app policy settings need user-facing controls before persistent approval is enabled?
- What expiry duration and reset UX should always approvals use?
- Should policy and approval audit records remain local only, or may aggregate redacted telemetry leave the Mac?

## Phase 5B status and remaining gates

- `[Resolved for the desktop prototype]` The first provider is the user-selected explicit API Endpoint already used by Suniye's Magic Format settings.
- `[Resolved for the desktop prototype]` A model run reaches the main-actor coordinator through an actor-safe approval continuation. The model cannot mutate SwiftUI state directly.
- `[Resolved for the desktop prototype]` The response protocol is a strict Codable decision object with action, completed, ask-user, blocked, and retryable-failure outcomes.
- `[Resolved for the desktop prototype]` Screenshot upload is a separate session choice and defaults to disabled.
- `[Verified]` Deterministic validation covers the coordinator's approval, policy, cancellation,
  stale-operation, and terminal-result paths. The full suite reports 1,088 passed, 1 skipped,
  and 0 failed tests.
- `[Verified]` Gated coverage passes at 95.08% (14,455/15,203 lines) at the 95% floor.
- `[Verified]` The focused Computer Use regression classes pass with 0 failures.
- `[Unknown]` A live provider's actual multimodal support, prompt reliability, response latency, and cancellation behavior still need a manual test.
- `[Unknown]` The current Core Graphics screenshot adapter must still be compared with ScreenCaptureKit on macOS 14 and later.
- `[Verified]` The live `@Computer` E2E validates Suniye navigation, target/window selection,
  same-process activation, Accessibility-only capture, approval presentation, and denial.
- `[Unknown]` Screen Recording capture, cross-process activation, and native input delivery still
  need a safe live target with the required permissions.
- `[Deferred]` Browser-specific control needs its own tab, DOM, extension, download, and upload contract.
- `[Deferred]` A separate native helper is not needed by the current same-process Swift design. Revisit it only if live permission, blocking, crash-isolation, or entitlement tests show a requirement.
