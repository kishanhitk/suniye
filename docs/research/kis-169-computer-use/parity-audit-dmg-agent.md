# DMG parity audit: macOS Computer Use agent

Status: draft

Audit date: 2026-08-03

Worktree: /Users/kishan/.codex/worktrees/eaaa/suniye

Branch: kis-169-computer-use

## Scope and evidence rules

This audit compares the current Suniye working tree with the local reference artifact:

/Users/kishan/Downloads/ChatGPT (1).dmg

The image was already mounted read-only at:

/private/tmp/suniye-chatgpt-dmg-mount

hdiutil info reported a read-only, unencrypted, compressed UDZO image. The mount reported
read-only. The image was not changed. The ASAR archive was read in memory. No artifact file was
extracted into the repository.

The artifact paths below use this notation for files inside the ASAR archive:

/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/app.asar:<internal path>

The labels have precise meanings:

- [Verified] means direct evidence exists in the mounted bundle, its readable JavaScript or
  declarations, native metadata, native symbols, or the current Suniye source.
- [Inferred] means the conclusion follows from verified evidence, but the artifact does not
  expose the complete source or server-side implementation.
- [Unknown] means the inspected evidence does not answer the question.

This file describes the working tree at audit time. Pre-existing uncommitted Suniye changes were
not modified by this audit.

## Executive result

- [Verified] The reference desktop path has separate runtime boundaries: the main app, a bundled
  cua_node runtime, a JavaScript model-facing API, a native client boundary, and a separate
  signed native Computer Use service.
- [Verified] The reference exposes a macOS app-level API based on Accessibility state plus a
  screenshot. It supports indexed Accessibility actions and screenshot-coordinate actions.
- [Verified] The reference performs an app-policy check before each public state read or action.
  It also has a user approval bridge and native permission/session errors.
- [Verified] The reference artifact exposes three distinct communication shapes: MCP over stdio
  for tool entry, a length-prefixed JSON-RPC Unix native pipe for the Node @oai/sky client, and
  an Apple Events capture bridge. The direct native client also contains an XPC transport.
- [Inferred] The reference model loop is approximately:

  ~~~text
  model/agent
    -> node_repl or direct MCP tool boundary
    -> model-facing Computer Use wrapper
    -> native client
    -> native service session
    -> target app Accessibility/input/screenshot APIs
    -> state or action result
    -> model/agent
  ~~~

- [Superseded] This early audit did not yet recover the client model catalog, exact tagged client
  source, prompt renderer, or serialized request. The later audit verifies client-side model
  selection, static prompts, request construction, context ordering, and the local agent loop.
  Provider-private inference remains unknown. See
  `runtime-request-and-model-selection-recovery-2026-08-08.md`.
- [Verified] Suniye now has the same broad semantic loop: observe, ask a model for a typed next
  decision, apply policy and approval, execute one action, then observe again.
- [Verified] Suniye does not yet have the reference runtime topology. Its Computer Use services
  run in the Suniye process, its model client uses an HTTP provider boundary, and its current
  project.yml has no Computer Use helper target.
- [Inferred] Suniye has conceptual parity for a desktop prototype, but not process, transport,
  native-helper, permission-orchestration, or browser parity.

## 1. Artifact inventory and bundle boundaries

### Main application

- [Verified] The mounted image contains one application bundle at:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app

- [Verified] The main executable is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/MacOS/ChatGPT

- [Verified] The main bundle metadata is at:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Info.plist

  It identifies the bundle as com.openai.codex, declares NSPrincipalClass as
  BrowserCrApplication, and declares Apple Events usage for Mac app control.

- [Verified] The main application resources include:

  ~~~text
  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/app.asar
  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/app.asar.unpacked
  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node
  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/native
  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins
  ~~~

- [Verified] The main app is not App Sandbox restricted in its inspected entitlements. It has
  Apple Events automation, an application group containing the Computer Use group, and other
  unrelated capabilities. This does not prove that every declared main-app capability is required
  for desktop control.

### Bundled JavaScript and Node runtime

- [Verified] The packaged ASAR package.json is at:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/app.asar:/package.json

  It identifies the packaged app as an Electron application, includes @oai/sky, node-pty,
  objc-js, ws, and zod, and contains an e2e:computer-use-native-pipe script entry.

- [Verified] The bundled Node runtime manifest is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/manifest.json

  It contains a Darwin arm64 Node runtime, bin/node, bin/node_repl, and the bundled module root
  lib/node_modules.

- [Verified] The model-facing package is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky

  Its package metadata points to the compiled JavaScript entrypoint under
  dist/project/cua/sky_js/src.

### Computer Use plugin boundary

- [Verified] The desktop plugin manifest is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/plugin.json

  It describes local Mac app control and says the user chooses apps, can stop actions, and can
  control screenshot training. The last statement is product text; the artifact does not expose
  the complete server-side implementation of that training choice.

- [Verified] The plugin has a direct MCP server definition at:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.mcp.json

  Its server command is ./bin/computer-use-client-launcher, with argument mcp, and its
  environment allow-list includes CODEX_HOME.

- [Verified] The launcher is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/bin/computer-use-client-launcher

  It resolves the native client from:

  $CODEX_HOME/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient

  It exits if that executable is absent, then runs it with the original arguments.

### Native service and native client

- [Verified] The packaged native service bundle is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app

- [Verified] Its service executable is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService

  Its bundle identifier is com.openai.sky.CUAService. Its metadata declares LSUIElement and a
  minimum macOS version of 14.4.

- [Verified] The native client bundle is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app

  Its executable bundle identifier is com.openai.sky.CUAService.cli.

- [Verified] The service and client are arm64 native executables. The inspected bundles are
  Developer ID signed. The service links AppKit, ApplicationServices, CoreGraphics,
  ScreenCaptureKit, ScriptingBridge, WebKit, and Swift frameworks. The client links the relevant
  AppKit, ApplicationServices, CoreGraphics, ScreenCaptureKit, ScriptingBridge, and WebKit
  frameworks.

- [Verified] The service bundle contains additional resources, including:

  ~~~text
  .../Codex Computer Use.app/Contents/Resources/Package_ComputerUse.bundle
  .../Codex Computer Use.app/Contents/SharedSupport/CUALockScreenGuardian.app
  ~~~

