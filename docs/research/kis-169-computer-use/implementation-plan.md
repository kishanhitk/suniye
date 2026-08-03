# KIS-169 independent Swift implementation plan

Status: Phase 0 observation, Phase 1 preview, Phase 2 automatic policy-authorized actions, Phase 3 typed agent loop,
Phase 4 policy, Phase 5A model transport, Phase 5B coordinator/model integration, and the current
desktop parity correction are added.
Browser control and a separate native helper remain unimplemented. Transient screenshot caching
and reference-specific state diffs remain open. The model can now resolve and launch installed
desktop apps for the next observation. The strict maintainability review is complete. A live
`@Computer` run validates the Suniye self-target path; provider, screenshot, and cross-process
validation remain open.

The phase sections below preserve the incremental design record. The superseding correction at the
end of this file is authoritative for the current behavior.

## Goal

Add an independent, user-controlled macOS Computer Use capability to Suniye.

The capability should observe an optional starting app, let the model select another app when
needed, apply the reference-backed app policy, execute the action automatically in the current
testing mode, and observe again.

## Non-goals

- Do not reuse ChatGPT binaries or package files.
- Do not add remote audio processing.
- Do not place business logic in SwiftUI views.
- Do not bypass macOS permissions or the per-action approval policy.
- Do not add browser automation in the first desktop milestone.
- Do not add model calls or input events in Phase 0.

## Proposed service boundaries

The observation, permission, action, approval, agent, app-target resolution, policy, storage,
audit, and model transport boundaries are implemented as typed seams. The coordinator now connects the
transport to the existing explicit API Endpoint settings and keychain.

- `ComputerUseCoordinator`: `@MainActor` lifecycle, UI state, user stop, and result publication.
- `ComputerUseAgent`: session state and model/action loop behind an async interface.
- `ComputerUseModelClient`: typed multimodal request and validated decision response.
- `ComputerUseObservationService`: app discovery, window target, AX text, and screenshot.
- `ComputerUseActionService`: dynamic secondary Accessibility actions and input events.
- `ComputerUseInputEventService`: native `CGEvent` click, key, and scroll adapters.
- `ComputerUsePermissionService`: Accessibility and Screen Recording checks and request flow.
- `ComputerUseApprovalService`: one-time, session, and app-scoped authorization grants.
- `ComputerUseApplicationCatalog`: running and installed app discovery, target resolution, and
  background app launch.
- `ComputerUsePolicy`: action risk classification and hard safety blocks.
- `ComputerUseApprovalStore`: session-memory and app/risk-scoped persistent approval records.
- `ComputerUseAuditRecording`: redacted approval and policy audit events.

The current action contract carries the observation generation for stale-state protection. It does
not carry a screenshot ID, origin, or z-order field. Every macOS observation includes one local
PNG screenshot; the reference's richer transient screenshot cache remains unimplemented.

Use protocols for all boundaries.

Keep platform APIs behind those protocols.

Phase 2 keeps `ComputerUseActionService` behind `ComputerUseActionServicing`. The coordinator
creates an authorization request from a model action. The action service checks permission,
activates the observed target, checks policy and observation generation, then calls a native
adapter. The Preview default authorizes automatically; no approval card is shown.

### Suggested Swift ownership

The names below are proposals. They do not require these exact file names.

- `ComputerUseCoordinator` should be `@MainActor`. It should expose start, stop, cancel, and result-publication commands.
- `ComputerUseSessionState` should be `Codable` and value based. It should contain the phase, target, latest observation summary, and failure.
- `ComputerUseAgent` should be an `actor`. It should run one session and call injected services.
- `ComputerUseObservationService` may use a serial platform queue. Do not pass raw `AXUIElement` values across actor boundaries.
- `ComputerUseActionService` should check cancellation before and after every native action.
- `ComputerUseModelClient` should return a `ComputerUseDecision`. It should never return executable Swift or arbitrary shell commands.
- `ComputerUsePermissionService` should report each permission separately. It should distinguish not granted, pending, denied, and unavailable.
- `ComputerUseApprovalService` should store only the authorization scope and expiry. It should not store screenshots or raw typed secrets.
- The agent should treat a model target decision as a new app/window observation request. A
  frontmost-app change alone is not user intervention.
