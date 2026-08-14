# macOS Computer Use UX reference verification

Research date: 2026-08-08

Scope: static inspection of `<home>/Downloads/ChatGPT (1).dmg`, its mounted application at
`/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app`, and current first-party OpenAI documentation.
No production code or visualization was changed for this research.

## Evidence rules

- `[Verified]` means the cited primary source directly contains or implements the claim.
- `[Inferred]` means the claim is the narrowest explanation consistent with verified evidence, but
  the complete implementation is not visible.
- `[Unknown]` means the inspected primary sources do not establish the answer.

Absence is handled narrowly. For example, “the exposed macOS API has no brightness method” is
verified from its exhaustive type declaration. “The product can never change brightness” is not
established and is therefore not claimed.

## Artifact identity

- `[Verified]` The DMG SHA-256 is
  `45ec006a0f3f0fa004b6fd4d6d5529979a05361f995ca2c51de3a3b04deee123`.
- `[Verified]` The mounted main bundle is version `26.727.51351` (`CFBundleVersion` `6119`) with
  bundle identifier `com.openai.codex`.
- `[Verified]` The bundled Computer Use service is version `26.727.1000550`
  (`CFBundleVersion` `1000550`) with bundle identifier `com.openai.sky.CUAService` and
  `LSUIElement=true`.

Primary paths:

- `<home>/Downloads/ChatGPT (1).dmg`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Info.plist`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/Info.plist`

## Direct answers

### 1. Exact model-facing macOS tool surface

#### The outer tool boundary

- `[Verified]` The bundled model guidance says to perform all Computer Use interactions through a
  persistent JavaScript `node_repl`. It tells the model to bootstrap the plugin-owned wrapper,
  which installs a frozen `sky` object with `target: "mac"`.
- `[Verified]` The plugin also declares an MCP server launched through
  `./bin/computer-use-client-launcher mcp`. The launcher resolves an installed native client below
  `$CODEX_HOME/computer-use/`.
- `[Verified]` A read-only MCP handshake was performed directly against the native client inside
  the mounted bundle. It negotiated MCP protocol `2025-06-18`, identified itself as
  `Computer Use`, and returned ten tools from `tools/list`.
- `[Verified]` The native MCP tools use the same names as the `sky` methods, but their schemas are
  not identical. For example, the direct MCP uses string element identifiers, omits
  `disableDiff`, and names the select-text mode `selection`; the JavaScript wrapper uses numeric
  `element_index`, exposes `disableDiff`, and names that field `selection_type`.
- `[Unknown]` The exact JSON Schema for the outer `node_repl` execution call is not embedded in the
  Computer Use wrapper. Therefore, it would still be incorrect to describe each `sky` method as a
  separate top-level tool when discussing the documented `node_repl` path.
- `[Unknown]` The artifact contains both a direct native MCP path and a `node_repl` wrapper path.
  Static files do not establish which path server-side orchestration selects for every task.

Primary paths:

- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/computer-use-node-repl.md`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.mcp.json`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/bin/computer-use-client-launcher`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/scripts/computer-use-client.mjs`

#### Exact direct native MCP tool schemas

`[Verified]` The native client's `tools/list` response advertised these tools. Every schema has
`additionalProperties: false`.

```ts
type DirectMCPTools = {
  list_apps: {};

  get_app_state: {
    app: string;
  };

  click: {
    app: string;
    click_count?: number; // JSON Schema integer
    element_index?: string;
    mouse_button?: "left" | "right" | "middle";
    x?: number;
    y?: number;
  };

  perform_secondary_action: {
    app: string;
    element_index: string;
    action: string;
  };

  set_value: {
    app: string;
    element_index: string;
    value: string;
  };

  select_text: {
    app: string;
    element_index: string;
    text: string;
    prefix?: string;
    suffix?: string;
    selection?: "text" | "cursor_before" | "cursor_after";
  };

  scroll: {
    app: string;
    element_index: string;
    direction: string;
    pages?: number; // fractional values are explicitly supported
  };

  drag: {
    app: string;
    from_x: number;
    from_y: number;
    to_x: number;
    to_y: number;
  };

  press_key: {
    app: string;
    key: string;
  };

  type_text: {
    app: string;
    text: string;
  };
};
```

