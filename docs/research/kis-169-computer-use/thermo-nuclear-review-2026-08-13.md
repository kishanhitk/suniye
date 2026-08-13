# Thermo-nuclear review — Computer Use (kis-169-computer-use-parity)

## Verdict: REQUEST CHANGES

One hard blocker gates merge: the four-way hotkey collision policy is smeared across four `didSet` observers plus the hydrator plus `HotkeyService`, it disagrees with itself pairwise, and the paste setter's missing `computerUse` check is a reachable data-loss bug (set paste == computerUse → Computer Use hotkey silently dies at registration → persisted shortcut is nil'd on next launch). Independent of that, the change also trips the approval bar on "no obvious missed dramatic simplification" and "no spaghetti growth in shared flows": a whole tool-dispatch layer is doubled for zero consumers, the model-visible tool result is shaped two unrelated ways that must agree, credential storage carries two byte-identical protocols behind a five-times-repeated branch, and the agent loop runs an implicit multi-flag audit state machine. Fix the blocker; land the top three simplifications before this is parity-clean. The minors are real but none block.

The nineteen slice findings collapse to fifteen after merge. No slice finding was a false positive; four were correctly self-downgraded by the verifiers and I concur. The one cross-cutting move the per-slice reviewers could not see: findings 3, 4, and 12 below are the *same editing pass* on `ComputerUseToolBackend` — collapsing the dispatch seam is the moment the phantom token and the duplicated identity key also disappear. Ranked, that pass deletes ~120 lines and two types at once.

---

## BLOCKER

### 1. Hotkey collision policy is a self-inconsistent pairwise matrix; paste↔computerUse edge is missing and loses the persisted shortcut
`Suniye/AppState.swift:445-478` (paste `didSet`), cross-checked against `:412-443` (dictation), `:480-513` (editMode), `:514-539` (computerUse), hydrator `:4466-4474`, `HotkeyService.swift:56-87`.

Category: spaghetti-branching → reachable correctness bug.

Verified matrix: dictation CLEARS editMode (429) and computerUse (434) but YIELDS to paste (421); editMode REVERTS on all three (486/492/499); computerUse REVERTS on all three (519-527); paste guards `isModifiedKeyCombo`, `!= hotkeyConfiguration` (456), `!= editModeHotkeyConfiguration` (462) — and never checks `computerUseHotkeyConfiguration`. Reachable path: set computerUse = ⌥Space (accepted), then paste = ⌥Space (paste `didSet` passes, clears the validation message at 468, both persist equal). `wireHotkey` → `startMonitoring` registers paste, then skips computerUse because its combo now matches paste (logs "computer use hotkey ignored: matches another hotkey") — the hotkey is dead with no user-facing error. Next launch, `hydrateGeneralSettings` re-normalization sets `computerUseHotkeyConfiguration = nil` and the persisted shortcut is gone. Three inconsistent resolution strategies (clear-other, yield-self, revert-self) coexist for what is supposed to be one invariant: four mutually-distinct shortcuts.

Fix: route every setter, the hydrator, and the service through one collision resolver (a `HotkeySlotAssignments` value type owning pairwise-distinctness), and hand `HotkeyService` an already-validated set so its re-check disappears. This collapses the four `didSet` bodies, the hydration renormalization, and the service guard into one place and makes the missing edge unrepresentable — the point is not "add the fourth check," it is that a policy expressible in four hand-maintained observers will keep drifting.

---

## MAJOR — missed dramatic simplifications (shared flows)

### 2. Model-visible tool result is shaped two unrelated ways (typed live projection vs. untyped JSON dict-surgery on replay) that must agree but share no code
`Suniye/Services/ComputerUseModelContext.swift:100-144, 187-243`, with `ComputerUseAgent.swift:278-301,384` and `ComputerUseToolResultEncoder.swift:20-21`.

Category: boundary-types.

