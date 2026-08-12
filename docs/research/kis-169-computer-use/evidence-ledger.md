# KIS-169 evidence ledger

Status: active research ledger.

Date: 2026-08-02

## Recording method

I record each evidence block after inspection.

I mark each claim as verified, inferred, or unknown.

I correct claims when later evidence changes their meaning.

## Atomic change log

### Entry 1: Worktree and source scope

- `[Verified]` The worktree is `/Users/kishan/.codex/worktrees/eaaa/suniye`.
- `[Verified]` The branch is `kis-169-computer-use`.
- `[Verified]` The source DMG is `/Users/kishan/Downloads/ChatGPT (1).dmg`.
- `[Verified]` The DMG mounted read-only at `/tmp/suniye-chatgpt-dmg-mount`.
- `[Verified]` No production code was changed before this research folder was created.

### Entry 2: ChatGPT app inventory

- `[Verified]` The app bundle identifier is `com.openai.codex`.
- `[Verified]` The app contains `Contents/Resources/cua_node`.
- `[Verified]` The app contains the `@oai/sky` package below `cua_node/lib/node_modules`.
- `[Verified]` The Sky package contains `Codex Computer Use.app`.
- `[Verified]` The ChatGPT app contains native resources named `sky.node`, `codex-macos`, and `launch-services-helper`.
- `[Verified]` The main app declares Apple Events usage for Mac app control.
- `[Verified]` The main app is not App Sandbox restricted.
- `[Verified]` The main app declares the application group `com.openai.sky.CUAService`.

### Entry 3: Sky macOS public API

Source family: `@oai/sky/dist/project/cua/sky_js/src/targets/mac`.

- `[Verified]` The macOS client sends `ComputerUseIPCListAppsRequest`.
- `[Verified]` The macOS client sends `ComputerUseIPCAppPolicyRequest`.
- `[Verified]` The macOS client sends `ComputerUseIPCAppGetSkyshotRequest`.
- `[Verified]` The macOS client sends `ComputerUseIPCAppPerformActionRequest`.
- `[Verified]` The macOS client sends `ComputerUseIPCAppStartRequest`.
- `[Verified]` The public macOS target exposes `list_apps` and `get_app_state`.
- `[Verified]` The public macOS target exposes click, drag, key press, scroll, text entry, value setting, text selection, and secondary accessibility actions.
- `[Verified]` The app state contains one screenshot and accessibility text.
- `[Verified]` The screenshot uses a data URL.
- `[Verified]` The app identifier can come from `list_apps()`.
- `[Verified]` The action element index comes from the latest app-state text.
- `[Verified]` Coordinate clicks and drags use app-window screenshot coordinates.
- `[Verified]` Key chords use names such as `Control_L+a` and `Super_L+d`.
- `[Verified]` Secondary actions pass an accessibility action name.

### Entry 4: Sky transport and helper launch

- `[Verified]` The macOS JavaScript client uses `MacNativePipeTransport`.
- `[Verified]` The default socket path is in the `com.openai.sky.CUAService` group container.
- `[Verified]` `SKY_CUA_SERVICE_NATIVE_PIPE_PATH` can override that socket path.
- `[Verified]` The client can ask the host service to ensure the Computer Use service.
- `[Verified]` The client can launch `Codex Computer Use.app` through the host launch-services bridge.
- `[Verified]` The transport uses JSON-RPC over a four-byte little-endian length prefix.
- `[Verified]` The transport rejects frames larger than eight megabytes.
- `[Verified]` The transport serializes requests through one promise chain.
- `[Verified]` The default client request timeout is 120 seconds.
- `[Verified]` The transport pings the service and checks the API version.
- `[Inferred]` The helper owns the native desktop operations, while Sky provides the model-facing JavaScript surface.

### Entry 5: Policy, approval, and errors

- `[Verified]` Each Sky action runs through `withComputerUsePolicy`.
- `[Verified]` The policy requests an app policy before an action.
- `[Verified]` The policy supports allowed, denied, and forbidden decisions.
- `[Verified]` A denied policy produces an app-blocked error.
- `[Verified]` A forbidden policy produces a safety-blocked error.
- `[Verified]` The user approval message includes the app display name.
- `[Verified]` Approval metadata identifies Computer Use and the app bundle identifier.
- `[Verified]` Approval persistence can include `session` and `always`.
- `[Verified]` Approval outcomes include accepted, canceled, and declined.
- `[Verified]` The product records Computer Use tool telemetry.
- `[Verified]` The error table includes app-not-allowed, app-not-found, accessibility, permissions, no-active-session, user-stopped-session, permissions-pending, user-intervened, ambiguous-app, and screen-locked errors.

### Entry 6: Native helper evidence

- `[Verified]` `Codex Computer Use.app` has bundle identifier `com.openai.sky.CUAService`.
- `[Verified]` Its minimum macOS version is 14.4.
- `[Verified]` Its executable is an arm64 Mach-O binary named `SkyComputerUseService`.
- `[Verified]` It links ApplicationServices, AppKit, CoreGraphics, ScreenCaptureKit, QuartzCore, WebKit, XPC, and other system frameworks.
- `[Verified]` Its binary contains symbols or strings for `AXUIElement`, `CGEvent`, `CGWindow`, `ScreenCaptureKit`, `Accessibility`, `Screen Recording`, window tracking, permission requests, and JSON-RPC socket classes.
- `[Verified]` The helper has an application group and Apple Events entitlement.
- `[Inferred]` The helper can use Accessibility, Core Graphics events, and ScreenCaptureKit. Binary strings alone do not prove which path each operation uses.
- `[Superseded by Entry 54]` This initial static-only pass did not recover the helper's behavior.
  A later live MCP session, preserved symbols, imports, and targeted disassembly recovered its
  observable protocol and major native algorithms. Five specific internal details remain unknown.

### Entry 7: Capture bridge

- `[Verified]` The readable worker code defines `ComputerUseIPCAppStartCaptureRequest`.
- `[Verified]` The readable worker code defines `ComputerUseIPCAppNextCaptureUpdateRequest`.
- `[Verified]` Capture updates include metadata, accessibility text, screenshot, completed, and failed variants.
- `[Verified]` Start responses include `none_granted`, `accessibility_granted`, and `screen_recording_granted` states.
- `[Verified]` Start can return `appshot_permissions_abandoned`.
- `[Verified]` The main app sends capture requests to the helper by Apple Event.
- `[Verified]` The Apple Event target uses the helper process identifier.
- `[Verified]` The worker retries selected transient Apple Event errors.
- `[Verified]` The worker validates returned screenshot paths, image types, and a 25 MB size limit.
- `[Verified]` The main app handles missing screenshots, failed updates, abandoned permissions, and completed captures without screenshots.
- `[Inferred]` Apple Events connect the Electron worker to the helper. The model-facing Sky action path uses the helper's JSON-RPC socket.

### Entry 8: App-specific instructions

- `[Verified]` The helper bundle contains app-specific instructions for Apple Music, Clock, iPhone Mirroring, Notion, Numbers, Slack, and Spotify.
- `[Verified]` The instructions describe state checks, focus checks, safe text entry, and app-specific action sequences.
- `[Verified]` The `window_result` wrapper can add app-specific instructions to the accessibility text.
- `[Inferred]` The product supplements generic actions with app-specific guidance when generic semantics are not reliable.

### Entry 9: Current unknowns

- `[Unknown]` The shipped DMG does not expose the exact model name or model prompt in the inspected readable files.
- `[Unknown]` The shipped DMG does not expose the full server-side model action loop.
- `[Unknown]` The exact macOS window-selection algorithm is not visible in the public Sky wrapper.
- `[Unknown]` The exact browser-control implementation is not the same as the macOS window target. More browser tracing is required.
- `[Unknown]` The exact cancellation message for an in-flight native macOS action is not visible yet.

### Entry 10: Capture worker and appshot flow

- `[Verified]` A `computer-use-worker` handles capture start and update-watch requests.
- `[Verified]` The worker polls the native helper for one update at a time.
- `[Verified]` The worker continues polling until it receives `completed` or `failed`.
- `[Verified]` The worker converts polling errors into a failed update with `update_poll_failed`.
- `[Verified]` The worker's readable `handleCancel()` method is empty.
- `[Verified]` The main app stores capture state by request ID.
- `[Verified]` The main app discards updates when the attachment generation is stale.
- `[Verified]` The main app stores metadata, AX text, and screenshots separately.
- `[Verified]` The main app requires a screenshot before it attaches the completed appshot context.
- `[Verified]` The main app reports `start_response_missing`, `permission_window_abandoned`, `start_request_failed`, and `completed_without_screenshot`.
- `[Inferred]` Capture cancellation may exist below this worker. The readable worker does not implement it.

### Entry 11: Host native addon

- `[Verified]` The Electron host loads `sky.node` as a native addon on macOS.
- `[Verified]` The addon exposes a frontmost-window query.
- `[Verified]` The addon exposes Computer Use service spawning.
- `[Verified]` The addon exposes a process-executable-path match check.
- `[Verified]` The host has a `computer-use-frontmost-window` handler.
- `[Verified]` The host has a `computer-use-start-capture` handler.
- `[Verified]` The host passes a helper process identifier to the Apple Event bridge.
- `[Inferred]` The host uses the native addon for helper lifecycle and frontmost-app lookup.

### Entry 12: Foreground screen context

- `[Verified]` The `capture_screen_context` tool is separate from the lightweight Codex page-state tool.
- `[Verified]` When the Codex window is focused, the tool returns lightweight Codex page and thread state.
- `[Verified]` On macOS, when another app is focused, the tool finds the foreground app and captures an appshot.
- `[Verified]` The appshot result includes accessibility text and an image.
- `[Verified]` The tool refuses to guess screen details when capture fails.
- `[Verified]` The tool checks whether screen context is enabled before capture.
- `[Inferred]` Appshots provide context to an agent, but they do not prove that the same path executes Computer Use actions.

### Entry 13: Runtime inspection limit

- `[Verified from prior local runtime evidence, not from the DMG]` Computer Use refused the `com.openai.codex` app for safety.
- `[Verified]` I did not retry that blocked UI path.
- `[Inferred]` Static artifact analysis is the safe evidence source for this task.

### Entry 14: Suniye orchestration and state

Source: `Suniye/AppState.swift`.