- `[Verified]` `app` accepts an app name, full app path, or unambiguous bundle identifier.
- `[Verified]` `list_apps` and `get_app_state` are annotated read-only, idempotent, non-destructive,
  and closed-world. The eight action tools are annotated non-read-only and non-idempotent, while
  still non-destructive and closed-world at the MCP annotation level.
- `[Verified]` The direct `get_app_state` description says it starts an app-use session if needed,
  returns the key window's screenshot and Accessibility tree, and must be called once per assistant
  turn before interacting with the app.
- `[Verified]` A read-only `list_apps` call returned a standard MCP result with telemetry metadata
  and one text content block:

  ```ts
  type DirectListAppsResult = {
    _meta: {
      "codex/telemetry": {
        span: { did_trigger_server_user_flow: boolean };
      };
    };
    content: [{ type: "text"; text: string }];
  };
  ```

  Its `text` contains one human-readable app record per line rather than a JSON array.
- `[Unknown]` `tools/list` does not declare output schemas. A live `get_app_state` call was not made
  because it could start an app session, request permissions/approval, or affect visible app state.
  Its description verifies screenshot plus Accessibility-tree semantics, but not the exact MCP
  content-block order or screenshot MIME encoding.
- `[Inferred]` The compiled success string `Action completed. Call get_app_state to fetch the
  updated UI state.` is the action tools' textual success result. The exact outer MCP result object
  for actions was not executed and remains unverified.

Read-only probe:

```text
<SkyComputerUseClient binary> mcp
initialize(protocolVersion="2025-06-18")
notifications/initialized
tools/list
tools/call(name="list_apps", arguments={})
```

Primary binary:

- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient`

The official Responses API's built-in `computer` tool is a different surface. Its documented
actions are `click`, `double_click`, `scroll`, `type`, `wait`, `keypress`, `drag`, `move`, and
`screenshot`, returned in an ordered `actions[]` array. It does not document this artifact's
app-scoped Accessibility tools (`get_app_state`, `set_value`, `select_text`, or
`perform_secondary_action`). The official API guide is therefore a conceptual loop reference, not
the parameter contract for this macOS artifact.

#### The exact readable `sky` API used by the model inside the REPL

`[Verified]` The exhaustive macOS `WindowComputerUseClient` declaration and bundled model guidance
define this surface:

```ts
type Sky = {
  target: "mac";

  list_apps: () => Promise<App[]>;

  get_app_state: (args: {
    app: string;
    disableDiff?: boolean;
  }) => Promise<AppState>;

  click: (args: {
    app: string;
    element_index?: number;
    x?: number;
    y?: number;
    mouse_button?: "left" | "right" | "middle" | "l" | "r" | "m";
    click_count?: number;
  }) => Promise<void>;

  drag: (args: {
    app: string;
    from_x: number;
    from_y: number;
    to_x: number;
    to_y: number;
  }) => Promise<void>;

  perform_secondary_action: (args: {
    app: string;
    element_index: number;
    action: string;
  }) => Promise<void>;

  press_key: (args: {
    app: string;
    key: string;
  }) => Promise<void>;

  scroll: (args: {
    app: string;
    element_index: number;
    direction: "up" | "down" | "left" | "right" | "u" | "d" | "l" | "r";
    pages?: number;
  }) => Promise<void>;

  select_text: (args: {
    app: string;
    element_index: number;
    text: string;
    prefix?: string;
    suffix?: string;
    selection_type?: "text" | "cursor_before" | "cursor_after";
  }) => Promise<void>;

  set_value: (args: {
    app: string;
    element_index: number;
    value: string;
  }) => Promise<void>;

  type_text: (args: {
    app: string;
    text: string;
  }) => Promise<void>;
};

type App = {
  id: string;
  displayName?: string;
  lastUsedDate?: string;
  useCount?: number;
  isRunning?: boolean;
};

