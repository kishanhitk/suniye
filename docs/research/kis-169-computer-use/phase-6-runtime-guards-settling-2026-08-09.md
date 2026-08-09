# Phase 6: runtime guards and loading-aware settling

Date: 2026-08-09
Branch: `kis-169-computer-use-parity`

## Scope

This phase completes the native runtime behavior that can be supported by direct artifact evidence:

- reject observation and action while the macOS session is locked;
- treat physical keyboard or pointer input after observation as user intervention;
- revalidate intervention state after native input and settling;
- wait about one second after every successful action;
- extend settling while the target AX tree reports a loading indicator, up to five seconds.

It does not add app-name routing, a target lock, frontmost-app assumptions, per-action approval, or
automatic lock-screen unlock.

## Reference evidence

- `[Verified]` Native symbols include `SystemLockScreenMonitor`,
  `CGSessionCopyCurrentDictionary`, and `CGSSessionScreenIsLocked`.
- `[Verified]` Native strings identify lock and unlock session notifications.
- `[Verified]` The recovered runtime includes a user-input intervention type with
  `requiresRequery`, a physical-input monitor, event-tap machinery, and a user-interaction
  debounce duration.
- `[Verified]` The recovered operating instructions require a fresh observation after an action.
- `[Verified]` The recovered settling guidance waits about one second normally and can extend the
  wait to about five seconds when loading continues.
- `[Unknown]` The artifact does not expose the complete event-filter list, debounce constant,
  exact loading predicate, or the cancellation boundary after native event synthesis has begun.

## Independent Swift implementation

### Runtime authorization

`ComputerUseRuntimeGuard` creates a short-lived authorization alongside each successful
observation. It contains a snapshot of cumulative HID-system event counters. An action is allowed
only if the screen is still unlocked and every monitored counter is unchanged.

The backend validates that authorization before native input and again after the action settles.
Every action still consumes its observation, so recovery requires another `get_app_state` call.

### Lock state

`SystemComputerUseScreenLockChecker` reads `CGSSessionScreenIsLocked` from
`CGSessionCopyCurrentDictionary`. A locked session fails with an instruction to unlock the Mac.

`[Independent choice]` Suniye does not implement the artifact's automatic unlock machinery. It
would require storing or requesting credentials and is not necessary to reproduce the safe,
observable behavior of refusing to drive a locked desktop.

### Physical input

`SystemComputerUsePhysicalInputSampler` snapshots the HID-system counters for mouse down, mouse
movement and dragging, scrolling, key down, and modifier changes.

`[Independent choice]` Counter snapshots are used instead of a persistent event tap. HID counters
distinguish physical input from Suniye's process-scoped synthetic events without adding a
long-lived monitor. The complete counter vector is retained; it is not reduced to a checksum.

If the vector changes, the agent terminates the run as cancelled. No deterministic target change
or frontmost-window rule participates in that decision.

### Settling

`SystemComputerUseActionSettler` waits one second after a successful action. It then samples a
fresh AX snapshot every 500 milliseconds while an `AXProgressIndicator` or `AXBusyIndicator`
exists, for at most ten checks.

`[Independent choice]` These two AX roles are the narrowest platform-native approximation to the
unrecovered loading heuristic. Snapshot failure is treated as no detected loading state; the next
model-selected action still requires its own fresh observation.

## Strict review corrections

- Revalidation after settling closes the interval in which physical input could occur during
  native action execution.
- The intervention snapshot stores every event counter instead of a lossy summed generation.
- Backend test doubles were split from the test cases to keep both files reviewable.
- Runtime, settling, backend, and agent responsibilities remain in separate focused types.

## Validation

- Focused runtime, backend, and agent suite: 25 tests, 0 failures.
- Direct adapter tests cover locked and missing session flags, the ordered HID counter vector,
  nested loading indicators, absent indicators, and AX snapshot failure.
- Full suite: 1,075 tests executed, 2 skipped, 0 failures.
- Gated coverage: 89.36% (13,041/14,593 lines), passing the requested 80% floor.
- E2E preflight and smoke both pass.
- Installed-app and live-provider results remain for the final validation phase.

## Remaining unknowns

- The exact reference debounce constant and event filter.
- Whether reference intervention cancels an event already being synthesized or only requires a
  subsequent observation.
- The complete reference loading-state heuristic.
- The exact locked-session recovery and automatic-unlock UX.
- Live behavior under the installed Preview's TCC identity.
