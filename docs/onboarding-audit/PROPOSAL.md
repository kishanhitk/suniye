# Onboarding redesign proposal (KIS-209)

**Status:** proposal — nothing here is implemented. Approve, amend, or reject per section; implementation is a separate ticket.
**Inputs:** `CODE-MAP.md`, `SCREENS.md` + `screens/`, and a 49-agent critique pass (5 lenses → 44 findings → every finding independently verified against the code; 0 refuted, 14 corrected in detail). The verified findings are indexed in §9 by id (VD-n visual drift, FLOW-n flow, PF-n permissions, COPY-n copy, D-n dead options). Everything below cites them.

---

## 1. Verdict

The July Fast-Path flow is the right *shape* (value → first dictation → Accessibility ask). What drifted is everything around the shape:

1. **It is the only surface in the app that is not on the glass.** Solid `windowBackground`, no `BehindWindowBlur`; the hand-off to the dashboard is a visible material jump (VD-1). Its type, controls, spacing and status presentation predate KIS-192/196/197 and PR #104 (VD-2…VD-8).
2. **Three real dead ends survive** in the most common first-run path: an empty footer on the Speak screen while the model downloads (`screens/02`, `04`), a resumed Speak screen whose download never restarts (`02d`), and a drag overlay that tells an already-listed app to drag itself into the list (`09b`) (FLOW-1, FLOW-3, PF-02).
3. **Permissions are asked from four surfaces with three label sets and no shared presentation** (PF-01, PF-03, PF-06). The dashboard re-asks for Accessibility the instant a user chose "Later" (FLOW-5).
4. The copy names the core action four ways (write / speak / type / dictate), hard-codes the product name once, and over-promises while the download is stalled (COPY-01, 03, 05).

Recommendation: **keep the flow thesis, rebuild the screens as pages on the existing design system, collapse to two screens, and build one `PermissionRow` that onboarding, General and the dashboard all render.** Details and the 3-screen fallback follow.

---

## 2. Design rules the onboarding must follow (from the shipped redesign)

Derived from `MainWindowComponents.swift`, `SettingsRows.swift`, `MainWindowView.swift`, `GeneralPage`, `SpeechModelPage`, `TranscriptsPage` (`screens/11`, `12`, `16`):

| Rule | Shipped form | Onboarding today |
|---|---|---|
| Pane = glass, cards = the one opaque tier | `BehindWindowBlur(.underWindowBackground)` + `windowBackground.opacity(0.9)` (`MainWindowView.swift:20-23`) | solid fill (`OnboardingView.swift:47`) |
| Semantic type only | `AppTypography.*`, `Font.body`/`title2`…; one fixed-size exception (`emptyIcon`) | 20 pt / 15 pt icon literals (VD-3); `onboardingTitle` = `Font.title` is fine |
| Page hierarchy | `DetailPageTitle` (title2 semibold) + one-line body subtitle, top-aligned with `detailPaddingTop` 24 | centred 28 pt title below a 64 pt brand lockup (VD-7) |
| Rows, not cards, for settings-like things | `SettingsGroup` + `ControlSettingRow` + `RowSeparator`; small `.bordered`/`.borderedProminent` controls | `SurfaceCard` with 14 pt padding, 20 pt icon, large prominent button (VD-5) |
| Status = `InlineStatusBanner` | tinted wash, icon carries the colour, body detail, optional progress + one small action (`SpeechModelPage.swift:23-38`) | 76 pt bar + underlined `.plain` text links; raw `.orange` glyph (VD-2) |
| Fields are recessed | `editorBackground` (`inputSurface`) for anything the user reads as a field | transcript box uses the elevated card surface (VD-4) |
| Colour carries one signal | icon tinted, text primary (`InlineStatusBanner` comment) | whole status lines in green/red/orange (VD-6) |
| Footer buttons | right-aligned `HStack { Spacer; secondary .bordered; primary .borderedProminent }`, regular size (`SpeechModelSheet`) | full-width `.large` pill + centred caption link |
| Metrics from `AppMetrics` | `cardCornerRadius`, `cardPadding`, `detailPadding*`, `emptyStateMaxWidth` 420 | literals 10/14/18/24/28/36/40 (VD-8) |
| Copy | factual, one sentence, on-device claim in one wording ("Recognition happens on this Mac. Audio is never uploaded.") | marketing hero + fragments (COPY-04), four privacy phrasings (COPY-09) |

