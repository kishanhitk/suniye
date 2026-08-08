# Suniye Computer Use parity audit

Date: 2026-08-08

Branch: `kis-169-computer-use`

Reference artifact: `/Users/kishan/Downloads/ChatGPT (1).dmg`

Reference build: `com.openai.codex` 26.727.51351 (6119)

## Overall verdict

Suniye is **not at overall ChatGPT/Codex Computer Use parity**. It is a functional,
single-process desktop-control prototype with a close match to the reference's public macOS action
vocabulary. It does not match the reference runtime architecture, policy and confirmation system,
full observation-diff behavior, error/session semantics, browser-control boundary, or verified
settings and activity UX.

This is not a percentage assessment. The missing areas are not equally weighted: native isolation,
safety policy, complete session semantics, and browser separation are release-level boundaries.

| Capability | Parity assessment | Evidence summary |
|---|---|---|
| Desktop action vocabulary | Broad parity | Both expose click, drag, key press, scroll, text entry, value setting, selection, and named secondary AX actions. |
| App discovery and targeting | Partial | Suniye resolves bundle IDs/display names and scans common app folders. The reference accepts display name, path, or bundle ID per call, returns usage metadata, reports ambiguity, and can launch through its helper. |
| Window discovery and activation | Partial | Both resolve app windows internally. Suniye relies on layer-zero Core Graphics windows and a local activation heuristic. The reference requests on-screen, non-desktop CG windows, joins them to AX windows, observes targets in the background, and conditionally coordinates focus for input. |
| Accessibility observation | Partial | Both provide indexed AX state. Suniye sends a bounded full flattened tree every turn. The reference assigns IDs in a depth-first rendered AX tree, retains revisions, maps IDs back to current AX elements, and supports insertion/removal diffs plus full-tree responses. |
| Screenshot handling | Partial | Both ground actions in a window screenshot. Suniye uses `CGWindowListCreateImage` in-process. The reference has window-ID-scoped ScreenCaptureKit and SkyLight/WindowServer paths with crop, size, opacity, shadow, delay, and encoding options. |
| Model and action loop | Partial | Suniye implements its own JSON chat-completions loop and requires a fresh observation before every action. The recovered reference instructions allow one or more ordered actions before fetching updated state for the next decision, use an approximately one-second base settle, and prefer AX indexes over coordinates. The client-selected model, request schema, context ordering, and Computer Use prompt injection are recovered; provider-private inference remains unknown. |
| Permissions | Partial | Both require Accessibility and screen capture. The reference has helper-owned permission/session states and Apple Events usage; Suniye has only main-process Accessibility and Screen Recording checks. |
| Approval and safety | Materially divergent | The reference performs policy checks on every app operation and can elicit session or persistent approval, with forbidden/denied outcomes and action-time safety rules. Suniye's default sets are empty and actions are auto-authorized. |
| Native helper and IPC | Missing | The reference ships a signed UI-element service and native client using versioned IPC. Suniye has no Computer Use helper target or authenticated IPC boundary. |
| Errors, cancellation, intervention | Partial | Suniye has typed local errors and cooperative cancellation. It lacks the reference's stable native error taxonomy for authentication, policy, ambiguity, lock screen, permission pending, user intervention, and incompatible versions. |
| UX | Partial | Suniye now has a conversation-first transcript, follow-up context, fixed composer, visible working/Stop state, and collapsed settings/debug sections below the conversation. The reference additionally has plugin-driven Any App/browser rows, extension management, and picture-in-picture activity controls. The complete reference turn UI remains partly unknown. |
| Browser control | Missing | The reference packages browser and Chrome control separately from desktop Computer Use. Suniye treats browsers as generic AX/screenshot desktop apps and has no extension, tab, DOM, Playwright, or CDP path. |
| Voice initiation | Suniye-specific addition | Suniye can route local dictation directly into a Computer Use task while the page is active. No parity claim is made for this behavior. |
| Automated confidence | Partial | The focused Swift suite passes, but there is no complete live provider + WindowServer + AX + CGEvent + browser + voice E2E matrix. |

## Reference evidence used

- `[Verified]` The DMG contains the Electron host, bundled `cua_node` runtime, the `@oai/sky`
  model-facing package, a separately signed `Codex Computer Use.app` service, and
  `SkyComputerUseClient.app`.
- `[Verified]` The service bundle identifier is `com.openai.sky.CUAService`; the helper and client
  are background UI-element applications and share the Computer Use app group with the host.
- `[Verified]` The JavaScript/native boundary identifies itself as `CodexComputerUseIPC-2` and
  carries framed JSON-RPC over a Unix socket. The native client also contains an XPC transport.