- [Verified] The service bundle contains app-specific guidance files under:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/Resources/Package_ComputerUse.bundle/Contents/Resources/AppInstructions

  The inspected files include AppleMusic.md, Clock.md, iPhone Mirroring.md, Notion.md,
  Numbers.md, Slack.md, and Spotify.md.

- [Unknown] The packaged copy under cua_node is not proof of which copy is used by a running
  installation. The main bundle contains path resolution based on CODEX_HOME, resource paths,
  and CODEX_ELECTRON_COMPUTER_USE_APP_PATH. The exact precedence selected in a live installation
  is not established here.

## 2. Runtime and transport architecture

The artifact exposes more than one entry path. They must not be collapsed into one unverified
architecture.

### Path A: direct plugin MCP entry

- [Verified] The plugin .mcp.json launches SkyComputerUseClient in mcp mode through the shell
  launcher described above.
- [Verified] The native client executable contains strings for stdio MCP transport, Computer Use
  request types, app approval events, CodexComputerUseIPC-2, and a native
  ComputerUseIPCXPCTransport.
- [Verified] The service executable contains corresponding IPC server/session names, including
  ComputerUseIPCServer, ComputerUseIPCJSONRPCSocketServer, ComputerUseIPCXPCSession, and
  sender-authorization/context-resolver names.
- [Inferred] The direct MCP client likely reaches the native service through the native client
  IPC layer, with XPC being a strong candidate because both binaries expose XPC transport/session
  symbols.
- [Unknown] The exact XPC endpoint, bootstrap mechanism, and whether the direct MCP client uses
  the same Unix socket as the JavaScript client are not exposed by the inspected native binaries.

### Path B: Node node_repl and @oai/sky

- [Verified] The model-facing instructions are:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/computer-use-node-repl.md

  They require node_repl, persistent JavaScript state, and bootstrap through the plugin wrapper.

- [Verified] The wrapper is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/scripts/computer-use-client.mjs

  It loads the packaged @oai/sky macOS create_client.js, creates a client with target mac,
  installs Chrome metadata, and exposes the frozen sky object to the Node REPL globals.

- [Verified] The macOS compiled client is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/create_client.js

  It exports target: mac, list_apps, get_app_state, and the Mac actions.

- [Verified] The main ASAR bundle contains a Ke function in:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/app.asar:/.vite/build/main-dcXtv3U5.js

  It configures a node_repl MCP server with nodeReplPath, NODE_REPL_NODE_MODULE_DIRS,
  NODE_REPL_NODE_PATH, NODE_REPL_TRUSTED_CODE_PATHS, CODEX_HOME, request metadata, and a
  120-second MCP startup timeout.

- [Verified] The JavaScript macOS transport implementation is:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/native-pipe.js

  It uses a native pipe connection and a Unix socket defaulting to:

  ~/Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService/IPC/computeruse.sock

  SKY_CUA_SERVICE_NATIVE_PIPE_PATH overrides the socket path.

- [Verified] If the socket is unavailable, the JavaScript transport first tries a host service
  ensure request through NODE_REPL_HOST_SERVICES_PIPE_PATH. If that is unavailable, it asks the
  trusted Node REPL Launch Services bridge to open the service path from SKY_CUA_SERVICE_PATH,
  $CODEX_HOME/computer-use/Codex Computer Use.app, or bundle identifier
  com.openai.sky.CUAService. It then retries the connection for up to five seconds and pings the
  service.

- [Inferred] In this path, the model-facing JavaScript code does not perform Accessibility or
  input operations itself. It calls the JavaScript client, which serializes a request to the native
  service.

- [Unknown] The artifact does not show the full server-side selection rule that chooses the
  direct MCP path versus the node_repl path for a particular model turn.

### Native-pipe wire contract

- [Verified] The JavaScript client uses JSON-RPC 2.0 messages with id, jsonrpc, method, and
  params.
- [Verified] The pipe frames each UTF-8 JSON message with a four-byte little-endian length.
- [Verified] The JavaScript decoder rejects frames larger than 8,388,608 bytes.
- [Verified] The pipe methods include ping and request.
- [Verified] A request carries clientApiVersion, optional codexTurnMetadata, a deadline in
  Unix milliseconds, request, and requestType.
- [Verified] The default client API version is CodexComputerUseIPC-2.
- [Verified] The default request timeout is 120 seconds. Requests are serialized through one
  promise chain. Pending requests are rejected when the pipe closes.
- [Verified] The request type names include:

  ~~~text
  ComputerUseIPCAppPolicyRequest
  ComputerUseIPCAppGetSkyshotRequest
  ComputerUseIPCListAppsRequest
  ComputerUseIPCAppPerformActionRequest
  ComputerUseIPCAppStartRequest
  ~~~

- [Verified] The helper binary contains sender authentication and sender-context resolver names.
- [Unknown] The exact sender authentication algorithm and trust decision are not recoverable from
  the inspected source and symbols.

### Apple Events capture bridge

- [Verified] The ASAR worker at:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/app.asar:/.vite/build/worker.js

  contains a computer-use-capture-native-bridge.
- [Verified] That bridge constructs Apple Events for service bundle identifier
  com.openai.sky.CUAService and uses AECreateAppleEvent, AESendMessage, and related Apple
  Event APIs.
- [Verified] Its capture request names include:

  ~~~text
  ComputerUseIPCAppStartCaptureRequest
  ComputerUseIPCAppNextCaptureUpdateRequest
  ~~~

- [Verified] Capture updates have metadata, Accessibility text, screenshot, completed, and failed
  variants. The start response includes permission states such as none_granted,
  accessibility_granted, screen_recording_granted, and both_granted.
- [Verified] The worker polls until completed or failed, and converts a polling exception to
  update_poll_failed.
- [Verified] The capture worker's own handleCancel() is empty in the inspected readable worker.
  This describes that worker only. It does not prove that the broader native session has no
  cancellation path.
- [Inferred] The artifact has a capture/appshot path that is separate from the model-facing
  action path. The Apple Events bridge must not be treated as the native-pipe action protocol.

## 3. Public action schema and model loop

### Public Mac API

@oai/sky documents the Mac API in:

/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/docs/sky-window-api.md

The Node REPL instructions repeat the same surface in:

/private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/computer-use-node-repl.md