The maintainer's standing constraint applies: converge on **this** custom language, not on a native `NavigationSplitView`/`Form` look.

---

## 3. Target flow

### 3a. Recommended: two screens

```
launch ─▶ (activeOnboardingStep derived synchronously from onboardingProgress — no dashboard flash)
   │
   ▼
[1] Dictate                         progress ● ○
    ── headline + one privacy line (what Welcome used to say, in one breath)
    ── model banner  (InlineStatusBanner: downloading N% · Cancel | failed: reason · Retry | loading)
    ── Microphone row (PermissionRow)
    ── first dictation box (appears when mic ∧ model ready; sample phrase; recessed field)
    footer:  [Skip for now]                         [Continue]  ← always rendered; Continue enabled after 1 success
   │
   ▼
[2] Dictate in any app              progress ● ●
    ── Accessibility row (PermissionRow: never-listed → overlay; listed/stale → toggle copy; granted → ✓)
    ── "Try it in Notes" row (granted only) with an in-app confirmation when the first real insertion lands
    footer:  [Later — use ⌘V]                       [Finish]    ← Finish enabled when granted
   │
   ▼
dashboard (sidebar appears = "the app unlocked"); the Later cohort gets ONE quiet reminder, not an instant re-ask
```

Why two, not three (FLOW-4, FLOW-8): Welcome's only job is "Get Started", a disk check and kicking a download that has *already started on appear* with nothing on screen saying so (`AppState.swift:2069-2071`, `screens/01`). Folding its headline and consent line into the top of screen 1 keeps the brand moment, makes the download visible from the first frame (with Cancel — the metered-network concern from the spec becomes a visible, cancellable banner instead of a silent 680 MB), and removes one click before any value. Disk preflight moves to launch and renders as the model banner's error state.

### 3b. Fallback: keep three screens

If Welcome stays, the minimum bar is: render the download banner on Welcome too; always render the Speak footer; restart the download on resume; kill the "Prepare Suniye" literal. Everything in §4–§7 still applies.

### 3c. Invariants (either variant)

- **Every screen always renders its primary button.** Disabled when gated, never absent (FLOW-3; today `OnboardingView.swift:467` renders nothing).
- **`startOnboardingIfNeeded()` (re)starts the ASR download for every unfinished step**, not only `.welcome` (FLOW-1; `AppState.swift:2069-2071`).
- **`activeOnboardingStep` is set from `onboardingProgress.resumeStep` during hydration**, not at the end of `bootstrap()` (FLOW-2; `:2047`). Today a mid-onboarding user with an installed model sees the dashboard for the whole model load, then Welcome.
- **No system Accessibility modal while onboarding is active.** The hotkey path on screen 2 must route to the in-app row, not `AXIsProcessTrustedWithOptions(prompt:)` (`:3957`, `:4512`) — that call is what lists the app toggled-off and breaks the drag overlay (PF-02).
- **Persist `accessibilityPromptShown`** wherever the system prompt runs; `beginAccessibilityOnboarding` picks the toggle copy when that *or* `lastKnownAccessibilityGranted` is true (PF-02).

---

## 4. Per-screen keep / change / drop

### 4.0 Chrome (all screens)

| | |
|---|---|
| **Keep** | 3→2 step dots with the a11y label; slide/fade transition with Reduce Motion fallback; `refreshPermissionStatus()` on appear/step change; `maxWidth` 420 column (= `AppMetrics.emptyStateMaxWidth`). |
| **Change** | Background → the detail-pane material (`BehindWindowBlur(.underWindowBackground)` + `windowBackground.opacity(AppMetrics.detailPaneOpacity)`) (VD-1). Top-align content at `detailPaddingTop`, title as `DetailPageTitle` scale with a body subtitle (VD-7). Footer → the sheet convention: right-aligned regular-size `.bordered` secondary + `.borderedProminent` primary, `⌘.`/Esc for the secondary (VD-5). All metrics from `AppMetrics` (VD-8). Dots: `MainWindowPalette.cardStroke` → `selectedFill` for the inactive state so they read in dark mode. |
| **Drop** | The 64 pt icon + app-name lockup on every screen (VD-7) — keep a 32 pt icon beside the headline on screen 1 only. The `OnboardingStep.title` names ("Speak", "Type Anywhere") that only VoiceOver hears and never match the visible heading (D6, COPY-10): label with the visible title. |

