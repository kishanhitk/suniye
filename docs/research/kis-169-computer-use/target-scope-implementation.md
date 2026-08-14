# Target scope correction

Date: 2026-08-03

Reference: `<home>/Downloads/ChatGPT (1).dmg`

This note records the target-scope correction as one atomic research entry. It separates verified
reference behavior from implementation choices and remaining unknowns.

## Findings

- `[Verified]` The inspected macOS reference accepts an `app` value on each state and input call.
  The public API does not expose one immutable session-wide app target.
- `[Verified]` The reference Computer Use skill says the macOS state call launches a requested app
  in the background when it is not running.
- `[Verified]` The previous Suniye agent required a non-empty application identifier and stopped
  when the frontmost process or selected key window changed.
- `[Verified]` That Suniye target lock was local implementation behavior. It was not established as
  a requirement by the inspected macOS API.
- `[Inferred]` A model can move between desktop apps by making another app-targeted state request.
  The DMG does not expose the complete host model loop.
- `[Verified]` The static prompts, client-side model selection, request composition, and local
  agent-loop ordering are recovered in
  `runtime-request-and-model-selection-recovery-2026-08-08.md`.
- `[Unknown]` Provider-private inference, launch retry timing not defined by the public prompt, and
  unrecovered native-helper orchestration remain open.

## Implemented correction

- `[Corrected 2026-08-08]` A task may start with no app, but it does not observe the active app.
  The first model request has no observation and includes available applications. The model must
  select an explicit app before observation, or return a terminal conversational decision.
- `[Implemented]` The model can return a typed `target` decision with a bundle ID or display name.
- `[Implemented]` The model request includes running and installed application candidates.
- `[Implemented]` The application catalog resolves dynamic process IDs, bundle IDs, display names,
  and installed app bundles. Non-running apps launch through modern asynchronous `NSWorkspace`
  APIs before observation.
- `[Implemented]` Each input action activates the target from its fresh observation immediately
  before posting input. This directs events without treating ordinary focus changes as failure.
- `[Preserved]` Accessibility, Screen Recording, observation-generation, policy, and approval
  checks remain active. They are separate from the removed target lock.
- `[Removed]` The frontmost/key-window intervention monitor and its target-validation error were
  removed. Explicit user stop and cancellation remain terminal controls.

## Validation

- `[Verified]` Focused Computer Use tests cover optional starting context, target switching,
  application launch through the seam, target activation, retry behavior, and model encoding.
- `[Verified]` The full deterministic suite is green after this correction.
- `[Not exercised]` A live third-party app launch, cross-process activation, Screen Recording
  capture, and a live provider loop still need macOS validation.

## Remaining parity work

- `[Open]` Decide whether Suniye needs a separate native helper for crash or permission isolation.
- `[Open]` Add and test a separate browser adapter.
- `[Open]` Compare transient screenshot caching and reference-specific state diffs.

## Bootstrap and self-target correction — 2026-08-08

- `[Verified]` The packaged Computer Use state API requires an explicit `app`. Its public app list
  does not expose frontmost state. The host's separate `computer-use-frontmost-window` route is for
  screen context/Appshots, not the Computer Use action loop.
- `[Corrected]` The Suniye agent no longer logs or observes a synthetic `frontmost` target when no
  starting app is selected.
- `[Implemented]` The model can answer conversational input without any desktop observation or
  action. An action returned before target selection and observation is rejected and retried.
- `[Implemented]` Observation and action both enforce the same application policy. The current
  Suniye bundle identifier is forbidden at that boundary, before Accessibility or input work.
- `[Unknown]` The model's response to an unexecuted production greeting turn is not present in the
  DMG. Client-side model selection and request ordering are recovered. No deterministic greeting
  or instruction matcher was added.

## Superseding target-scope correction — 2026-08-03

- `[Verified]` The public Mac contract is app-scoped; its window resolution is native-internal.
  Suniye removes the user-facing window picker, Bring Forward action, session target lock, and
  frontmost intervention monitor.
- `[Verified]` The agent no longer has local action, failure, or duration limits. Explicit
  cancellation, model/provider termination, platform errors, and provider timeout remain terminal.
- `[Verified]` Indexed actions and dynamic Accessibility action names are forwarded to the native
  adapter without cached observation prevalidation.
- `[Unknown]` Native helper IPC, server orchestration, and browser behavior remain unverified.
