# Native Computer Use algorithm recovery

Research date: 2026-08-09

Scope: the native Computer Use client and helper shipped in
`<home>/Downloads/ChatGPT (1).dmg`, plus symbol, import, string, and targeted ARM64
disassembly inspection. The native client was exercised only with read-only `list_apps` and
`get_app_state` calls against Calculator. No Suniye production code was changed.

## Evidence labels

- `[Verified]` is shown by a live call to this DMG build, an exported function signature, an
  imported API, a readable wrapper, or decoded control flow.
- `[Inferred]` is the narrowest explanation consistent with verified evidence.
- `[Unknown]` is not established by the inspected evidence.

## Corrected conclusion

The earlier statement that native behavior was unavailable because the helper is compiled was too
broad.

- `[Verified]` The public native protocol, exact ten-tool schema, live app-catalog format, live AX
  rendering, screenshot MIME type, background observation behavior, major service types, macOS API
  calls, event-synthesis paths, AX revision/diff machinery, and coordinate conversion are
  recoverable.
- `[Verified]` Many internal Swift names and complete method signatures are preserved in the helper.
- `[Verified]` Targeted ARM64 disassembly recovers concrete implementation details where symbols
  alone are insufficient.
- `[Unknown]` A symbol name proves that a path exists, but not every branch condition or ranking
  rule inside large optimized async functions. Those remaining points require complete decompilation
  plus validation, source access, or a controlled live matrix. They are listed precisely below.

## Exact inspected binaries

Service:

`ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService`

MCP client:

`ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient`

The client launches as `cua` and exposes `mcp`, `event-stream`, `computer-history`, `messages`, and
`turn-ended` subcommands.

## Live DMG-native MCP session

The shipped `SkyComputerUseClient mcp` process completed an MCP initialize handshake and reported:

- server name: `Computer Use`;
- server version:
  `14e7d17f1f59e77ca541a15071e980628cd08977a4dda111c96e0564d337056b`;
- tool capability with `listChanged: false`.

### Exact ten tools

The live `tools/list` response exposed exactly:

1. `list_apps`
2. `get_app_state`
3. `click`
4. `perform_secondary_action`
5. `set_value`
6. `select_text`
7. `scroll`
8. `drag`
9. `press_key`
10. `type_text`

`list_apps` and `get_app_state` are annotated read-only and idempotent. The eight action tools are
annotated non-read-only and non-idempotent. Every action and observation accepts an app value;
there is no session-wide public target lock.

### Live application catalog

`list_apps` says it returns:

- currently running applications;
- applications used within the last 14 days;
- usage-frequency details.

The live result rendered each application as:

`display name — full path — bundle identifier [frontmost?, running?, last-used date?, uses?]`

The result included running and historical applications. It marked WhatsApp as `frontmost`, while
Calculator was running but not frontmost.

The compiled service retains these app fields:

- `displayName`
- `bundleIdentifier`
- `appPath`
- `targetIdentifier`
- `lastUsedDate`
- `useCount`
- `isRunning`
- `isFrontmost`

Its catalog entry point is:

`AppUsageCatalog.loadApps(excluding:frontmostExcludingBundleIdentifier:timeout:)`

### Live target resolution and approval

The exact live `get_app_state` schema describes `app` as:

`App name, full app path, or unambiguous bundle identifier`

The first Calculator request emitted an MCP elicitation:

`Allow ChatGPT to use Calculator?`

The elicitation metadata allowed an `always` persistence choice. After an accepted response, the
state call completed. This directly verifies that target policy/approval runs before the native app
state is returned.

### Background observation is verified

Two `get_app_state(app: "Calculator")` calls succeeded and returned Calculator state and a
screenshot. A subsequent `list_apps` call still marked WhatsApp, not Calculator, as frontmost.

Therefore:

- `[Verified]` The reference can capture and inspect a running target app while another app remains
  frontmost.
- `[Verified]` `get_app_state` does not inherently bring its target application to the foreground.
- `[Unknown]` Particular action paths may still synthesize focus for the target internally when
  input requires it.

## Exact live AX rendering

The Calculator response identified:

- CUA app version `1000550`;
- app path, bundle identifier, and pid;
- window title and app name;
- a flattened accessibility tree with integer element identifiers.

The observed text format is a depth-indented preorder rendering. Each line can include:

- integer element identifier;
- AX role and role-specific name;
- `Description`;
- `Help`;
- stable application-provided `ID` when present;
- `(disabled)` state;
- `Secondary Actions`.

The live tree included the standard window, split group, Calculator keypad container, result text,
buttons, toolbar controls, window buttons, and menu bar. Element IDs were sequential from `0` to
`36` for this observation.

Examples from the live shape, paraphrased rather than treated as universal fields:

- the root was a standard window with `Raise` as a secondary action;
- the result area exposed `Copy`;
- disabled state appeared inline for the zoom button;
- toolbar controls exposed named secondary actions.