Mockup (780×680, screen 1, mic not granted, download running):

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●                                                       glass pane      │
│                                                                              │
│          ● ─── ○                                                              │
│                                                                              │
│          [icon]  Dictate                                                     │
│          Hold Globe and speak. Recognition happens on this Mac.              │
│          Audio is never uploaded.                                            │
│                                                                              │
│          ┌ InlineStatusBanner (info wash) ───────────────────────────────┐   │
│          │ ⬇  Downloading speech model                        [Cancel]   │   │
│          │    Parakeet TDT 0.6B v3 · 671 MB · 53%                        │   │
│          │    ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░                                    │   │
│          └───────────────────────────────────────────────────────────────┘   │
│                                                                              │
│          Permissions                                                         │
│          Microphone  ⓘ                                     [Allow Access]   │
│          ─────────────────────────────────────────────────────────────────   │
│                                                                              │
│          (first-dictation box appears here once mic ∧ model are ready)       │
│                                                                              │
│                                                                              │
│                                       [Skip for now]   [ Continue ] (dim)    │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Welcome (`screens/01`, `01b`, `17`)

| | |
|---|---|
| **Keep** | The analytics disclosure *content* (a consent line with an opt-out is right to have before the first event). |
| **Change** | Fold into screen 1's header (recommended) — headline becomes factual: "Dictate in any app on your Mac." (COPY-03, COPY-04). Consent line stays a caption under the footer; "Turn off" becomes a real `Toggle`/bordered button mirrored from Settings › Privacy, not a one-way underlined link (D7). |
| **Drop** | The three benefit columns ("Private by design / No cloud delay / Works offline") — marketing fragments with no verb, 64 pt of vertical dead space (`WelcomeView.swift:11-27`) (COPY-04). The hard-coded 20 pt icons (VD-3). The silent on-appear download with no indication (FLOW-4) — the download stays, the silence goes. |

If Welcome is kept (3b): headline + one privacy line + the download banner + the consent line + `Get Started`. Nothing else.

### 4.2 Speak (`screens/02`–`07`, `18`)

| | |
|---|---|
| **Keep** | The thesis: first dictation before the Accessibility ask, practice routed to `.onboardingPractice` with no AX prompt (`AppState.swift:3935-3937`). The sample phrase. The tri-state mic handling (notDetermined → Allow; denied → Open Settings + recovery copy; self-heal on focus). The escape hatch *existence*. Listening/Transcribing/result feedback. |
| **Change** | Title: one title, "Dictate" (not "Prepare Suniye" ↔ "Try your first dictation" — `:151`, the only hard-coded name, COPY-01). Subtitle derives from state and never claims work that is not happening (COPY-05): downloading → "The speech model is downloading."; failed → banner only; ready → "Hold \(hotkey) and say:". Mic card → `PermissionRow` (§5). Model line → `InlineStatusBanner` fed by the existing `asrModelBanner` (`AppState.swift:1235-1275`), which already carries title/detail/progress/tone and the failure reason (VD-2, COPY-05); `Cancel`/`Retry`/`Download` become small bordered buttons. Transcript box → recessed `editorBackground` via `.flatSurface(fill: editorBackground)` + `AppMetrics.cardCornerRadius`, keep the accent stroke while listening (VD-4); label "Transcript preview" → "What you said" (COPY-07). Status label: tinted dot/icon, primary text (VD-6). Footer always present: `[Skip for now] [Continue]`; Continue enabled after one success; Skip visible from the first frame (FLOW-3) — it is already gated by analytics `practiced`, so there is no need to hide it. Success line "That's it — this works in any app." → "Done. Next: let it type into your apps." (it does not yet work in any app — FLOW-6). |
| **Drop** | The empty-footer states (`:467`). The `onboardingPracticeLevels` meter nobody renders (D4). |

