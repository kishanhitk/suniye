# Phase 24: assistant Markdown rendering

Date: 2026-08-12

## Outcome

- `[Implemented]` Computer Use assistant messages render native Markdown for bold, italics,
  inline code, and links while preserving line breaks and list layout.
- `[Implemented]` User messages remain verbatim text. Tool names, arguments, and collapsed tool
  output remain monospaced raw text.
- `[Implemented]` Invalid or partially formed Markdown falls back to readable attributed or plain
  text instead of failing the conversation row.
- `[Not added]` No third-party Markdown renderer or web view was added.

## Validation

- `[Verified]` Tests cover strong emphasis, emphasis, preserved whitespace, and links.
- `[Verified live]` After rebuilding and restarting the installed Preview, the persisted response
  `Clicked **7** in Calculator.` rendered and exposed through Accessibility as
  `Clicked 7 in Calculator.`. A longer response retained line breaks and bullet markers without
  exposing emphasis delimiters.
- `[Verified]` The complete suite passes 1,143 tests with 2 skipped and zero failures. Gated line
  coverage is 87.05% (14,469/16,622 lines), above the required 80% floor.
