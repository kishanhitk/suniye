# DMG click and recovery verification

Research date: 2026-08-12

Scope: only `click(element_index)`, `AXPress`, `AXSelected`, coordinate/pointer fallback,
fresh observation, no-change recovery, and provider/network retries in the mounted first-party
ChatGPT/Codex bundle from `/Users/kishan/Downloads/ChatGPT (1).dmg`. The initial inspection was
read-only. The implementation and validation completed afterward are recorded at the end.

## Evidence labels

- **Verified**: directly readable source, binary string/symbol, or decoded branch in this bundle.
- **Inferred**: the narrowest interpretation consistent with verified evidence.
- **Unknown**: not established by the inspected artifact.

## Inspected artifact

- **Verified**: the DMG is mounted read-only at `/Volumes/ChatGPT Installer`; the requested
  `/private/tmp/suniye-chatgpt-dmg-mount` directory exists but was empty during this inspection.
- **Verified**: `ChatGPT.app` reports version `26.727.51351` and build `6119`.
- **Verified**: bundled `@oai/sky` is version `0.6.2`.
- **Verified**: SHA-256 identities used for this note:
  - `SkyComputerUseService`: `bbf2b878b2c1b1d5d7c0b7184443cd688952801a03094c276f82b734f90ea777`
  - Computer Use runtime prompt: `a52ede355c6637d05be9da5e3f19dbfd5f23fa5ec4c9513e3188bc8a57429c79`
  - `codex`: `d96ae1ca1ff6fc8587842fa04c92d3ee4d31651a811c2f89b65fcfd9c28473e2`

## 1. `click(element_index)`

### JavaScript boundary

- **Verified**: `click.js` forwards `app`, `click_count`, `element_index`, `mouse_button`, `x`,
  and `y` to `MacComputerUseClient.click`; it contains no click algorithm or fallback itself.
  [Source: `ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/dist/project/cua/sky_js/src/targets/mac/click.js:1`]
- **Verified**: `client.js` encodes an indexed click as
  `action.click.at.elementID = String(elementIndex)` and a coordinate click as
  `action.click.at.coordinate = [x, y]`. Default click count is `1`; default mouse button is left.
  [Source: `.../@oai/sky/dist/project/cua/sky_js/src/targets/mac/client.js:1`]
- **Verified**: the public type describes `element_index` as coming from the latest
  `get_app_state()` text and describes click as either indexed or coordinate based.
  [Source: `.../@oai/sky/dist/project/cua/sky_js/src/types/window/Click.d.ts:3-18`]

### Native semantic action selection

- **Verified**: the native helper exposes
  `UIElementProtocol.click(... alwaysSimulateClick: Bool, in: WindowUIElement, app:
  ApplicationUIElement, ...)` at `0x100753984`. Its decoded async body begins at
  `0x100757544`.
  [Source: `.../Codex Computer Use.app/Contents/MacOS/SkyComputerUseService`, `nm` plus ARM64
  disassembly]
- **Verified**: the decoded click body checks the element's exposed actions for `AXPick` first
  (`static UIElementAction.pick` at `0x1010da258`), then `AXPress`
  (`static UIElementAction.press` at `0x1010da248`). The relevant branch is
  `0x100757630-0x10075775c`.
- **Verified**: for the ordinary semantic branch, the click must have an exposed `AXPick` or
  `AXPress`, use the left mouse button, have a click count below two, and have
  `alwaysSimulateClick == false`. Otherwise execution enters the simulated-click side of the
  method and obtains the element's `clickablePoint()`. The decisive branch is
  `0x100757768-0x100757810`; `clickablePoint()` is at `0x100742b1c`.
- **Verified**: the bundle contains feature flag `feature/computerUseAlwaysSimulateClick` with
  description `Prefer simulating physical clicks over Accessibilty actions.`
  [Source: `SkyComputerUseService`, binary strings]

### `AXSelected` correction

