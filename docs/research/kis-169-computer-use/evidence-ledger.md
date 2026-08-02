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
- `[Verified]` Suniye lists running applications by exact bundle identifier.
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
- `[Verified]` Sixteen deterministic Phase 0 tests pass.
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