- `[Verified]` Public app operations pass through native app policy before state capture or action.
  Policy results include allowed, denied, and forbidden, plus risk and persistent-approval
  eligibility. The wrapper can request session or always approval.
- `[Verified]` The public macOS surface has `list_apps`, `get_app_state`, and app-scoped actions.
  Accessibility indexes are scoped to the latest observation, diffs are enabled by default, and
  callers are told to refetch state after actions.
- `[Verified]` A live MCP session against the DMG-shipped native client exposed exactly ten tools.
  Calculator state and a JPEG screenshot were captured twice while another app remained
  frontmost, proving background observation.
- `[Verified]` Preserved symbols, imported APIs, and targeted disassembly recover the helper's AX
  rendering/revision pipeline, on-screen/non-desktop CG-to-AX window matching, both screenshot
  backends, screenshot-to-screen coordinate transform, semantic AX actions, process-scoped event
  synthesis, conditional focus, settling, and stale-element refetch. See
  `native-algorithm-recovery-2026-08-09.md`.
- `[Verified]` The bundled UX assets expose Computer Use settings for Any App, Chrome/Edge,
  app-specific live-control plugins, extension management, and picture-in-picture activity.
- `[Verified]` Browser control is packaged as separate browser and Chrome plugins with browser-
  specific session, extension, and safety surfaces.
- `[Verified]` The artifact exposes model-profile base instructions and complete readable Computer
  Use operating instructions. The recovered GPT-5.6 Sol, Terra, and Luna base instructions are
  identical in this DMG.
- `[Verified]` The app-server accepts a client model override, the Responses request sends that
  resolved slug, and the request-construction algorithm and role ordering are recovered. A
  loopback request serialized by the DMG binary selected `gpt-5.6-luna`. See
  `runtime-request-and-model-selection-recovery-2026-08-08.md`.
- `[Unknown]` Provider-private inference, an actual response for an unexecuted task, five narrow
  native branch/ranking details, and the complete browser-extension protocol remain unavailable.

## Highest-priority parity gaps

1. Add a separately signed native Computer Use helper and client boundary with authenticated,
   versioned IPC, explicit deadlines, and stable errors.
2. Replace automatic approval with the reference-shaped per-operation policy and confirmation
   flow before any release. Keep automatic execution only as an explicit development mode.
3. Add observation diffs, forced full refresh, app-specific instructions, and loading-aware
   settling beyond the implemented one-second base delay.
4. Extend app resolution with full-path targeting, usage metadata, and explicit ambiguity errors.
   Suniye no longer silently forces the first running app.
5. Implement user intervention, lock-screen, permission-pending, helper-version, denied/forbidden,
   and cancellation semantics as first-class session outcomes.
6. Build browser control as a separate extension/session/DOM-oriented capability. Do not claim
   browser parity from generic desktop clicks.
7. Extend the conversation-first page with the verified settings integrations that are still
   absent: control scope, app/browser plugin state, extension management, and picture-in-picture
   activity. Do not invent unverified turn UI.
8. Add live E2E coverage across app launch, target switching, multi-window state, permission
   transitions, user intervention, stale observations, safe native actions, voice initiation, and
   the separate browser path.

## Implemented in this parity slice

- `[Implemented]` Observation freshness is explicit in every model request. A reused observation is
  marked stale and cannot enter approval or action execution.
- `[Implemented]` A stale observation may still help the model choose another target, ask the user,
  retry, block, or report completion.
- `[Implemented]` The system prompt now mirrors verified public workflow rules: prefer indexed AX
  actions, use screenshots as fallback, never invent indexes/actions, scope indexes to the current
  observation, target keyboard/text to one app, and obtain fresh state after every action.
- `[Implemented]` The base post-action settle changed from 150 milliseconds to the reference's
  documented approximate one second. Loading-aware waits of up to five seconds are not implemented.
- `[Implemented]` The optional starting-app control has a real “Let agent choose” state and refresh
  no longer auto-selects the first running app.
- `[Implemented]` The page is conversation-first. Prior user/assistant messages are included in
  follow-up model requests; the composer remains at the bottom; live work and Stop stay near the
  active turn; settings and observation debugging are collapsed below the transcript.
- `[Verified]` After a successful observation, a later `noWindow` can still reuse the previous
  observation for non-action recovery.
- `[Verified]` The reference `get_app_state` surface requires valid current state and directs
  callers to refetch after actions.
- `[Unknown]` The exact retry behavior inside the reference's hidden model orchestration is not
  available. Suniye's non-action stale-observation recovery therefore cannot be described as
  copied or verified behavior.

## Scope and evidence rules

The detailed implementation audit below covers current Suniye source and tests. The comparison
above additionally uses direct evidence from the mounted read-only reference DMG and its bundled
JavaScript declarations, native metadata, plugin documentation, policy wrapper, and UX assets.