- `ComputerUsePolicy` should be a pure value-based service. It should classify an action before approval.

### Suggested data types

The plan needs explicit types before implementation begins.

- `ComputerUseTarget`: bundle identifier, process identifier, window identifier, display name, and target generation.
- `ComputerUseWindow`: window identifier, title, bounds, owner process, key status, and visibility.
- `ComputerUseElement`: stable snapshot index, role, label, value summary, enabled state, bounds, actions, and child relation.
- `ComputerUseObservation`: target, AX text, element list, screenshot metadata, timestamp, and observation generation.
- `ComputerUseAction`: click, drag, press key, type text, scroll, set value, select text, or a
  dynamic secondary Accessibility action.
- `ComputerUseDecision`: action, complete, ask user, blocked, or retryable failure.
- `ComputerUseApprovalRequest`: app, window, action summary, risk class, text preview, and allowed approval scopes.
- `ComputerUseFailure`: stable category, user message, native code, retryability, and recovery action.

Element indexes must belong to one observation generation. The action service must reject stale indexes.

### Integration with current Suniye

- Add a narrow Computer Use coordinator property to `AppState`.
- Keep `AppState` responsible for lifecycle and published UI state.
- Keep agent state, model calls, and native action details outside `AppState`.
- Reuse the current `frontmostAppBundleIDProvider` pattern for deterministic tests.
- Reuse the current permission onboarding style, but use a separate Computer Use permission state.
- Reuse existing clipboard-safe text insertion only for a deliberately approved text action.
- Do not route Computer Use actions through `LLMPostProcessor` or Magic Format.
- Add all new files to `project.yml` before project generation.

## Proposed session loop

1. Create a session with a user task and an app target.
2. Check required permissions.
3. Discover and validate the app and key window.
4. Capture AX text and a bounded screenshot.
5. Send one typed observation to the model.
6. Validate the model decision.
7. Apply policy and approval checks.
8. Execute one action.
9. Wait for the target UI to settle.
10. Capture fresh state.
11. Stop on completion, user stop, cancellation, timeout, or terminal error.

Limit each session by time, action count, and repeated failure count.

### State transitions

The first design should define these states:

- `idle`
- `requestingPermissions`
- `selectingTarget`
- `observing`
- `waitingForModel`
- `awaitingApproval`
- `executing`
- `waitingForUI`
- `completed`
- `canceled`
- `failed`

Every transition should include a reason and a session identifier.

The coordinator should publish state changes to SwiftUI. The agent should return events, not mutate views.

### Observation rules

- Capture the target before the model call.
- Include the target app, window, and observation generation in the model request.
- Limit AX depth, element count, text length, and image size.
- Remove or mask password fields and other sensitive values before model transfer.
- Refresh the observation after every action.
- Never execute an action against an old observation without explicit revalidation.

### Action rules

- Validate the action schema before policy evaluation.
- Check target identity and observation generation.
- Check permission state.
- Check the safety policy.
- Request approval when required.
- Execute one action.
- Record the result without recording secret text.
- Wait for a bounded UI settle period.
- Observe again.

The first release should stop on repeated failure. It should not guess a replacement target.

## macOS API candidates

The implementation should evaluate these APIs in a small spike before production work:

- `NSWorkspace` and `NSRunningApplication` for app discovery.
- `AXUIElementCreateApplication` for the target application.
- `kAXWindowsAttribute` for target windows.
- `AXUIElementCopyAttributeValue` for tree traversal.
- `AXUIElementPerformAction` for the exact secondary action name exposed by the observed element.
- `AXUIElementSetAttributeValue` for editable values.
- `CGWindowListCopyWindowInfo` for window metadata.
- `CGWindowListCreateImage` for bounded window capture.
- ScreenCaptureKit for modern window or display capture when Core Graphics is insufficient.
- `CGEvent` for mouse, keyboard, drag, and scroll events.
- `AXIsProcessTrustedWithOptions` for Accessibility permission.
- `CGPreflightScreenCaptureAccess` and `CGRequestScreenCaptureAccess` for Screen Recording permission.

The final API set needs a live macOS test.

Phase 0 uses `CGWindowListCreateImage` as the first adapter. This choice is provisional. Compare it with ScreenCaptureKit during live validation.

