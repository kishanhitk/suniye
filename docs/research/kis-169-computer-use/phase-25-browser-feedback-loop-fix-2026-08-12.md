# Browser feedback-loop fix — 2026-08-12

## Failure

- `[Verified live]` Session `CU-34D876BA75B9` ran 90 tool calls before cancellation: 45
  observations, 41 clicks, three Escape key presses, and no text-entry action.
- `[Verified]` Most unchanged observations expanded back into the same approximately
  46,000-character Accessibility tree. The snapshot did not identify the focused element.
- `[Verified]` The selected OpenRouter model ID was `openai/gpt-5.6-luna`, but the model policy
  recognized only the unqualified `gpt-5.6-luna` spelling. Tool output was therefore limited to
  2,500 estimated tokens instead of the intended 10,000 and used middle truncation.

## Correction

- `[Implemented]` Model-policy selection now recognizes provider-qualified model IDs while
  retaining exact matching for the final model-name component.
- `[Implemented]` Accessibility snapshots capture the application-focused UI element and retain
  that identity through tree rendering.
- `[Implemented]` An unchanged tree now returns a compact no-change message followed by the
  focused element, matching the observed reference feedback shape. Changed diffs also include
  the current focused element.
- `[Not added]` There are no browser-specific matchers, deterministic task routes, extra approval
  rules, or arbitrary step limits.

## Validation

- `[Verified]` Regression tests failed before the correction and pass afterward. The full suite
  passes 1,145 tests with 2 skipped and zero failures.
- `[Verified]` Gated line coverage is 87.08% (14,493/16,643) against the 80% floor. E2E preflight
  and smoke pass.
- `[Verified live]` Debug Preview was rebuilt, installed, and restarted at
  `<home>/Applications/Suniye Preview.app`.
- `[Verified live]` From the Gmail inbox, installed Preview session `CU-66A245F07512` completed
  the original natural request: `Check my last email from Apple in my browser and see what they're
  asking for.` It selected Chrome, set the Gmail search field, pressed Enter, opened the newest
  result, and correctly summarized `Watch and learn.`
- `[Verified live]` The final repeated observations were 360 characters and explicitly reported
  focused Gmail row `1571`; the former repeated full-tree click loop did not recur.

## Remaining boundary

- `[Unknown]` Provider-private reasoning and server-side compaction are not observable and cannot
  be reproduced exactly through the portable Chat Completions transport.