- `[Verified]` means the behavior is directly established by current source or tests.
- `[Inferred]` means it is a consequence of verified implementation details but is not directly exercised end to end.
- `[Unknown]` means the repository does not provide enough evidence.

## Headline findings

- [Verified] Computer Use is implemented inside the main Suniye process. A `@MainActor` coordinator owns UI state, an actor owns the model/action loop, another actor serializes platform calls, and injected Swift services wrap macOS APIs. No Computer Use-specific helper or XPC boundary is instantiated. (`Suniye/Services/ComputerUseCoordinator.swift:20-28`, `Suniye/Services/ComputerUseAgent.swift:3-9`, `Suniye/Services/ComputerUsePlatformRunner.swift:3-15`, `project.yml:31-39`)
- [Verified] The feature is a screenshot-plus-Accessibility desktop agent driven by a generic OpenAI-compatible chat-completions endpoint. It is not a native provider-side computer tool protocol. (`Suniye/Services/ComputerUseModelClient.swift:54-75`, `Suniye/Services/ComputerUseModelClient.swift:224-283`)
- [Verified] Actions run without a user approval prompt under the default policy. Every action still receives an exact, one-use grant bound to request, app, window, observation generation, action, and session. (`Suniye/Services/ComputerUsePolicyService.swift:37-70`, `Suniye/Services/ComputerUsePolicyService.swift:104-129`, `Suniye/Services/ComputerUseActionService.swift:47-66`, `SuniyeTests/ComputerUsePhase5CoordinatorTests.swift:7-31`)
- [Verified] The agent has no iteration, failure, action, or elapsed-time limit. Retryable model failures and action failures continue the loop. (`Suniye/Services/ComputerUseAgent.swift:90-106`, `Suniye/Services/ComputerUseAgent.swift:214-219`, `Suniye/Services/ComputerUseAgent.swift:292-297`, `Suniye/Services/ComputerUseAgent.swift:359-365`)
- [Inferred] A provider that repeatedly fails or emits `retryable_failure` can keep the run alive until the user cancels or a non-recoverable observation error occurs.
- [Verified] The recent transient-window fix reuses the last successful observation when a later observation fails specifically with `noWindow`; the model receives that stale observation plus the failure message and may switch targets. (`Suniye/Services/ComputerUseAgent.swift:137-173`, `SuniyeTests/ComputerUsePhase3Tests.swift:355-391`)
- [Verified] There is no browser-specific control path, browser extension protocol, DOM observation, tab API, or browser action schema in the current Computer Use implementation. Browser apps are treated as ordinary macOS applications and windows. (`Suniye/Services/ComputerUseActionModels.swift:354-384`, `Suniye/Services/ComputerUseModels.swift:204-272`)
- [Verified] The full macOS test suite passed 1,096 tests with one skip and zero failures on 2026-08-08. Native WindowServer, Accessibility, screenshot, input-event, and SwiftUI rendering paths remain excluded from the coverage gate and are primarily tested through injected seams. (`scripts/coverage_exclusions.txt`)

## 1. Architecture and process boundaries

- [Verified] `MainWindowView` creates one window-scoped `ComputerUseCoordinator` and injects the current model configuration and voice handler registration into `ComputerUsePage`. (`Suniye/Views/MainWindow/MainWindowView.swift:3-7`, `Suniye/Views/MainWindow/MainWindowView.swift:59-71`)
- [Verified] `ComputerUseCoordinator` owns observable phase, application selection, permissions, the latest observation, task text, terminal result, and pending voice task. It also owns cancellation tokens and Swift `Task` handles. (`Suniye/Services/ComputerUseCoordinator.swift:20-56`)
- [Verified] The coordinator constructs the production application catalog, window discovery, window activation, permission, observation, action, policy, approval, and audit services through injectable protocol seams. (`Suniye/Services/ComputerUseCoordinator.swift:57-105`)
- [Verified] `ComputerUseAgent` is an actor with private loop state. Its external dependencies are a model client, approval authorizer, application catalog, observation service, and action service. (`Suniye/Services/ComputerUseAgent.swift:3-30`, `Suniye/Services/ComputerUseAgent.swift:90-118`)
- [Verified] `ComputerUsePlatformRunner` is a separate actor used by the coordinator to serialize catalog, permission, and manual-observation calls away from the main actor. (`Suniye/Services/ComputerUsePlatformRunner.swift:3-44`)
- [Verified] Remote model communication crosses the process boundary through `URLSession` in `ChatCompletionClient`; native discovery, observation, and action work stays in Suniye's app process. (`Suniye/Services/ComputerUseModelClient.swift:224-283`, `Suniye/Services/ChatCompletionClient.swift:77-115`)
- [Unknown] The repository does not establish how this in-process architecture behaves under prolonged WindowServer or Accessibility API stalls; the cancellation token cannot interrupt a native call already in progress. (`Suniye/Services/ComputerUseModels.swift:183-202`)

