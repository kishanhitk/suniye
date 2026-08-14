# Computer Use bootstrap and self-target parity

- Date: 2026-08-08
- Primary artifact: `<home>/Downloads/ChatGPT (1).dmg`
- Inspection mount: `/private/tmp/suniye-chatgpt-dmg-mount` (read-only)

This note is limited to initial app selection, `frontmost`, host-app control, conversational input, app-list filtering, and self-target enforcement. It does not claim behavior that is only available from a provider-side prompt, model, or service.

## Evidence labels

- **Verified**: directly present in the mounted artifact.
- **Inferred**: strongly suggested by multiple artifact facts, but not directly executable or fully recoverable from the artifact.
- **Unknown**: the artifact does not establish the behavior.

## Artifact identity

- **Verified**: DMG SHA-256: `45ec006a0f3f0fa004b6fd4d6d5529979a05361f995ca2c51de3a3b04deee123`.
- **Verified**: `ChatGPT.app` identifies itself as `CFBundleIdentifier = com.openai.codex`, version `26.727.51351`, build `6119`.
  - Source: `ChatGPT.app/Contents/Info.plist`.
- **Verified**: `app.asar` SHA-256: `a529edd72e10b08931c0d695b5e3e6a0be7f51874610dafc04f578436ab7d74d`.
- **Verified**: native Computer Use service SHA-256: `bbf2b878b2c1b1d5d7c0b7184443cd688952801a03094c276f82b734f90ea777`.
  - Source: `ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService`.

## Conclusions

| Question | Finding |
| --- | --- |
| Is `frontmost` the packaged Computer Use bootstrap? | **Verified: no such bootstrap is exposed.** The documented bootstrap is an explicit app name/identifier, or `list_apps()` when the app cannot be identified. |
| Does the public Computer Use app list expose which app is frontmost? | **Verified: no.** The native record has `isFrontmost`, but the public `list_apps()` mapper drops it. |
| Why does `computer-use-frontmost-window` exist? | **Verified:** it supports Appshots and realtime screen context in the host app. It is separate from the packaged Computer Use tool surface. |
| Can ordinary Computer Use target the host app? | **Inferred: it is intended to be forbidden.** Native symbols define ChatGPT/Computer Use host bundle groups and a forbidden-target classifier, and the policy wrapper blocks `forbidden` targets before observation or action. Exact array membership could not be executed from the read-only artifact. |
| How is `Hello` handled? | **Partly verified, final behavior unknown:** the DMG contains the static GPT-5.6 base instructions and Computer Use tool-selection instructions. It does not contain a captured live turn proving the final routing decision for `Hello`. No deterministic `Hello` target matcher was found. |
| Where does self-target enforcement live? | **Verified:** target classification and policy are native-service responsibilities; the JavaScript wrapper requests that policy and rejects `forbidden` before `get_app_state` and actions. |

## 1. Initial target and app selection

### Explicit app first

- **Verified**: the packaged Computer Use instructions say: “Start by getting the state for the app you want to use. When the task names an app, use that name directly.” The example calls `get_app_state({ app: "com.google.Chrome" })`.
  - Source: `ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/computer-use-node-repl.md:67-76`.
- **Verified**: only when the app cannot be identified from the task, prior context, or built-in apps do the instructions call `list_apps()`.
  - Source: same file, lines `78-82`.
- **Verified**: the instructions explicitly say not to call `list_apps()` merely to resolve a named app. They say to try `get_app_state` with the app name first.
  - Source: same file, lines `113-116`.
- **Verified**: the low-level Mac client rejects a missing or blank `app` with `TypeError("app is required")`.
  - Source: `ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/cua/dist/project/cua/sky_js/src/targets/mac/client.js`, function `d(e)` on minified line 1.

### `frontmost` is not exposed as Computer Use bootstrap state

- **Verified**: the public Mac Computer Use surface created by `create_client` is exactly `target`, `list_apps`, `get_app_state`, and app-scoped actions. It exposes no `frontmost` or `get_frontmost_app` operation.
  - Source: `.../targets/mac/create_client.js:1`, returned object in function `a`.
- **Verified**: the public `App` shape has `id`, `displayName`, `lastUsedDate`, `useCount`, and `isRunning`; it has no `isFrontmost` field.
  - Source: `.../computer-use-node-repl.md:44-50`.
- **Verified**: the native client type does contain `isFrontmost?: boolean` on `SkyDiscoveredApp`.
  - Source: `.../targets/mac/client.d.ts:4-12`.
- **Verified**: `list_apps.js` deliberately maps only bundle/display identity, running state, last-used date, and use count. It drops both `appPath` and `isFrontmost`.
  - Source: `.../targets/mac/list_apps.js:1`, the `.map(...)` return object.