- `[Verified]` `AppState` is both `@MainActor` and `@Observable`.
- `[Verified]` The existing phase machine has needs-model, downloading-model, loading, ready, recording, transcribing, and error states.
- `[Verified]` `AppState` owns audio capture, transcription, text insertion, hotkeys, Magic Format, history, settings, and analytics.
- `[Verified]` The state machine injects protocols for most services.
- `[Verified]` Tests can inject the frontmost app bundle identifier provider.
- `[Verified]` The recording session stores the frontmost bundle identifier before Suniye UI changes focus.
- `[Verified]` The current destination is system insertion, clipboard-only, onboarding practice, or edit rewrite.
- `[Verified]` The current dictation flow has one active session and rejects wrong-phase starts.
- `[Verified]` Audio capture and transcription are asynchronous.
- `[Verified]` Audio capture can cancel on interruption and system sleep.
- `[Verified]` The current dictation flow has no desktop observation loop.

### Entry 15: Suniye Accessibility and input

Sources: `Suniye/Services/TextInsertionService.swift`, `Suniye/Services/EditModeService.swift`, and `Suniye/Services/AccessibilityOnboarding.swift`.

- `[Verified]` Suniye reads the focused Accessibility element through `AXUIElementCreateSystemWide`.
- `[Verified]` Suniye reads AX value, selected text, and selected text range.
- `[Verified]` Suniye sets `kAXSelectedTextAttribute` when direct insertion works.
- `[Verified]` Suniye falls back to clipboard-preserving paste.
- `[Verified]` Suniye posts keyboard events through `CGEvent` at `.cghidEventTap`.
- `[Verified]` Suniye uses CGEvent Return to submit active input.
- `[Verified]` Edit Mode reads selected text through Accessibility or a clipboard copy fallback.
- `[Verified]` Suniye checks Accessibility trust before normal insertion.
- `[Verified]` Suniye has a Permiso Accessibility onboarding overlay with polling and a 300-second safety timeout.
- `[Verified]` The vendored permission helper uses `CGWindowListCopyWindowInfo` to locate a System Settings window.
- `[Verified]` These services support focused text insertion. They do not provide a general AX tree, window capture, mouse action, or screen image.

### Entry 16: Suniye permissions and bundle configuration

Sources: `Suniye/AppState.swift`, `Suniye/Info.plist`, and `project.yml`.

- `[Verified]` Suniye requests Microphone permission through AVFoundation.
- `[Verified]` Suniye checks Accessibility through `AXIsProcessTrusted` and `AXIsProcessTrustedWithOptions`.
- `[Verified]` Suniye routes users to the Accessibility System Settings pane.
- `[Verified]` Suniye declares microphone and speech-recognition usage descriptions.
- `[Verified]` Suniye does not declare a Screen Recording usage description.
- `[Verified]` Suniye has no current Screen Recording permission service.
- `[Verified]` The project targets macOS 14.0.
- `[Verified]` The project source of truth is `project.yml`.
- `[Inferred]` A Computer Use feature needs a new Screen Recording permission path and related project metadata.

### Entry 17: Suniye model and network seams

Sources: `Suniye/Services/LLMPostProcessor.swift`, `ChatCompletionClient.swift`, `MagicFormatCoordinator.swift`, and `LocalGemmaLlamaCppClient.swift`.

- `[Verified]` Existing LLM post-processing accepts text and returns text.
- `[Verified]` Existing chat messages encode string content only.
- `[Verified]` Existing Magic Format providers are Apple Foundation Models, local Gemma, and OpenAI-compatible HTTP.
- `[Verified]` Local Gemma runs a bundled `llama-server` process on loopback.
- `[Verified]` Local Gemma uses `/v1/chat/completions` and a text-only payload.
- `[Verified]` Existing Magic Format has provider resolution, timeouts, cancellation, and fallback behavior.
- `[Verified]` Existing per-app prompts add text instructions by bundle identifier.
- `[Verified]` No existing model protocol accepts screenshots, AX trees, or typed desktop actions.
- `[Inferred]` Computer Use needs a separate model protocol. It should not overload Magic Format.

### Entry 18: Suniye test and build seams

Sources: `SuniyeTests/TestDoubles.swift`, `project.yml`, and `scripts/coverage_exclusions.txt`.

- `[Verified]` Suniye tests already use spies and stubs for AppState service protocols.
- `[Verified]` Existing test doubles cover audio capture, transcription, text insertion, hotkeys, permissions, model management, and LLM providers.
- `[Verified]` The test target is generated from `project.yml`.
- `[Verified]` Coverage excludes live Accessibility onboarding, global hotkeys, hardware audio, and other OS-bound paths.
- `[Inferred]` A Computer Use loop should keep pure state and policy logic testable without live WindowServer access.

### Entry 19: Suniye capability gap

- `[Verified]` Suniye supports hold-to-talk dictation, local ASR, optional text cleanup, focused text insertion, clipboard copy, submit-key posting, and Edit Mode.
- `[Verified]` Suniye supports per-app text prompt bindings.
- `[Verified]` Suniye does not support app discovery for agent control.
- `[Verified]` Suniye does not support window discovery for agent control.
- `[Verified]` Suniye does not capture target app screenshots.
- `[Verified]` Suniye does not serialize AX trees for a model.
- `[Verified]` Suniye does not execute model-selected mouse, keyboard, scroll, drag, or semantic AX actions.
- `[Verified]` Suniye does not have Computer Use approvals, risk policy, action audit, or intervention monitoring.
- `[Verified]` Suniye does not have browser-specific control.

### Entry 20: Browser and desktop product surfaces

Sources: extracted `browser-use-settings`, `computer-use-settings`, and `browser` assets in the DMG.

- `[Verified]` The DMG contains a separate browser-use settings module.
- `[Verified]` The browser settings module describes management of an in-app browser.
- `[Verified]` The browser settings module says that browser extensions can be configured in Computer Use settings.
- `[Verified]` Computer Use settings expose an `Any App` control row.
- `[Verified]` Computer Use settings expose Chrome, Edge, and Safari browser rows.
- `[Verified]` The settings code manages Chromium browser extension installation and removal.
- `[Verified]` The settings code marks Safari extension support as coming soon in the inspected build.
- `[Verified]` Browser settings expose separate download and upload approval modes.
- `[Verified]` The inspected browser approval modes include `Always ask` and `Always allow`.
- `[Verified]` The inspected browser settings include browser history and download history surfaces.
- `[Inferred]` The browser path has a browser bridge or extension adapter that is separate from the macOS AX window adapter.
- `[Unknown]` The exact browser action schema, DOM representation, tab protocol, and extension message format are not established by this static inspection.
- `[Unknown]` The inspected settings do not prove whether browser and desktop actions share one model tool at runtime.

### Entry 21: Suniye settings and permission UI surface

Sources: `Suniye/MainWindowSection.swift`, `Suniye/Views/MainWindow/MainWindowView.swift`, and `Suniye/Views/MainWindow/MainWindowPages.swift`.

- `[Verified]` Suniye’s main settings navigation has Dashboard, History, Model, Magic Format, and General sections.
- `[Verified]` The General page shows Microphone and Accessibility permission rows.
- `[Verified]` The General page provides request and System Settings actions for those permissions.
- `[Verified]` Suniye has no current Computer Use settings section.
- `[Verified]` Suniye has no current Computer Use session overlay or approval view.
- `[Inferred]` Computer Use should have a dedicated settings surface because it adds permissions, app rules, approval scope, and privacy choices.
- `[Inferred]` An active-session overlay should be separate from the existing dictation floating indicator.

### Entry 22: Atomic research correction

- `[Corrected]` The earlier desktop-versus-browser conclusion was incomplete. The DMG has direct evidence of separate browser settings, extension handling, and file-transfer approvals.
- `[Retained]` The exact browser control protocol remains unknown. The implementation plan must keep browser control behind a separate adapter.

### Entry 23: Phase 0 Swift observation implementation

Sources: new Phase 0 files under `Suniye/Services/` and `SuniyeTests/ComputerUsePhase0Tests.swift`.

- `[Verified]` Suniye now has Codable value types for applications, windows, targets, AX elements, observations, screenshots, permissions, and observation errors.
- `[Verified]` Suniye keeps raw AX objects inside the Accessibility adapter.
- `[Verified]` Suniye lists running applications with both bundle identifiers and process-scoped selection IDs.
- `[Verified]` Suniye discovers visible layer-zero windows through `CGWindowListCopyWindowInfo`.
- `[Verified]` Suniye marks a frontmost window as a key-window candidate.
- `[Verified]` Suniye reads the target AX window and serializes a bounded tree with deterministic indexes.
- `[Verified]` Suniye records role, title, description, value summary, enabled state, focus, selection, bounds, actions, and child indexes.
- `[Verified]` Suniye redacts values for the `AXPasswordField` role.
- `[Verified]` Suniye captures a target window through `CGWindowListCreateImage` and encodes PNG data.
- `[Verified]` Suniye checks Accessibility and Screen Recording permission before observation.
- `[Verified]` Suniye supports cancellation before and during observation.
- `[Verified]` Suniye rejects an observation when its target application is missing or has no window.
- `[Verified]` Suniye assigns a new observation generation only after successful capture.
- `[Verified]` Seventeen deterministic Phase 0 tests pass.
- `[Verified]` The app target builds after XcodeGen regeneration.
- `[Verified]` Phase 0 adds no model call, input action, approval flow, browser adapter, or SwiftUI control surface.
- `[Inferred]` The observation DTOs can support a later actor or process boundary without passing raw AppKit or AX objects.

### Entry 24: Phase 0 correction

- `[Corrected]` The original plan listed harmless input-event verification under Phase 0. The implemented Phase 0 is read-only by design.
- `[Retained]` Input-event verification belongs to the controlled-action phase after policy and approval rules exist.

### Entry 25: Phase 0 reference mapping and API boundary

- `[Verified]` The Phase 0 application catalog is the Suniye equivalent of the DMG Sky `list_apps` surface.
- `[Verified]` The Phase 0 observation result combines one target window, AX text, stable element indexes, and an optional screenshot.
- `[Inferred]` This result shape follows the useful contract of the DMG Sky `get_app_state` surface without copying its code or transport.
- `[Verified]` Phase 0 uses `CGWindowListCreateImage` for the screenshot adapter.
- `[Unknown]` The final Suniye screenshot API remains open until a live macOS 14 permission test compares Core Graphics and ScreenCaptureKit.
- `[Verified]` Phase 0 does not implement the DMG’s native pipe, Apple Event bridge, model loop, or action wrappers.

### Entry 26: Phase 1 read-only surface

Sources: `Suniye/Services/ComputerUseCoordinator.swift`,
`Suniye/Views/MainWindow/ComputerUsePage.swift`,
`Suniye/MainWindowSection.swift`, and `SuniyeTests/ComputerUsePhase1Tests.swift`.