| Operation | Verified reference input | Verified behavior |
|---|---|---|
| list_apps | No input | Returns app id, display name, running state, last-used date, and use count when available. |
| get_app_state | app, optional disableDiff | Returns app identifier, screenshot or null, and Accessibility text. The default can return a diff. |
| click | app, element_index or x/y, optional mouse button and click count | Prefers an Accessibility element; falls back to app-window coordinates. |
| drag | app, from_x, from_y, to_x, to_y | Uses app-window coordinates. |
| press_key | app, key or key chord | Sends a key or modifier chord to the target app, not a global shortcut. |
| type_text | app, text | Types into the current target focus. Newline behavior can submit in some apps. |
| scroll | app, element_index, direction, optional pages | Scrolls an indexed Accessibility element. |
| set_value | app, element_index, value | Replaces an editable Accessibility value. |
| select_text | app, element_index, text, optional prefix/suffix/selection type | Selects text or places the cursor before or after a match. |
| perform_secondary_action | app, element_index, exposed action name | Invokes only an Accessibility action exposed by the current element. |

- [Verified] The public Mac client maps these operations to native action payloads such as
  click, drag, pressKey, type, scroll, setValue, selectText, and
  performSecondaryAction.
- [Verified] The JavaScript client validates finite coordinates, integer element indexes,
  non-empty keys, valid mouse buttons, valid directions, and positive finite page counts before it
  writes the native request.
- [Verified] The public model-facing action names are not the same as Suniye's current Swift
  wire names for every action. The reference uses press_key, type_text, set_value, and
  select_text; Suniye uses Swift Codable cases such as key_press, type_text, set_value, and
  select_text.

### State and action loop

- [Verified] The instructions require an initial get_app_state for the named app. If the app is
  unknown, the model may call list_apps.
- [Verified] After one or more actions, the instructions require a fresh get_app_state before
  deciding the next action.
- [Verified] The default Accessibility result can be a diff from the previous state. The model
  can request a full tree with disableDiff: true.
- [Verified] The runtime waits about one second after input and can wait longer when it detects a
  loading indicator before capturing the next state. This is documented behavior, not a guarantee
  for every application.
- [Verified] Native symbols show a cached/refetchable tree through
  RefetchableSkyshotAXTree, a lastAXTree, lastWindow, visibleRect, scalingFactor, and
  isAXTreeDiffingEnabled on ComputerUseAppController.
- [Verified] Native symbols show prepareToInteract, updateSkyshot, and action methods with
  optional returnSkyshot behavior.
- [Inferred] The effective state machine is:

  ~~~text
  resolve app
    -> ensure app session and policy
    -> capture skyshot (AX text plus screenshot)
    -> model chooses an action or terminal result
    -> policy and user approval
    -> native service refetches or validates the target element
    -> native action
    -> settle and capture fresh state
    -> repeat or finish
  ~~~

- [Unknown] The exact model response format, tool-call selection, system prompt, and server-side
  retry policy are not exposed by the inspected DMG. The public artifact proves the tool contract,
  not the complete model implementation.

### Suniye loop comparison

- [Verified] Suniye/Services/ComputerUseAgent.swift implements an actor-isolated loop. It
  observes the target, checks intervention, sends ComputerUseModelRequest, handles a typed
  ComputerUseModelDecision, requests approval, executes one action, applies a settle delay, and
  observes again.
- [Verified] Suniye/Services/ComputerUseAgentModels.swift supports action, completed, ask-user,
  blocked, and retryable-failure decisions.
- [Verified] Suniye enforces maximum actions, maximum failures, and maximum duration. Its
  cancellation token is cooperative and is checked between native calls.
- [Verified] Suniye/Services/ComputerUseModelClient.swift sends the observation to an
  OpenAI-compatible HTTP endpoint. It can include a screenshot as a data URL only when the
  configuration allows screenshot upload.
- [Inferred] Suniye matches the reference's observable state/action/state cycle at the agent
  level, but its model-facing contract is a typed HTTP decision response rather than model-authored
  JavaScript calling sky tools.
- [Verified] Suniye action results currently contain the action, target, and completion time. A
  fresh observation is obtained by the next loop iteration rather than being returned as a native
  action response.
- [Unknown] Suniye does not yet know whether its chosen provider supports the same multimodal
  semantics, latency, structured output reliability, or cancellation behavior as the reference
  model path.

## 4. App and window discovery

### Reference behavior

- [Verified] list_apps.js maps native app records to an id, display name, running state,
  last-used date, and use count.
- [Verified] The public app identifier can be a display name, full app path, process name, or
  bundle identifier. The instructions recommend retrying with the bundle identifier when a display
  name fails.
- [Verified] get_app_state is documented to launch the app in the background when it is not
  running. The model does not need to issue a separate launch command for the old Mac API.
- [Verified] The native service has app-controller methods and state for a running application,
  ordered windows, last window, and frontmost/focus handling.
- [Verified] The public old Mac API is app-targeted. It does not expose a stable public window
  object in sky-window-api.md.
- [Verified] The package also contains:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/docs/sky-window2-api.md

  That documented API uses explicit Window { app, id, title } objects, list_windows,
  get_window, launch_app, and get_window_state. Its target is windows and the package README
  labels it as the Windows API.
- [Unknown] The sky-window2-api.md contract is not evidence that the active macOS path uses
  explicit public window objects. The current Mac create_client.js exports the old app-level
  API.

### Suniye behavior

- [Verified] Suniye/Services/ComputerUseApplicationCatalog.swift lists NSWorkspace running
  applications. Its application id combines bundle identifier and process identifier.
- [Verified] Suniye/Services/ComputerUseApplicationCatalog.swift discovers visible layer-zero
  windows through CGWindowListCopyWindowInfo, stores a CG window id, bounds, title, owner PID,
  and an approximate key-window flag.
- [Verified] Suniye/Services/ComputerUseObservationService.swift selects an existing key-window
  candidate or the first visible window. It fails when the app is not running or has no window.
- [Verified] Suniye does not transparently launch a non-running target during observation.
- [Inferred] Suniye's process-scoped application id protects against PID reuse better than a raw
  display name, but it differs from the reference's model-facing bundle/app identifier behavior.
- [Inferred] Suniye needs an explicit policy for app launch, multiple matching apps, and ambiguous
  windows before it can claim discovery parity. The reference has an ambiguousApp error; Suniye's
  current error model does not expose that equivalent.

## 5. Accessibility and screenshot handling

### Reference behavior

