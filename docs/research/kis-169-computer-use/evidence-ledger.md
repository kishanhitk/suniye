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
- `[Unknown]` The exact helper implementation is not recoverable from the shipped binary.

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
`Suniye/Views/MainWindow/ComputerUseAgentPanel.swift`, and
`Suniye/Views/MainWindow/MainWindowView.swift`.

- `[Verified]` The production coordinator receives a model only when the user enables the existing API Endpoint provider, has valid endpoint/model settings, and has a non-empty keychain key.
- `[Verified]` Automatic, local, disabled, invalid, and missing-key settings fail closed to no configured Computer Use model.
- `[Verified]` Accessibility remains required for an agent run. Screen Recording is required only when the local observation includes a screenshot.
- `[Verified]` Screenshot upload is disabled by default and can be enabled only through a visible session UI toggle.
- `[Verified]` The model task editor, connection status, run control, upload consent, terminal result, and user question are now visible in the Computer Use page.
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
- `[Unknown]` The DMG does not expose the complete native helper implementation, server/model
  loop, or browser-extension route. Cross-process third-party input, fresh Screen Recording
  consent, and browser/cart behavior remain unverified in this run.

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