- `[Verified]` Suniye now exposes a dedicated Computer Use main-window section.
- `[Verified]` The Phase 1 surface lists eligible running applications and lets the user select one.
- `[Verified]` The Phase 1 surface shows Accessibility and Screen Recording permission state.
- `[Verified]` The Phase 1 surface can request both permissions through the Phase 0 permission service.
- `[Verified]` The Phase 1 surface can capture and preview the selected window's AX text and optional screenshot.
- `[Verified]` The Phase 1 surface supports cancellation without publishing an in-flight observation.
- `[Verified]` Discovery and observation run behind an actor boundary instead of directly in the SwiftUI view.
- `[Verified]` Fourteen deterministic Phase 1 coordinator tests pass.
- `[Verified]` Phase 1 adds no model call, input action, approval flow, browser adapter, or native helper.
- `[Inferred]` The dedicated coordinator can later host approval presentation and agent-session state without coupling those concerns to `AppState`.
- `[Unknown]` Live AX, Screen Recording, and target-window behavior has not yet been validated through the Phase 1 UI.

### Entry 27: Thermo-nuclear quality review

Review scope: the full Computer Use diff from main through the Phase 1 commits.

- `[Fixed]` The Phase 1 preview now uses Swift interpolation for window titles, generations, IDs, element counts, screenshot dimensions, and bounds.
- `[Fixed]` System application IDs now include the bundle identifier and process identifier. A bundle identifier alone is not a unique live target.
- `[Fixed]` Refresh clears the previous observation before loading a new application snapshot.
- `[Fixed]` The Accessibility adapter isolates its required Core Foundation casts behind explicit type-ID guards.
- `[Verified]` The actor boundary, service seams, and file sizes remain suitable for the next phase. No changed production file exceeds 1,000 lines.
- `[Retained]` The permission enum still has a future unavailable state, but the current system provider reports only granted or not granted.
- `[Unknown]` Live permission prompts, real AX trees, and screenshot behavior still require manual macOS validation.

### Entry 28: Phase 2 bounded actions and approval

Sources: `Suniye/Services/ComputerUseActionModels.swift`,
`Suniye/Services/ComputerUseActionService.swift`,
`Suniye/Services/ComputerUseInputEventService.swift`,
`Suniye/Services/ComputerUseCoordinator.swift`,
`Suniye/Services/ComputerUseAccessibilityReader.swift`,
`Suniye/Views/MainWindow/ComputerUseActionPanel.swift`, and
`SuniyeTests/ComputerUsePhase2Tests.swift`.

- `[Verified]` Suniye now has typed click, key press, scroll, text entry, and semantic Accessibility actions.
- `[Verified]` The action policy rejects non-finite or out-of-bounds clicks, oversized scroll values, invalid character keys, empty or oversized text, and stale or unsupported semantic element references.
- `[Verified]` The action service checks the exact approval request ID, Accessibility permission, frontmost process identity, current key-window identity, observation generation, approval scope, and cancellation before native execution.
- `[Verified]` Native input events are isolated behind `ComputerUseInputEventPosting`; text entry reuses the existing clipboard-preserving insertion service; semantic actions use `AXUIElementPerformAction` through the Accessibility adapter.
- `[Verified]` The coordinator creates an approval request for each action and supports Allow Once, Deny, Stop Session, and Cancel transitions.
- `[Verified]` A completed action disables further action requests until a fresh observation is captured.
- `[Verified]` Fifteen deterministic Phase 2 tests pass across models, policy, action service, target validation, approval, failure, and cancellation paths.
- `[Verified]` Phase 2 does not call a model, add browser control, or add a native helper process.
- `[Inferred]` Keeping native event posting and semantic AX execution behind separate protocols leaves a testable action service and preserves a future helper-process seam.
- `[Unknown]` Live `CGEvent` posting, coordinate-system alignment, clipboard restoration, and real semantic-action behavior still require manual macOS validation.

### Entry 29: Phase 3 typed agent loop

Sources: `Suniye/Services/ComputerUseAgentModels.swift`,
`Suniye/Services/ComputerUseAgent.swift`,
`Suniye/Services/ComputerUseInterventionMonitor.swift`, and
`SuniyeTests/ComputerUsePhase3Tests.swift`.

- `[Verified]` Suniye now has a typed model request containing the instruction, fresh observation, successful action results, bounded failure feedback, and iteration number.
- `[Verified]` Model decisions are typed as action, completed, ask-user, blocked, or retryable-failure values. Empty terminal messages are rejected before they drive the loop.
- `[Verified]` The agent uses an actor-isolated loop with fresh observation before each model request and after each successful action.
- `[Verified]` The agent requires one-time approval before every model-proposed action and passes the shared cancellation token to the model, approval, and action boundaries.
- `[Verified]` The agent bounds successful actions, repeated failures, and loop duration checks. It stops for cancellation, denial, user stop, frontmost-app changes, target-window changes, and target-not-frontmost action errors.
- `[Verified]` Model and action failure messages are retained in the next model request instead of being discarded.
- `[Verified]` The default model client fails closed with `notConfigured`; Phase 3 does not make a network or local model call.
- `[Verified]` The live intervention adapter checks the frontmost process and current key window through the existing window-discovery boundary.
- `[Verified]` Phase 3 deterministic tests pass for model values, decisions, retries, approvals, actions, limits, cancellation, and intervention.
- `[Inferred]` The typed model and approval protocols are the seam for a future local or remote provider, but the provider privacy contract must be decided first.
- `[Unknown]` The exact model, prompt, response schema, timeout behavior during an in-flight provider request, and coordinator event bridge remain open.

### Entry 30: DMG reference used for Phase 3 comparison

Sources: the mounted DMG paths
`ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/client.js`,
`computer-use-policy.js`, `native-pipe.js`, `get_app_state.js`, `window_result.js`, and
`errors.js`.

- `[Verified]` The DMG public macOS client uses request types named `ComputerUseIPCListAppsRequest`, `ComputerUseIPCAppPolicyRequest`, `ComputerUseIPCAppGetSkyshotRequest`, `ComputerUseIPCAppPerformActionRequest`, and `ComputerUseIPCAppStartRequest`.
- `[Verified]` The DMG client defaults to API version `CodexComputerUseIPC-2` and a 120-second request timeout.
- `[Verified]` The DMG public action wrappers call one shared `performAction` transport path. The readable wrappers expose click, drag, secondary Accessibility action, key press, scroll, set value, select text, and text entry.
- `[Verified]` The DMG policy wrapper requests an app policy before a tool action and distinguishes allowed, denied, and forbidden decisions.
- `[Verified]` The DMG policy wrapper can ask for session or always-persistent approval, records approval telemetry, and maps user-stopped and user-intervened server errors to a canceled tool result.
- `[Verified]` The DMG native pipe serializes JSON-RPC requests, assigns a request deadline, frames messages with a length prefix, validates response shape, and rejects oversized frames.
- `[Verified]` The DMG `get_app_state` wrapper turns native state into an app, screenshot, and text result. App-specific instructions may be prefixed to the returned text.
- `[Inferred]` Suniye’s Phase 3 typed model, approval, action, and observation seams follow the same useful separation, while keeping the implementation independent.
- `[Corrected]` Suniye’s Phase 3 one-time approval is not yet equivalent to the DMG’s app-policy and session/always-persistent approval layer. That comparison belongs to Phase 4.
- `[Unknown]` The readable DMG JavaScript does not expose the complete model prompt or the hidden service’s internal agent loop. We must not claim exact parity for those parts.

### Entry 31: Phase 4 policy boundary

Sources: `Suniye/Services/ComputerUsePolicyService.swift`,
`Suniye/Services/ComputerUseApprovalStore.swift`,
`Suniye/Services/ComputerUseAudit.swift`,
`Suniye/Services/ComputerUseActionModels.swift`, and
`SuniyeTests/ComputerUsePhase4PolicyTests.swift`.

- `[Verified]` Suniye now represents allowed, denied, and forbidden application policy outcomes.
- `[Verified]` The policy always permits one-time approval and can opt selected action risks into session and always scopes.
- `[Verified]` Text entry cannot receive persistent approval through the policy service.
- `[Verified]` Session approvals remain in memory and are removed when the session ends.
- `[Verified]` Always approvals persist only bundle identifier, action risk, scope, and optional expiry.
- `[Verified]` Expired and revoked always approvals are removed and are not returned.
- `[Verified]` Approval requests carry session identity, observation generation, and allowed scopes.
- `[Verified]` Approval and policy audit records contain redacted action summaries and do not contain typed text or screenshots.
- `[Inferred]` The boundary is ready for coordinator and agent integration, but those callers must use `prepare` and `grant` for policy re-evaluation.
- `[Unknown]` The final product defaults, expiry duration, user settings, and remote telemetry policy remain open.

### Entry 32: Phase 4 repository handoff

Sources: local Git status and `git push` output.

- `[Verified]` Commit `4d9161e` contains the Phase 4 safety policy slice.
- `[Verified]` Branch `kis-169-computer-use` tracks `origin/kis-169-computer-use`.
- `[Verified]` The Phase 4 branch state was pushed after tests and quality review.

### Entry 33: Phase 5A model transport

Sources: `Suniye/Services/ComputerUseModelClient.swift`,
`Suniye/Services/ChatCompletionClient.swift`, and
`SuniyeTests/ComputerUsePhase5ModelTests.swift`.

- `[Verified]` The transport validates an HTTP(S) endpoint, non-empty model ID, API key, timeout, and token limit before sending a request.
- `[Verified]` The model prompt includes the task, target metadata, Accessibility text and elements, and safe action summaries.
- `[Verified]` Typed action text is represented by its character count in recent action history.
- `[Verified]` Screenshot data is sent as an image content part only when the caller opts into screenshot upload.
- `[Verified]` Provider output must decode as one of the typed Computer Use decisions and pass non-empty message validation.
- `[Inferred]` This transport can serve the Phase 3 model-client seam without coupling it to the existing dictation formatter.
- `[Unknown]` The final product model, prompt, provider endpoint, and remote observation consent UX remain open until coordinator integration.

### Entry 34: Phase 5A repository handoff

Sources: local Git status and `git push` output.

- `[Verified]` Commit `316fd30` contains the Phase 5A model transport slice.
- `[Verified]` The Phase 5A slice was pushed to `origin/kis-169-computer-use` after focused tests and quality review.

### Entry 35: Phase 5B coordinator and approval integration

Sources: `Suniye/Services/ComputerUseCoordinator.swift`,
`Suniye/Services/ComputerUseAgent.swift`,
`Suniye/Services/ComputerUseAgentApproval.swift`, and
`SuniyeTests/ComputerUsePhase5CoordinatorTests.swift`.

