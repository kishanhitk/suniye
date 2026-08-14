# Code-mode recovery from ChatGPT 26.810.41047

Research date: 2026-08-14. Ticket: KIS-179.

Scope: static inspection of `<home>/Downloads/ChatGPT (2).dmg`, mounted read-only at
`/private/tmp/suniye-chatgpt2-mount/ChatGPT.app`. No binaries were executed. The prior
recovery (`prompt-recovery-2026-08-08.md`) covered version 26.727.51351; this document
records what changed and what the new artifact exposes that the old one did not.

## Evidence labels

- `[Verified]` is directly present in the mounted DMG.
- `[Inferred]` is the narrowest explanation consistent with the artifact.

## Version and packaging changes

- `[Verified]` App version 26.810.41047 (build 6570), up from 26.727.51351.
- `[Verified]` The plugin list grew. New bundled plugins: `computer-history`,
  `record-and-replay`, `messages`, `reminders-macos`, `sites`.
- `[Verified]` The computer-use plugin is now an MCP server. `.mcp.json` registers
  `./bin/computer-use-client-launcher mcp`; the launcher is a shell script that execs
  `${CODEX_HOME:-~/.codex}/computer-use/Codex Computer Use.app/Contents/SharedSupport/`
  `SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient`. The loose
  `scripts/computer-use-client.mjs` from 26.727 is gone.
- `[Verified]` The app bundles a private Node runtime at `Contents/Resources/cua_node/`
  with the npm package `@oai/sky` version 0.6.11 installed, including compiled JS,
  TypeScript declaration files, generated API docs, and the native service app bundles.
- `[Verified]` `Contents/Resources/native/sky.node` exists (native Node addon).

## Prompt changes since 26.727

- `[Verified]` `skills/computer-use/SKILL.md` is byte-identical to the recovered copy
  (SHA-256 `2079334b...`). The confirmation policy did not change.
- `[Verified]` `computer-use-node-repl.md` changed in exactly one section: bootstrap.
  The old plugin-owned wrapper (`setupComputerUseRuntime({ globals: globalThis })`) is
  replaced by a direct import:

  ```js
  globalThis.sky = (await import("@oai/sky")).sky;
  ```

  Everything else — API surface, workflow, notes, confirmation policy — is unchanged.

## The @oai/sky package (new recovery)

`package.json`: version 0.6.11, ESM, main `dist/project/cua/sky_js/src/index.js`,
dependency `@statsig/js-client` (feature gating). `publishConfig.executableFiles` lists
the shipped native binaries and reveals the safety machinery by name:

- Two service builds: `bin/mac/normal/` and `bin/mac/relaxed/` variants of
  `Codex Computer Use.app` (`[Inferred]` "relaxed" is a reduced-interlock build for
  internal/testing use; both contain the same bundle set).
- Each service bundle ships: `SkyComputerUseService` (the daemon),
  `SkyComputerUseClient.app` (the MCP client the launcher execs),
  `Codex Computer Use Installer.app` with a privileged
  `CodexComputerUseAuthorizationPlugin.bundle` + installer tool (`[Inferred]` a macOS
  authorization plugin, the mechanism behind their credential/hand-off policy), and
  `CUALockScreenGuardian.app` (`[Inferred]` the screen-lock guard from the parity
  report, shipped as its own app).

### Three API targets

`SkyClient` is a union type: `FullDesktopComputerUseClient | WindowComputerUseClient |
Window2ComputerUseClient`. Generated docs exist for each (`docs/sky-window-api.md`,
`sky-window2-api.md`, `sky-full-desktop-api.md`), all recovered verbatim below the
mount point.

**`window` (target: "mac")** — the shipped production surface. Identical to the ten
methods in the 26.727 prompt and to Suniye's tool contract. New detail beyond the old
prompt: `press_key` documents X-keysym chord syntax with aliases
(`Control_L+a`, `Super_L+d`, `Ctrl`, `Alt`, `Shift`, `KP_0`), and `AppState.text` is
"prefixed with app-specific guidance on first access when available" — the runtime
injects per-app hint text into the first observation of an app.

**`window2` (target: "windows")** — next-generation, window-scoped surface, not
app-scoped. Differences that matter:

- Targets are `Window` objects (`{app, id, title}`) from `list_windows()` /
  `list_apps()` (apps now carry a `windows` array). `get_window(id)` rehydrates a
  stale binding.
