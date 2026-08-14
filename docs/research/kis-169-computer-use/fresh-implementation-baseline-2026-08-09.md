# Fresh Computer Use implementation baseline

Date: 2026-08-09

Branch: `kis-169-computer-use-parity`

## Evidence labels

- `[Verified]` is established by the Git state or a repository search on this branch.
- `[Historical]` refers to preserved evidence from the previous implementation branch.
- `[Planned]` describes work that has not been implemented on this branch.

## Branch reset

- `[Verified]` This branch was created directly from `origin/main` commit `aebdf6809d0da96e6c033a12fec03fb58adb5c14`.
- `[Verified]` The previous `kis-169-computer-use` branch was preserved and pushed through commit
  `64f43e4` before this reset.
- `[Verified]` The complete `docs/research/kis-169-computer-use` directory was restored from the
  preserved branch.
- `[Verified]` No file under `Suniye` or `SuniyeTests` contains a `ComputerUse` symbol at this
  baseline.

## Interpretation rule

The research folder contains two kinds of material:

1. DMG and source recovery reports, which remain authoritative evidence for the reference
   behavior.
2. Phase and parity records from the prior prototype, which are `[Historical]` on this branch.

Do not infer that a feature exists in the fresh implementation merely because an older evidence
entry says `[Implemented]`. Current implementation claims require code and tests on this branch.

## Fresh implementation rule

- `[Planned]` Implement independently from the recovered observable contract.
- `[Planned]` Match verified feature behavior and logic before adding convenience behavior.
- `[Planned]` For the five unresolved native details, use the closest practical implementation and
  record the independent choice explicitly.
- `[Planned]` Do not carry forward deterministic instruction matching, session target locks,
  unconditional foreground observation, or other restrictions that were identified as prototype
  inventions.
- `[Planned]` Keep desktop and browser control as separate capabilities.
- `[Planned]` Run the strict maintainability review, full tests, coverage gate, and relevant E2E
  checks after every completed implementation phase before committing and pushing it.

## Phase 0 status

- `[Implemented]` `ComputerUseProtocol.swift` defines the normalized Swift domain contract for the
  exact ten recovered desktop operations and their app-scoped inputs and outputs.
- `[Implemented]` `ComputerUseSession.swift` is a cancellation-aware dispatcher over an injected
  native-tool boundary. It does not select, infer, or lock a target application.
- `[Implemented]` Click input is represented as a validated element or coordinate target instead of
  an optional field bag that could represent an invalid click.
- `[Verified]` Focused tests assert the exact operation names and mappings, all action routes, list
  behavior, and the absence of an exact app-identifier lock.
- `[Verified]` The phase passes the full repository suite, the requested 95% coverage gate, and the
  existing E2E preflight and smoke checks. Exact results are in
  `phase-0-tool-contract-2026-08-09.md`.
- `[Planned]` The model-facing wire decoder will preserve the recovered optional fields, defaults,
  aliases, and snake-case names while translating them into this normalized domain contract.
- `[Planned]` Fresh-observation authorization belongs to the agent decision loop, not this native
  dispatcher. That later boundary will allow an ordered action batch from one observation, then
  require a new observation before the next model decision.
- `[Not implemented]` This phase does not discover apps or windows, capture screenshots, render AX
  state, synthesize input, call a model, or expose Computer Use UI.

## Phase 1 status

- `[Implemented]` Application discovery combines `NSWorkspace` running processes with the
  recovered 14-day Spotlight metadata query.
- `[Implemented]` App resolution accepts only an exact display name, full path, or unambiguous
  bundle identifier. It contains no task-specific or fuzzy matcher and no frontmost fallback.
- `[Implemented]` Non-running targets launch without activation or recent-item insertion.
- `[Implemented]` Window discovery uses the recovered on-screen, non-desktop Core Graphics list,
  target-process Accessibility windows, and internal CG/AX cross-referencing without exposing a
  model-facing window picker.
- `[Independent choice]` The reference's live recent-app cache is implemented as a fresh Spotlight
  snapshot per call. The unrecovered final multi-window comparator is approximated with title and
  bounds correlation while preserving Core Graphics order. Details are recorded in
  `phase-1-app-window-discovery-2026-08-09.md`.
- `[Verified]` Thirteen focused tests pass after the required strict maintainability review.
- `[Verified]` The final full suite executes 1,002 tests with 1 skipped and 0 failures. Gated
  coverage is 95.14% (11,440/12,024 lines), and both repository E2E scripts pass.
- `[Not implemented]` AX rendering, screenshots, action execution, the agent/model loop,
  permissions, conversation UI, and browser control remain later phases.

## Phase 2 status

- `[Implemented]` Depth-first AX rendering, observation-scoped integer identity, retained
  per-window revisions, full-tree fallback, diffs, secure-value redaction, and internal element
  references.
- `[Implemented]` Background ScreenCaptureKit window capture produces a JPEG file URL and retains
  actual screenshot scale and window origin for later coordinate actions.
- `[Implemented]` The observation service composes exact app resolution, internal window discovery,
  concurrent AX/screenshot capture, and the public app-state result.
- `[Live blocked]` The read-only Calculator XCTest reached the native path but the test host lacks
  Accessibility permission (`-25211`). Installed Preview validation remains later work.
- `[Verified]` The final full suite executes 1,012 tests with 2 skipped and 0 failures. Gated
  coverage is 95.14% (11,685/12,282 lines), and both repository E2E scripts pass.
- `[Not implemented]` Native actions, model/agent wiring, permissions UX, chat UX, and browser
  control remain later phases.