- `[Verified]` The coordinator now owns an agent task and passes one session identifier through every model-proposed action in that run.
- `[Verified]` The coordinator presents agent approval requests through a checked continuation and resumes the agent only after Allow, Deny, Stop, or cancellation.
- `[Verified]` Agent approval requests are prepared by policy before presentation, and persistent scopes are granted through the same policy boundary used by manual actions.
- `[Verified]` The action service rechecks policy and remembered scope before it accepts a session or always grant.
- `[Verified]` Session approval reuse, user approval, and cancellation are covered by deterministic coordinator tests.
- `[Corrected]` The first coordinator test exposed a race where the UI phase became visible before the continuation was registered. Registration now occurs before publishing the pending request.
- `[Corrected]` The first approval handler required a coordinator observation that agent runs intentionally keep inside the agent. Agent approvals now resolve before the manual-action path and use the agent's fresh observation.

### Entry 36: Phase 5B model settings and consent UI

Sources: `Suniye/Services/ComputerUseModelConfigurationFactory.swift`,
`Suniye/AppState.swift`, `Suniye/Services/ComputerUseModelClient.swift`,
`Suniye/Views/MainWindow/ComputerUsePage.swift`,
`Suniye/Views/MainWindow/ComputerUseDetailsView.swift`, and
`Suniye/Views/MainWindow/MainWindowView.swift`.

- `[Verified]` The production coordinator receives a model only when the user enables the existing API Endpoint provider, has valid endpoint/model settings, and has a non-empty keychain key.
- `[Verified]` Automatic, local, disabled, invalid, and missing-key settings fail closed to no configured Computer Use model.
- `[Verified]` Accessibility remains required for an agent run. Screen Recording is required only when the local observation includes a screenshot.
- `[Verified]` Screenshot upload is disabled by default and can be enabled only through a visible session UI toggle.
- `[Corrected]` The legacy agent panel was replaced by a conversation-first transcript and fixed composer. Connection, permission, starting-app, and observation controls are collapsed at the bottom of the transcript.
- `[Inferred]` The configured endpoint may receive AX text whenever the user runs the agent. The UI discloses this boundary, but a live provider test is still required.
- `[Unknown]` Reliability of the prompt and decision schema across real providers and target applications remains unverified.

### Entry 37: Phase 5B repository handoff

Sources: local Git status, focused test output, `git commit`, and `git push` output.

- `[Verified]` Commit `ae6274d` contains the coordinator agent, approval, and policy integration slice.
- `[Verified]` Commit `6a1f6d3` contains the configured model connection, screenshot-consent UI, and configuration tests.
- `[Verified]` Both Phase 5B code commits were pushed to `origin/kis-169-computer-use`.

### Entry 38: Phase 5B validation and coverage handoff

Sources: `SuniyeTests/ComputerUsePhase5CoordinatorTests.swift`,
`scripts/coverage_exclusions.txt`, `scripts/e2e_preflight.sh`, `scripts/e2e_smoke.sh`,
the full `xcodebuild` result bundle, and local Git push output.

- `[Verified]` Coordinator tests cover policy denial, approval-scope rejection, persistent
  approval, canceled actions, canceled permission work, stale operation results, and blocked
  or failed agent terminal results.
- `[Verified]` The full suite reports 1,078 tests, with 1,077 passed, 1 skipped, and 0 failed.
- `[Verified]` The gated coverage report passes at 95.02% (13,803/14,526 lines). The new SwiftUI
  agent panel is excluded as render-only, with its coordinator behavior covered by tests.
- `[Verified]` `scripts/e2e_preflight.sh` and `scripts/e2e_smoke.sh` pass.
- `[Verified]` Commit `edf2abd` contains the coverage-hardening tests and render-only coverage rationale. It is pushed to `origin/kis-169-computer-use`.
- `[Unknown]` These checks do not verify a live provider response, real Accessibility trees, Screen Recording capture, or native input against a real target app.

### Entry 39: Reference parity audit

Sources: the mounted reference `sky-window2-api.md`, `sky-window-api.md`, the mounted Computer
Use safety skill, the detailed `parity-audit-dmg-agent.md`, and current Suniye source inspection.

- `[Verified]` The reference exposes app/window records, window state capture, window-relative
  coordinate actions, indexed value actions, drag, dynamic secondary Accessibility actions, and
  explicit window activation.
- `[Verified]` The reference has separate native client/service boundaries and public evidence of
  framed JSON-RPC and XPC transport names. The exact server-side model loop and sender-auth rules
  remain hidden.
- `[Verified]` The reference browser surface is a separate plugin with tab, DOM, extension, and
  CDP concepts. Desktop app control is not browser-control parity.
- `[Verified]` Suniye's parity matrix is recorded in `parity-audit.md`. It distinguishes broad
  desktop-loop parity from missing helper IPC, state diffs, screenshot identifiers, indexed click
  and scroll, installed-app launch, and browser control.

### Entry 40: Corrective desktop parity slice

Sources: `Suniye/Services/ComputerUseActionModels.swift`, `ComputerUseActionService.swift`,
`ComputerUsePlatformRunner.swift`, `ComputerUseWindowActivationService.swift`,
`ComputerUseCoordinator.swift`, `ComputerUsePage.swift`, and focused test output.

- `[Verified]` Coordinate actions use points relative to the selected window and convert to screen
  coordinates only inside the native action service.
- `[Verified]` The action boundary supports click count/button, positioned scroll, drag, AX value
  setting, and text selection with bounded validation and cancellation checks.
- `[Verified]` The UI lists target windows, provides an explicit Bring Forward action, and shows
  always-allowed approvals with revocation confirmation.
- `[Verified]` Agent startup activates the explicit target window once. Later frontmost/window
  changes remain intervention failures.
- `[Corrected]` Live frontmost-process state is now the source of truth for key-window marking;
  stale `ComputerUseApplication.isActive` values cannot authorize a background target.
- `[Corrected]` Always-approval UI refreshes after persistence rather than before the grant is
  stored.
- `[Verified]` The focused Computer Use test set reports 47 tests passed and 0 failures after the
  corrective slice.
- `[Unknown]` Real AX activation, multi-display coordinate conversion, native event delivery, and
  live provider behavior still require the planned Computer Use E2E run.

### Entry 41: Strict quality review corrections

Sources: the thermo-nuclear code quality review instructions, local source inspection, `git diff
--check`, and the current test target.

- `[Verified]` The oversized Phase 2 test file was split into focused action, support, and
  coordinator files. No production Computer Use file or test file in the reviewed slice exceeds
  the review's 1,000-line maintainability limit.
- `[Corrected]` Scroll-coordinate decoding no longer force unwraps an optional value.
- `[Corrected]` Test failure diagnostics now interpolate the expected value instead of printing a
  literal placeholder.
- `[Corrected]` Public action keys use the inspected reference names, while mouse-button aliases
  remain accepted at the decode boundary.
- `[Corrected]` Dynamic Accessibility action names are matched case-insensitively and the exact
  exposed native action name is used for execution.
- `[Verified]` `git diff --check` reports no whitespace errors.

### Entry 42: Final deterministic validation before live E2E

Sources: the focused `xcodebuild` run, the full `xcodebuild` result bundle at
`.derivedData/coverage.run2.xcresult`, `xcrun xcresulttool`, and `scripts/coverage_report.sh`.

- `[Verified]` The focused Computer Use suite reports 28 passed tests and 0 failures.
- `[Verified]` The full suite reports 1,085 passed, 1 skipped, and 0 failed tests, for 1,086 total.
- `[Verified]` Gated line coverage is 95.01% (14,439/15,197 lines) at the documented 95% threshold.
- `[Unknown]` Live provider behavior, WindowServer interaction, Accessibility capture, native
  event delivery, and permission prompts remain unverified until the planned `@Computer` E2E run.

### Entry 43: Live `@Computer` E2E and corrective fixes

Sources: `docs/research/kis-169-computer-use/e2e-computer.md`, the installed build at
`/Users/kishan/Applications/Suniye.app`, the Computer Use skill's `node_repl` session, and the
macOS diagnostic reports.

- `[Verified]` The live Suniye UI exposes the Computer Use page, target picker, window picker,
  Bring Forward control, permission rows, screenshot toggle, observation preview, task editor,
  typed action buttons, and semantic Accessibility actions.
- `[Verified]` Accessibility-only observation succeeds for a selected Suniye window when Screen
  Recording is not granted and screenshot inclusion is off.
- `[Verified]` A benign action request presents Allow Once, Deny, and Stop Session. Deny returns to
  the observation state without posting the native click.
- `[Corrected]` The first live navigation crash came from indexed `NSPopUpButton` item lookup
  during a SwiftUI/native menu count mismatch. The picker now uses bounded `itemArray` updates.
- `[Corrected]` The first live Bring Forward crash came from re-entrant AX raising of Suniye's
  own window. The activation service now skips that call for the current process after AppKit
  activation and keeps AX raising for other processes.
- `[Verified]` The final live run remained alive through navigation, same-process activation,
  observation, approval presentation, and denial.
- `[Unknown]` Screen Recording capture, live model behavior, cross-process activation, and native
  input delivery remain unverified.

### Entry 44: Post-E2E final validation

Sources: the final `xcodebuild` result bundle at `.derivedData/coverage.post-e2e-final.xcresult`,
`xcrun xcresulttool`, `scripts/coverage_report.sh`, `scripts/e2e_preflight.sh`,
`scripts/e2e_smoke.sh`, and the second strict quality review.

- `[Verified]` The full suite reports 1,088 passed, 1 skipped, and 0 failed tests, for 1,089 total.
- `[Verified]` Gated line coverage is 95.10% (14,453/15,197 lines) at the 95% threshold.
- `[Verified]` E2E preflight and smoke build checks pass.
- `[Verified]` The focused regression suite covers the popup mismatch and own-process activation
  policy with 3 passing tests.
- `[Verified]` No reviewed production or test file exceeds 1,000 lines, and `git diff --check`
  reports no whitespace errors.

### Entry 45: Corrective slice repository handoff

Sources: local Git status, `git log`, `git push`, and `git ls-remote`.

- `[Verified]` Commit `f15a04d` contains the native picker and own-process activation fixes, their
  regression tests, and the live E2E record.
- `[Verified]` The branch `kis-169-computer-use` is clean and tracks
  `origin/kis-169-computer-use` at commit `f15a04d`.

### Entry 46: Atomic target-scope correction

Sources: the mounted reference `sky-window-api.md` and Computer Use skill, the current target
scope implementation note, current Suniye Computer Use services and tests, and the final local
validation commands.

