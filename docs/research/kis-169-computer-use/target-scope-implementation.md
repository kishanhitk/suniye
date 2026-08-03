# Target scope correction

Date: 2026-08-03

Reference: `/Users/kishan/Downloads/ChatGPT (1).dmg`

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
- `[Unknown]` The reference server prompt, exact model, launch retry timing, and native helper
  orchestration are not visible in the inspected files.

## Implemented correction

- `[Implemented]` A task may start with no app or window. The first observation uses the active app.
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

## Superseding target-scope correction — 2026-08-03

- `[Verified]` The public Mac contract is app-scoped; its window resolution is native-internal.
  Suniye removes the user-facing window picker, Bring Forward action, session target lock, and
  frontmost intervention monitor.
- `[Verified]` The agent no longer has local action, failure, or duration limits. Explicit
  cancellation, model/provider termination, platform errors, and provider timeout remain terminal.
- `[Verified]` Indexed actions and dynamic Accessibility action names are forwarded to the native
  adapter without cached observation prevalidation.
- `[Unknown]` Native helper IPC, server orchestration, and browser behavior remain unverified.