The response also returned a `image/jpeg` screenshot as MCP image content. A second unchanged state
request returned the same full AX rendering and another screenshot rather than an empty textual
diff.

## AX flattening and revision architecture

The helper preserves enough Swift symbols to establish the concrete pipeline:

1. `ApplicationUIElement.flatTree(for:contextType:transformed:includingMenus:)`
2. `UIElementTree.render(with:)`
3. `UIElementRenderTree.setElementIDs()`
4. `UIElementRenderTree.depthFirstTraversal()`
5. `UIElementRenderTree.lines(indent:options:)`
6. `UIElementRender.line(indent:indentCount:options:)`

The transformed element stores role, identifier, description, value type, role description,
placeholder, value description, transformed string, help, title, value, subrole, AX element, and
whether its value is settable. The renderer supports detail-text and element-ID omission options.

The tree builder also supports:

- menu-bar inclusion;
- focus subtrees;
- bounded child transactions;
- URL shortening with individual and total limits;
- selection subtrees;
- mapping integer IDs back to AX elements and index paths.

These signatures explain the live output without inventing a second semantic element model: the
integer IDs are assigned to rendered AX elements and resolved against a retained tree revision.

## AX diff behavior

The exact diff machinery is present:

- `UIElementRenderDifference(oldTree:newTree:)`
- `UIElementRenderDifference(oldRender:newRender:)`
- `Change.inheritElementID()`
- `Change.lines(indent:options:)`
- `UIElementRenderDifferenceBuffer.sortChangesDepthFirst()`
- line options for suppressing insertion or removal subtrees;
- `UIElementTreeRevision.root(...)` and `appending(...)`;
- `renderTreeSnapshot()` and inspector snapshots for current, previous, and first trees;
- `SkyshotOperation.capture(... continuingFrom: ..., enableAXDiffing: ...)`;
- `SystemSelectionExtractor.extract(... continuingFrom: ..., enableAXDiffing: ...)`.

Therefore:

- `[Verified]` Diffs compare old and new render trees, inherit element IDs for matched elements,
  sort changes in depth-first order, and render insertion/removal-aware lines.
- `[Verified]` A request can disable AX diffing, and a capture can continue from a retained tree
  revision.
- `[Verified]` The controller stores `lastAXTree` as a refetchable tree and resolves element IDs
  against a current revision before interaction.
- `[Unknown]` The optimized binary has not yet yielded a trustworthy high-level statement of the
  exact node-matching equality keys, line-budget constants, or every fallback that causes a full
  tree instead of a diff. The unchanged live call returned a full tree, so “every subsequent state
  is a diff” would be false.

## Window discovery and selection

The controller exposes:

- `orderedWindows()`;
- AX-to-CG window matching in both directions;
- primary-window waiting;
- focused-context construction for an explicit window;
- optional override and additional screenshot window IDs.

Targeted disassembly of `orderedWindows()` verifies that it calls
`CGWindowListCreate(0x11, 0)`. On macOS those option bits are on-screen-only plus excluding desktop
elements. The function converts the returned window IDs to window objects and cross-references them
with AX window candidates before producing its ordered result.

The service also has:

- `NSWorkspace.resolveApplicationTarget(for:)`;
- `resolveApplicationTargetPreferringRunningApplication(for:)`;
- bundle-ID and running-target lookup;
- app opening by name or URL;
- waiting for launch completion;
- explicit ambiguity errors for duplicate bundle identifiers.

The embedded ambiguity copy instructs the caller to use an app name or full path when multiple apps
share a bundle identifier.

What is established:

- `[Verified]` Public resolution accepts name, full path, or unambiguous bundle identifier.
- `[Verified]` There is a path that prefers an already-running application target.
- `[Verified]` Window discovery joins on-screen, non-desktop CG windows with AX windows.
- `[Verified]` No public window picker or window identifier is required from the model.
- `[Unknown]` The exact comparator used when several valid windows for one application remain after
  matching is not yet reconstructed at a confidence level suitable for independent reimplementation.

## Screenshot capture

The screenshot pipeline exposes these concrete methods:

- `SkyshotOperation.capture(... imageSize:includeScreenshot:continuingFrom:...)`
- `SystemSelection.writeScreenshotToFile(... encoding:)`
- `ScreenshotImplementation.captureScreenshotBuffer(...)`
- `ScreenshotImplementation.captureScreenshotFile(...)`
- `ScreenshotImplementation.captureScreenshotWithSkyLight(windowIDs:rect:)`
- `SCScreenshotManager captureImageWithFilter:configuration:completionHandler:`

The buffer capture accepts:

- an app name;
- optional delay;
- optional image size;
- included window IDs;
- whether to crop to the first window;
- opacity behavior;
- whether to include the window shadow.

The helper therefore contains both ScreenCaptureKit and SkyLight/WindowServer capture paths. The
live Calculator response used JPEG encoding.