## 2. Application and window discovery

- [Verified] The running-app catalog comes from `NSWorkspace.shared.runningApplications`, excludes terminated and activation-policy-prohibited processes, requires a bundle identifier, and sorts the active app first and then by display name. (`Suniye/Services/ComputerUseApplicationCatalog.swift:8-29`, `Suniye/Services/ComputerUseApplicationCatalog.swift:97-115`)
- [Verified] Application IDs are bundle identifiers. Resolution accepts the ID, exact bundle identifier, or case-insensitive display name. (`Suniye/Services/ComputerUseApplicationCatalog.swift:31-41`, `Suniye/Services/ComputerUseApplicationCatalog.swift:117-119`)
- [Inferred] Multiple independently running instances with the same bundle identifier cannot be selected distinctly because identity collapses to the bundle identifier and resolution returns the first match.
- [Verified] The model's available-app list combines running apps with top-level `.app` bundles found in `/Applications`, `/System/Applications`, two CoreServices directories, and the user's `Applications` directory. Running apps sort before installed apps. (`Suniye/Services/ComputerUseApplicationCatalog.swift:49-65`, `Suniye/Services/ComputerUseApplicationCatalog.swift:141-158`)
- [Verified] A non-running app is launched with `NSWorkspace.openApplication`, without initial activation or adding it to recent items. Observation then polls for a visible window up to 20 times at 100 ms intervals. (`Suniye/Services/ComputerUseApplicationCatalog.swift:68-95`, `Suniye/Services/ComputerUseObservationService.swift:3-4`, `Suniye/Services/ComputerUseObservationService.swift:94-127`)
- [Verified] Window discovery uses `CGWindowListCopyWindowInfo` with `optionOnScreenOnly` and `excludeDesktopElements`, then keeps non-empty layer-zero windows owned by the target PID. (`Suniye/Services/ComputerUseApplicationCatalog.swift:161-205`)
- [Verified] Front-to-back CoreGraphics order is preserved. The first window is marked key only when its process is currently frontmost. (`Suniye/Services/ComputerUseApplicationCatalog.swift:207-223`, `SuniyeTests/ComputerUsePhase0Tests.swift:437-475`)
- [Verified] Observation chooses the marked key window, otherwise the first discovered window; there is no user-facing window selector. (`Suniye/Services/ComputerUseObservationService.swift:144-152`, `Suniye/Views/MainWindow/ComputerUsePage.swift:140-190`)

## 3. Observation, screenshots, and Accessibility

- [Verified] An observation contains a monotonically incremented generation, timestamp, exact application/window target, flattened Accessibility snapshot, and optional PNG screenshot. (`Suniye/Services/ComputerUseModels.swift:78-109`, `Suniye/Services/ComputerUseObservationService.swift:180-187`)
- [Verified] Default observation limits are depth 8, 500 AX elements, and 100,000 text characters; element bounds are included, password-like AX roles are redacted, and the target is not activated unless the caller opts in. (`Suniye/Services/ComputerUseModels.swift:111-120`, `Suniye/Services/ComputerUseAccessibilityReader.swift:505-587`, `Suniye/Services/ComputerUseAccessibilityReader.swift:680-693`)
- [Verified] Agent observations set `activateTarget = true`; manual captures use the default non-activating configuration. (`Suniye/Services/ComputerUseAgent.swift:136-145`, `Suniye/Services/ComputerUsePlatformRunner.swift:36-44`)
- [Verified] Target activation uses `NSRunningApplication.activate`; for another process it attempts `AXRaise`, but a failed or unsupported raise does not fail activation after the app itself activates. Suniye's own process skips AX raise to avoid re-entrant AppKit behavior. (`Suniye/Services/ComputerUseWindowActivationService.swift:5-11`, `Suniye/Services/ComputerUseWindowActivationService.swift:25-52`)
- [Verified] AX window resolution tries a matching focused window, then a unique exact-title match, then a unique bounds match with three-point tolerance, then the sole AX window. Ambiguous unmatched windows fail. (`Suniye/Services/ComputerUseAccessibilityReader.swift:70-143`)
- [Verified] The AX snapshot records role, subrole, title, description, value, enabled/focused/selected state, optional bounds, supported AX action names, and child indexes. (`Suniye/Services/ComputerUseModels.swift:63-82`, `Suniye/Services/ComputerUseAccessibilityReader.swift:538-599`)
- [Verified] Only AX values for password-like roles are redacted. The screenshot is not redacted before storage, preview, or transmission to the configured endpoint. (`Suniye/Services/ComputerUseAccessibilityReader.swift:542-546`, `Suniye/Services/ComputerUseScreenshotService.swift:22-34`, `Suniye/Services/ComputerUseModelClient.swift:247-265`)
- [Verified] Screenshot capture uses `CGWindowListCreateImage` for the selected window bounds and ID, requests best resolution, ignores framing, and encodes PNG. (`Suniye/Services/ComputerUseScreenshotService.swift:6-34`)
- [Verified] Observation checks Accessibility permission before window/AX reading and Screen Recording permission before screenshot capture. Any missing app, stopped app, window, AX window, permission, activation, or screenshot produces a typed observation error. (`Suniye/Services/ComputerUseObservationService.swift:130-178`, `Suniye/Services/ComputerUseModels.swift:145-179`)