- [Verified] The native service binary contains ComputerUseAppController, SkyshotCapture,
  SkyshotOperation, RefetchableSkyshotAXTree, Accessibility tree cache, focus/window tracking,
  and screenshot capture symbols.
- [Verified] The native service links ApplicationServices, CoreGraphics, and ScreenCaptureKit.
  Its symbols include CGImage capture and WindowServer/ScreenCaptureKit-related capture paths.
- [Verified] The exact native function names include captureAXTree, captureScreenshot,
  updateSkyshot, and updateSkyshotSettlingIfNeeded.
- [Verified] The public state contains Accessibility text and a screenshot URL. The wrapper adds
  app-specific instructions to the text on first use for many apps. It skips that prefix for
  Numbers and avoids repeating it for an app already seen in the session.
- [Verified] The model-facing instructions prefer Accessibility element indexes. They permit
  coordinate actions when the Accessibility tree is incomplete and tell the model to use a fresh
  screenshot in that case.
- [Verified] The native controller has a scaling factor, visible rectangle, window ordering, and
  cursor/focus-enforcer symbols. These are direct signs that display scale and target focus are
  handled below the JavaScript wrapper.
- [Inferred] The native service maintains a session-scoped AX tree and can refetch an element
  before acting when an index becomes stale. The symbol names support this conclusion; the exact
  refetch algorithm is not visible.
- [Unknown] The inspected evidence does not prove which screenshot implementation is selected for
  each app, display, or capture state. The service links both CoreGraphics and ScreenCaptureKit.

### Suniye behavior

- [Verified] Suniye/Services/ComputerUseAccessibilityReader.swift creates an application AX
  element, resolves a target window, walks a bounded tree, and serializes deterministic element
  indexes, roles, titles, descriptions, values, enabled/focused/selected state, bounds, actions,
  and child indexes.
- [Verified] ComputerUseObservationConfiguration limits AX depth, element count, and text
  length. It has sensitive-value redaction enabled by default.
- [Verified] Suniye/Services/ComputerUseScreenshotService.swift captures a target window with
  CGWindowListCreateImage and encodes PNG data.
- [Verified] Suniye represents screenshots as Data in ComputerUseObservation and constructs a
  base64 data URL for an HTTP model request when upload is enabled.
- [Verified] Suniye can observe without a screenshot when the task opts out. When a screenshot is
  requested, it requires Screen Recording permission.
- [Inferred] Suniye has no verified equivalent of the reference's AX diff protocol, refetchable tree
  object, app-specific instruction bundle, native focus enforcer, or display-scale abstraction.
- [Unknown] The current CGWindowListCreateImage output has not been live-compared with the
  reference service's ScreenCaptureKit/WindowServer output across Retina, multiple-display, and
  moved-window cases.

## 6. Supported actions: direct parity comparison

### Reference action semantics

- [Verified] The reference supports click, drag, key press, text typing, scroll, set value, text
  selection, and arbitrary exposed secondary Accessibility actions.
- [Verified] Element indexes come from the latest state. The instructions explicitly say to
  prefer an element index over coordinates and to use only an action exposed by that element.
- [Verified] Coordinates are app-window or screenshot-relative, not global screen coordinates.
- [Verified] The native action layer has methods for keyboard actions, secondary actions, text
  selection, set value, click, coordinate drag, and scroll.

### Suniye action semantics

- [Verified] The current working tree's Suniye/Services/ComputerUseActionModels.swift models:

  ~~~text
  click(point, clickCount, mouseButton)
  keyPress(key, modifiers)
  scroll(horizontal, vertical, optional point)
  typeText(text)
  setValue(elementIndex, value)
  drag(from, to)
  selectText(elementIndex, text, prefix, suffix, selectionType)
  semantic(elementIndex, action)
  ~~~

- [Verified] Suniye/Services/ComputerUseInputEventService.swift posts CGEvent click, drag,
  keyboard, and scroll events. Suniye/Services/ComputerUseAccessibilityReader.swift performs
  value setting, text selection, and semantic AX actions.
- [Verified] Suniye converts window-relative coordinates to screen coordinates by adding the
  observed window origin before posting events.
- [Verified] Suniye validates action bounds, element presence, enabled state, text lengths,
  click counts, finite scroll values, and current target identity.
- [Inferred] Suniye's click action is coordinate-only. The reference click can select an element index
  or coordinate.
- [Inferred] Suniye's scroll action is delta-and-coordinate based. The reference scroll is indexed
  element plus direction and pages. These are different semantics, not only different field names.
- [Inferred] Suniye's semantic action is an enum of known AX names. The reference accepts the exact
  secondary action name exposed by the current Accessibility element. Suniye therefore cannot yet
  express every valid secondary action without expanding its enum or adding a validated dynamic
  action name.
- [Inferred] Suniye now covers drag, set value, and select text. It has not been proven to
  match the reference's native selection disambiguation, autosubmit behavior, mouse-button mapping,
  key-name grammar, or app-specific action timing.

## 7. Permissions and entitlement behavior

### Reference evidence

- [Verified] The native service contains PermissionRequirement values named accessibility,
  screen recording, full disk access, automation messages, and contacts.
- [Verified] The native service contains PermissionRequester.requestPermissionsIfNeeded and
  PermissionWindowController.presentPermissions.
- [Verified] The helper bundle declares Apple Events automation and Contacts access in its
  entitlements and usage descriptions.
- [Verified] The main app declares Apple Events usage and automation entitlement. The main app
  also has file, camera, audio, calendar, and other capabilities unrelated to the basic desktop
  action contract.
- [Verified] Native strings include accessibility and screen-recording grant states, permission
  pending text, and permission-not-granted errors.
- [Unknown] The exact permission matrix is not visible. The presence of a permission requirement
  in the helper does not prove that every Computer Use action requires it.
- [Unknown] The inspected static files do not establish whether the main app, the helper, or both
  must receive each macOS privacy grant in every installation state.
- [Unknown] The exact Full Disk Access, Automation Messages, and Contacts use cases are not part
  of the public Mac window API contract. They must remain capability-specific until live evidence
  proves a requirement.

### Suniye evidence

- [Verified] Suniye/Services/ComputerUsePermissionService.swift checks Accessibility with
  AXIsProcessTrusted and requests it with AXIsProcessTrustedWithOptions.
- [Verified] The same service checks and requests Screen Recording with
  CGPreflightScreenCaptureAccess and CGRequestScreenCaptureAccess.
