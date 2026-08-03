# Direct voice-to-Computer Use integration

Date: 2026-08-03

Status: implemented in the `kis-169-computer-use` worktree; live microphone and provider
validation remain open.

## Goal

Let a user speak a Computer Use task through Suniye's existing hold-to-talk flow. When the
Computer Use page is visible, the transcribed task goes directly to the Computer Use coordinator.
It does not become text for the focused app, pass through Magic Format, or enter dictation history.

## Evidence boundary

- `[Verified]` `AppState` already owns the microphone, transcription, hotkey, and dictation
  lifecycle.
- `[Verified]` `ComputerUseCoordinator` already owns the Computer Use model/action loop and is
  main-actor isolated.
- `[Verified]` The installed Computer Use page is a distinct main-window section.
- `[Inferred]` The visible Computer Use page is the safest explicit routing context for direct
  voice tasks. A phrase matcher or a global mode would introduce an extra product rule that is
  not required by the inspected desktop contract.
- `[Unknown]` The reference application's complete voice-routing implementation is not exposed
  by the inspected DMG. This is an independent Suniye integration, not a claim about hidden
  reference code.

## Implemented architecture

### Small routing seam

`Suniye/Services/ComputerUseVoiceTaskHandling.swift` defines the main-actor boundary:

- `ComputerUseVoiceTaskHandling` accepts already-transcribed task text.
- `ComputerUseVoiceTaskSubmission` reports `started`, `queued`, or `rejected(message:)`.
- The protocol does not expose model, Accessibility, screenshot, or input implementation details.

This keeps `AppState` responsible for dictation and keeps Computer Use state inside its own deep
module.

### AppState integration

`AppState` holds a weak handler reference. The weak reference prevents the global dictation owner
from retaining a window-scoped coordinator.

`currentDictationDestination` resolves in this order:

1. onboarding practice;
2. direct Computer Use when the Computer Use page has registered its handler;
3. normal system insertion when Accessibility is available;
4. clipboard-only fallback.

For the Computer Use destination, the final transcript is sent raw to the handler. It skips:

- Magic Format;
- Accessibility text insertion;
- clipboard writes;
- submit-key handling;
- recent-result/history persistence;
- normal dictation-completed analytics, because this is an agent task rather than inserted text.

Microphone permission and the existing transcription service remain unchanged.

### Coordinator integration

`ComputerUseCoordinator` stores one pending voice instruction when the page is still loading apps,
waiting for permissions, or waiting for a configured model. It starts the agent automatically as
soon as `canRunAgent` becomes true.

The captured voice instruction is restored before launch, so a later edit of the manual task field
cannot replace a queued spoken task. A new voice task is rejected while observation or agent work
is already active; the current operation is not canceled or put into a failed state.

`cancel()` clears a queued voice task. Leaving the Computer Use page unregisters the handler and
cancels the coordinator, so a task cannot start after its routing context disappears.

### SwiftUI UX

`ComputerUsePage` registers the coordinator on appear and unregisters it on disappear.
`ComputerUseAgentPanel` explains the hold-to-talk gesture and shows a waiting message when a task
has been captured but Computer Use is not ready.

The existing text editor and Run button remain available as a manual fallback. Voice does not
require a second Computer Use shortcut or a confirmation card.

## End-to-end lifecycle

1. The user opens Computer Use and the page registers its coordinator with `AppState`.
2. The user holds the existing dictation hotkey.
3. `AppState` checks microphone permission and starts the existing audio capture.
4. The user releases the hotkey.
5. `AppState` transcribes with the existing local transcription service.
6. The raw transcript is submitted to the coordinator.
7. The coordinator starts immediately or queues until apps, permissions, and model configuration
   are ready.
8. The existing Computer Use agent performs its observation/model/action/re-observation loop.
9. Suniye ends the dictation session and returns its dictation phase to Ready while the agent
   continues independently.
10. The Computer Use page publishes the agent's terminal result.

## Permissions and failure behavior

- `[Verified]` Voice capture uses the existing Microphone permission path.
- `[Verified]` Computer Use separately requires Accessibility and Screen Recording before an agent
  can run, because its observation includes AX state and a screenshot.
- `[Verified]` Missing model or Computer Use permissions queues the task and exposes a recovery
  message in the Computer Use page.
- `[Verified]` Empty transcription fails the dictation session and does not launch an agent.
- `[Verified]` A missing page handler fails the session instead of silently inserting text.
- `[Verified]` A task submitted while the agent is observing or running is rejected and the active
  operation is preserved.
- `[Unknown]` Live speech-recognition timing, microphone interruption during a Computer Use voice
  task, and provider/network failure after voice submission still need a macOS E2E run.

## Test plan

Automated coverage added:

- AppState submits a spoken task without Accessibility text insertion or clipboard output.
- AppState reports a coordinator rejection as a dictation error.
- The coordinator starts a ready voice task automatically.
- The coordinator queues a task until a model is configured.
- The queued captured instruction takes precedence over a later manual editor change.
- Empty voice instructions are rejected.

Manual validation still required:

1. Install the Preview build.
2. Configure Model → API Endpoint with a supported endpoint and key.
3. Grant Computer Use Accessibility and Screen Recording permissions.
4. Open the Computer Use page, select a harmless read-only desktop task, hold the normal Suniye
   hotkey, speak the task, and release.
5. Verify that no text is inserted into the focused app and that the Computer Use result appears.
6. Repeat with the page closed to verify normal dictation routing is unchanged.

Browser tasks remain a separate adapter and should be tested through the browser extension path,
not through the desktop Computer Use voice route.