- `[Verified]` The public macOS reference takes an app target per state and input call. It does
  not expose one immutable session-wide app target.
- `[Verified]` The reference skill describes background launch when state is requested for a
  non-running app.
- `[Corrected]` The old Suniye frontmost/key-window intervention monitor was a local target lock,
  not a verified reference requirement. It is removed.
- `[Implemented]` Suniye now permits no starting app, exposes app candidates to the model, accepts
  typed target decisions, resolves installed apps, launches them through asynchronous `NSWorkspace`,
  and activates the fresh target immediately before input.
- `[Retained]` Accessibility, Screen Recording, policy, approval, observation-generation, explicit
  stop, cancellation, and action/session limits remain separate control boundaries.
- `[Verified]` The final full suite reports 1,088 passed, 1 skipped, and 0 failed tests, for 1,089
  total. Gated coverage is 95.08% (14,455/15,203 lines) at the 95% threshold.
- `[Verified]` `scripts/e2e_preflight.sh` and `scripts/e2e_smoke.sh` pass.
- `[Unknown]` Live third-party app launch, cross-process activation and input, Screen Recording
  capture, browser control, helper IPC, and the complete provider/model loop remain unverified.

### Entry 47: Automatic execution and removal of unverified target heuristics

Sources: the mounted reference `sky-window-api.md`, the Computer Use confirmation document, the
current Suniye coordinator/action boundary, the current Suniye application catalog, and the
focused Computer Use test run.

- `[Corrected]` Suniye's area/title window-priority heuristic was not supported by the inspected
  reference. Window discovery now preserves the native CGWindowList order.
- `[Implemented]` The Preview coordinator no longer exposes an interactive approval mode, pending
  approval continuation, or always-approval UI state. Actions run automatically after the task
  starts, as required by the current testing mode.
- `[Retained]` The lower action boundary still prepares and grants a one-time policy scope, then
  revalidates policy, permission, target identity, observation generation, and action shape before
  native execution.
- `[Verified]` The focused Computer Use suite reports 63 passed tests and 0 failures after this
  cleanup.
- `[Unknown]` The exact model-side confirmation taxonomy and host orchestration in the reference
  remain unavailable in the DMG. Automatic Preview execution is a local product/testing default,
  not a claim that every reference action is confirmation-free.

### Entry 48: Removal of the temporary manual action surface

Sources: the mounted DMG macOS client/action wrappers, the current Suniye coordinator and page,
the focused Computer Use test run, and the thermo-nuclear quality review.

- `[Verified]` The inspected DMG exposes Computer Use actions as app-scoped model/tool calls. It
  does not expose a Suniye-style “click center”, “press Return”, text-entry, or arbitrary AX-action
  panel in the macOS client contract.
- `[Implemented]` The temporary manual action panel, the coordinator's direct `requestAction`
  path, action-only phases, and the old interactive approval branches are removed from the current
  Preview surface.
- `[Retained]` Typed action models, native input/Accessibility services, automatic policy grants,
  stale-observation checks, per-action target activation, cancellation, and agent re-observation
  remain because they are part of the model-driven execution boundary.
- `[Verified]` The focused suite reports 67 passing tests and 0 failures after the removal.
- `[Unknown]` The reference's complete host UI and model-side orchestration remain unavailable;
  this cleanup removes only the verified-extra manual surface, not the reference-backed native
  action and policy boundaries.

### Entry 49: Final non-reference execution-path cleanup

Sources: the mounted macOS reference client and policy wrapper, the current Suniye Computer Use
services and page, the final `xcodebuild` result bundle at
`.derivedData/cleanup-final-3.xcresult`, `scripts/coverage_report.sh`,
`scripts/e2e_preflight.sh`, `scripts/e2e_smoke.sh`, the Preview install, and the final
`node_repl` Computer Use run.

- `[Implemented]` Removed the deterministic task matcher, hard-coded Bluetooth target, target
  lock and frontmost intervention monitor, first-app fallback, Chrome-specific prompt, manual
  approval/action surface, cached AX-element and exposed-action prevalidation, local agent
  action/failure/time caps, duplicate structured AX prompt rendering, remote screenshot-upload
  consent, Windows-only screenshot metadata, and user-facing window picker/Bring Forward UI.
- `[Retained]` The current desktop path remains app-scoped: applications are discovered and
  resolved through the macOS catalog, concrete windows are resolved internally for AX and input,
  observations always include a PNG screenshot, model decisions select an app or emit one
  canonical action/terminal decision, actions are automatically approved in the Preview testing
  path, and cancellation plus stale-observation identity checks remain at the execution boundary.
- `[Verified]` The full suite reports 1,080 tests executed, 1 skipped, and 0 failures. Gated line
  coverage is 95.02% (13,672/14,389 lines) at the 95% threshold.
- `[Verified]` E2E preflight and smoke checks pass. The Debug Preview build installs at
  `/Users/kishan/Applications/Suniye Preview.app`.
- `[Verified]` After relaunching the installed Preview, the Computer Use page no longer shows
  the removed window picker, Bring Forward control, screenshot toggle, manual action controls,
  or approval card. Accessibility and Screen Recording permission rows remain visible.
- `[Verified]` The safe live Calculator task completed automatically through the configured model:
  `Read the Calculator result and report it. Do not change the calculator.` The UI reported
  `Computer Use finished The Calculator result is 323`; the Calculator remained at `17 × 19 = 323`.
- `[Superseded by Entries 53 and 54]` This run had not yet recovered the client request loop or
  native helper algorithms. Those are now substantially recovered. Provider-private inference,
  five narrow native branch details, and the browser-extension route remain unknown;
  cross-process third-party input, fresh Screen Recording consent, and browser/cart behavior also
  remain unverified in this run.

### Entry 50: Direct voice-to-Computer Use integration

Sources: `Suniye/AppState.swift`,
`Suniye/Services/ComputerUseCoordinator.swift`,
`Suniye/Services/ComputerUseVoiceTaskHandling.swift`, the direct-voice focused tests, the final
`xcodebuild` result bundle at `.derivedData/direct-voice-final-3.xcresult`,
`scripts/coverage_report.sh`, `scripts/e2e_preflight.sh`, and `scripts/e2e_smoke.sh`.

- `[Implemented]` The visible Computer Use page registers a weak main-actor task handler with the
  existing AppState dictation pipeline.
- `[Implemented]` A normal Suniye hold-to-talk session routes its raw local transcript directly to
  Computer Use while that page is visible. It bypasses Magic Format, text insertion, clipboard
  output, submit-key handling, and dictation history.
- `[Implemented]` The coordinator reports started, queued, or rejected submissions; restores the
  captured voice instruction before launch; queues while model/apps/permissions prepare; and
  rejects overlapping observation or agent work without canceling the active operation.
- `[Implemented]` Leaving the Computer Use page unregisters the handler and cancels queued work.
- `[Verified]` The focused voice and coordinator tests pass in a signed macOS test run.
- `[Verified]` The full suite reports 1,087 passed, 1 skipped, and 0 failed tests, for 1,088 total.
- `[Verified]` Gated line coverage is 95.04% (13,769/14,487 lines), above the documented 95%
  threshold.
- `[Verified]` E2E preflight and smoke checks pass.
- `[Unknown]` Live microphone capture, live provider behavior after voice submission, Screen
  Recording capture, cross-process desktop input, and browser-extension routing remain open.

### Entry 51: Refreshed Preview voice UX smoke

Sources: the installed `/Users/kishan/Applications/Suniye Preview.app`, the Computer Use
`node_repl` session, and `docs/research/kis-169-computer-use/e2e-computer.md`.

- `[Verified]` The refreshed Preview build launches and opens the Computer Use page.
- `[Verified]` The page exposes the direct voice instruction, configured model status, and
  Accessibility/Screen Recording rows.
- `[Verified]` The refreshed page does not expose the removed manual action or approval controls.
- `[Not exercised]` No microphone recording, voice submission, provider request, or third-party
  app action was performed in this smoke check.

### Entry 52: Explicit bootstrap and host-policy correction

Sources: the mounted DMG Computer Use skill, JavaScript macOS client and policy wrapper, native
helper symbols and strings, `bootstrap-and-self-target-parity-2026-08-08.md`, the installed bundled
Computer Use client used only as a separate live cross-check, Suniye logs from the failed `Hello`
run, and the focused Computer Use tests.

- `[Verified]` The packaged Computer Use state call requires an explicit app. The documented start
  is a task-named app or app listing; public app data omits native frontmost state.
- `[Verified]` The host's `computer-use-frontmost-window` route belongs to screen-context/Appshot
  capture and is not exposed by the Computer Use macOS action client.
- `[Verified]` Suniye's failed `Hello` run logged `target=frontmost`, then executed a text-entry
  action against the Suniye Preview bundle. The assistant text in the composer was native agent
  input into its own focused text editor, not a SwiftUI state-binding copy.
- `[Corrected]` A Suniye run with no selected app now asks the model for a target or terminal
  decision before any observation. It never defaults to the active/frontmost app, and observation
  requires an explicit app identifier.
- `[Implemented]` Application policy now runs before both observation and action. It forbids the
  current Suniye bundle at that shared boundary while leaving discovery unchanged.
- `[Implemented]` A model action without an observation is rejected. Conversational completion can
  return without Accessibility, screenshot, or input work, and the composer remains empty.
- `[Verified]` The focused parity suite reports 94 passing tests and 0 failures before removing the
  remaining optional-frontmost observation path; the follow-up affected groups report 55 passing
  tests and 0 failures.
- `[Verified]` The final full suite reports 1,100 passed, 1 skipped, and 0 failed tests, for 1,101
  total. Gated line coverage is 95.11% (13,899/14,613 lines), above the documented 95% threshold.
- `[Verified]` E2E preflight and smoke checks pass after the correction.
- `[Verified]` The DMG contains the static GPT-5.6 base instructions and the complete readable
  Computer Use operating instructions. See `prompt-recovery-2026-08-08.md` and
  `recovered-prompts/`.
- `[Verified]` The client-side request construction, role ordering, and selected-model field are
  recovered, and a loopback request serialized by the DMG binary selected `gpt-5.6-luna`.
- `[Unknown]` Provider-private inference and the response for a particular unexecuted greeting turn
  remain unavailable. No deterministic greeting, noun, app, or task matcher was added.

### Entry 53: Client model and runtime-request recovery

Sources: the DMG `codex` executable, its `debug models` and `debug prompt-input` commands, official
Codex tag `rust-v0.146.0-alpha.9.2`, the isolated loopback request capture at
`/private/tmp/suniye-codex-request-audit-20260808/captured-request.json`, the DMG `app.asar`, and
`runtime-request-and-model-selection-recovery-2026-08-08.md`.