Live path projects `.appState` → `ModelVisibleAppState(app, text)` (context:187,239-242) to drop the screenshot. Replay path has only the persisted `String` and re-derives the same view by hand: `normalizePersisted` (194-215) does `JSONSerialization` → `removeValue(forKey:"screenshot")` → reserialize with `[.sortedKeys,.withoutEscapingSlashes]`, and `persistedScreenshotReference` (217-231) string-parses the same JSON to recover app+screenshot. Two shaping mechanisms for one fact, kept in agreement by hand. `try? … as? [String:Any]` at :202 is a silent fallback that would ship the raw screenshot URL on a parse miss — latent, not currently reachable (persisted `getAppState` output is always valid JSON), so major not blocker. The compact-JSON config is duplicated 4× (ToolResultEncoder:21, context:206, context:235, Agent:384); the `.image(...)` message is built 2× (Agent:295-301, context:51-57).

`ComputerUseAppState` is already `Codable` with a round-tripping custom `encode` (Protocol:35-45; nil screenshot → null). Fix: in the context builder, decode `activity.output` back into `ComputerUseToolResult` keyed on `activity.toolName` and feed it through the SAME `ComputerUseModelToolOutput.encode` projection the live path uses; take the screenshot URL off the decoded `.screenshot`. Deletes `normalizePersisted`, `persistedScreenshotReference`, and the untyped fallback; makes live/replay provably identical. Fold the 4× config and 2× image construction into shared helpers. (Error outputs and `applications` need a small decode-by-toolname switch — contained.)

### 3. Doubled tool dispatch: 10-case `Session.execute` adapter + 10-method `ComputerUseToolServing` protocol + 8 identical pass-through wrappers, for one production conformer
`Suniye/Services/ComputerUseToolBackend.swift:105-203`, `ComputerUseSession.swift:8-64`, `ComputerUseProtocol.swift:203-232`.

Category: modularity.

Verified: `Session.execute` is a pure 10-case adapter that unpacks the `ComputerUseToolCall` enum and re-passes named args (doing only `Task.checkCancellation`). `ComputerUseToolServing`'s 8 action methods on `ToolBackend` (click 105, performSecondaryAction 111, setValue 121, selectText 127, scroll 147, drag 163, pressKey 181, typeText 187) are each `performAction(app:) { context in try await actions.X(..., context:) }` — the entire observe/authorize/settle lifecycle lives in `performAction` (193-203). Grep confirms exactly one production conformer (`ToolBackend`) and one production caller (`Session.execute`); the test doubles (`RecordingComputerUseBackend`, ComputerUseProtocolTests.swift:183-258) implement all 10 methods only to record `call.name`. Nothing consumes the granular seam. Adding one tool touches ~8 parallel declarations.

Fix: narrow `ComputerUseToolServing` to one exhaustive seam `func execute(_ call: ComputerUseToolCall) async throws -> ComputerUseToolResult`, move the single switch into `ToolBackend` (which already owns `performAction` + `actions`), delete Session's 10-case re-expansion and the 8 wrappers. Behavior- and cancellation-preserving (both are actors); the recording doubles collapse to one method. See cross-cutting note.

### 4. Two byte-identical credential-store protocols and a `provider == .openRouter` store-selection branch re-derived across five controller methods
`Suniye/Services/ComputerUseModelSettings.swift:106-118, 268-270, 290-292, 305-320, 338-349`.

Category: spaghetti-branching.

`ComputerUseCredentialStoring` (106-111) and `SharedOpenRouterCredentialStoring` (113-118) declare the identical four methods — two protocols, one shape. The controller re-branches on `settings.provider == .openRouter` in five places: `hasAPIKey` (269), `saveAPIKey` (290), `clearAPIKey` (307), `effectiveAPIKey` (338-343), `refreshCredentialState` (347). The two cached booleans (`hasDedicatedAPIKey`/`usesSharedOpenRouterAPIKey`, 238-239) back two distinct UI strings (ComputerUseSettingsDisclosure.swift:138 vs 141-142) — both remain reproducible from `(provider, single hasActiveKey)`, so no UI regression from collapsing them.

