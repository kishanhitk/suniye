# Screen index

All captures: Suniye Preview (`dev.suniye.app.preview`), Debug build of `main` @ 1be1c56b, macOS 26, 780×680 window at 2×, light mode unless noted. Window captures use `screencapture -l`; the dashboard/settings captures use `-R` so the behind-window material composites (`-l` flattens it).

The preview's hotkey was set to ⌃⌥D for the practice captures (synthetic Globe events do not reach the hotkey monitors), so 05–07, 13 and the dashboard empty state read "Control + Option + D" where a real install reads "Globe". The dashboard stat header in 11/15 ("192 dictations") is a test artifact: the Preview build migrates the stable app's legacy `stats.json`; a fresh install shows zeros.

| File | State | How it was produced |
|---|---|---|
| `00-menubar-during-setup.png` | Menu bar while onboarding unfinished, model already installed: bold "Finish Setting Up Suniye Preview…" | first launch with `onboardingProgress=notStarted`, shared models dir present |
| `00-menubar-during-download.png` | Same item while the ASR download runs: "Downloading speech model — 73%"; note the enabled "Download Model" item below it | models dir empty, download in flight |
| `01-welcome.png` | Welcome, default (analytics on); the ASR download is already running in the background with no on-screen indication | fresh launch |
| `01b-welcome-analytics-off.png` | Welcome after "Turn off" | click on the underlined link |
| `02-speak-no-mic-downloading.png` | Speak — "Prepare Suniye", mic card + inline progress (53%) + Cancel. **No navigation buttons rendered** | Get Started with empty models dir |
| `02b-speak-no-mic-download-cancelled.png` | Speak after Cancel: "Speech model is not ready — Download". Still no navigation buttons | click Cancel |
| `02c-speak-no-mic-download-error.png` | Speak after a failed download: warning triangle + same "not ready" copy (error reason not shown) + Retry; disabled Continue + "Skip for now" appear | models dir made unwritable, click Download |
| `02d-speak-resumed-after-relaunch.png` | Speak resumed after quit/relaunch mid-download: subtitle says the model "prepares on your Mac" but nothing is downloading; only the small "Download" link; no navigation buttons (identical pixels to 02b) | quit while downloading, relaunch |
| `03-speak-mic-system-prompt.png` | System microphone prompt over the Speak screen (with 02c state underneath) | click Allow Microphone |
| `03b-speak-mic-denied.png` | Mic denied: card flips to "Open Settings" + recovery copy | Don't Allow |
| `04-speak-mic-granted-downloading.png` | Mic granted, model still downloading: mic card gone, only the progress line; no navigation buttons | Allow, model download in flight |
| `05-speak-ready-practice.png` | "Try your first dictation" — sample phrase + empty transcript preview + disabled Continue | download complete, model loaded |
| `06-speak-listening.png` | Hotkey held: accent border on the preview box + "Listening…" | ⌃⌥D held |
| `06b-speak-practice-empty-result.png` | Silent attempt: red "No speech detected. Try a short phrase." + "Skip for now" escape hatch appears | held 1.2 s with no speech |
| `06c-floating-indicator-while-practicing.png` | The floating indicator at the bottom of the screen during the practice dictation | region capture |
| `07-speak-practice-success.png` | Transcript + green "That's it — this works in any app." + enabled Continue | `say "Send the report by Friday morning."` while held |
| `08-type-anywhere-no-ax.png` | Type Anywhere before the grant: Open Settings + Allow Access, drag copy, disabled Finish, "Later — I'll paste with ⌘V" | Continue |
| `09-permiso-overlay.png` | The Permiso drag overlay panel (530×109, status-bar level) | Allow Access |
| `09b-permiso-overlay-over-settings-already-listed.png` | The overlay over the real Accessibility pane: "Drag Suniye Preview to the list above" while Suniye Preview is already listed with its toggle off | Allow Access after the app had been added to the list |
| `10-type-anywhere-stale-grant.png` | Stale-grant branch: orange "macOS reset this permission after an update…" copy, deep link instead of overlay | `lastKnownAccessibilityGranted=true` in prefs, relaunch, Allow Access |
| `11-dashboard-after-later-no-ax.png` | Dashboard right after "Later — I'll paste with ⌘V": Accessibility attention tile with **Grant Access** (AX surface #3) + empty state with the hotkey hint | Later |
| `12-settings-general-permissions-group.png` | Settings › General › Permissions group: Grant + Open Settings (AX surface #2) — the flat-settings reference design | sidebar › General |
| `13-type-anywhere-ax-granted.png` | Type Anywhere with AX granted: "Ready to dictate", green check, Try in Notes, enabled Finish | relaunched from a terminal that already holds AX (TCC is inherited), so the same view renders its granted branch |
| `15-dashboard-attention-tile-and-mf-nudge.png` | Dashboard top: attention tile + the post-onboarding Magic Format nudge card | history restored (≥3 results), `isEnabled=false` in LLM settings |
| `16-reference-speech-model-page.png` | Speech Model page — the flat-settings reference for model state UI | sidebar › Speech Model |
| `17-dark-welcome.png` | Welcome in dark mode | system appearance toggled |
| `18-dark-speak-ready.png` | Speak (practice-ready) in dark mode | system appearance toggled |

Not captured (code-only):
- Welcome disk-space refusal (`onboardingDiskSpaceMessage`, `OnboardingView.swift:116-121`) — needs < 2× model size free; the probe is injected, not fakeable from outside.
- Model "Loading speech model" spinner (`modelStatusLine`, :263-266) — lasts under a second on this machine.
- Permiso 300 s timeout copy (`OnboardingView.swift:429-433`).
- Overlay dismissed via the back chevron — no pixel change on the app window (only analytics), so no separate capture.
- "Finish setup first" transient in the floating indicator when the hotkey is held on Welcome (`AppState.swift:3919-3923`).
