# Runtime request and model-selection recovery

Research date: 2026-08-08

Scope: the `codex` executable shipped in `/Users/kishan/Downloads/ChatGPT (1).dmg`, the
matching official OpenAI Codex source tag, and an isolated local request capture. No Suniye
production code was changed for this audit.

## Evidence labels

- `[Verified]` is directly shown by the shipped executable, its locally captured request, the
  matching tagged source, or the DMG's packaged resources.
- `[Inferred]` is the narrowest explanation consistent with verified evidence.
- `[Unknown]` is not established by the available evidence.

## Corrected conclusions

1. `[Verified]` Normal model selection is client-side. A turn can specify a model override, and
   the client serializes the resolved model slug into the Responses API request.
2. `[Verified]` The service can exceptionally report a different model. The client treats this as
   a model reroute, not as the normal selection mechanism.
3. `[Verified]` The request-building algorithm, request schema, context composition, message-role
   ordering, and the Computer Use skill-injection position are recoverable.
4. `[Verified]` An actual request serialized by the DMG's `codex` binary was captured locally. It
   selected `gpt-5.6-luna` and showed the concrete input order described below.
5. `[Unknown]` The provider's private inference implementation, hidden server-side classifiers,
   and any service-side transformations after receipt remain outside the client artifact.
6. `[Unknown]` One exact production ChatGPT desktop request cannot be stated without identifying a
   particular thread, turn, configuration, enabled tools, permissions, conversation history, and
   runtime feature flags. Those dynamic values vary, but the client algorithm that orders and
   serializes them is recovered.

## Artifact and source identity

- `[Verified]` The DMG executable reports `codex-cli 0.146.0-alpha.9.2`.
- `[Verified]` The official OpenAI Codex repository has the exact tag
  `rust-v0.146.0-alpha.9.2`, peeled to commit
  `86cc9f2177cad015befd595286d8767a650f7d13`.
- `[Inferred]` This exact version match makes the tagged source the strongest readable description
  of the shipped executable's implementation.
- `[Unknown]` The executable does not expose the commit hash, so version equality alone is not a
  bit-for-bit build provenance proof. The direct request capture below independently verifies the
  relevant serialization behavior in the shipped binary.

Read-only source checkout used for the audit:

`/private/tmp/codex-source-audit.WMvAoK/codex`

## Client-side model selection

### Turn protocol

`TurnStartParams.model` is an optional model override for the current and subsequent turns:

`codex-rs/app-server-protocol/src/protocol/v2/turn.rs:71-124`

This is the app-server protocol used by a client to start a turn. The field is not merely a display
preference; it reaches the turn configuration.

### Request serialization

`ModelClientSession::build_responses_request` writes the resolved model profile's slug into the
wire request:

`codex-rs/core/src/client.rs:838-924`

The decisive assignment is `model: model_info.slug.clone()` at line 908 in the exact tagged
source.

### Exceptional server reroute

The response stream can contain a `ServerModel` event. The client compares that value with the
requested model and emits a `ModelReroute` event if they differ:

- `codex-rs/core/src/session/turn.rs:2286-2297`
- `codex-rs/core/src/session/mod.rs:3086-3123`

The inspected implementation associates this mismatch warning with a high-risk cyber fallback.
Therefore the precise boundary is:

- `[Verified]` User/client selection determines the requested model slug.
- `[Verified]` The service may exceptionally reroute and disclose the effective model.
- `[Unknown]` Provider-internal alias resolution, capacity routing, model implementation, and
  inference behavior remain private.

The phrase **provider-side model routing** must not be used to imply that the provider normally
chooses the user's selected model for the client. A more accurate unknown is **provider-internal
inference and exceptional reroute behavior**.

## Recovered request-construction algorithm

### Prompt object

`build_prompt` constructs a `Prompt` from:

- the ordered conversation/context input;
- model-visible tool specifications;
- the selected model's parallel-tool capability;
- base instructions;
- an optional final-output schema.