Fix: one `CredentialStoring` protocol (both concrete stores conform); `private var activeCredentialStore: any CredentialStoring { settings.provider == .openRouter ? shared : dedicated }`; route save/clear/get/has through it, branching on provider once; keep one observable `hasActiveAPIKey`. The genuinely provider-specific action — firing `onSharedOpenRouterCredentialChange` because the key is shared with Magic Format — stays as the lone conditional. Both stores remain injectable as `any CredentialStoring`; no test seam lost.

---

## MAJOR — spaghetti growth in shared flows

### 5. Agent loop self-audit/recovery is an implicit multi-flag state machine with set/reset scattered across three branches
`Suniye/Services/ComputerUseAgent.swift:131-243` (clears at 149/165/231; consumes at 171 and 225).

Category: spaghetti-branching.

Five loop vars (133-137). `needsPostActionObservation` set at 240, cleared at 149/165/231, consumed at 171 AND 225. `completionAudit` gate at 181-183. `unchangedStateRecovery` fires on the `>=2` counter (232), reset at 229/236 and implicitly whenever `needsPostActionObservation` is false. The observation-reset pair (`hasSuccessfulObservation=true` / `needsPostActionObservation=false`) is duplicated between the `applyInterventions` caller (148-149, 164-165) and the toolCall observation path (224/231). No single place decides which audit to inject.

Fix (directional): model the last executed step as one enum and centralize audit selection in a single policy function; de-duplicate the scattered observation-reset flips. Note `requestedCompletionAudit` (fire-once) and `consecutiveUnchangedPostActionObservations` (>=2 across iterations) are genuine cross-iteration state — they do not collapse into a pure function of the last step. The real win is removing the duplicated flag flips, not a fully pure policy.

### 6. Pending-voice-task launch is polled from every state transition with launch preconditions stated three times, and `submitVoiceTask` returns a wrong `.started` when busy
`Suniye/Services/ComputerUseCoordinator.swift:94-99, 110, 127, 152-159, 213-217, 261, 321-333`.

Category: spaghetti-branching.

`startPendingVoiceTaskIfPossible` is re-invoked from `configureModel` (110), `refreshPermissions` (127), `submitVoiceTask` (214), `requestPermission` (261). The launcher guard (322-325: `!isBusy`, `isModelConfigured`, `canControlComputer`) is a subset of `canSubmit` (94-99), and calls `submit()` which re-checks config+permissions (148-162). `submitVoiceTask` gates only on `isModelConfigured && canControlComputer` (213), omitting `!isBusy`, so during `.checkingPermissions`/`.requestingPermission` it enters the branch, the launcher silently bails, yet it returns `.started` (215). The sole consumer (`AppState.swift:3990-4002`) branches only on `.rejected` and derives its indicator from `coordinator.isRunning`, so the wrong `.started` is a latent API-contract lie today, not an observable bug — hence major, not blocker.

Fix: route precondition changes through one gate that evaluates `canSubmit` and returns whether it launched, so `submitVoiceTask` reports `.started`/`.queued` truthfully and preconditions are stated once. The four poll sites are inherent async completion points and cannot all be deleted; the wins are de-duplicating the preconditions and fixing the return value.

---

## MAJOR — boundary leak

### 7. Conversation persistence is a `didSet` side effect, so every in-memory mutation — including per-frame streaming activity updates — re-encodes and rewrites the whole conversation
`Suniye/Services/ComputerUseCoordinator.swift:31-35, 294-306`; store at `ComputerUseConversationStore.swift:47-51, 86-116`.

Category: modularity / boundary leak.

`var conversation { didSet { conversationStore.save(conversation) } }` (31-35). `appendActivity` mutates `conversation` on every `activitySink` emit (299 index-set / 305 append); the agent emits ~twice per tool call (start 208, completion 288, error 330). Each mutation fires `didSet` → full-array `JSONEncoder` over the growing array (saveToDisk 86-116) = O(N²) aggregate encode/IO across a run, coupling invisible at every call site. Mitigation: `save()` dispatches to a background serial queue (47-51), so encode/IO is off the MainActor — practical perf impact moderate. The durable defect is the boundary leak: a stored property secretly performing disk I/O on every streaming frame.

Fix: persist explicitly at real checkpoints (message append, `finish`) or debounce activity-driven writes, not a property observer. Drops mid-run activity from crash recovery — acceptable.