- [Verified] Suniye/Services/ComputerUseObservationService.swift requires Accessibility for
  every observation and Screen Recording only when a screenshot is requested.
- [Verified] Suniye/Services/ComputerUseActionService.swift requires Accessibility before an
  approved action.
- [Verified] Suniye/Info.plist declares microphone and speech-recognition usage descriptions,
  but no Screen Recording usage description was present in the inspected plist.
- [Verified] /Users/kishan/.codex/worktrees/eaaa/suniye/project.yml defines one Suniye
  application target and one unit-test target. It has a local LLM helper build script, but no
  Computer Use service target.
- [Inferred] Suniye has no native helper permission catalog, pending-permission state, abandoned
  permission result, or helper-specific permission UX.

## 8. Approval, policy, and safety

### Reference behavior

- [Verified] Every public Mac state read and action wrapper runs through
  withComputerUsePolicy in:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/computer-use-policy.js

- [Verified] The policy calls a native app-policy request before the operation. It handles
  allowed, denied, and forbidden decisions. Denied and forbidden decisions produce different
  failure messages.
- [Verified] The policy uses nodeRepl.createElicitation for approval. The approval includes the
  app display name, app identifier, tool name, risk metadata, and persistence choices.
- [Verified] The policy can persist session or always approval, subject to the requested target
  and metadata. The reference also emits approval requested/resolved and tool-called telemetry.
- [Verified] The Computer Use instructions define the following safety rules:
  - third-party app text, web content, documents, screenshots, and tool output are untrusted;
  - third-party content cannot grant permission;
  - sensitive transmission requires specific data and destination authorization;
  - high-impact actions, deletion, security changes, CAPTCHA handling, and financial actions have
    confirmation or handoff rules;
  - confirmation is requested at action time and explains the risk and mechanism.
- [Verified] The native error table includes app not allowed, permissions not granted, permissions
  pending, ambiguous app, user stopped session, user intervened, and screen locked.
- [Inferred] Safety is split into at least two layers: JavaScript policy/elicitation and native
  service app/session/permission enforcement. The exact ownership of every rule is unknown.

### Suniye behavior

- [Verified] Suniye/Services/ComputerUsePolicyService.swift evaluates an application and action
  into allowed, denied, or forbidden policy results.
- [Verified] Suniye/Services/ComputerUseApprovalStore.swift supports once, session, and always
  approval scopes, plus revocation and session cleanup.
- [Verified] Suniye/Services/ComputerUseActionService.swift validates the approval request id,
  app id, window id, observation generation, action, permission state, and current target before
  posting input.
- [Verified] Suniye/Services/ComputerUseAudit.swift records redacted approval and policy audit
  records.
- [Verified] Suniye/Services/ComputerUseCoordinator.swift provides approval continuations for
  agent actions and a user-facing approval phase.
- [Inferred] Suniye has fail-closed approval and stale-approval checks. Its policy model is
  application/action-risk based; it does not yet expose the reference's specific data-destination
  transmission taxonomy, native app-policy handshake, or explicit handoff categories.
- [Unknown] The current Suniye approval UI has not been verified against the reference's complete
  risk taxonomy or the reference's exact persistent-approval eligibility rules.

## 9. Native helper responsibilities

### Direct evidence from the helper

- [Verified] The service binary contains names for:

  ~~~text
  ComputerUseAppController
  ComputerUseAppInstance
  ComputerUseAppInstanceManager
  ComputerUseServiceLifecycle
  SkyshotCapture
  SkyshotOperation
  RefetchableSkyshotAXTree
  SkyshotClassifier
  PermissionCatalog
  PermissionRequester
  PermissionWindowController
  ComputerUseUserInteractionMonitor
  UserInterruptedIntervention
  ComputerUseURLBlocklist
  CUALockScreenGuardian
  ComputerUseIPCJSONRPCSocketServer
  ComputerUseIPCXPCSession
  ComputerUseIPCSenderAuthorization
  ~~~

- [Verified] Native symbols expose methods for app activation/deactivation, ordered windows,
  AX-tree update, click, keyboard action, secondary action, text selection, value setting,
  scrolling, focus enforcement, cursor movement, and user-requested session termination.
- [Verified] The service links the system frameworks required for Accessibility, AppKit window
  management, Core Graphics input/capture, screen capture, scripting, and WebKit-related app
  behavior.

### Responsibility boundary

- [Inferred] The helper owns the privileged, timing-sensitive desktop boundary:
  - resolve a running application and usable window;
  - establish an app session;
  - request or verify system permissions;
  - capture AX text and screenshots;
  - maintain or refetch the AX tree;
  - activate/focus the target safely;
  - perform native input and semantic AX actions;
  - detect session stop, intervention, locked screen, and service errors;
  - return structured state or failure through IPC.
- [Inferred] The main agent/UI layer owns model context, user approval, task state, and the
  decision to continue. The helper must still revalidate technical target and permission state;
  policy must not rely only on a stale main-process observation.
- [Unknown] The exact boundary between native safety policy, host policy, and model-side safety
  policy is not available from the binary.

## 10. Error, cancellation, and user intervention behavior

### Reference behavior

- [Verified] The JavaScript native-pipe client retries service connection, pings the service,
  enforces per-request timeouts, rejects invalid JSON-RPC responses, and rejects all pending calls
  when the pipe closes.
- [Verified] Reference error names include:

  ~~~text
  senderProcessNotAuthenticated
  couldNotGetRequestData
  couldNotGetRequestTypeName
  couldNotResolveRequestType
  unhandledEvent
  unknownError
  appNotAllowed
  runningApplicationNotFound
  accessibilityError
  permissionsNotGranted
  invalidApp
  noActiveSession
  userStoppedSession
  incompatibleClientVersion
  permissionsPending
  blockedURL
  userIntervened
  couldNotGetSenderPID
  ambiguousApp
  couldNotGetBootstrapPort
  screenLocked
  ~~~

- [Verified] The JavaScript policy telemetry maps userStoppedSession and userIntervened to a
  canceled terminal status.
- [Verified] Native symbols include a user-interrupted intervention record with requiresRequery
  and debounce state, plus a method to end by user request after pending operations.
- [Inferred] A user intervention invalidates the current state and requires a fresh state query
  before continuing. The public instructions also require fresh state after actions.
