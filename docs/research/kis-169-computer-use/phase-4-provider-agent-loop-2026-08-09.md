# Fresh implementation phase 4: provider and agent loop

Date: 2026-08-09

This note records the fresh-branch provider and agent-loop slice. It supersedes historical
prototype descriptions where they conflict with the current implementation.

## Verified reference behavior

- `[Verified]` The desktop capability exposes exactly ten operations: `list_apps`,
  `get_app_state`, `click`, `perform_action`, `set_value`, `select_text`, `scroll`, `drag`,
  `key`, and `type_text`.
- `[Verified]` The selected model slug is serialized by the client. Conversation messages,
  assistant tool calls, tool results, and later observations are kept in request order.
- `[Verified]` Parallel tool calls are disabled. The loop obtains current app state before an
  action and obtains fresh state again before a later action.
- `[Verified]` The recovered operating instructions tell the model to inspect the named app
  directly when it is evident, list apps only when it is unclear, launch apps in the background,
  prefer Accessibility semantics, use screenshot coordinates as a fallback, retry an app by
  bundle identifier when needed, and wait for native settling.
- `[Verified]` Normal assistant text can terminate the run or ask the user a question. There is no
  recovered desktop tool named `completed`, `select_target`, `approve`, or `policy`.
- `[Unknown]` Provider-private routing, inference, and hidden server-side instructions cannot be
  recovered from the client artifact.

## Suniye implementation

- `[Implemented]` `ComputerUseModelToolCatalog` exposes only the ten recovered desktop operations
  and their recovered wire argument names. `ComputerUseModelToolCallDecoder` maps them to the
  existing typed domain actions and applies only documented defaults.
- `[Implemented]` `ComputerUseRemoteModelClient` sends the user-selected endpoint, model, and API
  key. It preserves prior conversation, the current task, assistant tool calls, native tool
  results, and screenshots in order. It requests one tool call at a time.
- `[Implemented]` `ComputerUseAgent` starts with the user's task and lets the model choose whether
  to inspect an app, discover apps, act, recover from a tool error, ask the user, or finish. It has
  no deterministic task matcher, frontmost fallback, target lock, action cap, failure cap, or run
  duration cap.
- `[Implemented]` Native tool failures are returned to the model as ordered tool results so the
  model can recover. Explicit task cancellation remains cancellation and returns `Stopped` rather
  than being converted into a retryable tool error.
- `[Implemented]` The native backend's one-shot observation rule remains authoritative: a second
  action without a successful new `get_app_state` receives a stale-observation error. The model
  can then observe again and continue.
- `[Implemented]` Screenshot loading is bounded to JPEG or PNG files of at most 25 MB. A screenshot
  load failure does not discard the available Accessibility text or tool result.

## Independent implementation choices

- `[Independent choice]` Suniye currently uses its existing OpenAI-compatible Chat Completions
  endpoint. The inspected client uses a Responses/node-REPL route, so this transport is not
  byte-for-byte parity.
- `[Independent choice]` The ten native operations are direct function tools in Suniye. The
  inspected node-REPL variant wraps the equivalent native API in a single execution environment.
- `[Independent choice]` A screenshot is appended as a user multimodal image immediately after
  the corresponding tool result because generic Chat Completions providers do not share one
  uniform tool-result image format.
- `[Independent choice]` Suniye uses `tool_choice: auto`, a 2,048-token response limit, and the
  existing 120-second provider request timeout. These values are transport choices, not recovered
  native constants.
- `[Independent choice]` Native tool errors use a small JSON result envelope. The reference's
  exact client-side error serialization is not fully known.

## Validation

- `[Verified]` The thermo-nuclear review removed a force unwrap from response racing, moved the
  unchecked sendability assertion to the canonical URLSession wrapper, separated screenshot and
  result serialization responsibilities, and preserved cancellation as cancellation.
- `[Verified]` The full suite executes 1,052 tests: 1,050 pass, 2 are skipped live-permission
  tests, and none fail.
- `[Verified]` Gated line coverage is 94.93% (12,702/13,380 lines). The project policy is now an
  80% minimum by explicit product direction; this phase remains well above it.
- `[Verified]` E2E preflight and smoke both pass after project regeneration and a clean app build.

## Remaining work

- `[Not implemented]` The agent is not yet connected to the main-actor Computer Use coordinator or
  conversation surface.
- `[Not implemented]` Final permission, cancellation, user-intervention, direct-voice, and chat UX
  still need to be implemented against the fresh branch.
- `[Live required]` The selected provider's multimodal/tool-call compatibility and a complete
  installed-app cross-process run require live validation.
- `[Deferred]` Browser control remains a separate extension/DOM capability. It must not be folded
  into the desktop ten-tool contract.
