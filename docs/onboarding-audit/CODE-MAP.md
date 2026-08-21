# Onboarding code map (KIS-209, captured 2026-08-21 on `main` @ 1be1c56b)

Every line reference below was read on this commit — this is the audited
baseline, kept as-is so the findings in `PROPOSAL.md` §9 stay traceable. The
redesign on this branch replaces most of §2–§5 (two screens, `PermissionRow`,
`PermissionPresentation`, init-time step resume); read the current code for
line numbers. Screens are in `screens/`; `SCREENS.md` maps each file to the
state that produced it.

## 1. Files

| File | Role | Lines |
|---|---|---|
| `Suniye/OnboardingModels.swift` | `OnboardingStep` (3 cases), `OnboardingProgress` (persisted enum + legacy migration), `OnboardingPracticeResult` | 99 |
| `Suniye/Views/OnboardingView.swift` | The whole wizard UI: dots, brand header, three step bodies, navigation buttons | 540 |
| `Suniye/Views/WelcomeView.swift` | Welcome headline + three benefit columns | 44 |
| `Suniye/AppState.swift` | All onboarding state + state machine + permission flows + practice pipeline (5 320-line class) | see §3 |
| `Suniye/Services/AccessibilityOnboarding.swift` | `PermisoAccessibilityOnboarding`: presents the vendored drag overlay, polls `AXIsProcessTrusted`, 300 s timeout, observes overlay close | 181 |
| `Suniye/Vendor/Permiso/*` | Vendored drag-to-grant overlay (`OverlayWindowController.swift`: 530×109 non-key `NSPanel`, 14 pt back button at :233-283) | — |
| `Suniye/MainWindowController.swift` | Window host; `MainWindowRootView` swaps `OnboardingView` ↔ `MainWindowView` (:74-87); activation-policy revert gated on progress (:63-71) | 169 |
| `Suniye/StatusItemController.swift` | Menu-bar "Finish Setting Up…" / "Downloading speech model — N%" item (:41-46, :70-79) | — |
| `Suniye/SettingsModels.swift` | Persistence: `onboardingProgress` + legacy Bools still written (:417-423, :536-541) | — |
| `Suniye/Views/MainWindow/MainWindowPages.swift` | Post-onboarding surfaces: `MagicFormatNudgeCard` (:7-50), General › Permissions group (:92-133) | — |
| `Suniye/Views/MainWindow/TranscriptsPage.swift` | Dashboard attention tiles + nudge mount (:81-105), empty-state hotkey hint (:116-123) | — |
| `Suniye/Views/MainWindow/MainWindowComponents.swift` | Design system: `MainWindowPalette` (:71-87), `AppTypography` (:89-129), `AppMetrics` (:131-166), `SurfaceCard` (:358-375), `InlineStatusBanner` (:496), `AttentionTile` (:573), `EmptyStateCard` (:593) | 880 |
| `Suniye/Views/MainWindow/SettingsRows.swift` | `ControlSettingRow` (:145), `SettingsGroup` (:184) — the flat-settings row vocabulary | 218 |

## 2. Screens → code