Practice-ready mockup (middle of screen 1):

```
│          Hold Globe and say:                                                 │
│          “Send the report by Friday morning.”                                │
│          ┌ recessed field (editorBackground, accent stroke while listening) ┐│
│          │ What you said                                                    ││
│          │ Send the report by Friday morning.                               ││
│          └──────────────────────────────────────────────────────────────────┘│
│          ✓  Done. Next: let Suniye type into your apps.                      │
│                                                                              │
│                                       [Skip for now]   [ Continue ]          │
```

### 4.3 Type Anywhere (`screens/08`, `09*`, `10`, `13`)

| | |
|---|---|
| **Keep** | Asking after value. The "Later — clipboard mode" exit as a first-class path. The stale-grant detection idea. The Notes demo idea (real insertion is the product). |
| **Change** | Title "Dictate in any app" everywhere (title, row, step name) (COPY-03). AX card → `PermissionRow` with the four states in §5. **One primary button.** "Open Settings" stops being a co-equal button; it appears as the primary's *replacement* in the listed/stale states and as a small secondary only after an overlay dismiss/timeout (PF-04, PF-06). Overlay dismiss must change the row: "Still need access? Open Settings and turn \(app) on." (PF-08). Timeout hint at 60 s, not 300 s (PF-09; `AccessibilityOnboarding.swift:60`). "Later — I'll paste with ⌘V" → "Later — use ⌘V" (COPY-06) and it must *set a deferral* the dashboard honours (§6). Notes demo: after `openNotesForInsertionDemo()` the row shows "Waiting for your first dictation in Notes…" and flips to ✓ when `dictation_completed(.systemInsertion)` fires; if Notes is missing the button is hidden (D8, FLOW-6). |
| **Drop** | The duplicated stale-state buttons (PF-04). The first-person app voice. |

Mockup (screen 2, never-listed state):

```
│          ● ─── ●                                                              │
│                                                                              │
│          Dictate in any app                                                  │
│          Let Suniye type what you say into the app you are using.            │
│                                                                              │
│          Permissions                                                         │
│          Accessibility  ⓘ                                   [Allow Access]   │
│          Drag Suniye into the Accessibility list. Nothing is read from        │
│          your screen.                                                        │
│          ─────────────────────────────────────────────────────────────────   │
│                                                                              │
│                                     [Later — use ⌘V]     [ Finish ] (dim)    │
```

Granted state: row value becomes `✓ Allowed`; a second row `Try it in Notes  ⓘ  [Open Notes]` with the hotkey in a mono chip like General › Shortcuts; Finish enabled.

### 4.4 Permiso overlay (`screens/09`, `09b`)

| | |
|---|---|
| **Keep** | The drag-to-grant mechanic for the genuinely never-listed case; the grant poller + auto-refocus. |
| **Change** | Only present it when the app cannot already be listed (§3c flag) (PF-02). Add Esc handling and a ≥ 24 pt hit target for the back control, or a visible "Cancel" — today a 14 pt unbordered `NSButton` on a panel that can never become key (`OverlayWindowController.swift:188, 233-283`) (PF-07). Report `.dismissed` back into the row copy (PF-08). |
| **Drop** | Nothing structural; the vendored delta stays documented in `PERMISO_UPSTREAM.md`. |

### 4.5 Post-onboarding surfaces (`screens/11`, `12`, `15`, `00-*`)

| | |
|---|---|
| **Keep** | Dashboard attention tile as the default-section surface; General › Permissions group only while something is missing; the MF nudge after three real dictations; the menu-bar "Finish Setting Up…" item with live %; Dock icon kept while unfinished. |
| **Change** | All three permission surfaces render the same `PermissionRow`/banner content and the same label ("Allow Access") (PF-01, COPY-02). `GeneralPage` passes `askSurface: .settings` (today it defaults to `.onboarding`, PF-05; `MainWindowPages.swift:123`). The "Later" cohort: persist `accessibilityDeferredAt`; the dashboard tile is replaced for that cohort by a quieter `InlineStatusBanner(info)` "Dictations are copied to the clipboard. Allow Accessibility to type them directly." with one action — it must not re-ask in the same breath (FLOW-5). Menu bar: hide "Download Model" while a download is running (D1; `StatusItemController.swift:91-92`). |
| **Drop** | The three capability verbs (type / paste / insert) → "type" everywhere (PF-10). |