- `[Verified]` Screenshot capture is window-ID scoped and can include more than one window.
- `[Verified]` The helper can select crop, sizing, opacity, shadow, and encoding behavior.
- `[Unknown]` The exact runtime branch selecting ScreenCaptureKit versus the SkyLight fallback for
  every OS/window condition is not yet reconstructed.

## Coordinate conversion

Targeted disassembly fully recovers
`CursorPosition.applying(scalingFactor:convertingToScreenFromWindowFrame:)`:

1. Convert integer screenshot `x` and `y` to floating-point values.
2. Apply `CGAffineTransformMakeScale(scalingFactor, scalingFactor)`.
3. If a window frame is supplied, apply a translation by the frame's origin.
4. Return the resulting screen point.

In plain form:

`screenPoint = (screenshotPoint * scalingFactor) + optionalWindowOrigin`

This proves the core screenshot-to-screen transform. The surrounding API also carries whether a
window uses flipped coordinates for event generation.

## Input synthesis

The helper's event layer is more specific than a generic `CGEvent` assumption. It defines:

- `SynthesizedEvent.click(at:andDragTo:mouseButton:count:flags:inWindow:windowBounds:windowUsesFlippedCoordinates:)`
- `SynthesizedEvent.mouseEvent(...)`
- `SynthesizedEvent.scroll(...)`
- `SynthesizedEvent.moveMouse(...)`
- `SynthesizedEvent.pressKeys(...)`
- `SynthesizedEvent.pressKeysForHolding(...)`
- `SynthesizedEvent.type(string:)`
- `SynthesizedEvent.send(to: pid, ...)`
- `CGEventAPI.postToPid(event, pid:)`

This is app-scoped event delivery. It does not require the controlled app to remain globally
frontmost.

Element interactions have a semantic-first path:

- `prepareToInteract(with: elementID, ...)` resolves the current AX element;
- `positionElement(...)` can make the element actionable/visible;
- `UIElementProtocol.click(...)` can choose AX behavior or simulated clicking;
- `AXUIElementPerformAction` invokes exposed secondary actions;
- `AXUIElementSetAttributeValue` supports set-value and selection ranges;
- `sourceTextRange(forVisibleText:prefix:suffix:)` disambiguates text selection;
- scrollbar actions and synthesized scroll events both exist;
- `NSRunningApplication.pressKey(...)` and synthesized key events target a process.

Focus coordination is internal and conditional. The service defines
`syntheticallyActivateIfNeededForSendingClick`, a `SyntheticAppFocusEnforcer`, app activation
notifications, focus-steal prevention, and menu-dismissal suppression. This reconciles the live
background observation with actions that may need synthetic focus semantics: the target does not
need to become the user's visible frontmost app merely to be observed, while the input layer can
coordinate focus for a particular event.

## Waiting, stale elements, and intervention

The controller exposes:

- `waitForUIToSettle(delay:notificationDelay:includingScrollEvents:)`;
- `updateSkyshotSettlingIfNeeded(...)`;
- `prepareToInteract` against a refetchable AX tree;
- errors for elements ambiguous before or after refetch;
- an AX tree invalidation monitor with layout changes and destroyed elements;
- process-scoped and system event taps;
- physical-input monitoring and lock-screen request guards.

The packaged Computer Use prompt adds the model-facing rule: actions may be grouped, then state is
read again before the next decision; the runtime waits about one second and can extend loading waits
up to about five seconds.

- `[Verified]` The native layer can wait for AX/UI settling and refetch a stale tree before an
  indexed interaction.
- `[Verified]` User/physical input and target focus changes have dedicated monitoring paths.
- `[Unknown]` The exact debounce interval and every cancellation point inside an already-posting
  native event are not recovered.

## What is now sufficient for Suniye

The research now provides enough evidence to implement the observable native design independently:

- explicit app target per call;
- name/path/unambiguous-bundle resolution with duplicate errors;
- background observation without foreground activation;
- on-screen/non-desktop CG-window discovery joined to AX windows;
- flattened preorder AX rendering with observation-scoped integer IDs;
- retained AX revisions and depth-first insertion/removal diffs;
- window-ID screenshot capture with ScreenCaptureKit/SkyLight abstraction;
- exact screenshot-to-screen coordinate transform;
- semantic AX actions with process-scoped synthesized-event fallbacks;
- conditional synthetic focus support rather than unconditional app activation;
- settling, invalidation/refetch, approval, intervention, and stable-error boundaries.

Suniye should not copy private implementation code. It should reproduce these verified behaviors
using its own Swift types and tests.

## Remaining exact questions

These are the remaining native details that should not be guessed:

1. The final ranking comparator for multiple valid windows of one app.
2. The complete render-tree node matching/equality rule and line-budget constants for diffs.
3. The exact ScreenCaptureKit-versus-SkyLight selection matrix.
4. Every conditional branch selecting AX activation versus synthesized input for every role/app.
5. Exact user-intervention debounce and cancellation semantics during an event already being sent.

These are narrow implementation details, not gaps in the overall architecture, public tool schema,
state format, background-observation behavior, request flow, or action mechanisms.