- `launch_app` is an explicit method; observation no longer implies launch.
- `get_window_state` takes `include_screenshot` (default true) and `include_text`
  (default false) — screenshot-first observation, accessibility text on request.
  The old mac surface is text-first with mandatory screenshots.
- `WindowState.screenshots` is an array of bounded, z-ordered regions
  (`{id, url (data URL), originX/Y, width/height, zIndex}`) — transient UI (menus,
  popovers) is captured as separate layered screenshots. Coordinate actions accept a
  `screenshotId` so a click can be validated against the exact screenshot the model
  looked at.
- `AccessibilityState` is structured: `tree` plus extracted `focused_element`,
  `selected_elements`, `selected_text`, `document_text`.
- `scroll` is delta-based from a coordinate (`scrollX/scrollY`), not
  element+direction+pages.
- `activate_window` exists as an explicit "escape hatch"; input methods activate
  their target window automatically.
- `select_text` is absent from window2.
- `[Inferred]` from `target: "windows"` and `.exe` mentions in `launch_app` docs:
  window2 is the Windows-OS port surface; it is not what the shipped mac prompt uses.

**`full-desktop` (target: "linux")** — desktop-coordinate CUA for their hosted VM:
`get_screenshot()` returning raw bytes + data URL + filepath, coordinate
click/drag/move/scroll/type/press_key, drag paths as ordered point lists, and
`drag_handle()` (press, observe between moves, release) for observed drags.

## Mechanics: JS client layer

All from `dist/project/cua/sky_js/src/targets/mac/` unless noted. `[Verified]` by
static read of the shipped JS.

### Transport

- The client runs inside a trusted `nodeRepl` host runtime; the host provides
  `nodeRepl.nativePipe`, `nodeRepl.launchServices`, `nodeRepl.createElicitation`,
  `nodeRepl.withSuspendedTimeout`, `nodeRepl.setResponseMeta`, and
  `nodeRepl.requestMeta`. Absence of any hook is a transport error — model code
  cannot fake the runtime.
- Unix socket at `~/Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService/`
  `IPC/computeruse.sock`; length-prefixed framing (4-byte LE length + JSON), 8 MiB
  frame cap; strict JSON-RPC 2.0.
- Only three JSON-RPC methods exist on the wire: `ping` (API-version handshake,
  `CodexComputerUseIPC-3`), `request` (everything else), and `ensureService`
  (daemon spawn). Every app action tunnels through `request` with a `requestType`
  discriminator (`ComputerUseIPCAppPerformActionRequest` carries all eight mutating
  actions as sub-objects; `ComputerUseIPCAppGetSkyshotRequest` is observation).
- Per-request `deadlineUnixMilliseconds` (default 120 s); requests are serialized —
  one in-flight per transport, chained on a promise. Daemon-start fallback chain:
  `ensureService` over a host-services pipe, then `launchServices.openApplication`
  by path or bundle id `com.openai.sky.CUAService`.

### Per-call policy interposition

`withComputerUsePolicy(toolName, input, fn)` wraps `get_app_state` and all eight
mutating actions. `list_apps` is not gated (enumeration, no target app). Flow:

1. `getAppPolicy(app)` RPC returns `{target, decision, allowPersistentApproval}`;
   `decision` is `allowed` / `denied` (org policy) / `forbidden` (safety).
2. Unless a persisted approval exists, a user elicitation is raised:
   "Allow Computer Use to use \"<app>\"?" with persistence scopes `["session"]` or
   `["session","always"]` when the policy allows. Non-accept throws.
3. The approval wait runs inside `withSuspendedTimeout` so it does not consume the
   RPC deadline. Approval telemetry on request and resolve.
4. App input is TOCTOU-hardened (plain data property required, result frozen).

Audio recording (`start_audio_recording`, env-gated `SKY_ENABLE_AUDIO=1`) has its own
high-risk consent elicitation. This confirms the parity report's conclusion: the
safety interlock lives at the bridge, per call, not in the prompt.

### Error vocabulary

Daemon errors surface as `SkyComputerUseError` with numeric codes; the full recovered
`ServerErrorCode` map includes `appNotAllowed(-10006)`, `accessibilityError(-10008)`,
`permissionsNotGranted(-10009)`, `noActiveSession(-10011)`,
`userStoppedSession(-10012)`, `blockedURL(-10015)`, `userIntervened(-10016)`,
`ambiguousApp(-10018)`, `screenLocked(-10020)`. `userStoppedSession` and
`userIntervened` map to telemetry status "cancelled"; everything else "failed".