type AppState = {
  app: string;
  screenshot: { url: string } | null;
  text: string;
};
```

Primary paths:

- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/types/window/WindowComputerUseClient.d.ts`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/types/window/*.d.ts`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/docs/sky-window-api.md`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/computer-use-node-repl.md`

#### Exact result and failure semantics visible in the wrapper

- `[Verified]` `list_apps` returns the app records above. Its canonical `id` prefers the bundle
  identifier, then display name, then `"unknown"`.
- `[Verified]` `get_app_state` returns exactly `app`, `screenshot`, and Accessibility `text`.
  The text may be prefixed once per app with `<app_specific_instructions>...</app_specific_instructions>`.
- `[Verified]` With diffing enabled, later Accessibility text can be a diff rather than a full tree.
  `disableDiff: true` requests a full tree.
- `[Verified]` Every action method returns `Promise<void>`. A successful action does not itself
  return a new screenshot, Accessibility tree, target record, or semantic action result.
- `[Verified]` Failures throw either a `SkyComputerUseError` containing `name`, numeric `code`,
  `errorName`, `request`, and `requestType`, or a `SkyComputerUseTransportError` with a cause.
  Named native error codes include permission, invalid/ambiguous app, no active session,
  user-stopped session, user intervention, blocked URL, incompatible version, and screen locked.
- `[Verified]` The environment-specific model guidance says screenshot URLs are `file://` URLs
  and instructs the model to read the file and emit it with `nodeRepl.emitImage(...)`.
- `[Verified]` The generated `sky-window-api.md` describes the URL as a data URL. Static sources
  therefore disagree on URL scheme. The exact shape `{ url: string }` is verified; static
  inspection alone does not resolve the contradictory scheme descriptions.

Primary paths:

- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/list_apps.js`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/get_app_state.js`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/window_result.js`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/errors.js`

#### Native requests below the model-facing wrapper

These are transport details, not additional model-facing tools.

- `[Verified]` The wrapper uses API version `CodexComputerUseIPC-2` and defaults to a 120-second
  request timeout.
- `[Verified]` It sends request types `ComputerUseIPCListAppsRequest`,
  `ComputerUseIPCAppPolicyRequest`, `ComputerUseIPCAppGetSkyshotRequest`,
  `ComputerUseIPCAppPerformActionRequest`, and `ComputerUseIPCAppStartRequest`.
- `[Verified]` The native request envelope contains `clientApiVersion`, optional
  `codexTurnMetadata`, `deadlineUnixMilliseconds`, `requestType`, and `request`.
- `[Verified]` The action request contains one app plus one nested action. The JavaScript wrapper
  converts snake-case model arguments to native camel-case fields and converts element indexes to
  string element IDs.

Primary paths:

- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/client.js`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/native-pipe.js`

### 2. Context visibly passed through the model/tool loop

The artifact exposes two different context boundaries. They should not be described as one large
custom model request.

#### Context that can be returned to the model

- `[Verified]` JavaScript bindings in `node_repl` persist across calls. The model can keep an
  `AppState`, app list, or other values in runtime variables.
- `[Verified]` Text becomes outer tool output when JavaScript calls `nodeRepl.write(...)`.
- `[Verified]` A screenshot becomes image output to the model only when JavaScript reads the URL
  and calls `nodeRepl.emitImage(...)` as instructed by the bundled guidance.
- `[Verified]` The state available from `get_app_state` is the resolved app identifier,
  Accessibility text (full or diff), and an optional app-window screenshot URL.
- `[Verified]` App-specific operating instructions may be included in the Accessibility text on
  first access to an app. The wrapper tracks which apps already received those instructions.
- `[Verified]` Action calls expose completion by resolving with no value, or expose failure by
  throwing an error. A subsequent `get_app_state` is what returns updated UI evidence.
- `[Verified]` The guidance tells the model that when it cannot identify an app from the task,
  prior context, or built-in apps, it should call `list_apps`. This is model-led app selection;
  the artifact does not show a deterministic natural-language-to-app matcher.

#### Context passed from the REPL wrapper to the local native service

- `[Verified]` Each state/action request carries the requested app and operation arguments.
- `[Verified]` The client can attach `x-codex-turn-metadata` from `nodeRepl.requestMeta` as
  `codexTurnMetadata` to the native request.
- `[Verified]` The approval wrapper reads `call_id` or `item_id` from that metadata when available,
  resolves the app policy, and attaches app/tool approval metadata to its elicitation request.
- `[Verified]` The policy layer exposes Computer Use response metadata identifying the resolved
  app bundle identifier and tool surface. A Chrome-targeted call additionally sets
  `codex/computerUseChrome` response metadata for host UI handling.
- `[Unknown]` The complete schema and meaning of `x-codex-turn-metadata` are not present. Only the
  fields read by the local wrapper are verified.

Primary paths:

- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/computer-use-node-repl.md`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/scripts/computer-use-client.mjs`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/computer-use-policy.js`
- `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/native-pipe.js`

#### Prompt material recovered from the DMG

- `[Verified]` The earlier statement that the prompt was not present in the DMG was too broad.
  `ChatGPT.app/Contents/Resources/codex` embeds JSON model profiles containing
  `base_instructions` strings.
- `[Verified]` The embedded `gpt-5.6-luna` base instructions begin at byte offset `198377842`,
  decode to 17,730 UTF-8 characters, and have SHA-256
  `cbefa6b0bede0e332d957fca70ccacf9f12f4c0ecdf81b819e5cbe1a3b16e265`. The bundled
  `gpt-5.6-sol` and `gpt-5.6-terra` profiles contain identical base-instruction content.
- `[Verified]` The complete readable Computer Use-specific operating instructions are packaged at
  `plugins/openai-bundled/plugins/computer-use/.codex-plugin/computer-use-node-repl.md`. They define
  the persistent `node_repl` runtime, exact `sky` API, app selection, observation/action loop,
  Accessibility-versus-screenshot strategy, screenshot emission, retry behavior, automatic wait
  timing, background launch behavior, and the Computer Use confirmation policy.
- `[Verified]` A second Computer Use instruction source is packaged at
  `plugins/openai-bundled/plugins/computer-use/skills/computer-use/SKILL.md`. It contains the skill
  trigger description and a Computer Use confirmation policy.
- `[Verified]` The two Computer Use prompt files are ordinary plaintext. The node-REPL instruction
  file is 18,913 bytes with SHA-256
  `a52ede355c6637d05be9da5e3f19dbfd5f23fa5ec4c9513e3188bc8a57429c79`; the skill file is
  6,216 bytes with SHA-256
  `2079334b8e4329bd12eb30719198146f8f844605ca3c354410315d2a39688d4e`.

#### Runtime context correction

- `[Verified]` The exact tagged client source establishes the composition algorithm and final
  client-side role ordering for model base instructions, tool definitions, dynamic world state,
  user input, and selected skill/plugin injections.
- `[Verified]` The turn protocol accepts a client-side model override, and the request builder sends
  the resolved slug. A loopback request serialized by this DMG's binary selected `gpt-5.6-luna`,
  `medium` reasoning, and Responses Lite ordering.
- `[Verified]` Conversation, prior assistant messages, and tool outputs are retained as ordered
  response items and cloned from history for the next sampling request; context updates and
  compaction can modify that history according to explicit client code.
- `[Unknown]` The byte-for-byte dynamic values for an unspecified production turn and the result of
  compaction for a particular long conversation cannot be known before that turn exists.
- `[Unknown]` The artifact does not show one request in which a model receives “the task,
  conversation, current app state, screenshot, and prior action results” as named fields. That is
  not an established reference contract.
- `[Unknown]` The artifact does not establish whether every `node_repl` output remains verbatim in
  every later model turn, how it is truncated or summarized, or which state is retained only in
  the persistent runtime.
- `[Verified]` Client-side skill/plugin selection and tool visibility are represented in the local
  context and request builder. The DMG host also materializes either the node-REPL or legacy-MCP
  Computer Use prompt from a desktop feature flag.
- `[Unknown]` Hidden server-side safety classifiers, provider inference, and post-receipt routing or
  transformation are not recoverable from the local client.

See `runtime-request-and-model-selection-recovery-2026-08-08.md` for the exact source paths and
captured request.

The current official OpenAI Computer Use guide confirms that multiple harness shapes are valid:
a built-in screenshot/action loop, a custom tool/MCP harness, or a code-execution harness. Its
code-execution example explicitly accumulates a conversation containing the user prompt, model
outputs, and function-call outputs, and returns text/images from the harness. That is a first-party
example, not proof that this desktop artifact uses the same server implementation.

Primary URL:

- [OpenAI Computer use guide](https://developers.openai.com/api/docs/guides/tools-computer-use)
  (especially “Choose an integration path,” “Run the built-in Computer use loop,” and
  “Use a code-execution harness”)

### 3. Does the artifact prove app-free brightness or battery-health actions?

No.

- `[Verified]` Every exposed state or action method requires an `app` argument. The only method
  without an app is the read-only `list_apps()` discovery call.
- `[Verified]` There is no exposed brightness, battery, power, display, Control Center, global
  keyboard, shell, or generic OS-command method in the exhaustive macOS `Sky` declaration.
- `[Verified]` The model guidance explicitly says `press_key` and `type_text` target the specified
  app and cannot invoke global shortcuts.
- `[Verified]` The guidance says that if the required app is not evident, the model should use
  `list_apps`, and that `get_app_state` can transparently launch a chosen app in the background.
- `[Verified]` The confirmation policy contemplates non-sensitive display-setting changes. That
  proves a policy category, not a technical implementation for brightness.
- `[Inferred]` A model could potentially answer a battery-health request by choosing an app such
  as System Settings and reading its UI, or change brightness by operating an app-exposed control,
  if that app and control are discoverable and accessible. The artifact does not demonstrate that
  workflow or guarantee that the relevant macOS surface is targetable.
- `[Unknown]` Whether the inspected build can successfully complete either example end to end is
  not established without a live run against the relevant macOS UI.
- `[Unknown]` Whether server-side orchestration could choose a different non-Computer-Use tool for
  such a request is not visible in the DMG.

Therefore, Suniye should not encode “every task names an app,” but it also should not pretend that
the reference has app-free native OS controls. The verified reference behavior is: the model
chooses an app from the task/context or discovers apps, and every actual desktop state/action call
is app-scoped.

### 4. Foreground behavior and the meaning of “fresh state”

#### Foreground behavior

- `[Verified]` The public model-facing method shapes have no `frontmost`, `activate`, or
  session-wide target-lock parameter.
- `[Verified]` The guidance says `get_app_state` transparently launches an app “in the background”
  when it is not running.
- `[Verified]` The model-facing macOS API does not expose `activate_window`; that method belongs to
  a separate documented Window2 surface, not this macOS `WindowComputerUseClient` declaration.
- `[Verified]` A read-only live call to the Computer Use client shipped in the inspected DMG
  captured Calculator twice while WhatsApp remained the frontmost app before and after the calls.
  Observation therefore does not inherently activate the target.
- `[Verified]` The native helper contains conditional focus coordination, process-scoped event
  delivery, and semantic AX interaction paths. A particular input path may coordinate focus when
  needed; unconditional foreground activation is not the observation model.
- `[Unknown]` Static artifact evidence does not prove that all input actions work while the host
  conversation window remains visibly in front, nor does it prove that the target must visibly
  come forward.

Consequently, “Calculator comes forward” is not a verified reference UX requirement.

#### What the reference actually says about updated state

- `[Verified]` The bundled guidance says to begin with `get_app_state(app)` for the chosen app.
- `[Verified]` The direct native MCP tool description is more specific: `get_app_state` must be
  called once per assistant turn before interacting with the app. The native client also contains
  an error for trying another Computer Use action before that app session is active.
- `[Verified]` After performing **one or more** actions, it says to call `get_app_state(app)` before
  deciding what to do next. The reason given is to re-derive current `element_index` values from
  the latest Accessibility text rather than reusing stale indexes.
- `[Verified]` The guidance allows action batching before the next observation. It does not require
  a new observation immediately before every individual action.
- `[Verified]` “Once per assistant turn before interacting” is a turn-level prerequisite, not an
  observation-before-every-action rule.
- `[Verified]` The official built-in Computer Use API similarly permits an ordered `actions[]`
  batch, followed by one updated screenshot before the next model decision.
- `[Inferred]` The closest accurate UX wording is: “After the agent changes the UI, it checks the
  app again before planning the next step.”
- `[Unknown]` The artifact does not define a domain object named “target state.” That phrase should
  not be presented to users as reference terminology.

“Fresh state” therefore means a newly captured `AppState` for the app being operated: current
Accessibility text (full or diff) plus the current app-window screenshot. It does **not** mean a
frontmost-app lock, and the artifact does **not** prove observation-before-every-action enforcement.

The official guide independently describes the general visual loop as: receive one or more actions,
execute them in order, capture the updated screen, send it back, and repeat. This is useful as a
first-party conceptual cross-check, but the DMG's `sky` methods and Accessibility text are the
authoritative evidence for this macOS artifact.

Primary URL:

- [OpenAI Computer use guide](https://developers.openai.com/api/docs/guides/tools-computer-use)
  (steps 1–5 and “Possible Computer use actions”)

## UX conclusions supported by the artifact

- `[Verified]` The user request need not name an app. App choice is part of model reasoning; when
  uncertain, the model is instructed to discover apps.
- `[Verified]` Once the model invokes desktop Computer Use, each state read or action is scoped to
  one app. There is no session-wide target-lock parameter in either readable macOS surface.
- `[Verified]` The model can inspect Accessibility text first and emit/read screenshots when visual
  evidence is needed. The state API returns both; the guidance prefers Accessibility for
  efficiency and screenshots when Accessibility is incomplete.
- `[Verified]` The reference loop's observable action outcome is success/failure followed by a new
  app-state read, not a bespoke semantic result from each click or keystroke.
- `[Verified]` App selection, state inspection, action execution, and policy approval are separate
  concerns in the wrapper. The artifact does not justify deterministic task keyword matchers.
- `[Verified]` The reference wording is “current UI state” and “latest accessibility text,” not
  “target state.”
- `[Unknown]` Exact user-facing progress copy, shimmer behavior, stop-control placement, and the
  full conversation UX are outside the inspected tool contract and require direct UI evidence.

## Open questions requiring runtime or server evidence

1. What exact final prompt payload, message roles, and ordering are sent for a live Computer Use
   turn after static and dynamic instruction sources are composed?
2. How are conversation history and `node_repl` outputs retained, summarized, or truncated between
   model turns?
3. Does the native helper keep a target window in the background during each input method, or does
   it transiently activate/raise it?
4. Can this build complete battery-health inspection or brightness adjustment through a targetable
   macOS app, and if so which app/Accessibility surface does it choose?
5. What exact browser-control path is selected after the wrapper marks
   `codex/computerUseChrome`, and which state is passed to that separate path?

## Primary source index

### Mounted artifact

- Plugin manifest:
  `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/plugin.json`
- Model guidance and API surface:
  `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/computer-use-node-repl.md`
- Skill confirmation policy:
  `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/skills/computer-use/SKILL.md`
- Plugin runtime wrapper:
  `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/scripts/computer-use-client.mjs`
- Generated macOS API reference:
  `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/docs/sky-window-api.md`
- Exhaustive macOS public types:
  `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/types/window/`
- Public macOS wrapper implementation:
  `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/`
- Native service:
  `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService`
- Native MCP/IPC client:
  `/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient`

### Official OpenAI documentation

- [Computer use](https://developers.openai.com/api/docs/guides/tools-computer-use)
- [Computer use Markdown source](https://developers.openai.com/api/docs/guides/tools-computer-use.md)
