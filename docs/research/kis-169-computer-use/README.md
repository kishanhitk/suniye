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

Validation is green for the reviewed desktop path: 1,086 tests ran with 1,085 passed, 1 skipped,
and 0 failures. Gated line coverage is 95.01% (14,439/15,197) at the documented 95% threshold.
The focused Computer Use suite passes 28 tests. Live provider behavior and WindowServer
interaction still require manual validation.

## Files

- `evidence-ledger.md` records findings in small updates.
- `source-inventory.md` maps findings to DMG and Suniye source locations.
- `architecture.md` explains the observed Computer Use design.
- `implementation-plan.md` proposes an independent Swift design for Suniye.
- `open-questions.md` records gaps that need a decision or a live test.
- `parity-audit.md` is the current reference-to-Suniye parity matrix and corrective-slice record.
- `parity-audit-dmg-agent.md` is the detailed raw DMG audit used as supporting evidence.

## Evidence labels

- `[Verified]` means direct evidence exists in the inspected artifact or source.
- `[Inferred]` means a design conclusion follows from verified evidence.
- `[Unknown]` means the evidence does not answer the question.

## Research boundary

This work does not copy source code from the inspected artifact.

This work does not add browser control or a native helper.

The Phase 0 through Phase 5B slices and the current parity slice are ready for the reviewed
commit. The live Computer Use E2E result will be recorded separately.