### Timing and screenshots

- No post-action settle in the mac JS layer; settle is daemon-owned. (Linux has a
  100 ms `post_action_sleep`; mac does not use it.)
- `get_app_state` passes the daemon's screenshot `url` through untouched; missing
  skyshot is an error. The daemon may return `appSpecificInstructions`, which the
  client prepends once per app per session inside
  `<app_specific_instructions>...</app_specific_instructions>` tags (deduped by a
  session-scoped Set; suppressed for Numbers).

## Mechanics: native service layer

From `strings`/`codesign`/Info.plist inspection of `SkyComputerUseService`,
`SkyComputerUseClient`, and the installer bundles (`@oai/sky` v0.6.11, service
version 26.812.1000717, Bazel + SwiftProtobuf build, min macOS 14.4, Sparkle
auto-update on an alpha channel). `[Verified]` unless marked.

### Chromium accessibility activation — confirms Suniye's fix

The service binary contains `AXEnhancedUserInterface`, `AXManualAccessibility`,
`enableEnhancedUserInterface`, `enableElectronAccessibility`, `isChromium`, with
referenced targets `com.google.Chrome`, `org.chromium.Chromium`,
`me.proton.pass.electron`, plus `WebAreaUIElement` / `webAreaURL` /
`retrieveAttributedTextFromWebAreas`. `[Inferred]` mechanism: set the two AX
attributes on Chromium/Electron processes to force the web-content tree, then walk
`AXWebArea` nodes. This is exactly the fix Suniye shipped in
`SystemComputerUseAccessibilitySnapshotProvider` on 2026-08-14. The reference also
has a richer first-party Chrome-extension path ("get tab context", Google
Workspace/YouTube-transcript asset loaders) as an alternative to AX scraping.

### Settle implementation

The "runtime waits about 1 second, up to 5" from the prompt is implemented as:
cursor-motion gating (`idleVelocityThreshold`,
`cursorMotionDidSatisfyNextInteractionTiming`) plus AX-notification quiescence
(`_axNotificationDebounceTasks`, `AsyncDebounceSequence`, `debounceDeadline`).
Settle is event-driven, not a fixed sleep. Suniye's fixed settle in the observation
service is the simpler approximation.

### Native per-call policy (recorded for the deferred safety layer)

- `ComputerUseIPCAppPolicyDecision` per request; `AppApprovalStore` with
  allow/blocklists and `denied_bundle_ids`; org-policy and safety denial strings.
- URL-level gating mid-turn: `ComputerUseURLBlocklistCache`, SSRF protection for
  private/reserved IPs, "stopped due to encountering a disallowed URL".
- Approval surfaced through MCP `elicitation/create` with per-app persistence;
  auto-deny path exists.
- Messages sending has a dedicated gate (`MessagesPermissionGate`,
  recipient + text approval), matching the service's Apple Events + Contacts
  entitlements.

### Screen-unlock machinery (out of scope, recorded)

The installer writes a SecurityAgent plugin to
`/Library/Security/SecurityAgentPlugins/` and edits `system.login.screensaver` in
the authorization database, so an active Computer Use turn can auto-unlock the Mac.
The plugin verifies the requesting service's audit token, code-signing identifier,
and team ID over a dedicated socket before honoring an unlock, and
`CUALockScreenGuardian` bails on real physical input. Suniye has nothing comparable
and does not need it for KIS-179.

### Screenshots and transport

ScreenCaptureKit (`SCStream`/`SCContentFilter`) with JPEG encoding and a
configurable compression quality — same engine and format family as Suniye. IPC is
primarily XPC (`ComputerUseIPCXPCTransport`) with the JSON-RPC unix socket as a
second path; upstream control plane is line-delimited JSON-RPC to the Codex app
server.

## Mechanics: node_repl execution

From static string/AST inspection of `Contents/Resources/cua_node/`. `[Verified]`
unless marked.

- The runtime is a private **Node 24.19.0** (`cua_node/manifest.json`), not the OS
  Node. `node_repl` is a **Rust MCP server** (rmcp 1.5.0) that spawns `bin/node`
  with `--experimental-vm-modules` and talks JSONL over stdio to an embedded
  `kernel.js`.