| Step | View body | Title / subtitle | Navigation |
|---|---|---|---|
| Welcome | `OnboardingView.welcomeContent` :112-123 → `WelcomeView` | "Write at the speed of thought." + 3 benefits (`WelcomeView.swift:6-24`) | `Get Started` → `beginOnboardingSetup()` :453-461; analytics disclosure + "Turn off" :125-144, :463 |
| Speak | `speakContent` :148-183 | title flips "Prepare Suniye" ↔ "Try your first dictation" :151; subtitle 4-way :185-196 | `Continue` (disabled until practice success) :469-477; `Skip for now` escape hatch :479-487 gated by `showsSpeakEscapeHatch` :523-527 — **no buttons at all otherwise** (:467) |
| ↳ mic card | `microphoneCard` :202-238 | tri-state: `Allow Microphone` vs `Open Settings` (denied) | `requestMicrophonePermission(askSurface: .onboarding)` / `openMicrophonePrivacySettings()` |
| ↳ model line | `modelStatusLine` :240-296 | downloading (progress + Cancel) / loading / error (Retry) / needsModel (Download) | `cancelASRModelDownload()`, `startModelDownload()` |
| ↳ practice | `practicePrompt` :302-308, `transcriptPreview` :310-344, status label :346-356 | sample phrase + read-only preview box | driven by the global hotkey, not a button |
| Type Anywhere | `typeAnywhereContent` :360-444 | "Dictate anywhere" | `Finish` (disabled until AX) :494-502; `Later — I'll paste with ⌘V` :504-511 |
| ↳ AX card | :375-441 | granted: green check + `Try in Notes`; else `Open Settings` + `Allow Access`; caption 3-way: stale / timed-out / default drag copy :409-439 | `beginAccessibilityOnboarding(askSurface: .onboarding)`, `openAccessibilityPrivacySettings()`, `openNotesForInsertionDemo()` |
| Chrome | dots :59-75 (6 pt circles, 24×1 connectors), brand header :77-92 (64 pt icon + name) | shared by all three | — |

Container: `OnboardingView.body` :17-55 — plain `VStack`, content `maxWidth: 420`, `.background(MainWindowPalette.windowBackground)` (solid; **no** `BehindWindowBlur`), slide+fade transition keyed on step, `refreshPermissionStatus()` on appear and on step change.

## 3. `AppState` onboarding surface

| Concern | Lines |
|---|---|
| Persisted position `onboardingProgress` (private set, persists on change) | 542-551 |
| Legacy read-only accessors `hasSeenOnboardingWelcome` / `hasCompletedCoreOnboarding` | 553-554 |
| `activeOnboardingStep` didSet → clears practice result, emits step analytics | 556-566 |
| Practice state (`onboardingPracticeText/Result/Succeeded/Attempts`), disk-space message, AX timed-out / stale flags | 568-596 |
| Per-run analytics dedupe, `onboardingStartedAt`, `lastKnownAccessibilityGranted` | 598-605 |
| `magicFormatNudgeDismissed` (persisted) | 606-613 |
| Mic tri-state `hasMicPermission` / `hasMicPermissionBeenDenied`, `hasAccessibilityPermission` | 615-619 |
| `isOnboardingPracticeRecording/Processing` | 1492-1498 |
| `shouldShowMagicFormatNudge` (finished ∧ !llmEnabled ∧ !dismissed ∧ ≥3 results) + nudge analytics | 1503-1531 |
| `attentionItems` — dashboard tiles incl. `fixAction: .requestMicrophonePermission` / `.requestAccessibilityPermission` | 1534-1621 |
| `bootstrap()` → loads first *installed* model (fallback order) → `startOnboardingIfNeeded()` | 2016-2050 |
| `startOnboardingIfNeeded()` — resume at persisted step; auto-download **only when step == .welcome** | 2057-2072 |
| `beginOnboardingSetup()` — disk preflight, progress → `.speakReached`, start download if needed | 2091-2106 |
| `startOnboardingModelDownloadIfNeeded()` | 2108-2123 |
| `advanceOnboardingFromSpeak()` → `.typeAnywhereReached` | 2125-2131 |
| `finishOnboarding()` — completion + `onboarding_outcome` analytics, progress → `.finished` | 2137-2155 |
| `trackOnboardingStepShownIfNeeded()` | 2163-2172 |
| `asrModelReady` (installed ∧ phase ∈ ready/recording/transcribing) | 2176-2178 |
| `modelDownloadDiskSpaceMessage()` (2× expected size) | 2180-2189 |
| `refreshPermissions(requestMicrophone:promptAccessibility:askSurface:)` — the only place the **system AX modal** is triggered (`AXIsProcessTrustedWithOptions`, :2218-2221) | 2191-2235 |
| `updateLastKnownAccessibilityGranted()` | 2252-2262 |
| `beginAccessibilityOnboarding(askSurface:)` — stale-grant branch → deep link; helper disabled → deep link; else Permiso overlay + outcome analytics | 2267-2314 |
| `requestMicrophonePermission(askSurface:)` — denied → deep link; else system prompt | 2316-2326 |
| `handleAttentionFixAction` (dashboard tile dispatcher) | 2328-2335 |
| `setupMenuItemTitle` (menu-bar resume item) | 3377-3385 |
| `openNotesForInsertionDemo()` | 3390-3396 |
| Recording gate: welcome blocks ("Finish setup first"), Speak routes to `.onboardingPractice`, Type Anywhere allows real dictation | 3919-3923, 3935-3937, 5099-5104, 5197-5199 |
| Dictation-attempt AX prompt de-stacking (`!accessibilityOnboarding.isPresenting`) | 3950-3958, 4512-4521 |
| Practice completion (`completeOnboardingPracticeDictation`, attempt counter, analytics) | 4375-4432 |
| Practice failure from audio capture | 4547-4553 |
| Hydration + legacy migration (`legacyUserShowsUsage`) | 4683-4718 |