- [Unknown] The exact event that registers every user intervention, the debounce duration, and
  the exact cancellation behavior for a native action already in progress are not visible.

### Suniye behavior

- [Verified] Suniye/Services/ComputerUseModels.swift defines a cooperative
  ComputerUseCancellationToken. Native adapters check it between calls; an already-running
  synchronous Core Graphics or Accessibility call is not forcibly interrupted.
- [Verified] Suniye/Services/ComputerUseAgent.swift handles cancellation, model cancellation,
  observation cancellation, action cancellation, failure limits, action limits, and duration
  limits.
- [Verified] Suniye/Services/ComputerUseCoordinator.swift cancels active tasks, resolves
  pending approval continuations as stop-session, and returns the UI to a ready state.
- [Verified] Suniye/Services/ComputerUseInterventionMonitor.swift stops when the frontmost
  process changes, the target window disappears, or the target is no longer key.
- [Inferred] Suniye has a useful frontmost/window intervention guard. It has no native
  service connection lifecycle, protocol mismatch, socket-close, permissions-pending,
  ambiguous-app, screen-locked, or helper-crash error equivalent.
- [Unknown] Suniye has not been live-tested for intervention races during a real CGEvent or AX
  call, multiple displays, or a WindowServer restart.

## 11. Desktop control versus browser control

### Reference surfaces

- [Verified] The desktop plugin is a separate plugin at:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use

  Its Mac target is @oai/sky with app identifiers, AX text, screenshots, and native app actions.
- [Verified] The browser plugin is a separate plugin at:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/browser

- [Verified] Browser API documentation is at:

  /private/tmp/suniye-chatgpt-dmg-mount/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/browser/docs/api.json

  It exposes browser backends of types iab, extension, and cdp; browser sessions; tabs; and
  user-tab claiming.
- [Verified] A browser tab has separate playwright, dom_cua, and viewport cua surfaces.
  DOM CUA uses visible DOM node ids. Viewport CUA uses page coordinates. Playwright uses DOM
  snapshots, locators, roles, labels, and page operations.
- [Verified] Browser guidance prefers Playwright where possible, otherwise DOM or vision, and
  requires a fresh state check after interactions.
- [Verified] Browser safety documentation separately covers sensitive-data transmission,
  uploads, downloads, permissions, login, CAPTCHAs, deletion, messages, and browser interstitials.
- [Verified] Browser interruption guidance says to summarize naturally when the extension or user
  takes control, rather than exposing raw runtime errors.
- [Verified] The desktop wrapper adds Chrome metadata when the app input identifies Chrome,
  Google Chrome, com.google.chrome, or a Google Chrome app path. This is metadata, not proof that
  the desktop AX path and browser extension path are the same implementation.
- [Inferred] Browser control is a separate adapter with tab/session/DOM state. It should not be
  implemented as “select Chrome and use the desktop AX adapter” when browser semantics are needed.
- [Unknown] The exact browser extension message protocol and the routing rule between in-app
  browser, extension, and CDP backends are not established by this audit.

### Suniye status

- [Verified] Suniye has an app/window desktop target, AX state, screenshots, CGEvent input, and
  model decisions.
- [Verified] Suniye has no browser tab, DOM, Playwright, extension, CDP, download, upload, or
  browser-session adapter.
- [Inferred] Selecting a browser as a running macOS app would only be desktop-app control. It is
  not browser parity.

## 12. What Suniye already supports

- [Verified] App discovery through NSWorkspace for running applications.
- [Verified] Visible window discovery through CGWindowListCopyWindowInfo.
- [Verified] Bounded, serializable AX tree observation through ApplicationServices.
- [Verified] Optional target-window PNG capture through Core Graphics.
- [Verified] Accessibility and Screen Recording permission checks and request calls.
- [Verified] Coordinate click, click count, mouse button, drag, key press, scroll, text typing,
  AX value setting, text selection, and a constrained semantic AX action model.
- [Verified] Window-relative coordinate conversion and current-target validation.
- [Verified] Actor-isolated model loop with terminal states, bounded retries, action limits,
  duration limits, settle delay, and cancellation.
- [Verified] An OpenAI-compatible HTTP model client with strict Codable decision parsing.
- [Verified] Screenshot upload is an explicit configuration choice and is disabled by default in
  ComputerUseRemoteModelConfiguration.
- [Verified] Application/action policy, once/session/always approvals, revocation, stale approval
  checks, and redacted audit records.
- [Verified] Frontmost application and target-window intervention checks.
- [Verified] SwiftUI coordinator state and approval continuation integration.

## 13. What Suniye must add for reference-level parity

The following are gaps or design requirements. They are not production changes in this audit.

- [Inferred] A separate native Computer Use service boundary if process isolation, independent
  permission ownership, native crash isolation, or a trustworthy IPC authorization boundary is a
  product requirement.
- [Inferred] A versioned IPC contract with health checks, request deadlines, framed messages, structured
  transport errors, and sender authorization.
- [Inferred] A service lifecycle component that can start, reconnect, report pending permissions, and
  distinguish helper unavailability from target-app failure.
- [Inferred] Stable app and window resolution with explicit ambiguous-target behavior and optional
  background app launch.
- [Inferred] AX tree revision/diff/refetch behavior. Element indexes must be scoped to a state revision
  and invalidated after state changes.
- [Inferred] Exact public action semantics for indexed click and indexed scroll, plus validated dynamic
  secondary Accessibility action names.
- [Inferred] A native screenshot abstraction that can be compared against ScreenCaptureKit and Core
  Graphics on supported macOS versions and display configurations.
- [Inferred] Native permission orchestration with precise capability requirements and pending/abandoned
  outcomes.
- [Inferred] A safety taxonomy that distinguishes read-only observation, local state change, external
  transmission, high-impact communication, credentials, financial actions, deletion, security
  changes, CAPTCHAs, and handoff-required actions.
- [Inferred] Native lock-screen and user-intervention handling, including state re-query requirements.
- [Inferred] App-specific guidance only where live tests show generic AX semantics are insufficient.
- [Inferred] Browser control should be a separate tab/DOM/extension adapter, not an extension of
  the desktop service's AX model.

## 14. Proposed independent Swift implementation plan

This plan keeps Suniye's existing Swift actor and MainActor seams. It uses the artifact as a
behavioral reference, not as a source-code dependency.

### 14.1 Service boundaries

[Inferred] Use these boundaries:

1. ComputerUseCoordinator (@MainActor, existing)

   Owns user-visible phase, selected app, permission presentation state, approval sheet state,
   current task, and cancellation commands. It must not hold raw AX objects or block on native
   calls.

2. ComputerUseAgent (actor, existing)

   Owns the task loop, model requests, bounded retry policy, observation revision, and terminal
   result. It may request approval through an async protocol, but it must not mutate SwiftUI state.

3. ComputerUseModelClient (existing protocol, retain)

   Owns provider-specific authentication, request encoding, timeout, cancellation, and typed model
   decision parsing. Keep this independent from the native desktop transport.

4. ComputerUsePolicyService and ComputerUseApprovalStore (existing, extend)

   Own application allow-list policy, action risk, persistent scope, confirmation timing, data
   transmission disclosure, revocation, and redacted audit records. Policy decisions must be made
   before the native action and revalidated when the request reaches the helper.

5. ComputerUseNativeServiceClient (new app-side boundary)

   Exposes only Sendable Codable values:

   ~~~text
   listApps
   getAppPolicy
   startAppSession
   getAppState
   performAction
   cancelRequest
   ping
   ~~~

   It owns connection setup, framing, request ids, deadlines, version negotiation, reconnect, and
   conversion from wire errors to Swift errors.

6. SuniyeComputerUseService (new helper target)

   A small LSUIElement native macOS service. It owns AX objects, native window state, screenshot
   capture, input events, semantic AX actions, permission checks, target activation, and native
   intervention/lock checks. No model credentials or model prompt should enter this process.

7. ComputerUseServiceLauncher (new app-side service)

   Resolves the bundled helper, starts it through Launch Services, waits for the socket, pings it,
   and reports a structured startup failure. It must not silently fall back to a different helper
   binary.

8. ComputerUseBrowserAdapter (future, separate)

   Owns browser tabs, DOM/Playwright state, extension/CDP transport, browser-specific permissions,
   and browser safety. Do not put this in the desktop AX helper.

### 14.2 Native IPC design

[Inferred] A Swift implementation can preserve the reference's useful guarantees without
copying private native request names:

- Use a Unix-domain socket in an application-group container.
- Frame each JSON message with a four-byte little-endian length prefix.
- Include id, jsonrpc, method, and params in each request.
- Include a protocol version, session id, request id, deadline, and optional turn metadata.
- Reject frames above a fixed maximum before allocation. The reference uses 8 MiB.
- Serialize requests if the helper has one active UI transaction per app.
- Add ping, startSession, getState, performAction, and cancel methods.
- Return structured errors with stable codes, retryability, and safe user-facing text.
- Validate the connecting process before accepting requests. The exact signing check must be
  designed and tested with public Security APIs; do not assume a path is an identity.
- Close and fail all pending requests on EOF, helper exit, protocol mismatch, or deadline expiry.

[Unknown] Whether Suniye should choose a Unix socket, XPC, or both cannot be settled from the
artifact alone. The reference uses a Unix JSON-RPC path for the JavaScript client and exposes an
XPC path in the direct native client. Start with one documented Swift transport unless a live
permission or security test requires two transports.

### 14.3 Native helper responsibilities

[Inferred] Implement the helper in this order:

1. AppSessionManager: resolve bundle id/path/display name, detect ambiguity, launch if explicitly
   allowed, bind one session to one process and selected window.
2. AccessibilitySnapshotter: create AX application/window elements, walk a bounded tree, assign
   state-revision element ids, collect exposed actions, and produce text plus optional diff.
3. ScreenshotProvider: implement a protocol with Core Graphics and ScreenCaptureKit adapters. Run
   a live macOS 14 comparison before choosing the default.
4. InputExecutor: perform coordinate and indexed actions. Recheck the state revision, target PID,
   window identity, and frontmost/key state immediately before input.
5. PermissionCoordinator: report exact missing capability, pending request, user abandonment, and
   granted state. Request only the capabilities needed for the requested operation.
6. InterventionMonitor: observe frontmost app/window and relevant AX focus/window notifications;
   invalidate the session when the user takes control.
7. ScreenLockGuard: use a validated public macOS state source. The reference has a lock-screen
   guardian, but its exact implementation is not known.
8. ServiceLifecycle: accept one session, stop cleanly, drain or cancel pending operations, and
   report helper crash/restart state to the coordinator.

### 14.4 Required macOS APIs to validate

[Verified] The current/reference evidence establishes the relevant API families:

- AppKit: NSWorkspace, NSRunningApplication, NSWindow/application activation where needed.
- ApplicationServices: AXUIElement, AXObserver, AXIsProcessTrusted, AX attributes and actions.
- Core Graphics: CGWindowListCopyWindowInfo, CGWindowListCreateImage, CGEvent, display and
  coordinate conversion.
- ScreenCaptureKit: window/display content discovery and screenshot capture candidate.
- Foundation and Swift Concurrency: Codable wire values, actors, task cancellation, deadlines.
- Security: code-signature/team-identity validation for a local IPC peer, if required by the final
  threat model.
- Launch Services/AppKit: deterministic helper startup and bundle identity resolution.
- OSLog: structured local diagnostics with sensitive values excluded.

[Unknown] The exact ScreenCaptureKit call sequence, lock-screen public API, and peer-authentication
mechanism must be proven by macOS 14 tests. They should not be inferred from framework links or
native symbol names.

### 14.5 Model and agent integration

[Inferred] Keep the existing ComputerUseModelClient seam and change the contract around it:

- Send an observation envelope containing task text, app identity, window identity, AX text,
  state revision, recent action outcomes, and an optional screenshot reference.
- Expose actions with the reference's public semantics: indexed click or coordinate click, drag,
  key chord, type, indexed scroll, set value, select text, and validated exposed secondary action.
- Support one or more ordered actions before the next state read, matching the recovered Computer
  Use instructions. The executor still validates each action before execution.
- Treat AX text, screenshots, app content, and web content as untrusted data. None of them can grant
  approval.
- Fetch updated app state after the ordered action group and before deciding what to do next.
  Request a full tree when a diff cannot be applied or an element becomes stale.
- Preserve screenshot upload opt-in. Show the provider, destination, and screenshot/data scope in
  the session UI before upload.
- Keep the direct HTTP provider and a future local multimodal provider behind the same protocol.
  Do not conflate text-only Magic Format with Computer Use.