- `[Corrected]` Normal model selection is not provider-side. The app-server turn protocol accepts a
  client model override, and the client sends the resolved model slug in the Responses request.
- `[Verified]` The service may exceptionally report a different model. The client compares it with
  the requested slug and emits a model-reroute event on mismatch.
- `[Verified]` The request schema, Lite/non-Lite construction, initial context ordering, world-state
  ordering, user-message placement, and selected skill/plugin injection placement are recovered
  from the exact tagged source.
- `[Verified]` The DMG app-server, initialized with ChatGPT desktop client information, serialized a
  loopback request selecting `gpt-5.6-luna`. It ordered Lite tool definitions, GPT-5.6 base
  instructions, dynamic developer context, repository instructions, the user task, and the
  Computer Use skill prompt.
- `[Verified]` The DMG host chooses the node-REPL or legacy-MCP Computer Use skill variant from a
  desktop feature flag. In node-REPL mode it materializes the detailed node-REPL instructions as
  `skills/computer-use/SKILL.md`.
- `[Unknown]` Provider-private inference, hidden classifiers, post-receipt transformations, and the
  model response for an unexecuted production turn remain unavailable.
- `[Not implemented]` This entry changes research conclusions only. No Suniye production code was
  changed.

### Entry 54: Native helper live protocol and algorithm recovery

Sources: the DMG-shipped `SkyComputerUseClient` and `SkyComputerUseService`, a live local MCP
session using read-only `list_apps` and `get_app_state` against Calculator, preserved Swift
symbols and imported macOS APIs, targeted ARM64 disassembly, and
`native-algorithm-recovery-2026-08-09.md`.

- `[Corrected]` The prior claim that native helper behavior was unavailable because the helper is
  compiled was too broad.
- `[Verified]` The native MCP server exposes exactly ten app-scoped tools. `list_apps` reports
  running/recent apps and usage metadata; `get_app_state` accepts app name, full path, or an
  unambiguous bundle identifier.
- `[Verified]` The first Calculator state call elicited app approval. Accepted state contained a
  depth-indented preorder AX tree with observation-scoped integer IDs and a JPEG screenshot.
- `[Verified]` Calculator remained in the background while WhatsApp stayed frontmost across two
  state calls. Observation does not inherently activate the target application.
- `[Verified]` Window discovery requests on-screen, non-desktop CG windows and cross-references
  them with AX candidates. No public model-facing window picker or window ID is required.
- `[Verified]` The helper retains AX revisions, maps IDs to AX elements, compares render trees,
  inherits matched IDs, and supports depth-first insertion/removal changes and stale-element
  refetch.
- `[Verified]` Both ScreenCaptureKit and SkyLight/WindowServer screenshot paths exist. The helper
  supports window-ID capture, crop, size, opacity, shadow, delay, and encoding options.
- `[Verified]` Screenshot coordinates are scaled and optionally translated by the target window
  origin. Actions use semantic AX mechanisms with process-scoped synthesized click, drag, scroll,
  key, and text fallbacks plus conditional focus coordination.
- `[Verified]` UI settling, AX invalidation, physical-input, focus, and lock-screen monitoring
  paths exist.
- `[Unknown]` The final multi-window comparator, exact AX diff equality/budget rules, complete
  capture-backend branch matrix, every AX-versus-synthesized-input branch, and exact intervention
  debounce/already-posting cancellation behavior remain unrecovered.
- `[Not implemented]` This entry changes research conclusions only. No Suniye production code was
  changed.

### Entry 55: Fresh implementation phase 0 tool contract

Sources: `ComputerUseProtocol.swift`, `ComputerUseSession.swift`,
`ComputerUseProtocolTests.swift`, the recovered node-REPL API surface, and the live native
`tools/list` evidence recorded in `native-algorithm-recovery-2026-08-09.md`.

- `[Implemented]` The fresh implementation defines the exact ten recovered desktop operation names
  and normalized, app-scoped Swift input and output types.
- `[Implemented]` An actor dispatcher routes every operation through an injected async native-tool
  boundary and checks cancellation before dispatch.
- `[Corrected]` An initial exact-string active-app set was removed. It would have imposed a hidden
  target lock that the recovered public tool surface does not have.
- `[Implemented]` Click target input is a validated element-or-coordinate enum. The future wire
  decoder remains responsible for matching the recovered optional JSON fields and aliases.
- `[Verified]` Five focused tests pass, covering the exact operation list and name mapping, all
  action routes, discovery without target selection, and alternate app identifiers without a
  session lock.
- `[Verified]` The full suite passes with 989 tests executed, 1 skipped, and 0 failures. Gated line
  coverage is 95.20% (11,177/11,741 lines) at the requested 95% threshold.
- `[Verified]` The existing E2E preflight and smoke checks pass.
- `[Not implemented]` App discovery, window selection, AX state, screenshots, action execution,
  model requests, agent orchestration, permissions, approvals, UI, and live E2E remain future
  phases.

### Entry 56: Fresh implementation phase 1 app and window discovery

Sources: the mounted DMG JavaScript macOS client and native service, targeted native strings and
imports, the locally executed Spotlight query and `mdls`, `ComputerUseApplicationCatalog.swift`,
`SystemComputerUseApplicationInventory.swift`, `ComputerUseWindowDiscovery.swift`,
`SystemComputerUseWindowInventory.swift`, the native bridge, and focused tests.

- `[Verified]` The reference public app shape, 14-day Spotlight query, usage metadata, background
  launch configuration, exact app identifier forms, and on-screen/non-desktop CG window request
  are recovered from the mounted artifact.
- `[Implemented]` Suniye discovers running and recent applications, resolves only exact names,
  paths, or unambiguous bundle identifiers, and launches a stopped target without activation.
- `[Implemented]` Suniye obtains native CG window descriptions through a narrow Objective-C++
  bridge, reads target-process AX windows, cross-references them, and preserves CG ordering.
- `[Verified]` The implementation contains no fuzzy noun or task matcher, no frontmost target
  fallback, no public window selection requirement, and no automatic app activation during
  discovery.
- `[Independent choice]` A per-call Spotlight snapshot replaces the reference's live indexed
  cache. Duplicate metadata precedence and a two-point title/bounds CG-to-AX matcher are explicit
  closest-match decisions because the native final ordering and comparator remain unknown.
- `[Corrected]` The strict review split platform adapters from pure policy, removed an unnecessary
  resolution parameter, stabilized duplicate merging, and made bridge nullability explicit.
- `[Verified]` Thirteen focused tests pass with zero failures. The final full suite executes 1,002
  tests with 1 skipped and 0 failures; gated coverage is 95.14% (11,440/12,024 lines); E2E
  preflight and smoke both pass.
- `[Verified]` The two live macOS adapters are documented coverage exclusions because they require
  NSWorkspace/Spotlight/Launch Services or the window server/Accessibility permission. Pure window
  description decoding remains gated and tested.
- `[Not implemented]` Observation rendering/revisions, screenshots, actions, model/agent wiring,
  permissions, conversation UI, and browser control remain future phases.

### Entry 57: Fresh implementation phase 2 observation

Sources: the mounted native service symbols and live-state findings in
`native-algorithm-recovery-2026-08-09.md`, `ComputerUseAccessibilityTree.swift`,
`ComputerUseObservationService.swift`, the two system adapters, and Phase 2 tests.

- `[Implemented]` Suniye independently renders bounded depth-first AX state with integer IDs,
  retains app/window-scoped revisions, maps IDs to tree paths, inherits matched IDs, supports
  diffs and `disableDiff`, and redacts secure text values.
- `[Implemented]` Background window screenshots use public ScreenCaptureKit, JPEG encoding, actual
  display scale, the window frame, and bounded transient file retention.
- `[Implemented]` AX and screenshot capture run concurrently after exact app and internal window
  resolution; observation does not activate the target.
- `[Independent choice]` Match keys, diff punctuation, traversal limits, and ScreenCaptureKit-only
  backend selection are explicit closest matches because the exact native details remain unknown.
- `[Corrected]` The strict review removed hard-coded scale and prevented revisions from leaking
  across windows in the same app.
- `[Live blocked]` The read-only Calculator XCTest failed with AX `-25211` because its host lacks
  Accessibility permission. It remains opt-in and skipped in ordinary headless runs.
- `[Verified]` The final full suite executes 1,012 tests with 2 skipped and 0 failures; gated
  coverage is 95.14% (11,685/12,282 lines); E2E preflight and smoke pass.

### Entry 58: Fresh implementation phase 3 native actions

Sources: `phase-3-native-actions-2026-08-09.md`, `ComputerUseActionService.swift`,
`ComputerUseToolBackend.swift`, `SystemComputerUseAccessibilityActions.swift`,
`SystemComputerUseInputEvents.swift`, the shared AX platform adapter, and focused tests.

- `[Implemented]` The fresh backend executes all eight recovered action tools against app-scoped
  observations; `list_apps` and `get_app_state` complete the exact ten-tool service.
- `[Implemented]` The latest successful app observation is one-shot. Actions verify the current
  process and CG window, consume the observation before native work, settle after success, and
  require a fresh observation for the next action.
- `[Corrected]` A failed state refresh can no longer leave an older observation authorized.
- `[Implemented]` AX press, arbitrary secondary action, value replacement, UTF-16 text selection,
  process-scoped click/drag/scroll/key/text events, and screenshot-to-screen coordinate conversion
  are isolated behind typed native seams.
- `[Corrected]` The strict review preserved requested right/middle and multi-click semantics,
  centralized repeated action orchestration, and replaced three duplicate AX casting/read layers
  with one platform adapter.
- `[Independent choice]` Scroll calibration, Unicode chunking, AX refetch limits,
  `AXScrollToVisible`, repeated semantic presses, and the single ScreenCaptureKit capture path are
  closest matches rather than verified internal constants or branches.
- `[Not yet implemented]` Loading-aware extended settling, conditional focus, user-intervention
  monitoring, lock-screen guards, model/agent integration, permissions UX, direct voice, and chat
  rendering remain later phases.
- `[Verified]` The post-review full suite executes 1,041 tests with 2 skipped and 0 failures; gated
  coverage is 95.38% (12,277/12,871 lines); E2E preflight and smoke both pass.
- `[Live required]` Safe cross-process native action testing remains pending under the final
  installed Preview's Accessibility and Screen Recording identity.

### Entry 59: Fresh implementation phase 4 provider and agent loop