---

## 5. One permission component

The state is already single-sourced (`hasMicPermission`, `hasMicPermissionBeenDenied`, `hasAccessibilityPermission`, `accessibilityGrantLikelyStale`, `accessibilityAssistTimedOut`); the *presentation* is re-implemented three times (PF-03). Proposal: a value type `PermissionPresentation(kind: .microphone | .accessibility, state:)` → `{ title, info, detail, primary: (label, action), secondary: (label, action)? , tone }`, rendered by

- `PermissionRow` (a `ControlSettingRow` with the detail line underneath) — used by onboarding and `GeneralPage`;
- `AttentionTile` (existing `InlineStatusBanner`) — fed from the same presentation for the dashboard.

States and copy (one verb per idea: *allow* for the act, *type* for the capability, *dictation* for the product):

| Kind · state | Title / info | Detail | Primary | Secondary |
|---|---|---|---|---|
| Mic · notDetermined | Microphone ⓘ "Needed to hear your dictation." | Suniye listens only while you hold the hotkey. Audio never leaves your Mac. | Allow Access → system prompt | — |
| Mic · denied/restricted | Microphone | Microphone access is off. Turn it on in System Settings; this screen updates by itself. | Open Settings | — |
| Mic · granted | Microphone | — | ✓ Allowed (value, no button) | — |
| AX · never listed | Accessibility ⓘ "Needed to type into other apps." | Drag Suniye into the Accessibility list. Nothing is read from your screen. | Allow Access → overlay | — |
| AX · listed but off (prompted before, or stale after update) | Accessibility | macOS listed Suniye but left it off. Turn Suniye on in the Accessibility list. | Open Settings | — |
| AX · overlay dismissed / timed out | Accessibility | Still need access? Open Settings and turn Suniye on. | Allow Access | Open Settings |
| AX · granted | Accessibility | — | ✓ Allowed | — |
| AX · deferred ("Later") — dashboard only | Clipboard mode | Dictations are copied to the clipboard. Allow Accessibility to type them directly. | Allow Access | — |

Analytics: `askSurface` is passed explicitly by every caller (`.onboarding`, `.settings`, `.dashboard`, `.dictationAttempt`).

---

## 6. Copy table

| Element | Current | Proposed |
|---|---|---|
| Hero | Write at the speed of thought. | Dictate in any app on your Mac. |
| Benefits row | Private by design · No cloud delay · Works offline | (drop) — one line: Recognition happens on this Mac. Audio is never uploaded. |
| Analytics line | Anonymous usage stats help improve \(app). [Turn off] | Anonymous usage stats help improve \(app). [toggle] |
| Screen 1 title | Prepare Suniye / Try your first dictation | Dictate |
| Screen 1 subtitle (downloading) | Allow microphone access while the speech model prepares on your Mac. | Allow the microphone while the speech model downloads. |
| Screen 1 subtitle (stalled/failed) | The speech model is preparing on your Mac. | (none — the banner says what failed, with Retry) |
| Model line | Downloading speech model · 53% · Cancel (link) | banner: Downloading speech model — Parakeet TDT 0.6B v3 · 671 MB · 53% · [Cancel] |
| Model error | Speech model is not ready · Retry (link) | banner: Download failed — \(reason) · [Retry] |
| Transcript box label | Transcript preview | What you said |
| Placeholder | Your words will appear here after you speak. | Your dictation appears here. |
| Success | That's it — this works in any app. | Done. Next: let Suniye type into your apps. |
| Empty attempt | No speech detected. Try a short phrase. | (keep) |
| Skip | Skip for now | (keep) |
| Screen 2 title / step / row | Dictate anywhere / Type Anywhere / Type into any app | Dictate in any app (all three) |
| Screen 2 subtitle | Allow \(app) to type into the app you are using. | Let \(app) type what you say into the app you are using. |
| AX button | Allow Access / Grant / Grant Access / Enable (VoiceOver) | Allow Access (all surfaces, including the VoiceOver label) |
| Later | Later — I'll paste with ⌘V | Later — use ⌘V |
| Notes | Try it in Notes. Click into a note and hold \(hotkey). [Try in Notes] | Try it in Notes: click into a note and hold \(hotkey). [Open Notes] |
| Tile / Settings detail | …so transcribed text can be inserted. / Required to paste transcribed text into other apps. | Needed to type your dictation into other apps. |
| Ellipses / quotes | "Listening..." / "Transcribing..." (ASCII) | … and curly quotes, app-wide (COPY-08 — onboarding is not the only offender) |