## 4. Supported action set

- [Verified] The schema supports coordinate click, AX-element click, key press with modifiers, element-relative scroll, Unicode text entry, AX value setting, coordinate drag, AX text/cursor selection, and arbitrary named secondary AX actions on indexed elements. (`Suniye/Services/ComputerUseActionModels.swift:354-384`)
- [Verified] Click supports left, right, and middle buttons plus click counts; scroll supports four directions; selection supports selecting text or placing the cursor before or after it. (`Suniye/Services/ComputerUseActionModels.swift:14-65`, `Suniye/Services/ComputerUseActionModels.swift:55-59`)
- [Verified] Coordinate clicks and drags are window-relative in the model schema and converted to global screen coordinates. (`Suniye/Services/ComputerUseModelClient.swift:71-74`, `Suniye/Services/ComputerUseActionService.swift:159-167`)
- [Verified] Coordinate mouse events and scrolling post through the HID event tap; key events post directly to the target PID. (`Suniye/Services/ComputerUseInputEventService.swift:4-38`, `Suniye/Services/ComputerUseInputEventService.swift:79-114`, `Suniye/Services/ComputerUseInputEventService.swift:116-158`)
- [Verified] `type_text` posts Unicode keyboard events directly to the target PID rather than using Suniye's clipboard-paste fallback. (`Suniye/Services/ComputerUseActionService.swift:103-116`, `Suniye/Services/TextInsertionService.swift:109-139`)
- [Verified] Left element clicks perform `AXPress`; non-left element clicks use the element center when bounds exist. `set_value`, text selection, and secondary actions resolve the indexed element again from the current target AX tree. (`Suniye/Services/ComputerUseActionService.swift:197-227`, `Suniye/Services/ComputerUseAccessibilityReader.swift:211-281`, `Suniye/Services/ComputerUseAccessibilityReader.swift:283-360`)
- [Verified] There are no dedicated wait, hover-only, screenshot-only, shell, file, menu-bar, notification, clipboard-read, or browser-navigation actions in the action enum. (`Suniye/Services/ComputerUseActionModels.swift:354-384`)

## 5. Model protocol and loop

- [Verified] Computer Use requires enabled `.openAICompatible` settings, a validated HTTP(S) endpoint, model ID, and keychain API key. The factory raises the timeout and output budget to at least 120 seconds and 2,048 tokens. (`Suniye/Services/ComputerUseModelConfigurationFactory.swift:3-31`, `Suniye/AppState.swift:782-786`, `Suniye/Services/ComputerUseModelClient.swift:27-52`)
- [Verified] A run without a selected app begins with a model request that has no observation and includes discovered applications. The model must select an explicit app or return a terminal decision; an action before observation is rejected. Later requests contain the fresh or stale observation for the selected app. (`Suniye/Services/ComputerUseAgentModels.swift`, `Suniye/Services/ComputerUseAgent.swift`)
- [Verified] The rendered prompt includes task text, target app, available apps, flattened AX text, action summaries, failure messages, and the screenshot as a base64 data URL. (`Suniye/Services/ComputerUseModelClient.swift:146-184`, `Suniye/Services/ComputerUseModelClient.swift:247-265`)
- [Verified] The transport sends one non-streaming chat-completions-style request at temperature zero. The response must decode to one JSON decision: action, target, completed, ask-user, blocked, or retryable-failure. Markdown-fenced JSON is tolerated. (`Suniye/Services/ComputerUseModelClient.swift:78-92`, `Suniye/Services/ComputerUseModelClient.swift:188-220`, `Suniye/Services/ComputerUseModelClient.swift:258-283`, `Suniye/Services/ComputerUseAgentModels.swift:56-97`)
- [Verified] The loop order is bootstrap target/terminal decision when needed, then observe/activate, ask the model for one decision, optionally authorize and execute one action, wait one second, and observe again. A target decision changes the application ID and immediately starts the next observation. (`Suniye/Services/ComputerUseAgent.swift`, `Suniye/Services/ComputerUseModelClient.swift`)
- [Verified] Invalid non-empty decisions, provider errors, retryable model decisions, action errors, and post-action settling errors are accumulated as failures and retried. An unconfigured model and most observation errors terminate as failed. (`Suniye/Services/ComputerUseAgent.swift:184-220`, `Suniye/Services/ComputerUseAgent.swift:250-255`, `Suniye/Services/ComputerUseAgent.swift:292-352`)
- [Verified] The prompt history arrays are not bounded or summarized by the agent. (`Suniye/Services/ComputerUseAgent.swift:90-105`, `Suniye/Services/ComputerUseAgent.swift:176-182`)
- [Inferred] Long-running tasks can grow request size on every iteration, especially when failures repeat.

