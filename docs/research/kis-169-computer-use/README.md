# KIS-169 Computer Use research

This folder records the Computer Use research and the Phase 0 through the current desktop parity
implementation for Suniye.

The source artifact is `/Users/kishan/Downloads/ChatGPT (1).dmg`.

The research uses read-only DMG inspection and Suniye source inspection.

Phase 0 adds a read-only Swift observation service. Phase 1 adds a target picker, permission
surface, observation preview, and cancellation flow. Phase 2 adds bounded desktop actions with
one-time approval. Phase 3 adds a typed agent loop with re-observation, limits, and intervention
checks. Phase 4 adds app policy, scoped approval storage, revocation, and redacted audit records.
Phase 5A adds an independent OpenAI-compatible model transport and strict decision parsing.
Phase 5B connects that transport to the coordinator and existing API settings, adds coordinator
approval continuations, and adds a task UI with screenshot-upload consent disabled by default.
The current parity slice adds the reference action shapes that fit the existing process boundary,
window selection and activation, screenshot identity checks, indexed clicks, dynamic Accessibility
actions, and always-allowed approval management.

The desktop path is connected. It still requires a configured API Endpoint model, Accessibility,
and Screen Recording when screenshots are enabled. It is not full runtime parity: browser control,
helper IPC, transient screenshot caching, and installed-app launch remain open or deferred.

The final post-E2E run reports 1,089 tests with 1,088 passed, 1 skipped, and 0 failures. Gated
line coverage is 95.10% (14,453/15,197) at the documented 95% threshold. The focused regression
suite passes 3 tests. The live
`@Computer` run passes navigation, target/window selection, same-process activation,
Accessibility-only observation, and approval denial. Provider behavior, screenshot capture, and
cross-process input still require separate validation.

## Files

- `evidence-ledger.md` records findings in small updates.
- `source-inventory.md` maps findings to DMG and Suniye source locations.
- `architecture.md` explains the observed Computer Use design.
- `implementation-plan.md` proposes an independent Swift design for Suniye.
- `open-questions.md` records gaps that need a decision or a live test.
- `e2e-computer.md` records the live `@Computer` run, failures, fixes, and remaining unknowns.
- `parity-audit.md` is the current reference-to-Suniye parity matrix and corrective-slice record.
- `parity-audit-dmg-agent.md` is the detailed raw DMG audit used as supporting evidence.

## Evidence labels

- `[Verified]` means direct evidence exists in the inspected artifact or source.
- `[Inferred]` means a design conclusion follows from verified evidence.
- `[Unknown]` means the evidence does not answer the question.

## Research boundary

This work does not copy source code from the inspected artifact.

This work does not add browser control or a native helper.

The Phase 0 through Phase 5B slices, the current parity slice, and the post-E2E corrective slice
are committed after review and pushed to `origin/kis-169-computer-use`.
