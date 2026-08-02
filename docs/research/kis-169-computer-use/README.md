# KIS-169 Computer Use research

This folder records the Computer Use research and the Phase 0 through Phase 5B implementation for Suniye.

The source artifact is `/Users/kishan/Downloads/ChatGPT (1).dmg`.

The research uses read-only DMG inspection and Suniye source inspection.

Phase 0 adds a read-only Swift observation service. Phase 1 adds a target picker, permission
surface, observation preview, and cancellation flow. Phase 2 adds bounded desktop actions with
one-time approval. Phase 3 adds a typed agent loop with re-observation, limits, and intervention
checks. Phase 4 adds app policy, scoped approval storage, revocation, and redacted audit records.
Phase 5A adds an independent OpenAI-compatible model transport and strict decision parsing.
Phase 5B connects that transport to the coordinator and existing API settings, adds coordinator
approval continuations, and adds a task UI with screenshot-upload consent disabled by default.

The desktop path is connected. It still requires a configured API Endpoint model, Accessibility,
and Screen Recording when screenshots are enabled. Browser control and a separate native helper
remain out of scope until their contracts are verified.

## Files

- `evidence-ledger.md` records findings in small updates.
- `source-inventory.md` maps findings to DMG and Suniye source locations.
- `architecture.md` explains the observed Computer Use design.
- `implementation-plan.md` proposes an independent Swift design for Suniye.
- `open-questions.md` records gaps that need a decision or a live test.

## Evidence labels

- `[Verified]` means direct evidence exists in the inspected artifact or source.
- `[Inferred]` means a design conclusion follows from verified evidence.
- `[Unknown]` means the evidence does not answer the question.

## Research boundary

This work does not copy source code from the inspected artifact.

This work does not add browser control or a native helper.

The Phase 0 through Phase 5B slices are committed after review and pushed to
`origin/kis-169-computer-use`.
