# Edit Learning — Design Spec

**Date:** 2026-06-11
**Status:** Approved

## Context

Wispr Flow auto-learns vocabulary from user corrections: after it pastes a
transcription, it watches the target text field, diffs the user's manual edits
against the inserted text, and adds corrected proper nouns to the personal
dictionary. Suniye will build the same loop on top of its existing
vocabulary feature.

Suniye already has the two halves this needs:

- `TextInsertionService` captures a pre-insertion `TextInsertionContext` via
  the Accessibility (AX) APIs (field value, selected range, adjacent chars)
  and holds the focused `AXUIElement`.
- A vocabulary list (`LLMSettings.keywords`) is injected into the Magic
  Format prompt ("terms to preserve exactly"). It is currently inject-only;
  nothing writes to it automatically.

What is missing is post-insertion observation, a diff/classify step, and a
write path into the vocabulary.

## Decisions

| Question | Decision |
| --- | --- |
| What is learned from a correction | Vocabulary terms only (no replacement-rule map) |
| Add UX | Silent immediate add + subtle toast "Learned 'X'" with Undo (~5s) |
| Which words qualify | Proper nouns + rare/out-of-dictionary terms only, phonetically similar to the replaced word |
| Capture mechanism | Snapshot at insertion + deferred re-reads (timers + terminal events), **not** live `AXObserver` |

`AXObserver` was rejected because AX change notifications are unreliable in
Chromium/Electron apps (Slack, Notion, browsers) — exactly where users
dictate — while plain AX value reads work broadly.

## Architecture

New components:

- **`EditLearningService`** (`Suniye/Services/EditLearningService.swift`) —
  owns the tracking lifecycle. Protocol-based, injected into `AppState`,
  matching the existing service DI pattern. Holds at most one active
  snapshot; starting a new dictation finalizes the previous one first.
- **`TranscriptionEditDiff`** (pure) — locates the inserted region in a
  re-read field value (exact match first, then anchoring on the snapshot's
  surrounding context) and produces word-level substitution pairs
  `(original, replacement)` via token alignment.
- **`CorrectionClassifier`** (pure) — filters substitution pairs to
  learnable corrections (rules below).
- **`LearningToastPresenter`** — small transient borderless panel
  (floating-indicator style): "Learned 'Kishan' — Undo", visible ~5s.

Extensions to existing types:

- **`LLMSettings`** gains `autoLearnedKeywordsRaw`, stored separately from
  user-entered `keywordsRaw`; the `keywords` computed property merges both
  (case-insensitive dedupe, existing `parseKeywords` semantics). Separate
  storage enables the ✨/"Learned" badge in the vocabulary UI and gives Undo
  a clean removal target.
- **`TextInsertionService`** exposes its AX field-value read as
  `readFieldValue(element:)` so the learner re-reads the same `AXUIElement`
  it inserted into.
- **`AppState`** gains `addAutoLearnedTerm(_:)` / `removeAutoLearnedTerm(_:)`
  and wires the service into the post-insertion flow.

## Data flow

```text
insertText() succeeds
  → AppState builds InsertionSnapshot
      (inserted text, post-insertion field value, insertion range location,
       AXUIElement ref, target app pid/bundle id, timestamp)
  → EditLearningService.beginTracking(snapshot)
  → re-read field at checkpoints: 10s and 30s timers
    and terminal events: app/focus switch, next dictation start, 60s max
  → TranscriptionEditDiff → substitution pairs
  → CorrectionClassifier → ≤3 qualified words per dictation
  → AppState.addAutoLearnedTerm() → toast with Undo
  → vocabulary flows into Magic Format prompt (existing path, unchanged)
```

Checkpoint timers exist because the dominant flow is *dictate → fix a name →
send*, and sending clears the field; waiting only for focus change would find
nothing to diff. Each qualified word commits at most once per tracking
session; later re-reads cannot double-add.

## Classification rules

A substitution `old → new` qualifies when **all** hold:

1. `new` is proper-noun-like: capitalized mid-sentence, OR out-of-dictionary
   per `NSSpellChecker`, OR acronym / camelCase / contains digits.
2. Phonetic similarity between `old` and `new` of at least 0.6 — normalized
   edit-distance similarity (1 − distance/maxLength) over a phonetic skeleton
   (small metaphone-style normalizer implemented in-repo, fully
   unit-tested). The 0.6 starting threshold is tuned via the classifier's
   unit-test fixtures. This separates "fixed the transcription" from
   "changed my mind about content".
3. `new`.count ≥ 3 and `new` not already in vocabulary (case-insensitive).

Case-only changes qualify only when the word is out-of-dictionary
("kishan → Kishan" learns; "the → The" does not). Common-word corrections
("their → there") never qualify.

## Edge cases and failure behavior

- **Clipboard-fallback insertion** (no AX-readable field): tracking never
  starts; the feature is silently inactive in those apps.
- **Stale AX element / target app quit / AX permission lost**: re-read
  fails → discard the snapshot silently. No retries beyond the scheduled
  checkpoints, never block or surface errors.
- **Field cleared (message sent)**: diff yields only deletions → nothing
  learned.
- **Mid-edit checkpoint** (user typed "Kis" of "Kishan" at 10s): partial
  words fail the phonetic + OOV gates; the 30s/terminal reads catch the
  finished edit.
- **Rapid successive dictations**: new dictation finalizes the previous
  snapshot before tracking the new one.

## Settings, UI, privacy

- Toggle **"Learn from my edits"**, default on, in the vocabulary section of
  `MagicFormatPage`.
- Auto-learned terms show a ✨/"Learned" badge in the vocabulary UI; user
  removal works for both lists.
- Everything is local. Only the element we inserted into is ever re-read.
  Snapshots are discarded after finalize; field contents are never persisted.

## Testing

- **Bulk of coverage on the pure parts:** `TranscriptionEditDiff` (region
  anchoring under surrounding edits, alignment) and `CorrectionClassifier`
  (phonetic threshold, OOV, content-change rejection, case-only rules).
- **`EditLearningService`:** mocked field reader + injected clock for
  trigger/lifecycle tests (checkpoint ordering, finalize-once, snapshot
  replacement).
- **Integration:** one test through `AppState` with test doubles, following
  the existing DI pattern. Tests are app-hosted.
- Workflow: Linear issue → `kis-NNN` worktree branch → non-draft PR with
  unit + integration tests.

## Out of scope (future work)

- sherpa-onnx hotword boosting from the learned list (would bias the NeMo
  transducer recognizer itself, not just the Magic Format prompt).
- Learning formatting preferences (punctuation, casing style) from edits.
- Replacement-rule map ("always replace X with Y" post-STT).
