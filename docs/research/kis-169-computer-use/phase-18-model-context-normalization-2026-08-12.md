# Phase 18: model context normalization

Date: 2026-08-12

## Reference boundary

- `[Verified]` The inspected runtime keeps ordered model items rather than reducing prior tool
  activity to display text. Function calls and their outputs remain protocol pairs.
- `[Verified]` The inspected truncation utility estimates one token per four UTF-8 bytes, keeps a
  prefix and suffix on valid UTF-8 boundaries, and inserts an
  `…N tokens truncated…` marker.
- `[Verified]` The inspected `gpt-5.6-luna` metadata declares a 272,000-token context window and a
  10,000-token tool-output truncation policy. Generic fallback model metadata uses a 10,000-byte
  policy, equivalent to 2,500 approximate tokens under the same estimator.
- `[Verified]` The inspected compaction path selects recent useful history under a token budget and
  preserves image content separately from text.
- `[Unknown]` The artifact does not define a 50-message limit or a two-screenshot limit for
  Suniye's provider-portable Chat Completions transport. Those limits are product choices for this
  implementation, not recovered constants.

## Implementation

- `[Implemented]` Completed local activities are reconstructed for the model as an assistant
  function call followed by its matching tool result. Pending or incomplete activity is omitted.
- `[Implemented]` Model-facing `get_app_state` results omit the local screenshot file URL. The
  screenshot remains a separate image message, while the persisted conversation and collapsed
  result disclosure retain the full raw local output for diagnosis.
- `[Implemented]` Every provider request is compacted to at most the requested 50 messages while
  keeping function-call/result/image groups intact. The current instruction and latest
  observation are mandatory; remaining groups are selected newest first under the model token
  budget.
- `[Implemented]` At most the two newest screenshot messages are retained. This avoids repeatedly
  uploading stale captures while preserving recent visual context.
- `[Implemented]` When a new user turn rebuilds the current conversation, the two newest
  historical screenshot files are loaded back into image messages beside their matching
  observation pairs. Missing or unreadable temporary files are skipped without failing the task.
- `[Implemented]` Oversized model-facing tool output uses the recovered middle-truncation format.
  Luna receives its recovered 10,000-token limit; unknown custom models use the conservative
  generic 10,000-byte-equivalent fallback.
- `[Retained]` Local conversation persistence is lossless. Cleanup changes only the model request
  and does not hide or destroy raw tool output in Suniye.

## Independent choices

- `[Independent choice]` Suniye uses a deterministic local 50-message compactor because the user
  selected that history size and the current transport has no Responses compaction item.
- `[Independent choice]` Unknown models use a 100,000-token context budget and the generic
  10,000-byte-equivalent tool-output limit. Provider metadata is not available through the current
  custom endpoint contract.
- `[Independent choice]` The two newest screenshots are retained. The exact reference image
  retention count for this desktop path is not exposed.

## Scope boundary

- `[Not changed]` Suniye still uses one-call-at-a-time Chat Completions function tools. This slice
  does not add a persistent JavaScript runtime, encrypted reasoning items, Responses streaming, or
  server-side compaction.
- `[Not added]` No task matcher, target restriction, approval rule, hidden summary, or destructive
  local-history cleanup was introduced.

## Validation

- `[Verified]` Focused tests cover protocol pairing, local/model output separation, screenshot URL
  removal, the 50-message limit, token-budget selection, latest-observation retention, two-image
  retention, model metadata selection, and ASCII/Unicode middle truncation.
- `[Verified]` The full suite passes 1,124 tests with 2 skipped and zero failures.
- `[Verified]` Gated coverage is 87.00% (14,075/16,179 lines), above the 80% floor.
- `[Verified]` E2E preflight and smoke pass.