---

## MINOR — boundary / modularity / legibility

These are correctly rated. Fix opportunistically; none blocks.

### 8. Phantom capability token: `ComputerUseRuntimeAuthorization` is empty and `prepareForObservation`/`validateAction` do the identical screen-lock check
`Suniye/Services/ComputerUseRuntimeGuard.swift:15, 35-42`; token threaded through `ComputerUseToolBackend.swift:14-22, 209-212, 234-241`. The observe-before-act invariant is actually enforced by `observationsByTarget.removeValue` throwing `observationRequired` (209-211), not the token. Delete the type, collapse the two methods into one `ensureScreenUnlocked()`, drop the dead fields from `AuthorizedObservation`/`PreparedAction`. Behavior-preserving. **Part of the ToolBackend cleanup pass — see cross-cutting note.**

### 9. Indicator presentation inlined into the 5133-line `AppState` instead of the coordinator
`Suniye/AppState.swift:4770-4810, 3369-3370, 4300-4312, 3998-4002`. Phase→`FloatingIndicatorState` mapping + completed→idle reset task, with `computerUseIndicatorResetTask?.cancel(); = nil` at five sites and `guard activeDictationSession == nil` in four cases. Move the mapping + timer onto a presenter/the coordinator owning one reset task. Note: `finalIndicatorState` is a generic parameterized hook with `.idle` default (not a computer-use branch in the shared epilogue), and the `activeDictationSession` coordination reflects an inherent single-shared-indicator constraint a presenter still needs — the remedy relocates part of it. What genuinely survives: five cancel sites + inline mapping in a god object.

### 10. Three run-tracking optionals encode one fact "a run is in flight"
`Suniye/Services/ComputerUseCoordinator.swift:47-49, 172-185, 265-267, 308-313`. `activeRun`/`activeRunID`/`activeInterventions` are set/cleared together; the `activeRunID == runID` staleness guard exists because identity is a loose field. Fold ONLY these three into one `struct ActiveRun` held as a single optional; guard becomes `activeRun?.id == runID`. Do NOT fold `debugSessionID` (observed UI property at :37, lifetime deliberately outlives the run) — that changes UI behavior. Staleness-guard concept relocates, not eliminated.

### 11. View page-visibility boolean overrides the shared dictation destination resolver
`Suniye/AppState.swift:3363-3365, 4909-4917` (consumed at 3776). `isComputerUsePageActive` (a UI flag) makes `currentDictationDestination` return `.computerUseTask`, so the global hotkey / manual trigger redirect based on which page is on screen. Route the on-page mic/manual affordance to `.computerUseTask` explicitly (or push page-active into the coordinator) and drop the branch from the resolver. Distinct from the dedicated computerUse hotkey path (3586-3593), which passes destination explicitly.

### 12. Application-identity formula reimplemented verbatim in two services
`Suniye/Services/ComputerUseToolBackend.swift:244` and `ComputerUseObservationService.swift:98-99`. `bundleIdentifier ?? applicationURL.standardizedFileURL.path` keys `observationsByTarget` in one and forms `applicationKey` (suffixed `#window.id`) in the other. `ComputerUseApplicationRecord` (ApplicationCatalog.swift:3-25) owns a *different* identity (`publicApplication.id`), so this storage identity leaks into two services and can drift. Add `var identityKey: String` on the record; use it at both sites (ObservationService still appends `#window.id`). **Part of the ToolBackend cleanup pass.**

### 13. Duplicated `applicationWindows` unwrap across three accessibility adapters
`Suniye/Services/SystemComputerUseAccessibilitySnapshotProvider.swift:97-107`, `SystemComputerUseWindowInventory.swift:45-53`, inlined third variant at `SystemComputerUseAccessibilityActions.swift:244-247`. Consolidate ONLY the unwrap: a non-throwing canonical `SystemComputerUseAccessibilityAPI.applicationWindows(from:) -> [AXUIElement]?` that each site maps to its own domain error. Do NOT introduce a single throwing helper or a shared roots resolver — the three adapters carry three distinct error enums (`.attributeUnavailable` / `.accessibilityFailure(rawValue)` / degrade-to-`[]`) and a throwing helper would flatten those domains and change surfaced errors.

