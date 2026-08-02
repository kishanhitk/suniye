# KIS-169 Computer Use research

This folder records the Computer Use research and the Phase 0 and Phase 1 implementation for Suniye.

The source artifact is `/Users/kishan/Downloads/ChatGPT (1).dmg`.

The research uses read-only DMG inspection and Suniye source inspection.

Phase 0 adds a read-only Swift observation service. Phase 1 adds a read-only target picker,
permission surface, observation preview, and cancellation flow. Neither phase adds model calls
or desktop actions.

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

This work does not add model control, desktop actions, approvals, or browser control.

The Phase 0 and Phase 1 slices are committed. No push has been performed.
