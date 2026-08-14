# Phase 9: debug session correlation

Date: 2026-08-11

## Outcome

- `[Implemented]` Every Computer Use run receives a compact random identifier in the form
  `CU-XXXXXXXXXXXX`.
- `[Implemented]` The coordinator publishes the current or most-recent identifier while the app is
  running. It remains available after completion, cancellation, or failure and is replaced when
  the next run begins.
- `[Implemented]` The Computer Use header shows `Copy debug ID` directly beside `New
  conversation`, with temporary copied feedback. It is not hidden in the settings disclosure.
- `[Implemented]` Every Computer Use agent lifecycle and tool-boundary log line includes
  `session=<identifier>`. Tool arguments, task text, Accessibility content, screenshots,
  credentials, and endpoints remain excluded.

## Debug workflow

1. Ask the user to click `Copy debug ID` beside `New conversation` after the affected run.
2. Ask them to provide the copied `CU-...` value.
3. Search both active and rotated logs:

   ```bash
   rg -n 'session=CU-XXXXXXXXXXXX' \
     "$HOME/Library/Application Support/Suniye/logs/app.log" \
     "$HOME/Library/Application Support/Suniye/logs/app.log.1"
   ```

This returns only the lifecycle and tool-result metadata for that run, including ordered step
numbers, tool names, result summaries, error types, and the terminal outcome.

## Validation

- `[Verified]` Coordinator tests prove the identifier shown by coordinator state is exactly the
  identifier passed to the agent task.
- `[Verified]` Agent tests prove every successful lifecycle and tool log contains the same fixed
  identifier.
- `[Verified]` The full suite executes 1,091 tests with 2 skipped and 0 failures. Gated coverage is
  88.41% (13,400/15,156 lines), above the 80% floor.
- `[Verified]` The corrected installed Preview displayed `Copy debug ID` directly beside `New
  conversation`. It copied `CU-1E9806DCABD2` exactly, and the expanded settings section contained
  only model and permission controls.
- `[Verified]` Searching the installed app's active and rotated logs by a copied ID recovered one
  contiguous run trace: start, nine ordered tool attempts/results, and completion.
