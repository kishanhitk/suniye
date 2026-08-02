# KIS-169 independent Swift implementation plan

Status: Phase 0 observation implementation added. Model control and desktop actions remain unimplemented.

## Goal

Add an independent, user-controlled macOS Computer Use capability to Suniye.

The capability should observe a selected app, ask a model for one safe action, request approval when needed, execute the action, and observe again.

## Non-goals

- Do not reuse ChatGPT binaries or package files.
- Do not add remote audio processing.
- Do not place business logic in SwiftUI views.
- Do not grant a model unrestricted control.
- Do not add browser automation in the first desktop milestone.
- Do not add model calls or input events in Phase 0.

## Proposed service boundaries

These boundaries are design proposals, not code changes.

- `ComputerUseCoordinator`: `@MainActor` lifecycle, UI state, user stop, and approval presentation.
- `ComputerUseAgent`: session state and model/action loop behind an async interface.
- `ComputerUseModelClient`: typed multimodal request and validated decision response.
- `ComputerUseObservationService`: app discovery, window target, AX text, and screenshot.
- `ComputerUseActionService`: semantic AX actions and input events.
- `ComputerUsePermissionService`: Accessibility and Screen Recording checks and request flow.
- `ComputerUseApprovalService`: one-time, session, and app-scoped approval decisions.
- `ComputerUseInterventionMonitor`: frontmost app, target window, and user stop signals.
- `ComputerUsePolicy`: action risk classification and hard safety blocks.

Use protocols for all boundaries.

Keep platform APIs behind those protocols.

### Suggested Swift ownership

The names below are proposals. They do not require these exact file names.

- `ComputerUseCoordinator` should be `@MainActor`. It should expose start, stop, cancel, and approval-result commands.
- `ComputerUseSessionState` should be `Codable` and value based. It should contain the phase, target, latest observation summary, pending approval, and failure.
- `ComputerUseAgent` should be an `actor`. It should run one session and call injected services.
- `ComputerUseObservationService` may use a serial platform queue. Do not pass raw `AXUIElement` values across actor boundaries.
- `ComputerUseActionService` should check cancellation before and after every native action.
- `ComputerUseModelClient` should return a `ComputerUseDecision`. It should never return executable Swift or arbitrary shell commands.
- `ComputerUsePermissionService` should report each permission separately. It should distinguish not granted, pending, denied, and unavailable.
- `ComputerUseApprovalService` should store only the approval scope and expiry. It should not store screenshots or raw typed secrets.
- `ComputerUseInterventionMonitor` should publish target changes and user stop events.
- `ComputerUsePolicy` should be a pure value-based service. It should classify an action before approval.

### Suggested data types

The plan needs explicit types before implementation begins.

- `ComputerUseTarget`: bundle identifier, process identifier, window identifier, display name, and target generation.
- `ComputerUseWindow`: window identifier, title, bounds, owner process, key status, and visibility.
- `ComputerUseElement`: stable snapshot index, role, label, value summary, enabled state, bounds, actions, and child relation.
- `ComputerUseObservation`: target, AX text, element list, screenshot metadata, timestamp, and observation generation.
- `ComputerUseAction`: click, drag, press key, type text, scroll, set value, select text, or semantic AX action.
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
- `userIntervened`
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
- `AXUIElementPerformAction` for semantic actions.
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
- Prefer the frontmost key window after explicit target selection.
- Store both PID and window ID. A bundle identifier alone is not enough for a live session.

The exact window selection policy is a product decision. The implementation must show the selected app and window before control begins.

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
- Use `AXUIElementPerformAction` for supported semantic actions.
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

### User intervention

Pause when the target app exits, the target window changes, or the frontmost app changes during a controlled action.

Ask the user whether to resume only after a fresh observation. Do not silently move control to the new app.

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

### Phase 2: Controlled actions

Add click, key press, scroll, text entry, and semantic AX actions.

Require approval for every action.

Start with click, key press, scroll, and text entry. Add drag, set value, select text, and semantic actions only after each has a focused integration test.

### Phase 3: Agent loop

Add the model interface, action validation, re-observation, limits, and user intervention.

Use a fake model in tests. Do not connect a remote model until the privacy decision and approval UX are complete.

### Phase 4: Risk policy

Add action risk classes, persistent approvals, audit records, and hard blocks.

Define revocation, retention, secret masking, and export behavior before enabling persistent approval.

### Phase 5: Browser adapter

Design browser control as a separate capability after desktop behavior is stable.

Do not infer DOM or tab state from a desktop screenshot. Define a browser-specific observation and action protocol after a separate browser audit.

## Definition of done for this design phase

- The DMG findings are recorded in the evidence ledger.
- Every important claim has a status label.
- Suniye’s existing support and missing capability are explicit.
- The model boundary is separate from Magic Format.
- Permission and approval UX have an explicit flow.
- Native helper use is a decision gate, not an assumption.
- Browser control is a separate adapter.
- Phase 0 remains read-only.
- No model, action, approval, or browser code is enabled.
