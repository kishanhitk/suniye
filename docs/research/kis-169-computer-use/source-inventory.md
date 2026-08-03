# KIS-169 source inventory

This file maps the research notes to the inspected sources.

## DMG

Source:

`/Users/kishan/Downloads/ChatGPT (1).dmg`

The image was mounted read-only at:

`/tmp/suniye-chatgpt-dmg-mount`

The selected JavaScript files were extracted to:

`/tmp/suniye-cua-inspect`

These temporary paths are inspection paths. They are not Suniye dependencies.

### Main app metadata

Inspected bundle path:

`ChatGPT.app/Contents/Info.plist`

Useful fields:

- bundle identifier `com.openai.codex`;
- display name ChatGPT;
- build `26.727.51351`;
- minimum macOS `12.0`;
- Apple Events usage description;
- application group for the Computer Use helper;
- no App Sandbox entitlement.

Status: `[Verified]` by plist and entitlement inspection.

### JavaScript API and transport

Inspected package path:

`ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky`

Useful files:

- `package.json`;
- `README.md`;
- `docs/sky-window-api.md`;
- `docs/sky-window2-api.md`;
- `docs/sky-full-desktop-api.md`;
- `dist/project/cua/sky_js/src/targets/mac/client.js`;
- `dist/project/cua/sky_js/src/targets/mac/create_client.js`;
- `dist/project/cua/sky_js/src/targets/mac/native-pipe.js`;
- `dist/project/cua/sky_js/src/targets/mac/computer-use-policy.js`;
- `dist/project/cua/sky_js/src/targets/mac/errors.js`;
- `dist/project/cua/sky_js/src/targets/mac/window_result.js`;
- macOS action wrapper files;
- macOS TypeScript declaration files.

These files establish the public macOS target, action inputs, app policy, approval bridge, error names, and Unix transport.

Status: `[Verified]` by source inspection.

## Superseding source inventory correction — 2026-08-03

- `[Verified]` The current production surface does not contain the removed action panel, target
  lock/intervention monitor, screenshot-choice state, cached element/action policy, or local agent
  limits.
- `[Verified]` `ComputerUseCoordinator` owns app-level UI/session state; internal window discovery
  remains in `ComputerUseObservationService`, `ComputerUseAccessibilityReader`, screenshot capture,
  and window activation adapters.
- `[Verified]` `ComputerUseModelClient` sends Accessibility text and the observation screenshot;
  the former duplicate element renderer and internal window metadata are removed.
- `[Unknown]` No source inventory can establish the inspected artifact's full native helper or
  server-side model implementation.

## Corrective parity slice (historical implementation record)

The current parity slice extends the desktop path with these boundaries:

- `Suniye/Services/ComputerUsePlatformRunner.swift` isolates platform discovery, activation,
  permission, observation, approval-store, and action calls from the MainActor coordinator.
- `Suniye/Services/ComputerUseWindowActivationService.swift` owns AppKit and Accessibility window
  activation for an explicitly selected target.
- `Suniye/Services/ComputerUseActionModels.swift` and `ComputerUseActionService.swift` add bounded
  click metadata, indexed clicks, positioned scroll, drag, AX value setting, text selection, and
  dynamic secondary Accessibility actions. Coordinate actions can validate a screenshot ID.
- `Suniye/Views/MainWindow/ComputerUsePage.swift` adds window selection, Bring Forward, and
  the optional local screenshot control.
- `docs/research/kis-169-computer-use/parity-audit.md` records the reference comparison.

Status: `[Verified]` by focused tests, source inspection, and the live `@Computer` run for the
Suniye self-target. Cross-process WindowServer activation remains `[Unknown]`.

### Reviewed validation

- The full macOS test run reports 1,088 passed, 1 skipped, and 0 failed tests.
- The gated coverage report is 95.10% (14,453/15,197 lines) at a 95% threshold.
- The focused regression suite reports 3 passed tests and 0 failures.
- Strict review split the large Phase 2 test file, removed a coordinate force unwrap, improved
  failure diagnostics, and aligned public action keys with the inspected reference contract.
- The live `@Computer` run validates navigation, target/window pickers, same-process activation,
  Accessibility-only observation, and approval denial.

Status: `[Verified]` by `xcodebuild`, `xccov`, local source inspection, and the live `@Computer`
run. Provider, Screen Recording, and cross-process behavior remain `[Unknown]`.

### Native helper

Inspected bundle path:

`ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app`

Useful items:

- `Contents/Info.plist`;
- `Contents/MacOS/SkyComputerUseService`;
- `Contents/Resources/Package_ComputerUse.bundle`;
- `Contents/Resources/Package_Appshot.bundle`;
- `Contents/Resources/SkyComputerUseClient.app`;
- `Contents/Resources/CUALockScreenGuardian.app`.

The helper executable was inspected with `file`, `otool`, `codesign`, and `strings`.

Status:

- framework links and named native components: `[Verified]`;
- source-level implementation: `[Unknown]`;
- exact native operation path: `[Unknown]`.

### Capture bridge

Inspected extracted file:

`worker.js`

Useful symbols and behavior:

- `computer-use-worker`;
- `ComputerUseIPCAppStartCaptureRequest`;
- `ComputerUseIPCAppNextCaptureUpdateRequest`;
- Apple Event request construction;
- screenshot URL validation;
- capture update polling;
- stale attachment-generation handling;
- completed and failed update handling.

Status: `[Verified]` for readable worker behavior. Native helper behavior remains `[Unknown]`.

### Host bridge

Inspected extracted files:

- `main-dcXtv3U5.js`;
- `app-initial-iBPGfcXU.js`;
- `src-CLstCQVF.js`.

Useful behavior:

- loading `sky.node`;
- frontmost-window lookup;
- helper process lookup and launch;
- `computer-use-frontmost-window`;
- `computer-use-start-capture`;
- foreground appshot context;
- permission error classification.

Status: `[Verified]` for readable host behavior.

### App-specific guidance

Inspected path:

`Package_ComputerUse.bundle/Resources/AppInstructions`

Files include:

- `AppleMusic.md`;
- `Clock.md`;
- `iPhone Mirroring.md`;
- `Notion.md`;
- `Numbers.md`;
- `Slack.md`;
- `Spotify.md`.

Status: `[Verified]` that the bundle contains app-specific guidance. The complete runtime selection policy is `[Unknown]`.

### Browser assets

Inspected extracted files:

- `browser-N_xc8tjF.js`;
- `browser-use-settings-BMRbLPpa.js`;
- `browser-use-settings-B3B8gSK5.js`;
- `computer-use-settings-BXahkuOI.js`.

These files show separate in-app browser settings, extension setup, browser references, and download/upload approval settings.

Status:

- separate product surface: `[Verified]`;
- exact browser wire protocol: `[Unknown]`.

## Suniye

The Suniye source was inspected in this worktree. The following files were central:

- `Suniye/AppState.swift`;
- `Suniye/Services/TextInsertionService.swift`;
- `Suniye/Services/EditModeService.swift`;
- `Suniye/Services/AccessibilityOnboarding.swift`;
- `Suniye/Services/LLMPostProcessor.swift`;
- `Suniye/Services/ChatCompletionClient.swift`;
- `Suniye/Services/MagicFormatCoordinator.swift`;
- `Suniye/Services/LocalGemmaLlamaCppClient.swift`;
- `Suniye/MainWindowSection.swift`;
- `Suniye/Views/MainWindow/MainWindowView.swift`;
- `Suniye/Views/MainWindow/MainWindowPages.swift`;
- `Suniye/Info.plist`;
- `project.yml`;
- `SuniyeTests/TestDoubles.swift`;
- `scripts/coverage_exclusions.txt`.

Phase 0 added these source files:

- `Suniye/Services/ComputerUseModels.swift`;
- `Suniye/Services/ComputerUseApplicationCatalog.swift`;
- `Suniye/Services/ComputerUseObservationService.swift`;
- `Suniye/Services/ComputerUseAccessibilityReader.swift`;
- `Suniye/Services/ComputerUsePermissionService.swift`;
- `Suniye/Services/ComputerUseScreenshotService.swift`;
- `SuniyeTests/ComputerUsePhase0Tests.swift`.

Status: `[Verified]` by the Phase 0 build and test run.

Phase 1 added these source files:

- `Suniye/Services/ComputerUseCoordinator.swift`;
- `Suniye/Views/MainWindow/ComputerUsePage.swift`;
- `SuniyeTests/ComputerUsePhase1Tests.swift`.

Phase 1 also adds the `computerUse` main-window section and regenerates the Xcode project.

Status: `[Verified]` by the Phase 1 build and targeted test run.

Phase 2 added these source files and boundaries:

- `Suniye/Services/ComputerUseActionModels.swift`;
- `Suniye/Services/ComputerUseActionService.swift`;
- `Suniye/Services/ComputerUseInputEventService.swift`;
- `SuniyeTests/ComputerUsePhase2ActionTests.swift`;
- `SuniyeTests/ComputerUsePhase2TestSupport.swift`;
- `SuniyeTests/ComputerUsePhase2Tests.swift`.

Phase 2 also extends `ComputerUseCoordinator.swift` and
`ComputerUseAccessibilityReader.swift`, and regenerates the Xcode project.

Status: `[Verified]` by the Phase 2 build and focused test run. The native event adapter and
Accessibility action boundary remain platform-bound paths. The temporary SwiftUI manual action
panel was removed in the 2026-08-03 parity cleanup; current actions enter through the agent loop.

Phase 3 added these source files and boundaries:

- `Suniye/Services/ComputerUseAgentModels.swift`;
- `Suniye/Services/ComputerUseAgent.swift`;
- `SuniyeTests/ComputerUsePhase3Tests.swift`.
- `SuniyeTests/ComputerUsePhase3TestSupport.swift`.

Phase 3 also regenerates the Xcode project. Live WindowServer behavior remains outside the
headless coverage gate where the current exclusion file documents it.

Status: `[Verified]` by the Phase 3 full test and coverage run. The model client is an
unconfigured default plus test doubles; no live provider is connected.

Phase 4 added these policy and safety files:

- `Suniye/Services/ComputerUsePolicyService.swift`;
- `Suniye/Services/ComputerUseApprovalStore.swift`;
- `Suniye/Services/ComputerUseAudit.swift`;
- `SuniyeTests/ComputerUsePhase4PolicyTests.swift`.

Phase 4 also extends the approval models and regenerates the Xcode project.

Status: `[Verified]` by the Phase 4 focused policy test run. The policy boundary is not yet
wired to the coordinator or a live model provider.

Phase 5A added the independent model transport files:

- `Suniye/Services/ComputerUseModelClient.swift`;
- `SuniyeTests/ComputerUsePhase5ModelTests.swift`.

Phase 5A also extends `Suniye/Services/ChatCompletionClient.swift` with a raw request-body
transport path and regenerates the Xcode project.

Status: `[Verified]` by focused model transport tests. Phase 5A is the transport boundary; Phase
5B connects it to the coordinator and production settings.

Phase 5B added the coordinator/model integration files:

- `Suniye/Services/ComputerUseAgentApproval.swift`;
- `Suniye/Services/ComputerUseModelConfigurationFactory.swift`;
- `Suniye/Views/MainWindow/ComputerUseAgentPanel.swift`;
- `SuniyeTests/ComputerUsePhase5CoordinatorTests.swift`;
- `SuniyeTests/ComputerUseModelConfigurationTests.swift`.

Phase 5B also extends `Suniye/AppState.swift`,
`Suniye/Services/ComputerUseCoordinator.swift`,
`Suniye/Services/ComputerUseModelClient.swift`,
`Suniye/Views/MainWindow/ComputerUsePage.swift`, and
`Suniye/Views/MainWindow/MainWindowView.swift`.

Status: `[Verified]` by focused coordinator, model, and configuration tests. The desktop path is
connected to an explicit API Endpoint configuration. A live provider run, live WindowServer
action, browser adapter, and separate native helper remain `[Unknown]` or intentionally deferred.

These files establish the current state machine, permissions, Accessibility insertion, model seams, settings surface, build source of truth, and test seams.

Status: `[Verified]` by source inspection.

## Direct voice integration slice — 2026-08-03

The current implementation adds these files and references:

- `Suniye/Services/ComputerUseVoiceTaskHandling.swift`;
- `Suniye/Services/ComputerUseCoordinator.swift`;
- `Suniye/AppState.swift`;
- `Suniye/Views/MainWindow/ComputerUsePage.swift`;
- `Suniye/Views/MainWindow/ComputerUseAgentPanel.swift`;
- `Suniye/Views/MainWindow/MainWindowView.swift`;
- `SuniyeTests/AppStateComputerUseVoiceTests.swift`;
- `SuniyeTests/ComputerUsePhase5CoordinatorTests.swift`.

Status: `[Verified]` by signed build and focused tests. Live microphone and provider execution
remain `[Unknown]`.

## Trace rule

Use `evidence-ledger.md` for claim status.

Use `architecture.md` for system understanding.

Use `implementation-plan.md` for proposed Suniye work.

Use `open-questions.md` for unresolved decisions.