### 14. `modelStatusMessage` and `modelStatusIsError` recompute the same validation coalescing in two passes
`Suniye/Views/MainWindow/ComputerUseSettingsDisclosure.swift:130-168`. Add one computed `status: (text: String?, isError: Bool)` on `ComputerUseModelSettingsController` derived once from validation fields + `connectionState`; view reads both from it. Controller already holds `.failed(message)`/`credentialError` strings, so relocating the copy is consistent with the codebase's "logic in state/services" convention.

### 15. `readinessMessage` re-derives the canonical `canControlComputer` gate inline
`Suniye/Views/MainWindow/ComputerUsePage.swift:203-204` tests `accessibility != .granted || screenRecording != .granted`, exactly `!canControlComputer` (PermissionService.swift:29-31). Dual source of truth for a safety gate — add a third permission to `canControlComputer` and this clause silently drifts. Replace with `!coordinator.permissionSnapshot.canControlComputer`. The broader `startBlockReason` relocation is optional and moves user-facing copy into the service — treat separately.

### 16. `ComputerUsePrimaryClickOperation` enum + `primaryClickOperations` + consuming switch carry no info beyond an action string
`Suniye/Services/SystemComputerUseAccessibilityAPI.swift:9-12, 44-46`, consumer `SystemComputerUseAccessibilityActions.swift:11-30`. Both switch arms call `worker.performPrimaryActionIfPossible(<string>, on:)` and return true; only the string differs (`ComputerUseAccessibilityActionResolver.pickAction` vs `kAXPressAction`). Delete the enum and helper; iterate the strings directly. The only other reference (AccessibilityTreeTests.swift:240-244) tests the redundant helper and is disposable with it.

### 17. `windowUsesFlippedCoordinates` is dead production configurability; `ComputerUseMouseEventDescriptor` is a single-use pass-through
`Suniye/Services/SystemComputerUseInputEvents.swift:4-9, 11-25, 234-257`. Sole production `ComputerUseInputEventTarget` constructor (ComputerUseActionService.swift:389) hardcodes `true`; `false` appears only in tests (ComputerUseActionServiceTests.swift:10). `configure()` copies four target fields into the descriptor then reads back only `.eventLocation` and `.windowID` (== `target.windowID`), so the struct adds only the coordinate transform. Drop the flag from both structs; replace the descriptor with a free `eventLocation(screenPoint:target:)` or inline the transform.

### 18. Element-click path calls `accessibility.center()` up to twice and uses `cursorPoint` optionality as a "center failed" flag
`Suniye/Services/ComputerUseActionService.swift:168-214`. `cursorPoint` nil'd only in the non-cancellation catch (178-179); the synthetic-fallback else at :201 re-invokes `center()` — reached only when it already failed. Capture the caught error once and rethrow it in the fallback instead of re-calling. Note: the swallow is NOT pointless — it enables the AX-only success path (left click succeeds where `center()` fails, returns at :195); a behavior-preserving fix rethrows the stored error, it does not reorder the AX attempt (that would drop the cursor overlay on the common success path).

---

## Cross-cutting note (one editing pass, three findings)

Findings **3, 8, and 12** are the same cleanup on `ComputerUseToolBackend` / the `ComputerUseToolServing` seam. Collapsing the dispatch to a single `execute(_ call:)` (3) is the moment `AuthorizedObservation`/`PreparedAction` lose their phantom `runtimeAuthorization` field (8) and `targetKey` moves onto the record as `identityKey` (12). Done together this deletes Session's 10-case switch, 8 wrapper methods, one empty type, one redundant guard method, and one duplicated formula — and shrinks the 10-method test doubles to one. Sequence it as one commit; reviewing the pieces in isolation understates the payoff.

---
Method: 7 slice reviewers + per-slice adversarial verification + cross-cutting synthesis (13 agents). 18 findings survived verification, merged to 15. Reviewed at branch head on 2026-08-13.