- The tool the model calls is named **`js`** (server `node_repl`, also `js_reset`
  and `js_add_node_module_dir`), default timeout **30 s**, host-enforced (kernel
  reset on expiry). The prose "node_repl" in the skill maps to this `js` tool.
- **Top-level await** works because each execution is compiled as a fresh **ESM
  cell** (`new SourceTextModule(...)`), not an async wrapper.
- **Cross-call persistence** is a synthetic-module bridge: the new cell imports
  `"@prev"`, a `SyntheticModule` re-exporting the previous namespace, and the
  kernel **AST-rewrites** submitted source (meriyah parser) to redeclare carried
  names and emit commit markers so a binding is carried forward only once it
  finished initializing. `var` is redeclarable across cells; `const`/`let` are not
  (re-decl throws "already declared"). This is heavy machinery.
- **Two vm contexts**: untrusted (model code) and trusted (hash/path-allowlisted
  packages like `@oai/sky`). Isolation is a vm-context boundary. Model code is
  denied `process`; env is an allowlisted frozen snapshot; only builtins pass a
  narrow denylist. The Node child additionally runs under an OS sandbox
  (network-isolation + unix-socket allowlist; a hard "gaas-browser" mode). Running
  `js` itself triggers an approval elicitation with strict auto-review.
- Output: `console.log` and `nodeRepl.write(value)` are captured per-exec
  (`write` adds no newline); `nodeRepl.emitImage`/`emitAudio` return media items.
  No byte cap on `output` in the kernel (`[Inferred]` host-side cap); the only
  kernel truncation is a 16 KiB redacted source echo for logging.

## Consequence for Suniye: we do not replicate the persistence machinery

The reference's ESM-cell + synthetic-module-bridge + AST-rewrite design exists
because `node_repl` is a **general-purpose** Node REPL shared across skills
(Playwright, fs, OCR, arbitrary `import`) that must persist bindings across many
calls and load untrusted packages. That is what forces Node, two vm contexts,
seatbelt, network isolation, and trust hashing.

Suniye's code-mode is **computer-use-only**. The single capability is `sky`, which
we bridge to native Swift — there is no package loading, no `import`, no fs, no
network, no `process`. That collapses the whole design:

- **JavaScriptCore is a capability-empty sandbox by default.** A fresh `JSContext`
  exposes no filesystem, network, or process. We inject exactly `sky` and
  `nodeRepl.write`. The model cannot reach anything else — so we need none of the
  reference's seatbelt/network-isolation/trust-hash apparatus.
- **We do not persist top-level bindings across calls, by design.** The reference
  needs persistence mainly for its once-per-session bootstrap; we pre-inject `sky`,
  so that reason is gone. And the reference's own workflow tells the model to
  re-derive element indexes from the latest observation every turn — stale
  cross-call state is already discouraged. So each `node_repl` call is
  self-contained. This lets us wrap each call in an async IIFE (top-level await
  works) without the meriyah AST rewrite and synthetic-module bridge. The prompt
  states plainly that top-level state does not carry between calls — the opposite
  of the reference, and aligned with re-observe-each-turn.
- The one genuinely hard part that remains is bridging JS `Promise`s to Swift
  `async` and pumping the JSC microtask queue until the top-level promise settles
  or a wall-clock timeout fires. That is the crux of `ComputerUseScriptRuntime`.
- Lift verbatim into our tool description: default **30 s** per-call timeout and
  the "output added without newline" semantics of `nodeRepl.write`.

## Consequences for KIS-179 (Suniye code-mode)

1. The mac production surface is still the ten app-scoped methods — Suniye's existing
   `ComputerUseToolCall` maps 1:1. Code-mode does not require adopting window2.
2. The bootstrap in the prompt reduces to one line; for Suniye the `sky` object is
   pre-injected and the bootstrap section disappears entirely.
3. `press_key` chord documentation (X-keysym + aliases) should be lifted into our tool
   schema description verbatim; our current description is thinner.
4. The "app-specific guidance on first access" pattern is worth copying later
   (per-app hint text prefixed to the first observation), tracked separately.
5. window2's screenshot-first observation (`include_text: false` default) and layered
   transient-UI screenshots are directionally informative for token cost but are a
   different product generation; out of KIS-179 scope.