---

## 7. Dead options and code to remove (D-n)

| Item | Evidence | Action |
|---|---|---|
| `advanceOnboarding()` | `AppState.swift:2075-2088`; only callers are tests | delete, tests call the three transitions |
| `onboardingPracticeLevels` | `:1483-1490`; no view reads it | delete |
| `accessibilityDragHelperEnabled` | persisted + decoded (`SettingsModels.swift:442-550`) with no UI writer | delete the setting; keep the injection seam for tests |
| Legacy `hasSeenOnboardingWelcome` / `hasCompletedCoreOnboarding` mirror-writes | `SettingsModels.swift:417-420`, `AppState.swift:4736-4738` | stop writing; keep *reading* for one more release for the migration truth table, then delete |
| `OnboardingStep.title` | only feeds the a11y label (`OnboardingView.swift:74`) | label with the visible heading |
| Menu-bar "Download Model" while downloading | `StatusItemController.swift:91-92` | hide while `phase == .downloadingModel` |
| Welcome "Turn off" one-way link | `OnboardingView.swift:134-141` | two-way control mirrored from Settings |
| "Try in Notes" with no Notes.app | `AppState.swift:3390-3396` logs and returns | hide the button when `urlForApplication` is nil |

---

## 8. Suggested implementation slices (after approval)

1. **Flow fixes with no design change** (can ship first, small): always-present footer; restart download on resume for any step; derive `activeOnboardingStep` at hydration; hide "Download Model" while downloading; `askSurface` from `GeneralPage`; `accessibilityPromptShown` flag + no system modal during onboarding. (FLOW-1/2/3, PF-02/05, D1)
2. **`PermissionPresentation` + `PermissionRow`**, wired into onboarding, `GeneralPage`, `AttentionTile`; label/copy unification; the "Later" deferral banner. (PF-01/03/04/06/08/09/10, FLOW-5, COPY-02)
3. **Screen rebuild on the design system**: material, page hierarchy, footer, `InlineStatusBanner` via `asrModelBanner`, recessed field, semantic icons, metrics; fold Welcome (or fix it per 3b). (VD-1…8, FLOW-4/8, COPY-01/03/04/05/07)
4. **Dead-code removal** (§7) and the app-wide ellipsis/quote sweep.

Each slice is independently reviewable; slice 1 is worth shipping even if the rest is rejected.

Open decisions for the maintainer:
- Two screens (3a) or three (3b).
- Whether "Later" suppresses the dashboard tile for a fixed period or until the next real dictation.
- Overlay: add Esc + bigger target (vendored change) or drop the drag helper in favour of the toggle deep-link everywhere.

---

## 9. Verified findings index

Severity · verdict (C = confirmed, P = confirmed with the noted correction).

**Visual drift**
- VD-1 · high · C — Solid pane vs behind-window glass everywhere else (`OnboardingView.swift:47` vs `MainWindowView.swift:20-23, 75`).
- VD-2 · high · C — Model status as 76 pt bar + underlined text links vs `InlineStatusBanner` on `SpeechModelPage`.
- VD-3 · medium · P — Icons at fixed 20/15 pt (`WelcomeView.swift:33`, `OnboardingView.swift:207, 379, 388`); correction: `emptyIcon` is also fixed-size, so the contrast is with `onboardingTitle` only.
- VD-4 · medium · C — Transcript box hand-rolls an elevated card; fields use `editorBackground`. Visible in dark mode (`18`).
- VD-5 · medium · C — Full-width `.large` pills vs the app's small/regular controls and sheet footer.
- VD-6 · medium · C — Whole status lines coloured (`:346-356`) vs icon-only tint.
- VD-7 · medium · C — 64 pt brand lockup on every screen.
- VD-8 · low · C — Literal metrics instead of `AppMetrics`.

