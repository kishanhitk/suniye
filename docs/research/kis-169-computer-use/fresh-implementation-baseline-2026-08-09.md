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