### App and window discovery detail

- Use `NSWorkspace.shared.runningApplications` for the initial app catalog.
- Use `NSRunningApplication.bundleIdentifier`, `localizedName`, `processIdentifier`, and `isTerminated`.
- Use `NSWorkspace` application URLs when the user selects an app that is not running.
- Use `AXUIElementCreateApplication(pid)` and `kAXWindowsAttribute` for Accessibility windows.
- Use `CGWindowListCopyWindowInfo` to correlate window IDs, owners, bounds, names, and layers.
- Prefer the frontmost key window when the active app is used or a starting target omits a window.
- Store both PID and window ID. A bundle identifier alone is not enough for a live session.

The exact window selection policy is a product decision. A starting app and window are optional.
The agent can select a different target from a later model decision.

### Accessibility tree detail

The tree reader should request only useful attributes. Candidate attributes include role, subrole, title, description, value summary, enabled, focused, selected, position, size, identifier, actions, and children.

The serializer should:

- assign indexes in a deterministic traversal order;
- retain role and label information;
- include bounds only when coordinate actions need them;
- omit passwords and sensitive values;
- cap depth and total output size;
- return a snapshot generation.

AX objects should stay inside the platform adapter. The model should receive text and typed element metadata.

### Screenshot detail

Test both `CGWindowListCreateImage` and ScreenCaptureKit on macOS 14.

- Use a bounded target-window image when the target window is available.
- Use ScreenCaptureKit when the required window capture quality or display behavior needs it.
- Do not capture the full display by default.
- Record image dimensions, scale, origin, and timestamp.
- Apply a size limit before model transfer.
- Treat a missing screenshot as an observation failure unless the chosen model supports AX-only mode.

The Phase 0 implementation uses `CGWindowListCreateImage` as a provisional first adapter.
The production screenshot API remains unselected until live macOS validation compares it
with ScreenCaptureKit.

### Input actions

- Use `CGEvent` for coordinate mouse clicks, key presses, drags, and scrolls.
- Use `AXUIElementPerformAction` for the exact validated secondary action name exposed by the
  observed element.
- Use `AXUIElementSetAttributeValue` for supported value replacement.
- Use the current clipboard-preserving insertion path only for approved text entry.
- Keep keyboard layout and modifier mapping in a tested value type.
- Add a short settle delay only after measuring real application behavior.

The native action service must not provide a general-purpose shell or AppleScript escape hatch.

## Model and decision protocol

Do not couple the agent loop to the existing text post-processor.

Define a separate typed model interface.

The request should contain:

- user task;
- target app and window identity;
- current AX text;
- current screenshot;
- recent action results;
- current error or user intervention state.

The response should contain one of:

- a validated action;
- a task-complete result;
- a user-question result;
- a blocked result;
- a retryable error result.

Validate action names, target indices, coordinates, text sizes, key chords, and time limits before execution.

The provider, model name, network boundary, and privacy display need a product decision.

### Model integration choices

- `[Verified]` Existing Suniye Magic Format models accept text only.
- `[Verified]` Existing local Gemma uses a text-only chat-completion payload.
- `[Inferred]` Computer Use needs a separate multimodal provider interface.
- `[Unknown]` The DMG does not identify the exact model used for Computer Use.

The first provider should be selected only after these decisions:

1. Can the model accept a screenshot and structured AX text?
2. Can it return strict structured output?
3. Where does image and AX data go?
4. Can the provider cancel a request?
5. What is the timeout and retry policy?

The agent should use a typed `Codable` envelope. It should reject unknown actions, missing fields, oversized text, invalid coordinates, and unsupported key chords.

The provider should receive a task, observation, policy limits, and recent action results. It should not receive permission secrets, keychain data, or arbitrary local files.

### Local-first privacy decision

Suniye’s existing hard constraint covers local audio and transcription. It does not answer whether screenshots and AX text may leave the Mac.

The product must choose one of these modes before model integration:

- local observation and local multimodal model;
- local observation with explicit remote model consent;
- remote model disabled for Computer Use.

Until that decision exists, the safe implementation default is no remote screenshot transfer.

## Permission and approval UX

Use a dedicated Computer Use settings page and a visible active-session surface.