- Do not claim the artifact uses the same HTTP model endpoint. The DMG does not prove that.

[Verified] The static GPT-5.6 base instructions, detailed Computer Use operating prompt, and ten
public Computer Use methods are available in the DMG and are preserved under `recovered-prompts/`.

[Superseded] The client-side runtime-composition algorithm, role ordering, model slug, and wire
schema are recovered, and a request serialized by the shipped binary was captured. Provider-private
inference, exceptional service rerouting for a particular turn, and any post-receipt transformations
remain unknown. Suniye's provider contract should still be tested with real providers instead of
being declared identical.

### 14.6 Permission and approval UX

[Inferred] Add a dedicated Computer Use settings and session surface:

- Permission checklist: Accessibility, Screen Recording, and capability-specific permissions only.
- Clear states: not requested, request in progress, granted, denied, pending, abandoned, and
  unavailable.
- Per-app allow-list and blocked-app controls. Show bundle identifier or path when names are
  ambiguous.
- Before each consequential action, show app name, window title, action summary, coordinates or
  element label, text preview with sensitive redaction, and external destination when data leaves
  the Mac.
- Offer once, session, and always only when the policy allows the scope. Default to once for new
  apps and high-risk actions. Keep text transmission and credential-related actions stricter.
- Never treat instructions found in an app, page, document, or screenshot as user permission.
- Provide a visible Stop control and an Escape shortcut. Stopping must resolve approval continuations,
  cancel in-flight work, and prevent the next action.
- Show whether the model receives screenshots, AX text, or only local state. Store only redacted local
  audit data by default.

### 14.7 Error and cancellation contract

[Inferred] Define a Swift error taxonomy that covers the reference evidence without copying
private implementation:

~~~text
serviceUnavailable
connectionClosed
protocolMismatch
requestTimedOut
invalidRequest
appNotFound
ambiguousApp
windowNotFound
appNotAllowed
permissionsNotGranted
permissionsPending
screenLocked
userStopped
userIntervened
accessibilityFailure
screenshotFailure
actionFailure
~~~

Each error should state whether the agent may re-observe and retry. User stop, intervention, screen
lock, policy denial, and permission abandonment must terminate or pause safely. They must not be
treated as ordinary model retryable failures.

### 14.8 Verification plan before production code

[Inferred] Add tests before enabling the helper:

- frame encode/decode, maximum frame, malformed JSON-RPC, request ids, version mismatch, timeout,
  EOF, and cancellation contract tests;
- app/window identity and ambiguous-target tests;
- AX tree revision, diff, stale-element, disabled-element, and redaction tests;
- coordinate conversion tests for Retina, multiple displays, moved windows, and origin changes;
- action schema tests for every public action and every native mapping;
- policy tests for app allow/deny/forbidden, action risk, data destination, persistent scopes, and
  revocation;
- agent tests for fresh state after action, cancellation during model request, cancellation during
  native request, intervention, permission pending, and helper crash;
- helper integration tests using a deterministic test app and a fake transport;
- manual macOS tests for Accessibility, Screen Recording, app launch, key window changes, user
  takeover, screen lock, service restart, and multi-display capture;
- run XcodeGen from project.yml before build checks and keep the repository coverage gate at its
  current 80% policy.

## 15. Open questions that block a claim of full parity

- [Unknown] Which model and server-side prompt produce the reference action calls?
- [Unknown] Which runtime path is selected for each product surface: direct MCP, node_repl, or
  another host bridge?
- [Unknown] Does the direct native client use the same helper socket as @oai/sky, or only the
  same service through XPC?
- [Unknown] What is the native sender-authentication rule?
- [Unknown] What exact app/window resolution algorithm handles multiple instances, background
  windows, hidden windows, and app launch?
- [Unknown] Which screenshot implementation is used for each target and display state?
- [Unknown] What permission set is required for read-only AX, screenshot, input, messages, files,
  and browser actions individually?
- [Unknown] What event marks user intervention, how long is it debounced, and when is re-query
  required?
- [Unknown] What is the exact cancellation behavior for an input event already posted or an AX
  action already executing?
- [Unknown] Which persistent approvals are permitted for each risk class, and how are they revoked
  across app updates or helper restarts?
- [Unknown] How does the browser extension/DOM/CDP route connect to the model and how does it
  share or not share desktop policy?
- [Unknown] Does Suniye's local-first requirement require a local multimodal model, or is a
  remote provider with explicit screenshot consent acceptable for the first release?

## Concise parity finding

[Verified] Suniye has a credible same-process desktop prototype with AX observation, window
screenshots, typed actions, approval, an agent loop, and intervention checks.

[Verified] The reference has a separate native service and client topology, versioned IPC, richer
AX/screenshot state handling, native permission/session enforcement, explicit app policy before each
operation, and a separate browser control surface.

[Inferred] The next parity-critical work is the native service/client contract and live macOS
validation. Browser control should remain a separate future track.

[Unknown] Full parity cannot be claimed until the model-side loop, direct-client XPC route,
permission matrix, cancellation/intervention triggers, and live screenshot/window behavior are
verified.

## Post-audit Suniye correction: 2026-08-03

The implementation changed after the audit sections above were written. The current Suniye desktop
contract now includes indexed clicks, validated arbitrary exposed Accessibility actions, screenshot
IDs for screenshot-grounded coordinate actions, selected-window activation, and the matching UX.
The historical gaps in the earlier sections remain valid as audit-time findings. The remaining
desktop gaps are installed-app launch, transient screenshot caching, reference-specific state diffs,
helper IPC, and live macOS validation.

## Superseding Suniye cleanup note — 2026-08-03

- `[Verified]` The DMG Mac wrappers forward app-scoped operations to the native service and do not
  define a user-facing window picker, cached element validator, or local action-loop limit.
- `[Implemented]` Suniye removes those local extras while retaining the internal native window
  resolver needed to operate macOS Accessibility and screenshots.
- `[Implemented]` Suniye's Preview path uses automatic authorization, always includes the
  observation screenshot, and removes the duplicate structured element prompt rendering.
- `[Corrected]` The client-side model selection, request schema, context ordering, prompt-variant
  selection, and local agent loop are recoverable and are documented in
  `runtime-request-and-model-selection-recovery-2026-08-08.md`. Provider-private inference remains
  unknown. Native-helper internals are tracked separately in the native algorithm recovery note.