Sources: `phase-4-provider-agent-loop-2026-08-09.md`, the recovered operating instructions and
request-order evidence, `ComputerUseAgent.swift`, `ComputerUseRemoteModelClient.swift`, the exact
tool catalog and decoder, and focused/full validation.

- `[Verified]` The inspected desktop contract exposes exactly ten operations, disables parallel
  tool calls, preserves ordered conversation/tool results, and uses normal assistant text for a
  terminal response or user question.
- `[Implemented]` Suniye exposes exactly those ten operations to the configured model and decodes
  them into the typed native backend without a deterministic matcher, frontmost fallback, target
  lock, invented completion tool, or local action/failure/duration cap.
- `[Implemented]` The agent preserves prior conversation, the current task, assistant tool calls,
  native results, and screenshots in order. Native errors return to the model for recovery;
  cancellation remains terminal.
- `[Implemented]` The selected endpoint, model, and key come from existing user settings without
  requiring Magic Format to be enabled.
- `[Independent choice]` The current wire uses direct function tools over Suniye's existing
  OpenAI-compatible Chat Completions transport. The inspected app's Responses/node-REPL transport
  and provider-private behavior are not reproduced byte for byte.
- `[Corrected]` The strict review removed a force unwrap, localized the sendability assertion,
  separated screenshot/result serialization, and prevented cancellation from being converted into
  a retryable tool error.
- `[Verified]` The full suite executes 1,052 tests with 1,050 passed, 2 skipped, and 0 failed.
  Gated coverage is 94.93% (12,702/13,380 lines) against the explicitly selected 80% floor. E2E
  preflight and smoke both pass.
- `[Not implemented]` Main-actor coordinator integration, final permission/intervention/voice/chat
  UX, and installed live-provider Computer Use validation remain subsequent work.

### Entry 60: Fresh implementation phase 5 coordinator, chat, permissions, and voice

Sources: `phase-5-coordinator-chat-voice-2026-08-09.md`,
`ComputerUseCoordinator.swift`, `ComputerUsePermissionService.swift`,
`ComputerUseVoiceTaskHandling.swift`, the three Computer Use SwiftUI files, and focused/full
validation.

- `[Implemented]` A main-actor observable coordinator owns model configuration, permission state,
  conversation history, queued voice work, one active agent task, cancellation, and terminal
  result publication. The actor agent cannot mutate SwiftUI state directly.
- `[Implemented]` A submitted instruction is appended to conversation history and removed from the
  composer before the agent starts. Assistant output is appended only to the transcript. Follow-up
  runs receive prior conversation once and the current instruction once.
- `[Implemented]` The page exposes a single contextual Send/Stop control, generic shimmering
  `Working` status, new-conversation reset, and one collapsed settings disclosure at the bottom.
  No target picker, target lock, frontmost fallback, manual native-action panel, approval card, or
  debug observation panel is present.
- `[Implemented]` Accessibility and Screen Recording use the public TCC preflight/request APIs.
  When access remains denied, the settings disclosure can open the corresponding System Settings
  privacy pane.
- `[Implemented]` While the Computer Use page is visible, Suniye's existing local hold-to-talk
  pipeline routes the raw transcript to the coordinator. It bypasses Magic Format, clipboard and
  focused-app insertion, submit-key handling, and dictation history.
- `[Corrected]` The strict review split the page into focused files, allowed model changes to apply
  to the next run while preserving the current run, generation-guarded overlapping permission
  requests, and queued voice work during permission preparation.
- `[Independent choice]` The exact SwiftUI layout, permission-settings deep links, visible-page
  voice routing, and voice queue lifecycle are Suniye integrations. The inspected artifact does
  not reveal those exact host-level implementations.
- `[Verified]` The full suite executes 1,064 tests with 2 skipped and 0 failures. Gated coverage is
  89.32% (12,938/14,485 lines) against the requested 80% floor. E2E preflight and smoke pass.
- `[Unknown]` Live provider behavior, installed-app TCC behavior, cross-process actions,
  physical-input intervention timing, lock-screen behavior, loading-aware settling, and browser
  control remain unverified or unimplemented.

### Entry 61: Fresh implementation phase 6 runtime guards and settling

Sources: `phase-6-runtime-guards-settling-2026-08-09.md`, recovered native lock/intervention
symbols and settling instructions, `ComputerUseRuntimeGuard.swift`,
`ComputerUseActionSettler.swift`, backend and agent integration, and focused tests.

- `[Implemented]` Each observation captures an unlocked-session authorization and a full vector
  of physical HID event counters. The action validates it before native input and after settling.
- `[Implemented]` A locked session fails with an unlock instruction. Physical user input after an
  observation terminates the run as cancelled and requires a new run or observation.
- `[Implemented]` Successful actions wait one second, then poll fresh target AX state every 500
  milliseconds while a progress or busy indicator remains, up to five seconds.
- `[Corrected]` The strict review added post-settle intervention validation, replaced a lossy
  counter sum with the complete vector, and split backend test doubles from the test cases.
- `[Independent choice]` Suniye uses HID counter snapshots instead of a persistent event tap and
  uses `AXProgressIndicator`/`AXBusyIndicator` as its loading predicate. It does not implement
  automatic lock-screen unlock.
- `[Unknown]` Exact intervention debounce, event filtering, already-posting action cancellation,
  full loading heuristics, and lock-screen recovery details remain unrecovered.
- `[Verified]` The focused runtime, backend, and agent suite executes 25 tests with 0 failures.
- `[Verified]` The full suite executes 1,075 tests with 2 skipped and 0 failures. Gated coverage is
  89.36% (13,041/14,593 lines) against the requested 80% floor. E2E preflight and smoke pass.
- `[Pending]` Installed Preview and live model validation.

### Entry 62: Live observation and cold-launch parity

Sources: `phase-7-live-observation-launch-parity-2026-08-09.md`, mounted native service symbols,
direct reference and installed-Preview live sessions, window matcher and launcher changes, and
focused/full validation.

- `[Verified]` The reference waits for application launch completion and for a primary window. A
  cold Calculator `get_app_state` succeeded directly in 791 milliseconds.
- `[Corrected]` Suniye now correlates CG and AX windows by matching geometry when AX bounds exist;
  dynamic title differences no longer reject the same window. Title remains a fallback when AX
  bounds are unavailable.
- `[Implemented]` Background launch waits until the application finishes launching and a matched
  primary window appears, without activating the app or adding it to recent items.
- `[Independent choice]` The five-second primary-window timeout and 50-millisecond polling interval
  are closest-match values because the exact native constants remain unknown.
- `[Verified]` Installed Preview tasks read Battery Health as `Normal`, calculated `17 × 19` as
  `323`, and cold-launched/observed Calculator in one model tool call after the fix.
- `[Verified]` The multi-action Calculator trace alternated every native action with
  `get_app_state`, providing live evidence of fresh observation before each newly selected action.
- `[Corrected]` Privacy-bounded lifecycle diagnostics exclude task text, arguments, AX content,
  screenshots, paths, endpoints, and credentials.
- `[Verified]` The strict review found no new oversized module, routing heuristic, target lock,
  forced-frontmost behavior, or raw payload logging.
- `[Verified]` The full suite executes 1,078 tests with 2 skipped and 0 failures. Gated coverage is
  89.36% (13,083/14,641 lines) against the requested 80% floor. E2E preflight and smoke pass.

### Entry 63: Native virtual cursor recovery

Sources: `fake-cursor-dmg-agent-report.md`, the mounted DMG's `SkyComputerUseService`,
`sky.node`, `Package_ComputerUse.bundle/Contents/Resources/Assets.car`, the extracted ASAR, and
live Sky screenshots from the installed helper.

- `[Verified]` The native helper contains a dedicated `ComputerUseCursor` subsystem with a cursor
  window, `SoftwareCursorStyle`, `FogCursorStyle`, `CursorView`, `CursorMotionPath`, target window
  state, cursor active/location notifications, and the feature flag
  `feature/computerUseCursor` (`Enable the virtual cursor in Computer Use`).
- `[Verified]` The helper ships a transparent compiled `SoftwareCursor` image asset. The host
  `sky.node` bridge carries cursor active state and location and exposes a remote-hosted PIP
  cursor-location path.
- `[Verified]` The ASAR also contains a separate browser-only `browser-agent-cursor-overlay` with
  pointer-events-disabled rendering and animated cursor movement. It is not the native Mac helper
  cursor.
- `[Verified]` A later installed helper returned a post-action Calculator skyshot containing the
  virtual cursor at the clicked button. The installed helper version differs from the mounted DMG
  version, so this is corroboration rather than exact-build proof.
- `[Inferred]` The desktop cursor is a helper-owned presentation sidecar: it moves to the same
  resolved target point as the native action, animates with spring/arc/scoot state, and can be
  forwarded to a PIP presentation. The public ten-tool contract remains unchanged.
- `[Unknown]` The exact mounted-build screenshot compositor, cursor style gate, physical-pointer
  behavior, fade timing, and pressed animation remain unrecovered.
- `[Verified]` Suniye currently has no equivalent cursor window, cursor state, action-location
  bridge, or desktop overlay. Adding one is a parity gap, not a reason to add another model tool or
  target-selection restriction.

### Entry 64: Suniye native virtual cursor implementation

Sources: `phase-8-native-virtual-cursor-2026-08-11.md`, production Swift sources, XCTest results,
coverage report, E2E scripts, installed Preview, and the natural Calculator run.

- `[Implemented]` A passive nonactivating AppKit overlay presents cursor movement, click, drag,
  and scroll feedback at the same resolved screen coordinates used by the action service.
- `[Implemented]` The cursor is an internal presentation service. The ten public model tools,
  provider request, prompt, application discovery, and approval behavior are unchanged.
- `[Implemented]` Superseded animations are cancelled, Reduced Motion is honored, and action-run
  cancellation propagates through optional Accessibility-center resolution.
- `[Verified]` The full suite executes 1,089 tests with 2 skipped and 0 failures. Gated coverage is
  88.95% (13,380/15,043 lines) against the 80% floor. E2E preflight and smoke pass.
- `[Verified]` The installed Preview completed `Open Calculator and click the 7 button.`,
  re-observed Calculator value `71`, and returned `Done.`
- `[Unknown]` Exact reference animation constants, style gate, physical-pointer behavior, and the
  screenshot/PIP cursor-composition branch remain unavailable and were not guessed.

### Entry 65: Per-run debug session correlation

Sources: `phase-9-debug-session-correlation-2026-08-11.md`, coordinator and agent tests, full-suite
coverage, installed Preview UI, clipboard verification, and the installed app log.

- `[Implemented]` Each run receives one compact `CU-...` debug identifier. Coordinator state keeps
  the current or most-recent value, and the agent task carries the identical value.