## 4. Navigation graph

```
launch ──bootstrap()──▶ startOnboardingIfNeeded()
  │ progress=.notStarted            → Welcome   (auto-starts ASR download, :2069-2071)
  │ progress=.speakReached          → Speak     (download NOT restarted — see SCREENS.md 02d)
  │ progress=.typeAnywhereReached   → Type Anywhere
  │ progress=.finished              → MainWindowView (dashboard)
  ▼
Welcome ──Get Started──▶ disk preflight ──fail──▶ Welcome + red disk message (:116-121)
                                        └─ok──▶ Speak  [.speakReached]

Speak   (mic × model × practice matrix; title/subtitle/buttons derive from it)
  mic:   notDetermined → [Allow Microphone] → system prompt → granted | denied
         denied        → [Open Settings] → deep link; self-heals on window focus (:58-61 MainWindowController)
  model: downloading → [Cancel] → needsModel → [Download]
         error       → [Retry]
         ready       → practice box appears
  practice (hotkey held, destination .onboardingPractice):
         Listening… → Transcribing… → success ("That's it — this works in any app.") | error ("No speech detected…")
  exits: [Continue] enabled only after one practice success
         [Skip for now] only after ≥1 attempt ∨ phase==.error ∨ mic denied
         (no exit rendered otherwise — e.g. resumed Speak with download not started)
  ──▶ Type Anywhere [.typeAnywhereReached]

Type Anywhere
  AX granted      → green check, [Try in Notes] (opens Notes.app), [Finish]
  AX not granted  → [Allow Access] → (lastKnownAccessibilityGranted ? deep link + stale copy
                                      : Permiso overlay + System Settings pane)
                    overlay ends: granted → auto-dismiss + refocus | dismissed (chevron) → silent | timeout 300 s → orange hint
                    [Open Settings] → deep link
                    [Later — I'll paste with ⌘V] → finishOnboarding()  (clipboard-mode cohort)
  ──Finish / Later──▶ finishOnboarding() [.finished] ──▶ MainWindowView

Post-onboarding (data-driven, not steps):
  dashboard AttentionTile "Accessibility permission missing" [Grant Access]  (AppState:1578-1586 → beginAccessibilityOnboarding(.dashboard))
  dashboard AttentionTile "Microphone permission missing"    [Grant Access]
  dashboard MagicFormatNudgeCard after 3 real dictations     [Set Up Magic Format | Not Now]
  Settings › General › Permissions group (only while something is missing)
  menu bar: "Finish Setting Up <App>…" / "Downloading speech model — N%" while unfinished
  window close while unfinished keeps the Dock icon (activation policy stays .regular)
```