- **Unknown**: whether a provider-side prompt or model not stored in the DMG ever uses the literal string `frontmost` as an internal planning concept.
- **Verified**: nothing in the artifact’s exposed Computer Use bootstrap supports passing `target=frontmost` as a special target. A literal `frontmost` passed as `app` would enter ordinary app resolution; the artifact does not define it as a sentinel.

## 2. What `computer-use-frontmost-window` actually does

- **Verified**: the Electron host registers `"computer-use-frontmost-window": async () => process.platform === "darwin" ? Ao() : null`.
  - Source: `ChatGPT.app/Contents/Resources/app.asar`, byte offset `3,808,770`; bounded text begins at offset `3,807,270`.
- **Verified**: realtime screen context first checks whether the host’s primary window is focused. If it is, it returns a lightweight host page/thread summary. Otherwise it invokes `computer-use-frontmost-window` and captures an Appshot of the foreground app.
  - Source: `app.asar`, byte offset `25,512,923`; bounded text begins at `25,511,423`.
  - Relevant symbols/strings: `capture_screen_context`, `route: codex_app_state`, `route: appshot`, and `computer-use-frontmost-window`.
- **Verified**: the composer Appshot hotkey also refetches `computer-use-frontmost-window` before starting an Appshot capture.
  - Source: `app.asar`, byte offset `31,865,550`; bounded text begins at `31,864,050`.
- **Verified**: these `frontmost` references belong to host screen-context/Appshot capture. They are not exported by `.../targets/mac/create_client.js` and are not part of the Computer Use skill’s API surface.
- **Unknown**: whether any provider-side agent orchestration, absent from the DMG, independently requests foreground context before choosing a Computer Use app.

## 3. Host-app observation and control

### A separate self-observation path exists

- **Verified**: when the host app itself is foreground, `capture_screen_context` does not run ordinary Accessibility/screenshot Computer Use against itself. It returns an internal lightweight page/thread summary through `app.get_summary`.
  - Source: `app.asar` around byte offset `25,512,923`.
- **Verified**: this is a separate screen-context tool path. It is not evidence that ordinary `get_app_state`, `click`, or `type_text` can target `com.openai.codex`.

### Ordinary Computer Use passes through app policy

- **Verified**: `get_app_state.js` wraps native state capture in `withComputerUsePolicy("get_app_state", ...)`.
  - Source: `.../targets/mac/get_app_state.js:1`.
- **Verified**: action adapters do the same. For example, `click.js` calls `withComputerUsePolicy("click", ...)`, and `type_text.js` calls `withComputerUsePolicy("type_text", ...)` before invoking the native client.
  - Sources: `.../targets/mac/click.js:1`, `.../targets/mac/type_text.js:1`.
- **Verified**: `withComputerUsePolicy` asks the native service for `getAppPolicy(app)`. A `forbidden` decision throws: `Computer Use is not allowed to use the app '<bundleIdentifier>' for safety reasons.`
  - Source: `.../targets/mac/computer-use-policy.js:1`, function `p`, decision switch in its nested function.
- **Verified**: the native helper exports these Swift symbols:
  - `SystemSoftware.BundleIdentifiers.computerUseHostBundleIdentifiers`
  - `SystemSoftware.BundleIdentifiers.chatGPTBundleIdentifiers`
  - `SystemSoftware.BundleIdentifiers.allowsForbiddenComputerUseTargets`
  - `SystemSoftware.BundleIdentifiers.isForbiddenComputerUseTarget(_:)`
  - Source: `SkyComputerUseService`; `nm -nm | xcrun swift-demangle` addresses `0x100212304`, `0x1002123a8`, `0x10021255c`, and `0x1002125ec` respectively.
- **Verified**: the same native binary contains the bundle strings `com.openai.codex`, `.alpha`, `.beta`, `.dev`, and `.nightly`, plus ChatGPT Mac variants, in the contiguous string region beginning at decimal file-string offset `15,090,656`. It also contains `ComputerUseAllowForbiddenTargets` at `15,092,080`.
- **Inferred**: `com.openai.codex` is a member of the native `chatGPTBundleIdentifiers` forbidden-target group. The symbol names, adjacent bundle strings, forbidden-target predicate, and override key all support this, but static string extraction alone does not prove the exact runtime array contents.
- **Inferred**: ordinary Computer Use is therefore intended to reject observation and control of the host app before native capture/action execution.
- **Unknown**: the exact full forbidden-target list and any build/configuration conditions that alter it. The override symbol exists, but the DMG does not document supported production use of that override.

## 4. Conversational input such as `Hello`

- **Verified**: the packaged skill describes Computer Use as a capability for tasks that require “reading or operating app UI.” It also says to prefer a dedicated interface when one can complete the task.
  - Source: `.../computer-use-node-repl.md:2-10`.
