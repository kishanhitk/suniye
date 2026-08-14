# Phase 1: application and window discovery

Date: 2026-08-09

Branch: `kis-169-computer-use-parity`

Status: implemented, reviewed, and validated

## Evidence labels

- `[Verified]` is directly supported by the mounted DMG, its packaged JavaScript, native binary,
  current source, or an executed test.
- `[Inferred]` follows from verified evidence but is not exposed as a complete implementation.
- `[Independent choice]` is Suniye's closest practical behavior where the exact native algorithm
  remains unrecovered.
- `[Unknown]` is not established by the available artifact.

## Reference behavior used by this phase

- `[Verified]` The packaged `list_apps` adapter maps each native record to an ID using bundle
  identifier, then display name, then `unknown`. It exposes display name, running state, last-used
  date, and use count.
- `[Verified]` Native strings and imports show a Spotlight application query constrained to
  application bundles used in the last 14 days. The native service reads path, display name,
  bundle identifier, last-used date, and use count metadata.
- `[Verified]` The native service also reads currently running applications and maintains an
  indexed application snapshot from metadata query updates.
- `[Verified]` The app-scoped state contract accepts an application name, a full application path,
  or an unambiguous bundle identifier.
- `[Verified]` A non-running application is launched without activation and is not added to recent
  items.
- `[Verified]` The native service calls `CGWindowListCreate` with on-screen-only and
  exclude-desktop options, then obtains window descriptions.
- `[Verified]` Window discovery cross-references Core Graphics windows with Accessibility windows.
  Observation can remain in the background; discovering or observing a window does not itself
  require bringing that app forward.
- `[Unknown]` The final native comparator for multiple eligible windows is still not recovered.

## Suniye implementation

- `[Implemented]` `ComputerUseApplicationCatalog` combines running and recent application records,
  removes only explicitly excluded host bundle identifiers, and exposes the recovered public app
  shape.
- `[Implemented]` Resolution is deliberately exact: case-insensitive display name, standardized
  full path, or exact bundle identifier. It does not contain fuzzy matching, task keyword rules,
  noun matching, frontmost fallback, or a session target lock.
- `[Implemented]` A duplicate name or bundle identifier resolves only when exactly one copy is
  running; otherwise it reports ambiguity with the candidate paths.
- `[Implemented]` `SystemComputerUseApplicationInventory` uses `NSWorkspace` for running processes
  and a synchronous Spotlight snapshot on a detached utility task for recent application bundles.
- `[Implemented]` `SystemComputerUseApplicationLauncher` uses
  `NSWorkspace.OpenConfiguration` with activation and recent-item insertion disabled.
- `[Implemented]` A narrow Objective-C++ bridge performs the reference window-list call because
  the current Swift SDK marks `CGWindowListCreate` unavailable to Swift.
- `[Implemented]` `SystemComputerUseWindowInventory` converts the untyped Core Graphics
  descriptions into typed snapshots and reads the target process's AX windows, focused window,
  main window, titles, positions, and sizes.
- `[Implemented]` `ComputerUseWindowDiscovery` filters by the resolved process and usable on-screen
  bounds, cross-references CG and AX candidates, and preserves Core Graphics ordering. It does not
  add a user-facing window picker or foreground-activation rule.

## Narrow independent choices

- `[Independent choice]` Suniye takes a fresh synchronous Spotlight snapshot for each catalog
  request. The reference keeps a live metadata-query snapshot. The visible app data is equivalent,
  but cache lifetime and update timing are not exact.
- `[Independent choice]` Running records are emitted before recent-only records, duplicate paths
  retain their first identity, and missing usage metadata is filled from the duplicate record. The
  native final ordering and duplicate precedence are not recovered.
- `[Independent choice]` CG and AX windows match by consistent non-empty titles plus bounds, or by
  bounds alone when one title is absent. Bounds use a two-point tolerance. The reference's exact
  cross-reference predicate is unknown.
- `[Independent choice]` When AX bounds are unavailable, an equal non-empty title may identify the
  matching candidate. No title, area, focused, main-window, or frontmost ranking is added after
  matching.

## Quality review corrections

- `[Verified]` The required thermonuclear review separated pure catalog/window policy from AppKit,
  Spotlight, Core Graphics, and Accessibility adapters. Every new production file is under 200
  lines.
- `[Corrected]` Duplicate non-running records now have deterministic first-record identity rather
  than implicitly treating the incoming record as primary.
- `[Corrected]` The always-true `preferRunning` parameter was removed from ambiguity resolution.
- `[Corrected]` Native bridge pointer nullability is explicit, removing warnings introduced by the
  Foundation-backed window description API.

## Validation so far

- `[Verified]` Thirteen focused tests pass with zero failures. They cover metadata merging, public
  IDs, explicit host exclusion, exact-only resolution, rejection of `calc` and `bluetooth`,
  duplicate ambiguity, running-copy precedence, background launch routing, CG/AX correlation,
  CG ordering, absence of focused/title/area ranking, unusable-window removal, title fallback, and
  typed CG-description decoding.
- `[Verified]` The exact 14-day Spotlight query returns locally installed applications, and `mdls`
  confirms Calculator supplies the expected bundle identifier, display name, last-used date, and
  use-count fields on the test Mac.
- `[Verified]` The final full repository run executes 1,002 tests with 1 skipped and 0 failures.
- `[Verified]` Gated coverage is 95.14% (11,440/12,024 lines), above the requested 95% threshold.
- `[Verified]` The two new live platform adapters are documented coverage exclusions: one requires
  NSWorkspace, Spotlight, and Launch Services; the other requires the window server and
  Accessibility permission. Pure CG-description decoding remains in a gated file and is tested.
- `[Verified]` `scripts/e2e_preflight.sh` and `scripts/e2e_smoke.sh` both pass.

## Not implemented in Phase 1

- AX tree rendering, observation revisions, stable element IDs, and diffs.
- Window screenshot capture and screenshot metadata.
- Input synthesis and semantic AX actions.
- Model request construction, decision decoding, or the agent loop.
- Permission, cancellation, user-intervention, approval, and conversation UX.
- Browser-extension control.