- **Verified**: `AXPress` and `AXPick` are Accessibility **actions**. `AXSelected` is an
  Accessibility **attribute** represented separately by `UIElementAttribute.selected`; the
  helper also has an `isSelected` getter for reading selection state.
  [Source: `SkyComputerUseService` symbols at `0x100730874`, `0x1007308e0`,
  `0x10073dff4`, and `0x10074af00`]
- **Verified**: the decoded normal click-action selection uses `AXPick`/`AXPress`, not
  `AXSelected`.
- **Verified**: no direct write of `UIElementAttribute.selected` appears in the decoded
  `UIElementProtocol.click` body. Therefore treating a successful `AXSelected = true` write as a
  successful primary click is not supported by this reference path.
- **Unknown**: whether an app-specific or lower-level indirect helper ever writes `AXSelected` on
  an edge path. The artifact does not justify claiming that it never happens anywhere in the
  service.

### Pointer fallback boundary

- **Verified**: the helper contains app-scoped input primitives:
  `ApplicationUIElement.sendClick`, `SynthesizedEvent.click`, and `CGEventAPI.postToPid`.
  `SynthesizedEvent.click` accepts a point, drag endpoint, mouse button, click count, flags,
  optional window ID/bounds, and flipped-coordinate state.
  [Source: `SkyComputerUseService` symbols at `0x10067836c` and `0x1006b2f9c`, plus imported
  event APIs]
- **Verified**: the click method has a simulated-click branch and first resolves a clickable
  point for the indexed element.
- **Inferred**: this branch ultimately uses the service's app-scoped synthesized-event machinery;
  the available symbols and surrounding architecture strongly support that reading.
- **Unknown**: the exact complete fallback sequence for every role and failure condition—for
  example, whether every failed `AXPress` is retried as a pointer click, which focus-enforcement
  branch is selected, and which native errors suppress fallback. The optimized indirect branches
  do not prove a single universal rule. Suniye should not invent one and call it verified parity.

## 2. Fresh observation and stale element handling

- **Verified**: the native tool description for `get_app_state` says it `must be called once per
  assistant turn before interacting with the app`.
  [Source: `SkyComputerUseService`, binary string adjacent to the public MCP tool schema]
- **Verified**: the model-facing Computer Use prompt says to start with `get_app_state` when the
  target app is known. After one or more UI actions, it says to call `get_app_state` before the
  next decision and re-derive fresh element indexes instead of reusing stale ones.
  [Source: `ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/computer-use-node-repl.md:67-100`]
- **Verified**: if prior Accessibility text was disregarded, the prompt says to request a fresh
  full tree with `disableDiff: true`; normal observations may return an AX diff.
  [Source: `computer-use-node-repl.md:84-86`]
- **Verified**: native indexed interaction has a second, separate stale-element defense. The
  controller keeps a refetchable AX tree, attempts to refetch invalidated elements, and returns
  explicit errors for invalid IDs and ambiguous matches before or after refetch.
  [Source: `SkyComputerUseService` symbols `ComputerUseAppController.prepareToInteract` at
  `0x100069e14` and `RefetchableSkyshotAXTree`; associated binary error strings]

These are complementary rules: the model must observe at least once per assistant turn, while the
native helper may still refetch an element that became stale between observation and action.

## 3. No-change recovery

- **Verified**: when UI behavior is unexpected, the prompt tells the model to fetch the latest
  state. It prefers Accessibility indexes, but tells the model to switch to screenshots,
  coordinate clicks, and key presses when AX is incomplete or behaves unexpectedly.
  [Source: `computer-use-node-repl.md:103-117`]
- **Verified**: the runtime automatically waits about one second after recent actions and can
  extend the wait by up to about five seconds when loading or state-change indicators are present.
  [Source: `computer-use-node-repl.md:117`]
- **Verified**: the prompt does not specify a numeric repeated-no-change threshold, a fixed click
  retry count, or a deterministic rule that chooses an actionable descendant.
- **Unknown**: provider-private reasoning may still learn to abandon repeated no-op clicks, but
  that cannot be recovered from the client bundle. A Suniye-specific no-change counter would be an
  independent product choice, not verified reference parity.

## 4. Retry behavior

### App identifier retry