## 5. The Accessibility request surfaces (all routes)

| # | Surface | Code | What the user sees |
|---|---|---|---|
| 1 | Onboarding › Type Anywhere › `Allow Access` | `OnboardingView.swift:399-404` → `beginAccessibilityOnboarding(.onboarding)` | Permiso drag overlay + System Settings pane (`screens/09*`) |
| 2 | Settings › General › Permissions › `Grant` | `MainWindowPages.swift:123` → `beginAccessibilityOnboarding()` (default surface `.onboarding` — mislabelled in analytics) | same overlay (`screens/12`) |
| 3 | Dashboard attention tile › `Grant Access` | `AppState.swift:1578-1586` (`fixAction`) → `handleAttentionFixAction` :2328-2335 → `beginAccessibilityOnboarding(.dashboard)` | same overlay (`screens/11`, `15`) |
| 4 | **Implicit**: hold the hotkey without AX (incl. on Type Anywhere itself) | `beginRecordingFlow` :3950-3958 and `requireAccessibilityForInsertion` :4512-4521 → `refreshPermissions(promptAccessibility: true)` → `AXIsProcessTrustedWithOptions(prompt)` | the **system** "would like to control this computer" modal; it also adds the app to the Accessibility list with the toggle off |
| + | `Open Settings` secondary buttons on 1 and 2 | `openAccessibilityPrivacySettings()` :2350 | deep link only |

Surface 4 matters: once it fires, the app is *listed* in the Accessibility pane, and surfaces 1–3 then show an overlay that says "Drag <App> to the list above" for an app that is already in the list (`screens/09b`). The stale-grant branch (:2272-2278) only catches this when a grant was previously *seen*.

## 6. Microphone request surfaces

| Surface | Code |
|---|---|
| Onboarding › Speak card | `OnboardingView.swift:221-227` → `requestMicrophonePermission(.onboarding)` |
| Settings › General › Permissions | `MainWindowPages.swift:103` → `requestMicrophonePermission()` (default surface `.settings`) |
| Dashboard attention tile | `AppState.swift:1565-1573` → `.requestMicrophonePermission` → `.dashboard` |
| Implicit: hotkey without mic | `beginRecordingFlow` :3930-3932 → `refreshPermissions(requestMicrophone: true, askSurface: .dictationAttempt)` |

## 7. Persistence & reset (for anyone re-running this audit)

- Single JSON blob in `UserDefaults` key `dev.suniye.general.settings` (`GeneralSettingsStore.swift:14-31`), bundle domain `dev.suniye.app.preview` for the Preview build. Values are `Data`; `defaults write -string` is ignored. Write with `-data <hex-of-json>`.
- Fresh-user reset that survives the legacy heuristic (`legacyUserShowsUsage`, `AppState.swift:4712-4717` — any installed model or history marks the install as finished): write `{"onboardingProgress":"notStarted"}` explicitly rather than deleting the key.
- `bootstrap()` loads *any* installed model from the shared `~/Library/Application Support/Suniye/models` (shared with the stable app) and silently switches `selectedASRModelID` to it (:2021-2027). To see download states, the models directory must be empty for the process.
- TCC: `tccutil reset Microphone|Accessibility dev.suniye.app.preview`. `AVCaptureDevice` caches the mic status in-process; a reset needs a relaunch to be observed.
- Debug builds compile analytics to a no-op (`SuniyeAnalytics/.../Analytics.swift:7-9`), so walking the flow does not pollute the funnel.
- Synthetic Globe (fn) `flagsChanged` events do not reach the hotkey monitors; the practice screens were driven with the hotkey set to ⌃⌥D via prefs (`{"hotkeyConfiguration":{"kind":"keyCombo","keyCode":2,"carbonModifiers":6144}}`), which is why those captures read "Hold Control + Option + D" instead of "Hold Globe".