## 6. Permissions

- [Verified] Desktop observation and agent execution are gated on both Accessibility and Screen Recording permission. (`Suniye/Services/ComputerUseCoordinator.swift:130-155`)
- [Verified] Permission state and prompts use `AXIsProcessTrusted`, `AXIsProcessTrustedWithOptions`, `CGPreflightScreenCaptureAccess`, and `CGRequestScreenCaptureAccess`. (`Suniye/Services/ComputerUsePermissionService.swift:5-45`)
- [Verified] Action execution rechecks Accessibility but not Screen Recording; subsequent re-observation still requires both. (`Suniye/Services/ComputerUseActionService.swift:62-66`, `Suniye/Services/ComputerUseObservationService.swift:139-174`)
- [Verified] Voice task capture additionally depends on Suniye's existing microphone permission and local transcription pipeline, although microphone permission is not part of the Computer Use permission snapshot. (`Suniye/AppState.swift:1552-1565`, `Suniye/AppState.swift:3710-3738`)
- [Unknown] The current source does not request or expose a separate Input Monitoring permission state, so this audit cannot establish whether macOS will require it for every supported CGEvent path on every supported OS configuration.

## 7. Approvals, policy, and safety

- [Verified] Production coordinator wiring uses `ComputerUseApprovalPolicyActor`, not the simpler automatic-authorizer default on the agent initializer. (`Suniye/Services/ComputerUseCoordinator.swift:69-82`, `Suniye/Services/ComputerUseAgent.swift:11-16`)
- [Verified] The default policy has no configured denied or forbidden bundle IDs and no persistent-approval risks. It still forbids the current Suniye host bundle and apps without bundle identifiers; other apps receive `.once` scope. (`Suniye/Services/ComputerUsePolicyService.swift`)
- [Verified] Authorization is automatic: the policy service selects a remembered allowed scope or `.once`, stores it if applicable, creates the grant, and records the decision. There is no user decision callback in this path. (`Suniye/Services/ComputerUsePolicyService.swift:104-150`)
- [Verified] The conversation UI has no approval dialog or approval controls; actions remain automatic under the current development policy. (`Suniye/Views/MainWindow/ComputerUsePage.swift`, `Suniye/Services/ComputerUsePolicyService.swift`)
- [Verified] Session and persistent approval storage exists, but the default policy cannot issue those scopes. Persistent records use `UserDefaults`; session records are in-memory and keyed by bundle, risk, and session UUID. (`Suniye/Services/ComputerUseApprovalStore.swift:38-58`, `Suniye/Services/ComputerUseApprovalStore.swift:60-132`)
- [Verified] Before observation and input, the shared app policy rejects denied or forbidden targets. The action service additionally validates approval, exact target and generation binding, current Accessibility permission, and target activation. (`Suniye/Services/ComputerUseObservationService.swift`, `Suniye/Services/ComputerUseActionService.swift`)
- [Verified] Audit logs contain bundle ID, risk, a content-reduced action summary, scope, request ID, and session ID. Text-entry summaries record only character counts. (`Suniye/Services/ComputerUseAudit.swift:16-42`, `Suniye/Services/ComputerUseActionModels.swift:569-592`)
- [Unknown] No release policy configuration or end-user policy-management UI is established by the current Computer Use wiring.

## 8. Cancellation, errors, and user intervention