Show the target app, current window, permission state, and Stop control.

Request Accessibility before action execution.

Request Screen Recording before screenshot capture.

Explain why each permission is needed.

Show a system-settings route when the user must grant permission manually.

For approval, show:

- app name and bundle identifier;
- action type;
- target label or coordinates;
- text that will be entered;
- risk reason;
- current screenshot or AX excerpt when safe to show;
- Allow once;
- Allow for this session;
- Deny;
- Stop session.

Never allow an always-approved rule to bypass hard safety blocks.

Keep persistent approval keyed to an app and action class.

Do not persist approval for credentials, payments, legal acceptance, security settings, or destructive deletion.

### Permission flow

Use separate status rows for:

- Accessibility: reads the target app and performs semantic actions.
- Screen Recording: captures the target window image.

Show a short reason before each System Settings route. Refresh status when Suniye returns to the foreground.

Do not request Screen Recording at app launch. Request it when the user starts a screenshot-based Computer Use session.

### Approval flow

Use a visible, modal approval card for the pending action.

The card should show:

- selected app and window;
- action name;
- target label, role, and bounds when available;
- text preview with sensitive text masked;
- risk class;
- why approval is needed;
- Allow once;
- Allow for this session;
- Deny;
- Stop.

The card must stay visible while an action is pending. The user must be able to stop the session without opening Settings.

Persistent approval is a later phase. If added, key it by app identity and action class. Add a reset control and an audit record.

### User stop and target changes

The user can stop a run from the approval surface or the Computer Use page.

Do not treat a frontmost-app or key-window change as user intervention. The model can select a
different app or window with a target decision. The next observation resolves that target, and the
action service activates the observed target before it posts input.

## Native helper decision

Start with one Suniye process.

Keep the first implementation inside Swift services.

Consider an XPC helper only when isolation or permission separation requires it.

If a helper becomes necessary, define a narrow Codable request and response protocol.

Do not expose raw process execution or arbitrary socket access.

### Helper boundary decision

The DMG uses a separate native helper. That is evidence about ChatGPT, not a requirement for Suniye.

Start with one Suniye process because it keeps testing and permission diagnosis simple.

Create a helper only if a live spike shows one of these needs:

- a permission prompt must be isolated from the main app;
- a native API blocks the main process;
- a crash must not terminate the UI;
- a separate entitlement or sandbox boundary is required.

If a helper is added, use a versioned `Codable` IPC protocol over `NSXPCConnection` or another narrow local channel. Define request IDs, cancellation, timeouts, and service restart behavior first.

## Testing plan

Test the pure session state machine first.

Inject fake model, observation, action, permission, approval, and intervention services.

Cover:

- malformed model decisions;
- stale element indices;
- permission denial and pending permission;
- approval decline, timeout, and cancellation;
- user stop during model wait and action wait;
- repeated action failure;
- target app exit;
- frontmost-window intervention;
- screenshot failure;
- session action and time limits.

Add a small local fixture app for Accessibility and screenshot integration tests.

Keep platform-only tests out of the pure state-machine target.

Add fixture data for:

- an AX tree with stale indexes;
- a password field;
- a disabled button;
- a changed window generation;
- a screenshot with a known size;
- each policy risk class;
- each approval scope.

Use live tests only for the smallest AppKit, Accessibility, WindowServer, and ScreenCaptureKit seams. Keep those tests opt-in when they need user permissions.

## Delivery phases

### Phase 0: API spike

Implement and verify app discovery, AX tree traversal, window capture, permissions, and cancellation.

The current Phase 0 code is read-only. It does not post input events.

Record results in the evidence ledger.

Exit criteria:

- one chosen target app can be listed;
- one key window can be identified;
- AX text can be serialized with stable indexes;
- one bounded screenshot can be captured;
- permission states are observable;
- cancellation stops an observation before it publishes state;
- all findings are recorded as verified, inferred, or unknown.

Phase 0 implementation files:

- `Suniye/Services/ComputerUseModels.swift`;
- `Suniye/Services/ComputerUseApplicationCatalog.swift`;
- `Suniye/Services/ComputerUseObservationService.swift`;
- `Suniye/Services/ComputerUseAccessibilityReader.swift`;
- `Suniye/Services/ComputerUsePermissionService.swift`;
- `Suniye/Services/ComputerUseScreenshotService.swift`;
- `SuniyeTests/ComputerUsePhase0Tests.swift`.