- `[Corrected]` `Copy debug ID` is directly beside `New conversation` in the Computer Use header;
  it is not hidden in the settings disclosure.
- `[Implemented]` Every agent lifecycle and tool-boundary event includes `session=<ID>` without
  logging task text, tool arguments, AX content, screenshots, credentials, or endpoints.
- `[Verified]` The corrected installed Preview shows `Copy debug ID` beside `New conversation`,
  copies the exact `CU-...` value, and no longer shows debug UI inside the settings disclosure.
  Searching `app.log` and `app.log.1` by a copied ID recovers the complete ordered run trace.
- `[Verified]` The full suite executes 1,091 tests with 2 skipped and 0 failures. Gated coverage is
  88.41% (13,400/15,156 lines) against the 80% floor.

### Entry 66: Remove speculative physical-input cancellation

Sources: installed session `CU-6E2061703015`, live Codex/ChatGPT concurrent-use behavior,
`ComputerUseRuntimeGuard.swift`, agent/backend integration, regression tests, and installed Preview
session `CU-CC7B23592202`.

- `[Verified]` The failed session completed app discovery and observation, began a click, then
  cancelled with `reason=user_intervened` at the same moment Suniye became key.
- `[Corrected]` Global HID-counter changes no longer invalidate a fresh observation or cancel a
  run. Users can continue using the Mac while Computer Use is running.
- `[Removed]` `SystemComputerUsePhysicalInputSampler`, physical-input authorization snapshots,
  `ComputerUseRuntimeError.userIntervened`, its agent cancellation message, and intervention-only
  test doubles/tests.
- `[Retained]` Locked-screen rejection, one-action-per-fresh-observation enforcement, explicit
  Stop cancellation, and loading-aware action settling.
- `[Verified]` During installed Preview session `CU-CC7B23592202`, `Copy debug ID` was clicked while
  the task was working. The run continued through 13 model/tool steps, completed the Calculator
  action, and returned `Done.` The correlated trace contains no intervention cancellation.
- `[Verified]` The full suite executes 1,088 tests with 2 skipped and 0 failures. Gated coverage is
  88.55% (13,376/15,106 lines) against the 80% floor.

### Entry 67: Minimal inline tool activity

Sources: `phase-10-inline-agent-activity-2026-08-11.md`, production Swift sources, focused tests,
full-suite XCTest results, and coverage report.

- `[Corrected]` The earlier transport/debug-heavy activity UI was rejected before release and
  removed. Chat does not show model requests, provider responses, HTTP metadata, lifecycle rows,
  tool results, error payloads, expandable details, connector lines, or per-tool icons.
- `[Implemented]` Each model-issued tool call appears in order as one plain selectable monospaced
  row containing only its raw tool name and raw JSON argument string.
- `[Implemented]` Tool activity appears between the user task and final assistant response and is
  excluded from subsequent model context.
- `[Implemented]` Explicit Stop produces only the final assistant message `Stopped.`.
- `[Verified]` Focused validation executes 19 tests with zero failures. The full suite executes
  1,090 tests with 2 skipped and 0 failures. Gated coverage is 88.44% (13,420/15,174 lines) against
  the 80% floor.
- `[Verified]` Installed Preview session `CU-616B85F2116D` rendered one raw `get_app_state` call as
  plain text between the user task and final assistant message. Live Accessibility and screenshot
  inspection found no activity icon, lifecycle, transport, result, disclosure, connector, or
  separate completion row.
- `[Observed]` The provider resolved the phrase `Suniye Preview` to the separate app `Preview` and
  returned that app's PDF window title. This app-name ambiguity was recorded rather than hidden by
  deterministic client routing.

### Entry 68: Persistent cursor and replacement-window parity

Sources: `phase-11-run-scoped-cursor-and-native-parity-2026-08-12.md`,
`deep-code-parity-audit-2026-08-12.md`, three independent code-level audits, focused and full
XCTest runs, coverage, E2E scripts, the installed Preview, sessions `CU-DACA4C3C5CD5` and
`CU-463FE693F46D`, and independent observations through the bundled Computer Use runtime.

- `[Verified]` The inspected desktop cursor remains at its last pointer-action location while the
  model reasons and animates from that retained point to the next pointer target.
- `[Implemented]` Suniye's passive cursor is now run-scoped. It has no action-local hide timer and
  is cleared only on completion, failure, Stop, or New Conversation.
- `[Corrected]` A stale window still invalidates the authorized action. The next observation now
  waits for an on-screen replacement window in the same running process instead of reopening the
  app and misreporting the timeout as `launchFailed`.
- `[Removed]` The temporary all-window/off-screen CG and screenshot fallback was removed because
  the recovered normal reference path enumerates on-screen, non-desktop windows.
- `[Verified live]` Installed Preview session `CU-463FE693F46D` completed the natural battery
  health task through System Settings and reported `Normal, 100%`. An independent observation of
  the resulting Battery Health sheet verified `Normal 100%`.
- `[Observed]` Installed Preview session `CU-DACA4C3C5CD5` completed a 13-step Calculator loop with
  strict observation/action alternation, but the model chose `17 × 9` and reported `153` for the
  requested `17 × 19`. The native loop worked; model planning/context fidelity remains a known
  architecture-level gap from the inspected Responses plus persistent-JavaScript runtime.
- `[Verified]` The final focused suite executes 32 tests with zero failures. The full suite executes
  1,093 tests with 2 skipped and zero failures. Gated coverage is 88.45% (13,397/15,146 lines)
  against the 80% floor. E2E preflight and smoke pass.

### Entry 69: Background-Space observation parity

Sources: `phase-12-background-space-observation-2026-08-12.md`, mounted native binary symbols,
direct bundled-runtime observations, Core Graphics and Accessibility probes, installed Preview
sessions `CU-87E929416B23` and `CU-1294CF91EBB9`, XCTest, coverage, and E2E scripts.

- `[Corrected]` Entry 68's removal of the all-window path is superseded. Live reference behavior
  proves that Computer Use can observe an application on another Space without bringing it
  forward, and the native binary contains the corresponding private WindowServer capture path.
- `[Verified]` Helium exposes no on-screen Core Graphics window and an empty `AXWindows` array in
  this state, while the complete Core Graphics list plus `AXMainWindow`/`AXFocusedWindow` identify
  its real browser window and complete Accessibility tree.
- `[Corrected]` Direct probing rejected the earlier AX-enablement hypothesis for this failure:
  `AXManualAccessibility` is unsupported and `AXEnhancedUserInterface` is already true. No
  Chromium-specific enablement branch remains in Suniye.
- `[Implemented]` Suniye tries the normal on-screen match first, then the complete window list;
  shares the AX main/focused fallback across discovery, observation, and actions; and tries
  ScreenCaptureKit before the dynamically resolved SkyLight/WindowServer image function.
- `[Verified]` ScreenCaptureKit enumerates the off-Space window with
  `onScreenWindowsOnly: false` but fails capture with `SCStreamErrorDomain -3811`. The recovered
  `SLSHWCaptureWindowListInRect` path returned the correct 3420-by-2148 image without activation.
- `[Verified live]` Session `CU-87E929416B23` naturally read the two Helium tabs in one observation.
  Session `CU-1294CF91EBB9` opened and closed a new tab with a fresh observation after each action;
  an independent observation verified that the original two-tab state was restored.
- `[Verified]` The full suite executes 1,093 tests with 2 skipped and zero failures. Gated coverage
  is 88.46% (13,411/15,160 lines) against the 80% floor. E2E preflight and smoke pass.
- `[Unknown]` The exact full private-backend branch matrix, every WindowServer option bit, and
  future private-API compatibility remain unavailable. No behavior beyond the verified fallback
  was added.

### Entry 70: Collapsed inline tool results

Sources: `phase-13-collapsed-tool-results-2026-08-12.md`, production Swift sources, focused tests,
and installed Preview session `CU-B4C2E8F64CFC`.

- `[Supersedes Entry 67]` Inline activity still defaults to the minimal raw tool name and raw JSON
  arguments, but each completed call now also has a collapsed raw-result disclosure.
- `[Implemented]` The agent emits a pending activity and then its exact encoded tool result under
  the same private identifier. The coordinator replaces the pending activity in place, producing
  one timeline row rather than a second result row.
- `[Implemented]` Results include the payload actually sent back to the model: `null`, encoded app
  lists or app states, and encoded error objects. Activity remains excluded from later model chat
  history.
- `[Verified live]` All completed calls in session `CU-B4C2E8F64CFC` rendered collapsed by default.
  Expanding `set_value` revealed `null`; collapsing it hid the result again. An expanded
  `get_app_state` showed its complete encoded app state and Accessibility text.
- `[Verified]` A failed tool-call regression confirms that the completed activity exposes the same
  encoded error object returned to the model. The full suite executes 1,094 tests with 2 skipped
  and zero failures; gated coverage is 88.24% (13,453/15,246). E2E preflight and smoke pass.
- `[Retained]` No model transport, provider response, lifecycle row, result summary, connector,
  per-tool icon, or separate completion row is shown.

### Entry 71: Browser link primary-click correction

Sources: `phase-14-browser-link-click-2026-08-12.md`, mounted reference runtime, production Swift
sources, focused tests, installed Preview sessions `CU-93344C32D67F` and `CU-73FFF3CFD120`.

- `[Verified]` Session `CU-93344C32D67F` itself executed only `get_app_state`; it never issued a
  click. The preceding run in the same conversation issued an indexed click and a coordinate
  click, but Helium remained on `kishans.in`.
- `[Verified]` The reference runtime activated the same `Gita GPT` Accessibility link and observed
  `gita.kishans.in` afterward.
- `[Supersedes Entry 68]` A single indexed primary click now tries `AXPress` before using settable
  `AXSelected` as a fallback. Selection is not treated as successful activation when press is
  available. Multi-click behavior remains repeated `AXPress`, followed by the existing
  process-scoped pointer fallback when semantic activation is unavailable.
- `[Inferred]` The old selection-first policy could report success without activating some
  selectable controls and best matches the reported hover/focus-like symptom. The historical run
  did not record which native branch returned success, so that branch attribution is not verified.
- `[Verified live]` After terminating the old process and launching the newly installed Preview,
  natural-language session `CU-73FFF3CFD120` observed Helium, called
  `click(element_index: 79)`, observed again, and reported success. An independent observation
  confirmed Helium at `gita.kishans.in`.
- `[Verified]` The full suite executes 1,095 tests with 2 skipped and zero failures. Gated coverage
  is 88.27% (13,458/15,246), above the 80% floor. E2E preflight and smoke pass.
