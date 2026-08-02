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
- Should Suniye control one selected app or the whole desktop?
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
- Phase 1 currently uses a target picker. Does that remain the right product policy after live testing?
- Does running discovery and observation behind the Phase 1 actor boundary behave correctly for real AX targets?

## Phase 2 live validation

- Does the `CGEvent` event tap post click, key, and scroll events after the required macOS permissions are granted?
- Do AX window bounds and `CGEvent` screen coordinates use the same origin and display scale for each target app?
- Does a target remain safe to act on when its window moves, resizes, or changes key-window state after observation?
- Do target applications expose the observed element indexes consistently during semantic action resolution?
- Does the existing clipboard-preserving text insertion path protect clipboard state during an approved text action?
- Is a one-time approval card sufficient for the first local integration, or does the product need a separate persistent approval service later?

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