### Phase 1: Read-only observation

Add target selection, AX text, screenshot preview, permission UX, and cancel.

Do not execute model actions yet.

Add a target picker and an observation preview. Let the user inspect the selected app, window, AX text, and screenshot before any action is possible.

Implementation added:

- `Suniye/Services/ComputerUseCoordinator.swift` runs discovery and observation behind a main-actor UI state boundary.
- `Suniye/Views/MainWindow/ComputerUsePage.swift` provides target selection, permission requests, observation preview, and cancel.
- `Suniye/MainWindowSection.swift` adds the Computer Use navigation surface.
- `SuniyeTests/ComputerUsePhase1Tests.swift` covers loading, permission gating, observation, cancellation, and target changes.

The Phase 1 surface is read-only. It does not post input events or call a model.

### Phase 2: Controlled actions

Add click, key press, scroll, text entry, and dynamic secondary Accessibility actions.

Apply the policy grant automatically for every action in the current testing mode.

The current action boundary also covers drag, set value, and select text behind test seams.

Implementation added:

- `Suniye/Services/ComputerUseActionModels.swift` defines typed actions, keys, modifiers, approval requests, grants, results, and errors.
- `Suniye/Services/ComputerUseActionService.swift` validates actions and binds execution to the exact approval request, Accessibility permission, per-action target activation, and the observation generation.
- `Suniye/Services/ComputerUseInputEventService.swift` owns native `CGEvent` posting for click, key, and scroll actions.
- `Suniye/Services/ComputerUseAccessibilityReader.swift` resolves the observed AX element index
  and performs the approved dynamic secondary action.
- `SuniyeTests/ComputerUsePhase2ActionTests.swift`, `ComputerUsePhase2TestSupport.swift`, and
  `ComputerUsePhase2Tests.swift` cover action models, policy, service seams, target activation,
  automatic grants, failures, and cancellation.

Phase 2 does not call a model. The native action service is exercised through typed test seams;
the temporary manual SwiftUI action controls were removed during the parity cleanup.

The parity correction adds a platform runner, per-action target activation, window-relative
coordinate conversion, optional starting context, installed-app resolution, and always-allowed
approval management. A model target decision can switch the next observation to another app or
window. Frontmost-app changes are not treated as user intervention.

Transient screenshot caching, reference-specific state diffs, and helper IPC remain separate work
items. Indexed click and dynamic secondary Accessibility actions are now in the desktop action
contract.

### Phase 3: Agent loop

Add the model interface, action validation, re-observation, limits, target selection, and stop
cancellation.

Use a fake model in tests. Do not connect a remote model until the privacy decision and approval UX are complete.

Implementation added:

- `Suniye/Services/ComputerUseAgentModels.swift` defines terminal outcomes, typed model requests and decisions, failure feedback, cancellation-aware model boundaries, and bounded session limits.
- `Suniye/Services/ComputerUseAgent.swift` runs one actor-isolated loop. It observes fresh state, exposes available apps to the model, applies target decisions, validates actions, obtains an automatic one-time policy grant, executes through the Phase 2 action service, records failures, waits for UI settlement, and re-observes.
- `Suniye/Services/ComputerUseApplicationCatalog.swift` resolves bundle IDs, display names, dynamic process IDs, installed app bundles, and background launches.
- `SuniyeTests/ComputerUsePhase3Tests.swift` covers model value validation, target changes, completed and blocked outcomes, retries, action results and failure feedback, automatic policy grants, limits, and cancellation; `ComputerUsePhase3TestSupport.swift` keeps the fakes and observation fixtures separate.

Phase 3 has a default model that fails closed with `notConfigured`. Phase 5B supplies the live
transport through the coordinator only when the user has configured an explicit API Endpoint.
The provider must honor the cancellation token and the privacy policy.

### Phase 4: Risk policy boundary

Implementation added:

- `Suniye/Services/ComputerUsePolicyService.swift` distinguishes allowed, denied, and forbidden applications and derives permitted approval scopes from action risk.
- `Suniye/Services/ComputerUseApprovalStore.swift` keeps session approvals in memory and persists only app bundle identifier, action risk, scope, and optional expiry for always approvals.
- `Suniye/Services/ComputerUseAudit.swift` records approval and policy outcomes with action summaries that never include typed text.
- `Suniye/Services/ComputerUseActionModels.swift` now carries session identity, observation generation, allowed scopes, and redacted text previews.
- `SuniyeTests/ComputerUsePhase4PolicyTests.swift` covers policy decisions, persistence, expiry, revocation, exact grants, and audit redaction.

Persistent approval is opt-in by policy configuration and is never enabled for text entry. The
coordinator and agent consume this boundary in Phase 5B.

### Phase 5A: Model transport

Implementation added:

- `Suniye/Services/ComputerUseModelClient.swift` builds a typed chat-completion request from the task, redacted action history, Accessibility observation, and optional screenshot.
- `Suniye/Services/ChatCompletionClient.swift` now accepts an already-encoded request body while preserving the existing text-only API.
- `SuniyeTests/ComputerUsePhase5ModelTests.swift` covers configuration validation, prompt redaction, screenshot inclusion, JSON parsing, request encoding, and malformed provider output.

The transport fails closed for invalid configuration, requires an HTTP(S) endpoint and API key,
does not put typed action text in the prompt history, and includes an observation screenshot when
the local observation contains one. Phase 5B connects it to the coordinator and existing API
settings.

### Phase 5B: Coordinator and model settings

Implementation added:

- `Suniye/Services/ComputerUseAgentApproval.swift` isolates automatic policy preparation, remembered-scope lookup, and grant creation behind an actor-safe seam.
- `Suniye/Services/ComputerUseCoordinator.swift` now owns the agent task, shared session identity, cancellation, result publication, and remote model configuration.
- `Suniye/Services/ComputerUseModelConfigurationFactory.swift` maps only an explicitly selected API Endpoint, valid model settings, and a non-empty key to the Computer Use transport.
- `Suniye/Views/MainWindow/ComputerUseAgentPanel.swift` adds the task editor, model status, run action, and terminal question display.
- `Suniye/Views/MainWindow/MainWindowView.swift` passes the existing model configuration into the Computer Use page.
- `SuniyeTests/ComputerUsePhase5CoordinatorTests.swift` covers automatic action execution, policy blocking, cancellation, and session-scoped configuration.
- `SuniyeTests/ComputerUseModelConfigurationTests.swift` covers provider gating, key trimming, and model mapping.
- The coordinator tests also cover policy denial, automatic one-time authorization, canceled
  permission work, stale operation results, and terminal outcomes.

The remote model is not configured for automatic, local, or missing-key settings. Accessibility
and Screen Recording are required before an agent run because every macOS observation includes a
screenshot. The screenshot is sent with the model request without a second upload-consent gate.
The live E2E validates same-process activation and Accessibility-only observation. A provider run,
Screen Recording capture, and cross-process native input still need manual macOS validation.

The current prompt describes the expanded typed action forms and the window-relative coordinate
origin. It does not claim to reproduce the reference's unknown server prompt or provider choice.

### Current implementation correction: 2026-08-03

- `[Implemented]` Actions are no longer exposed through a separate manual SwiftUI control panel.
  The current path is model decision, automatic policy authorization, native action execution, and
  fresh observation.
- `[Implemented]` The coordinator no longer owns interactive approval continuations, action-only
  phases, or direct action-request state.
- `[Retained]` The policy service and approval grant are technical authorization records. They do
  not present a Preview prompt in the current testing mode.
- `[Implemented]` The public action boundary uses dynamic `perform_secondary_action` values from
  the current Accessibility observation; there is no separate semantic-action enum.
- `[Implemented]` The Preview surface no longer has a screenshot choice or remote screenshot-upload
  approval toggle. Observation capture always includes a screenshot, and the model request includes
  it when available.
- `[Implemented]` The Preview surface no longer exposes a macOS window picker or Bring Forward
  control. The native observation and action services still resolve the key/first window internally.
- `[Implemented]` Cached Accessibility-element/action prevalidation, local agent action/failure/time
  caps, target locking, intervention monitoring, and diagnostic window metadata are removed.