Source: `codex-rs/core/src/session/turn.rs:1143-1158` and
`codex-rs/core/src/client_common.rs`.

### Responses API wire schema

The exact request structure is defined by `ResponsesApiRequest`:

1. `model`
2. `instructions`
3. `input`
4. optional `tools`
5. `tool_choice`
6. `parallel_tool_calls`
7. optional `reasoning`
8. `store`
9. `stream`
10. optional `stream_options`
11. `include`
12. optional `service_tier`
13. optional `prompt_cache_key`
14. optional `text`
15. optional `client_metadata`

Source: `codex-rs/codex-api/src/common.rs:251-275`.

The WebSocket form has the same core fields and adds `previous_response_id`, which this conversion
sets to `None`: `codex-rs/codex-api/src/common.rs:277-320`.

### GPT-5.6 Luna Responses Lite ordering

The DMG model catalog marks `gpt-5.6-luna` as `use_responses_lite: true` and supports text and image
input. In this mode, `build_responses_request`:

1. serializes model-visible tool definitions as an `additional_tools` developer item;
2. inserts that item at input index 0;
3. inserts the selected model's base instructions as the next developer message;
4. appends the already-ordered conversation/context input;
5. leaves top-level `instructions` empty;
6. omits top-level `tools`;
7. sends `parallel_tool_calls: false` even when the model profile supports parallel calls.

Source: `codex-rs/core/src/client.rs:848-880` and `:907-923`.

For a non-Lite model, the same code instead places base instructions in top-level `instructions`
and tool definitions in top-level `tools`.

## Recovered initial-context ordering

`build_initial_context_with_world_state` composes the first model-visible context in this order:

1. optional model-switch instructions;
2. developer instructions, unless isolated for a guardian reviewer;
3. personality instructions when they are not already baked into the model prompt;
4. available-skills instructions;
5. recommended-plugin context, as contextual user content;
6. extension-provided thread-context fragments;
7. extension-provided turn-context fragments;
8. optional token-budget context and guidance;
9. rendered world-state sections;
10. optional multi-agent usage hint;
11. multi-agent mode;
12. aggregated contextual-user message;
13. optional separate guardian developer message.

Source: `codex-rs/core/src/session/mod.rs:3314-3574`.

The world-state sections are added in this order:

1. realtime state;
2. `AGENTS.md` instructions;
3. permissions instructions;
4. collaboration-mode instructions;
5. environment context;
6. deferred-environment instructions;
7. apps instructions;
8. plugins instructions;
9. optional deferred-tools state;
10. extension-contributed sections;
11. multi-agent mode.

Source: `codex-rs/core/src/session/world_state.rs:38-146`.

## Recovered per-turn ordering

On the first sampling step, `run_turn`:

1. captures the step context;
2. records initial context or context updates;
3. builds selected skill and plugin injections;
4. records the actual user input;
5. records the skill/plugin injection items;
6. clones the resulting history;
7. builds and streams the sampling request.

Source: `codex-rs/core/src/session/turn.rs:184-232` and `:274-318`.

Therefore, before the GPT-5.6 Lite prefix is added, the first-turn history is:

`initial context -> user task -> selected skill/plugin injections`

For a linked Computer Use skill, the Computer Use prompt is an injected model-visible item after
the user task. The base instructions and tool catalog are then prefixed by the Lite request builder.

## Direct request capture from the shipped DMG binary

The audit used the DMG's `codex app-server`, initialized with ChatGPT desktop client information, an
isolated temporary Codex home, and a loopback-only HTTP capture server. The app-server created a
thread, accepted a `turn/start` request with `model: gpt-5.6-luna`, `effort: medium`, and an explicit
Computer Use skill input, then serialized the provider request. The custom provider endpoint was
`127.0.0.1`; no request was sent to a real model provider. The exact DMG Computer Use node-REPL
prompt was installed into that isolated home.

Captured request:

`/private/tmp/suniye-codex-request-audit-20260808/captured-request.json`

SHA-256:

`b0e50dbcdf0abc14d26340199d5ebb92ba2ba6765949f9dfe26d92de89fdc1a3`

Verified top-level values:

| Field | Captured value |
| --- | --- |
| `model` | `gpt-5.6-luna` |
| `instructions` | empty |
| input item count | 6 |
| `tool_choice` | `auto` |
| `parallel_tool_calls` | `false` |
| `reasoning` | `effort: medium`, `context: all_turns` |
| `store` | `false` |
| `stream` | `true` |
| `include` | `reasoning.encrypted_content` |
| top-level `tools` | absent |

Verified input order:

| Index | Type | Role | Meaning |
| --- | --- | --- | --- |
| 0 | `additional_tools` | developer | Three tools visible in this isolated CLI session |
| 1 | `message` | developer | 17,730-character GPT-5.6 base instructions |
| 2 | `message` | developer | Dynamic permissions, plugin, and skills context |
| 3 | `message` | user | Repository `AGENTS.md` context |
| 4 | `message` | user | The audit task and linked Computer Use skill mention |
| 5 | `message` | user | The selected Computer Use skill prompt wrapper |

This capture verifies the request builder and ordering in the shipped executable, not only in the
matching source.

### Capture limitation

- `[Verified]` The capture used the DMG's app-server path with client name/title `chatgpt` /
  `ChatGPT` and desktop build version `26.727.51351`.
- `[Verified]` The request was generated from a real app-server thread and `turn/start`, not from a
  hand-assembled approximation of the provider payload.
- `[Unknown]` A signed-in production desktop turn can have different dynamic tool definitions,
  world state, metadata, conversation history, enabled connectors, feature flags, and transport
  selection. This capture proves the algorithm and one concrete ChatGPT-client-configured turn; it
  does not claim that all six concrete items are byte-identical to every desktop turn.

## Computer Use prompt variant selection

The DMG's `app.asar` contains logic that chooses a Computer Use skill variant from desktop feature
availability:

- `computerUseNodeRepl == true` selects `node-repl`;
- otherwise it selects `legacy-mcp`;
- for `node-repl`, `.codex-plugin/computer-use-node-repl.md` is copied over
  `skills/computer-use/SKILL.md` in the materialized bundled marketplace;
- the chosen `bundledContentVariant` is written to the plugin manifest.

This resolves the earlier prompt-precedence question: the materialized skill file for the selected
variant is the active injected prompt. Both source files exist in the bundle, but the node-REPL
variant replaces the legacy skill file when that feature is active.

## Remaining unknowns, narrowed

The following are still legitimately unknown from client artifacts:

1. Provider-private model weights, inference implementation, hidden classifiers, and post-receipt
   transformations.
2. Whether a particular production request is exceptionally rerouted by the service; the client
   can only learn this from the response's `ServerModel` event.
3. The byte-for-byte payload of an unspecified future turn, because its conversation, permissions,
   tools, runtime state, and feature flags do not exist until that turn is created.
4. Long-run server behavior not represented by the client protocol, if any.

The following must no longer be listed as wholly unknown:

- the client-selected model slug;
- the client request schema;
- the request-construction algorithm;
- developer/user role ordering;
- the position of selected Computer Use skill instructions;
- Lite versus non-Lite placement of base instructions and tools.

## Implication for Suniye parity

Suniye can copy the observable behavior independently without inventing orchestration rules:

- let the user-selected model resolve to an explicit request model slug;
- keep the model/tool/context order deterministic and testable;
- inject the Computer Use operating instructions at the same logical boundary as a selected skill;
- send current observations and prior tool results as ordered conversation items;
- preserve the distinction between client-selected model and exceptional server reroute;
- avoid claiming parity with provider-private inference behavior.

This report recovers reference behavior for study. It does not copy reference source code into
Suniye and does not implement production changes.