- [Verified] Cancellation combines Swift task cancellation with a lock-protected token checked between native calls, before and after model requests, and throughout action execution. It cannot abort a CoreGraphics or AX call already running. (`Suniye/Services/ComputerUseModels.swift:183-202`, `Suniye/Services/ComputerUseAgent.swift:127-155`, `Suniye/Services/ComputerUseAgent.swift:389-424`)
- [Verified] The coordinator rejects stale async results with operation UUID checks and cancels observation/agent tasks plus the shared token when the user cancels, refreshes, changes app, or leaves the page. (`Suniye/Services/ComputerUseCoordinator.swift:254-263`, `Suniye/Services/ComputerUseCoordinator.swift:266-299`, `Suniye/Services/ComputerUseCoordinator.swift:340-358`, `Suniye/Services/ComputerUseCoordinator.swift:419-474`, `Suniye/Views/MainWindow/ComputerUsePage.swift:85-88`)
- [Verified] `completed`, `ask_user`, `blocked`, `cancelled`, and `failed` are terminal agent phases. Only `.failed` maps to the coordinator's failed phase; the other terminal outcomes map to `agentCompleted`. (`Suniye/Services/ComputerUseAgentModels.swift:7-13`, `Suniye/Services/ComputerUseCoordinator.swift:476-487`)
- [Verified] An `ask_user` result appears as an assistant message. The user's next chat message starts a new agent run with the prior user/assistant conversation supplied as context. There is no continuation token or resumption of the prior run's private action/failure state. (`Suniye/Services/ComputerUseCoordinator.swift`, `Suniye/Views/MainWindow/ComputerUsePage.swift`)
- [Verified] Observation cancellation returns the manual coordinator to ready without an error; an agent cancellation returns a terminal cancelled result. (`Suniye/Services/ComputerUseCoordinator.swift:396-415`, `Suniye/Services/ComputerUseAgent.swift:431-443`)
- [Verified] Provider request cancellation propagates into `URLSession`, and request timeout is implemented by racing the request against a task-group deadline. (`Suniye/Services/ChatCompletionClient.swift:112-166`)

## 9. Voice integration

- [Verified] The visible Computer Use page registers its coordinator as a weak voice-task handler on appear and unregisters it on disappear. (`Suniye/Views/MainWindow/ComputerUsePage.swift:77-88`, `Suniye/AppState.swift:1507`, `Suniye/AppState.swift:3232-3237`)
- [Verified] While that handler exists, ordinary hold-to-dictate sessions route the locally transcribed text to Computer Use instead of inserting or copying it. (`Suniye/AppState.swift:1552-1565`, `Suniye/AppState.swift:3710-3738`, `Suniye/AppState.swift:4574-4582`, `SuniyeTests/AppStateComputerUseVoiceTests.swift:6-37`)
- [Verified] A voice task starts immediately when model and permissions are ready, queues while configuration or permissions are missing, and is rejected while an agent or observation is already running. (`Suniye/Services/ComputerUseCoordinator.swift:205-224`, `Suniye/Services/ComputerUseCoordinator.swift:489-505`, `SuniyeTests/ComputerUsePhase5CoordinatorTests.swift:33-139`)
- [Verified] Empty transcripts and a disappearing page handler fail safely; accepted and queued tasks do not use normal text insertion. (`Suniye/AppState.swift:3766-3795`, `SuniyeTests/AppStateComputerUseVoiceTests.swift:40-126`)
- [Unknown] There is no test of microphone capture, real ASR, a live remote model, and native desktop actions as one continuous automated voice-to-action flow.

## 10. Browser support

- [Verified] There is no dedicated browser service, extension transport, DOM/accessibility bridge, tab/session API, URL navigation API, or browser-specific permission flow in the current Computer Use source.
- [Verified] A browser can appear in the generic application catalog and be selected or targeted by bundle ID/display name like any other app. (`Suniye/Services/ComputerUseApplicationCatalog.swift:20-65`, `Suniye/Services/ComputerUseAgentModels.swift:56-62`)
- [Inferred] Suniye can attempt browser tasks through visible browser chrome and web content exposed through macOS Accessibility plus screenshot coordinates, using the same generic desktop actions.
- [Unknown] The repository does not establish reliable DOM element identity, tab control, authenticated-page behavior, navigation completion detection, downloads/uploads, or extension-assisted browser automation.

## 11. UX

- [Verified] Computer Use is a conversation-first main-window section with user and assistant messages, follow-up context, a fixed composer, working/Stop state, and a new-conversation action. Model status, permissions, optional starting app, manual observation capture, screenshot, and AX text are in collapsed sections below the transcript. (`Suniye/Views/MainWindow/ComputerUsePage.swift`, `Suniye/Views/MainWindow/ComputerUseDetailsView.swift`)
- [Verified] The starting-app picker exposes “Let agent choose,” and refresh preserves an unset selection instead of choosing the first running app. (`Suniye/Services/ComputerUseCoordinator.swift`, `Suniye/Views/MainWindow/ComputerUseDetailsView.swift`)
- [Verified] Agent start is disabled until a model exists and both desktop permissions are granted, but it does not require a selected app at the coordinator level. (`Suniye/Services/ComputerUseCoordinator.swift`, `Suniye/Views/MainWindow/ComputerUsePage.swift`)
- [Verified] Failed agent results now show `Computer Use failed`; non-failed terminal outcomes—including blocked, cancelled, and ask-user—show under `Computer Use finished`. (`Suniye/Services/ComputerUseCoordinator.swift:158-178`, `Suniye/Services/ComputerUseCoordinator.swift:476-487`, `Suniye/Views/MainWindow/ComputerUsePage.swift:23-55`)
- [Verified] The collapsed observation details can expose the captured screenshot and flattened AX text; it does not show individual action history, failure history, current iteration, or audit records. (`Suniye/Views/MainWindow/ComputerUseDetailsView.swift`)

