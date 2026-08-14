# Computer Use prompt recovery from the ChatGPT DMG

Research date: 2026-08-08

Scope: static inspection of `<home>/Downloads/ChatGPT (1).dmg` and its mounted app at
`/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app`. No production code was changed.

## Evidence labels

- `[Verified]` is directly present in the DMG or reproduced by a deterministic extraction.
- `[Inferred]` is the narrowest explanation consistent with the artifact.
- `[Unknown]` is not established by the static artifact.

## Corrected conclusion

- `[Verified]` The previous statement that the DMG does not contain the complete Computer Use
  prompt material was too broad. The DMG contains both the model's static base instructions and
  the complete readable Computer Use-specific operating instructions.
- `[Verified]` The static Computer Use instructions define tool choice, app discovery, app-state
  reads, Accessibility and screenshot use, action sequencing, retries, timing, background launch,
  and the confirmation policy.
- `[Verified]` The matching tagged client source and the DMG binary's built-in prompt renderer
  expose the request-construction algorithm and model-visible role ordering. An isolated loopback
  capture also records an actual request serialized by the shipped binary.
- `[Unknown]` A byte-for-byte request for an unspecified production turn cannot exist as static
  data because conversation history, selected skills, tools, permissions, environment state, and
  feature flags are dynamic. Provider-private processing after receipt is also not exposed.

Therefore, two different meanings must not be conflated:

1. The static model and Computer Use instruction sources are recoverable from the DMG.
2. The runtime-composition algorithm and ordering are recoverable, while the concrete dynamic
   values for a particular future turn are not fixed data in the DMG.

## Recovered model base instructions

- `[Verified]` `ChatGPT.app/Contents/Resources/codex` is a Mach-O executable containing JSON model
  catalog entries with a `base_instructions` field.
- `[Verified]` The `gpt-5.6-luna` base-instruction string starts at byte offset `198377842` in this
  DMG's `codex` executable.
- `[Verified]` Decoding the JSON string produces 17,730 UTF-8 characters with SHA-256
  `cbefa6b0bede0e332d957fca70ccacf9f12f4c0ecdf81b819e5cbe1a3b16e265`.
- `[Verified]` The bundled `gpt-5.6-sol`, `gpt-5.6-terra`, and `gpt-5.6-luna` profiles contain
  identical base-instruction content in this artifact.
- `[Verified]` The recovered base instructions are preserved at
  `recovered-prompts/gpt-5.6-base-instructions.md`.

The recovered headings include personality, writing style, technical communication, working with
the user, commentary and final-answer behavior, formatting, visualizations, execution rules, file
editing, autonomy, destructive actions, and skill loading.

## Recovered Computer Use instructions

### Computer Use skill

Source:

`ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/skills/computer-use/SKILL.md`

- `[Verified]` This 6,216-byte plaintext file defines when Computer Use applies and contains a
  Computer Use confirmation policy.
- `[Verified]` Its SHA-256 is
  `2079334b8e4329bd12eb30719198146f8f844605ca3c354410315d2a39688d4e`.
- `[Verified]` A byte-identical research copy is preserved at
  `recovered-prompts/computer-use-skill.md`.

### Computer Use runtime instructions

Source:

`ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/computer-use-node-repl.md`

- `[Verified]` This 18,913-byte plaintext file is the detailed Computer Use operating prompt.
- `[Verified]` Its SHA-256 is
  `a52ede355c6637d05be9da5e3f19dbfd5f23fa5ec4c9513e3188bc8a57429c79`.
- `[Verified]` A byte-identical research copy is preserved at
  `recovered-prompts/computer-use-node-repl.md`.

It explicitly instructs the model to:

- Use persistent JavaScript `node_repl` for Computer Use interactions.
- Bootstrap the plugin-owned `@oai/sky` wrapper instead of importing it directly.
- Use the ten-method macOS `sky` surface.
- Call `get_app_state` directly when the requested app is evident.
- Call `list_apps` when the app cannot be identified from the task, prior context, or built-ins.
- Perform one or more actions and then read updated app state before deciding again.
- Prefer current Accessibility element indexes over coordinates.
- Use screenshots when Accessibility information is incomplete.
- Retry a display-name failure with the bundle identifier from `list_apps`.
- Avoid manual sleeps because the runtime waits about one second and up to five seconds for loading.
- Treat `press_key` and `type_text` as app-scoped rather than global input.
- Let `get_app_state` launch an app in the background when needed.
- Follow the embedded Computer Use confirmation policy.

## Other prompt inputs visible in the artifact

- `[Verified]` The `codex` binary contains configuration and runtime fields for base instructions,
  developer instructions, model instruction files, permissions instructions, app instructions,
  collaboration-mode instructions, environment context, plugin instructions, skills, and
  `AGENTS.md` content.
- `[Verified]` The model catalog contains different base-instruction strings for different model
  profiles, including GPT-5.6, GPT-5.5, GPT-5.4, GPT-5.4 mini, GPT-5.2, and auto-review.
- `[Verified]` The exact tagged client source defines how the host composes the selected model's
  base instructions, tools, world state, user input, and selected skill/plugin injections.
- `[Verified]` The shipped binary's loopback-captured GPT-5.6 Luna request orders Lite tools, base
  instructions, dynamic developer context, environment context, the user task, and the selected
  Computer Use skill in that sequence.
- `[Unknown]` Long-run compaction and truncation outcomes depend on the concrete conversation and
  runtime token state.

## What this changes for Suniye research

- `[Verified]` Suniye does not need an invented Computer Use operating prompt to approximate the
  reference. The exact feature-specific instructions and tool-use rules are available for study.
- `[Verified]` The reference prompt does not use a deterministic natural-language app matcher or a
  session-wide target-lock tool.
- `[Verified]` The reference prompt allows one or more actions between app-state reads. It does not
  specify a mandatory screenshot immediately before every individual low-level action.
- `[Verified]` No production integration or prompt replacement was performed during this audit.

## Remaining unknowns

1. Provider-private inference, hidden classifiers, and post-receipt transformations.
2. The byte-for-byte dynamic values of an unspecified production turn.
3. How a particular long conversation, tool history, screenshots, and persistent REPL state are
   compacted when its actual token limits are reached.

The prompt-variant precedence is no longer unknown. The DMG host chooses `node-repl` when the
`computerUseNodeRepl` feature is active and copies
`.codex-plugin/computer-use-node-repl.md` over `skills/computer-use/SKILL.md` in the materialized
plugin. See `runtime-request-and-model-selection-recovery-2026-08-08.md` for source paths, request
schema, ordered context construction, and the captured request.