- **Verified**: when an action or observation fails for an app display name, the prompt instructs
  the model to retry the same operation with the bundle identifier returned by `list_apps()`.
  This is target-resolution recovery, not a network retry.
  [Source: `computer-use-node-repl.md:113-117`]

### Sky native-pipe retry

- **Verified**: `MacNativePipeTransport.create` first attempts a native-pipe connection for
  250 ms. If unavailable, it asks the trusted host service to ensure/launch Computer Use, then
  retries connection for up to five seconds. Connection attempts sleep for 100 ms between tries.
  [Source: `.../@oai/sky/dist/project/cua/sky_js/src/targets/mac/native-pipe.js:1`, constants
  `U = 5000`, `connect(..., 250)`, `connect(..., 5000)`, and `R(100)`]
- **Verified**: an already-issued native action request is not automatically replayed by this JS
  client. `MacComputerUseClient.request` deletes a closed cached transport and rethrows the error;
  it does not call the action again.
  [Source: `.../@oai/sky/dist/project/cua/sky_js/src/targets/mac/client.js:1`]

### Model-provider retry

- **Verified**: the bundled `codex` host contains separate configuration fields
  `request_max_retries` and `stream_max_retries` and the runtime string
  `stream disconnected - retrying sampling request (`. This proves a provider sampling-stream
  retry path exists outside `@oai/sky`.
  [Source: `ChatGPT.app/Contents/Resources/codex`, binary strings]
- **Unknown**: this bundle inspection does not establish the active default retry counts, exact
  backoff, full retryability classification, or whether a particular `network connection was
  lost` error is retried after partial response content. Those details must not be guessed.

### Current public Codex retry source

- **Verified**: current public OpenAI Codex source defines four request retries and a 200 ms base
  delay. It retries transport errors and HTTP 5xx responses, does not retry HTTP 429, and applies
  exponential backoff with jitter in the range `0.9 ..< 1.1`.
  [Sources: `openai/codex` `codex-rs/model-provider-info/src/lib.rs` and
  `codex-rs/codex-client/src/retry.rs`, inspected 2026-08-12]
- **Verified**: this source is independent evidence from the current public Codex repository. It
  is not proof that the inspected DMG build used exactly the same defaults.

## Implementation consequence for Suniye

The strongest parity-supported correction is narrower than a generic fallback policy:

1. Do not treat `AXSelected = true` as successful primary-click activation.
2. For an indexed ordinary click, prefer an exposed `AXPick`, then an exposed `AXPress`.
3. Preserve a distinct simulated-click path, including an `always simulate click` policy input,
   but do not claim an exact universal AX-failure-to-pointer fallback until that branch is proven.
4. Require `get_app_state` once per assistant turn before app interaction and reobserve after one
   or more actions before the next decision.
5. Keep native-pipe startup retry, action replay, and model-provider retry as three separate
   policies; the reference does not conflate them.

## Implementation update

Completed on 2026-08-12:

- Replaced Suniye's semantic primary-click order with exposed `AXPick`, then exposed `AXPress`.
- Removed `AXSelected` writes from primary-click handling.
- Routed non-single clicks and elements without either semantic action through the existing
  process-scoped synthesized-click path.
- Added the recovered once-per-assistant-turn observation requirement to the model-facing tool
  description and instructions.
- Added provider-request retry behavior matching the current public Codex defaults described
  above. This retries only the model HTTP request; it never replays a native action.
- Added regression coverage for click order, simulated fallback, observation wording, retry
  budget, backoff, and non-retryable failures.

Validation:

- Focused Computer Use suite: 31 tests passed.
- Full macOS suite: 1,150 tests passed, 2 skipped, 0 failures.
- Gated line coverage: 87.12% at an 80% threshold.
- `scripts/e2e_preflight.sh`: passed.
- `scripts/e2e_smoke.sh`: passed.

## Live invoice-task comparison

Completed on 2026-08-12 with the bundled Computer Use runtime against Google Chrome and Gmail.

- **Verified**: the reference runtime completed the natural task of finding the MacBook invoice
  and reporting its invoice number.