- `[Verified]` The focused Computer Use suite reports 67 passed tests and 0 failures.
- `[Unknown]` The reference host's complete UX and server-side agent orchestration are not exposed
  by the DMG, so the remaining page-level UX is still a Suniye surface rather than claimed exact
  parity.

The deterministic suite passes with 1,089 tests, 1,088 passed, 1 skipped, and 0 failures. Gated
line coverage is 95.08% (14,455/15,203), above the documented 95% floor. The focused Computer Use
regression classes also pass. The live E2E result is recorded in `e2e-computer.md`.

## Current direct voice integration — 2026-08-03

The direct voice path is implemented as a narrow bridge from the existing dictation pipeline to
the existing Computer Use coordinator. The detailed design and evidence boundary are in
`direct-voice-integration-plan.md`.

- `[Implemented]` The visible Computer Use page registers a weak
  `ComputerUseVoiceTaskHandling` handler with `AppState`.
- `[Implemented]` The existing Suniye hold-to-talk session transcribes locally and routes the raw
  task directly to Computer Use while that page is visible.
- `[Implemented]` Computer Use tasks bypass Magic Format, focused-app insertion, clipboard output,
  submit-key handling, and dictation history.
- `[Implemented]` The coordinator starts immediately when ready, queues while model/apps/
  permissions are preparing, and rejects overlapping work without canceling the active task.
- `[Implemented]` The page explains the voice gesture and exposes queued-task status while keeping
  the manual task editor as a fallback.
- `[Verified]` Focused signed tests cover direct submission, rejection, automatic start, queued
  model configuration, captured-instruction precedence, and empty-task validation.
- `[Unknown]` Live microphone capture, provider behavior after voice submission, and browser
  extension routing remain unverified.

### Later: Browser adapter

Design browser control as a separate capability after desktop behavior is stable.

Do not infer DOM or tab state from a desktop screenshot. Define a browser-specific observation and action protocol after a separate browser audit.

## Definition of done for the research and staged implementation

- The DMG findings are recorded in the evidence ledger.
- Every important claim has a status label.
- Suniye’s existing support and missing capability are explicit.
- The model boundary is separate from Magic Format.
- Permission UX and policy authorization have explicit boundaries.
- Native helper use is a decision gate, not an assumption.
- Browser control is a separate adapter.
- Phase 0 remains read-only.
- Phase 2 actions require a one-time policy grant and fresh observation state.
- The desktop coordinator model run is connected behind explicit API settings and automatic policy authorization.
- Browser code and a separate native helper are not enabled because their contracts remain unverified.

## Superseding implementation plan correction — 2026-08-03

The implementation follows the inspected macOS app-scoped contract:

- `[Verified]` Keep one app-scoped state/action adapter. Resolve a concrete native window only
  inside the AX, screenshot, activation, and input adapters; do not expose window selection as a
  model or user-session concept.
- `[Verified]` Let the native boundary resolve element indexes and Accessibility action names.
  Do not mirror or validate a cached element/action table in the coordinator or agent.
- `[Verified]` Keep automatic approval as the Preview default while preserving the policy actor,
  permission checks, cancellation token, observation-generation check, and redacted audit seam.
- `[Verified]` Capture and include the macOS screenshot on every observation. Keep the local
  Screen Recording requirement explicit in permission UX.
- `[Unknown]` Add helper IPC only after its endpoint, sender authentication, process lifecycle, and
  permission ownership are verified; it is not required by the current same-process plan.

## Final cleanup validation correction — 2026-08-03

- `[Verified]` The final implementation removes local task matching, target locking and
  intervention monitoring, window-selection UX, manual action/approval controls, cached AX
  prevalidation, local agent counters, duplicate AX prompt rendering, screenshot-upload consent,
  and Windows-only screenshot fields.
- `[Verified]` The final full suite is 1,080 tests executed, 1 skipped, 0 failures, with gated
  coverage at 95.02% (13,672/14,389 lines).
- `[Verified]` The Preview install and safe Calculator model run pass after a fresh app relaunch.
- `[Unknown]` The native helper/IPC contract, exact host prompt and server loop, browser adapter,
  Screen Recording consent path, and cross-process input still require separate evidence.