## 12. Testing and current confidence

- [Verified] The focused suite covers observation and permission seams, coordinator state, action schemas and delegation, agent decisions/retries/cancellation, policy and approval storage, model payload/parsing, window activation policy, model configuration, and dictation routing. (`SuniyeTests/ComputerUsePhase0Tests.swift:7-497`, `SuniyeTests/ComputerUsePhase2ActionTests.swift:7-749`, `SuniyeTests/ComputerUsePhase3Tests.swift:6-748`, `SuniyeTests/ComputerUsePhase4PolicyTests.swift:6-299`, `SuniyeTests/ComputerUsePhase5CoordinatorTests.swift:7-343`, `SuniyeTests/ComputerUsePhase5ModelTests.swift:11-326`, `SuniyeTests/AppStateComputerUseVoiceTests.swift:6-126`)
- [Verified] The full `xcodebuild` test run completed 1,096 passing tests with one skip and zero failures on 2026-08-08. Gated line coverage was 95.01% (13,851/14,578), above the repository's 95% floor.
- [Verified] The transient-window regression test specifically scripts successful self-observation, `retryable_failure`, `noWindow`, a target switch, and completion; it asserts the stale observation's failure context is sent to the model. (`SuniyeTests/ComputerUsePhase3Tests.swift:355-391`)
- [Verified] The failure-UX regression test asserts an observation failure produces coordinator phase `.failed` and title `Computer Use failed`. (`SuniyeTests/ComputerUsePhase5CoordinatorTests.swift:205-229`)
- [Verified] Live NSWorkspace/WindowServer discovery, AX traversal, AX raise, TCC prompts, window screenshot capture, CGEvent posting, and SwiftUI Computer Use views are excluded from coverage with explicit platform-bound reasons. (`scripts/coverage_exclusions.txt:25-30`, `scripts/coverage_exclusions.txt:49-51`)
- [Verified] The repository has no dedicated automated Computer Use E2E script or UI-test target; the focused tests use injected stubs for native and provider behavior.
- [Unknown] A live Accessibility inspection of the installed Suniye Preview UI timed out twice with Computer Use runtime error `-10005 timeoutReached`; visual parity is therefore not claimed by this audit.
- [Unknown] The passing suite does not establish full live reliability across arbitrary applications, multi-window applications, browsers, changing Spaces, minimized/hidden windows, permission revocation during actions, or real provider output variability.

## 13. Recent transient-window fix assessment

- [Verified] Before a first successful observation, `noWindow` remains terminal. After a successful observation, any later `noWindow` reuses that last observation, increments failure count, and continues to the model. Other observation failures remain terminal. (`Suniye/Services/ComputerUseAgent.swift:137-173`)
- [Verified] The reused observation retains its original generation, app/window target, AX snapshot, screenshot, and timestamp; the only new state is the appended localized failure message. (`Suniye/Services/ComputerUseAgent.swift:90-105`, `Suniye/Services/ComputerUseAgent.swift:157-162`, `Suniye/Services/ComputerUseModels.swift:103-109`)
- [Inferred] This can recover when the next model decision switches to another app, as the regression test demonstrates.
- [Verified] If the model emits an action against a reused observation, the agent rejects it before approval or action execution and records a retryable fresh-observation failure. (`Suniye/Services/ComputerUseAgent.swift`, `SuniyeTests/ComputerUsePhase3Tests.swift`)
- [Inferred] Repeated `noWindow` results can repeatedly reuse the same observation without a built-in limit.
- [Unknown] No live test establishes whether this recovery is safe or reliable for hidden, minimized, closed, moved, or Space-separated windows.

## 14. Open questions from current evidence

- [Unknown] What explicit liveness limit should terminate repeated provider, action, or transient-window failures?
- [Unknown] Should a future native helper reject stale action requests independently of the in-process agent boundary?
- [Unknown] Should `ask_user` eventually resume the same native session instead of starting a contextual follow-up run?
- [Unknown] Which actions, apps, or data classes should require user confirmation before release, given the current approve-by-default wiring?
- [Unknown] Is browser control intentionally generic desktop control, or will a separate browser-extension/DOM path be added?
- [Unknown] What live installed-app E2E matrix is required before treating native observation and action paths as release-ready?