- **Verified**: it first narrowed the Gmail search from a broad Apple query to
  `from:(apple.com) MacBook`.
- **Verified**: clicking the fresh AX link for the invoice did not immediately open the message.
  A fresh observation showed that the correct Gmail result row had focus. The runtime then sent
  Return, observed again, and read the opened invoice.
- **Verified**: this recovery was generic model/tool behavior. It did not use a Gmail-specific
  native action or deterministic result matcher.
- **Verified**: Suniye session `CU-AD39742777B5` repeatedly clicked correct-looking invoice
  candidates, but the focused Gmail row remained a different result. Subsequent Return and arrow
  keys therefore acted on the wrong row.

### Recovered window-targeted event details

Targeted disassembly of `SynthesizedEvent.mouseEvent` at `0x1006b3fb8` establishes the missing
native metadata:

- **Verified**: when a window ID is available, the helper writes it to Core Graphics mouse event
  fields `91` and `92`, corresponding to `mouseEventWindowUnderMousePointer` and
  `mouseEventWindowUnderMousePointerThatCanHandleThisEvent`.
- **Verified**: when window bounds are available, the helper changes the event location from a
  global screen point to a window-local point. It subtracts the window origin and conditionally
  inverts local Y using the window height.
- **Verified**: the native target object retains PID, Accessibility window, window ID, window
  bounds, and flipped-coordinate state.
- **Verified**: Suniye previously posted only a global point to the PID. It omitted both window
  fields and the window-local location.

### Suniye correction

- **Implemented**: Suniye pointer events now receive the currently observed PID, window ID,
  window bounds, and coordinate-orientation state.
- **Implemented**: click, drag, and scroll events set both recovered Core Graphics window fields
  and use the recovered window-local coordinate conversion before posting to the target PID.
- **Verified by test**: 15 focused action-service tests pass, including local-coordinate,
  Y-inversion, and exact target-forwarding coverage.
- **Verified live**: installed Preview session `CU-98FF617A7580` completed the natural task
  `Open the MacBook invoice email in Chrome and tell me the invoice number.` in seven tool calls:
  observe, set the Gmail query, observe, press Return, observe, click the result, and observe.
  The final state contained the opened Apple invoice body and attachment, and Suniye returned the
  correct invoice number `MC59950569`.

### Gmail field focus and stale-result recovery

- **Verified**: the packaged helper's `set_value` changes Gmail's `Search mail` value and leaves
  that exact text field focused. A following app-scoped `press_key` with `Return` submits the
  search. This was reproduced live with the bundled Computer Use helper.
- **Verified**: Suniye previously changed the field value without focusing it. Its following
  app-scoped Return produced no Accessibility change, leaving old search results visible. The
  model then reported an invoice number from that stale result set.
- **Implemented**: Suniye now attempts to set `AXFocused = true` on a focusable set-value target
  before writing `AXValue`. Focus remains best effort for value-settable elements that do not
  expose a settable focus attribute.
- **Verified**: the packaged helper appends the currently focused UI element to a full state
  response as well as to a diff. Suniye previously appended it only to diffs.
- **Implemented**: Suniye now appends the focused element to every Accessibility response. This
  keeps the focus fact at the end of a large tree, where middle truncation cannot discard it.
- **Implemented**: model instructions now state that existing app content may belong to an
  earlier task and must match the current request before the agent acts on it.
- **Implemented**: after two actions each produce an explicit unchanged Accessibility
  observation, the agent requests a different recovery strategy instead of allowing an unbounded
  sequence of near-identical coordinate clicks.

### Final validation

- **Verified live**: Suniye session `CU-98FF617A7580` returned invoice number `MC59950569` from
  the opened Apple invoice after seven tool calls. An independent fresh Chrome observation
  confirmed the same invoice number in the Gmail message body.
- **Verified**: the complete macOS test suite passed with 1,155 tests executed, 2 skipped, and
  0 failures.
- **Verified**: gated line coverage was 87.16% (`14,624 / 16,778`) against the 80% requirement.
- **Verified**: `scripts/e2e_preflight.sh` and `scripts/e2e_smoke.sh` passed.
