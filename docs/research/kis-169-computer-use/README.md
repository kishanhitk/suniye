# KIS-169 Computer Use research

This folder records the Computer Use research and the Phase 0 through Phase 5A implementation for Suniye.

The source artifact is `/Users/kishan/Downloads/ChatGPT (1).dmg`.

The research uses read-only DMG inspection and Suniye source inspection.

Phase 0 adds a read-only Swift observation service. Phase 1 adds a target picker, permission
surface, observation preview, and cancellation flow. Phase 2 adds bounded desktop actions with
one-time approval. Phase 3 adds a typed fake-only agent loop with re-observation, limits, and
intervention checks. No live model provider, browser control, or native helper is connected.
Phase 4 adds app policy, scoped approval storage, revocation, and redacted audit records. No live
model provider, browser control, or native helper is connected. Phase 5A adds an independent
OpenAI-compatible model transport, strict decision parsing, and screenshot-upload opt-in. The
transport is not yet connected to the coordinator or production UI.

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

This work does not copy ChatGPT code.

This work does not add model control, browser control, or a native helper.

The Phase 0 through Phase 5A slices are committed after review and pushed to
`origin/kis-169-computer-use`.