**Flow**
- FLOW-1 · high · P — Resumed Speak never restarts the download (`AppState.swift:2069-2071`), empty footer, subtitle claims "preparing". Correction: with the mic ungranted the screen still shows "Allow Microphone", so it is a dead end for the *model*, not a buttonless screen.
- FLOW-2 · high · P — Dashboard renders before onboarding (`activeOnboardingStep` set at `:2047`). Correction: on a true first install with no model the gap is sub-frame; the seconds-long flash hits returning mid-onboarding users who already have a model.
- FLOW-3 · medium · C — Footer absent in download/cancelled/mic-granted states (`:467`).
- FLOW-4 · medium · P — Welcome is a splash; download starts on appear with no indication. Correction: ~680 MB, and Welcome also hosts the analytics link.
- FLOW-5 · medium · P — "Later" lands on a dashboard that re-asks at once. Correction: three post-finish surfaces, not four (the menu item disappears on finish).
- FLOW-6 · medium · C — Notes demo has no confirmation; practice success copy over-claims.
- FLOW-7 · low · C — No Back; dots are decoration.
- FLOW-8 · medium · C — Target flow synthesis (§3).

**Permissions**
- PF-01 · high · P — Labels: Allow Access / Allow Microphone / Grant / Grant Access / Enable (VoiceOver). Correction: three verbs, five strings.
- PF-02 · high · P — Drag overlay for an already-listed app (`09b`); root cause = the implicit system prompt (`:3957`, `:4512`) lists the app and never sets `lastKnownAccessibilityGranted`. Correction: the stable install is irrelevant (separate bundle id / row).
- PF-03 · high · P — No shared presentation model. Correction: state *is* single-sourced; presentation is not.
- PF-04 · medium · P — Stale state: two buttons, identical action (`:2273-2278`). Correction: timed-out state differs.
- PF-05 · medium · C — `GeneralPage` grants logged as `.onboarding` (`MainWindowPages.swift:123`).
- PF-06 · medium · C — Two-button vs one-button surfaces; primary already opens Settings.
- PF-07 · medium · C — 14 pt chevron on a never-key panel; no Esc.
- PF-08 · low · C — Overlay dismiss changes nothing on the row.
- PF-09 · low · P — 300 s before the hint. Correction: "Open Settings" is available the whole time; only the hint waits.
- PF-10 · low · P — type / paste / insert for one capability. Correction: mic drifts across two verbs, not three.

**Copy**
- COPY-01 · high · C — "Prepare Suniye" hard-coded (`OnboardingView.swift:151`).
- COPY-02 · medium · C — Three button verbs for one grant.
- COPY-03 · medium · C — write / speak / type / dictate.
- COPY-04 · medium · C — Marketing hero + fragments.
- COPY-05 · medium · C — "preparing" while stalled; failure reason hidden (the reason exists in `asrModelBanner`).
- COPY-06 · medium · P — First-person app voice in a sentence-long button. Correction: one other first-person string exists app-wide, in the user's voice.
- COPY-07 · low · C — "Transcript preview" jargon.
- COPY-08 · low · P — ASCII ellipsis/straight quotes. Correction: app-wide (~28 sites), not onboarding-specific.
- COPY-09 · low · P — Four wordings of the on-device claim across screens the user meets in sequence.
- COPY-10 · low · C — VoiceOver step label ≠ visible headline.

**Dead options**
- D1 · medium · C — "Download Model" menu item enabled while downloading (`00-menubar-during-download`).
- D2 · medium · C — Legacy Bools mirror-written (`SettingsModels.swift:417-420`).
- D3 · low · C — `advanceOnboarding()` test-only.
- D4 · low · C — `onboardingPracticeLevels` unused.
- D5 · low · C — `accessibilityDragHelperEnabled` has no UI writer.
- D6 · low · C — `OnboardingStep.title` a11y-only and mismatched.
- D7 · low · C — One-way "Turn off" link.
- D8 · low · C — "Try in Notes" silent when Notes is missing.