- **Verified**: no deterministic mapping from `Hello`, greetings, or other conversational text to `frontmost`, a running app, or any app bundle identifier was found in the packaged Computer Use plugin, Mac client, or native symbol/string evidence inspected for this note.
- **Verified**: the DMG contains the static GPT-5.6 base instructions and the complete readable
  Computer Use operating instructions. The latter scopes Computer Use to tasks that require reading
  or operating local app UI and says to prefer dedicated interfaces when available.
  - Sources: `recovered-prompts/gpt-5.6-base-instructions.md` and
    `recovered-prompts/computer-use-node-repl.md`.
- **Verified**: the client-side request-construction algorithm, message ordering, and selected-model
  field are recovered. A loopback capture from the DMG binary verifies those mechanics.
- **Unknown**: the resulting model response for a production `Hello` turn, because that specific
  remote turn was not executed or captured.
- **Inferred**: because `Hello` neither names an app nor requests reading/operating app UI, the intended routing is a normal conversational response without starting Computer Use. This is a routing inference from the skill scope, not a recovered hidden rule.

## 5. App-list filtering

- **Verified**: the JavaScript `list_apps()` adapter applies no explicit filter. It calls native `listApps()`, maps returned records, and returns them.
  - Source: `.../targets/mac/list_apps.js:1`.
- **Verified**: `list_apps()` is not wrapped in `withComputerUsePolicy`; it only clears response metadata and adds telemetry.
  - Source: same file.
- **Verified**: filtering capability exists inside the native helper. Its Swift symbol is:
  - `ComputerUse.AppUsageCatalog.loadApps(excluding: Set<String>, frontmostExcludingBundleIdentifier: String?, timeout: Duration?)`
  - Source: `SkyComputerUseService`, demangled symbol at address `0x1000498d4`.
- **Verified**: the native IPC list handler is:
  - `ComputerUseIPCListAppsRequest.handle(senderContext:)`
  - Source: `SkyComputerUseService`, demangled symbol at address `0x100130378`.
- **Unknown**: the exact `excluding` set and `frontmostExcludingBundleIdentifier` passed by that compiled async handler in this build. Symbol inspection proves the filtering seam, not its runtime arguments.
- **Unknown**: whether `list_apps()` omits the host app, returns it and relies on policy to forbid it, or varies by sender context. The DMG’s readable JavaScript does not answer this, and the native async body could not be safely executed in isolation.
- **Verified**: even if the native result records which discovered app is frontmost, that property is removed by the public JavaScript mapper. Therefore public `list_apps()` cannot be used to implement a reference-equivalent “pick the frontmost app” rule.

## 6. Enforcement boundary

The artifact supports this boundary:

1. **Verified**: the model-facing tool must provide an explicit `app` for observation and actions.
2. **Verified**: the JavaScript adapter requests native app policy before `get_app_state` and every inspected action.
3. **Verified**: the native service owns target resolution, policy classification, forbidden-target categories, and the final `allowed` / `denied` / `forbidden` decision.
4. **Verified**: the JavaScript policy wrapper converts `forbidden` into a safety error before calling the observation/action closure.
5. **Verified**: `list_apps()` follows a separate discovery path and does not itself run the per-app policy wrapper.
6. **Unknown**: whether additional provider-side self-target instructions exist outside the artifact.

Self-target enforcement is therefore not a model prompt-only rule. The directly verified enforcement points are the native app-policy result and the JavaScript policy gate around observation/actions.

## Parity implications limited to this evidence

- Do not treat `target=frontmost` as reference behavior. It is absent from the exposed Computer Use bootstrap and public app data.
- Do not add a text matcher that maps greetings or nouns to apps. No such matcher was found.
- Keep conversational routing separate from desktop execution. The exact model decision remains Unknown, but the packaged skill scopes Computer Use to actual UI tasks.
- Keep self-target safety at the app-policy/target-resolution boundary, before observation and actions. Do not rely only on prompting.
- Do not invent an app-list exclusion set from the bundle strings. The existence of native filtering is Verified; its exact runtime arguments are Unknown.

## Inspection limitations

- The DMG was inspected read-only.
- The native helper is compiled Swift. Exported symbols and embedded strings were available, but source and the exact async list-handler body were not.
- Attempting to launch the artifact under LLDB to print the static bundle arrays was denied by macOS attach policy. No array contents were claimed as Verified from that failed attempt.
- The packaged Node wrapper could not be executed in the available trusted REPL because its required `NODE_REPL_NODE_MODULE_DIRS` bootstrap environment is immutable in that session. No live output from a different installed Computer Use build was substituted as artifact evidence.
- The static model base instructions and Computer Use operating instructions are present and have
  been recovered from the DMG. Client-side model selection, runtime composition, and role ordering
  are also recovered. Provider-private inference and the response to an unexecuted production turn
  remain Unknown.
