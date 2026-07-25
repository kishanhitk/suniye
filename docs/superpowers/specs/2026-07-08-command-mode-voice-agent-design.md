# Command Mode — voice-driven, on-device computer-use agent (KIS-168)

## Summary

Add a voice **Command Mode** to Suniye: hold a dedicated hotkey, speak a task,
and an on-device AI agent carries it out on the Mac — the Codex Computer Use
paradigm, but voice-first and fully local. The agent is a real tool-using loop
(see → decide → act → observe → repeat), not a fixed command list and not a
script generator. It perceives the screen through the **accessibility tree**
(structured text, not pixels), reasons over it with a **downloadable larger
local model**, and acts through a small set of typed **tools**.

Privacy is the hard constraint: **nothing about the command or the screen leaves
the device.** The agent brain is a second, bigger local model the user downloads
only if they enable this feature — distinct from the ASR (transcription) and
Gemma (cleanup) models already shipped.

## Goals

- Speak a task; the agent completes it across apps, deciding the steps itself.
- Cross-app **single-shot commands** as the first shipping slice ("open Chrome",
  "paste this into Notes", "search X", scriptable-app actions), with the
  architecture already being a multi-step agent loop underneath.
- 100% on-device. Zero network calls in the command path.
- Reuse Suniye's existing voice spine, floating indicator, local-LLM download
  infra, `TextInsertionService`, and the already-granted Accessibility permission.

## Non-goals (north star — later tickets)

- **Vision / screenshots / GUI-grounding models.** Even a big local model is
  unreliable at pixel-level UI grounding; the agent's eyes are the AX tree.
  Screen Recording is not requested.
- **Deep grounding in poorly-AX'd Electron/web apps** (e.g. "reply to the last
  Slack message"). Best-effort only; the honest weak spot.
- **Cloud agent brain.** Out of scope by decision (privacy). The selectable
  provider stack could later expose a cloud option, but not here.

## Architecture — the agent loop

```
hotkey (hold) → speak task → ASR → transcript = task
      │
      ▼
  CommandModeAgent loop:
      1. read_screen()  → compact AX-tree text (frontmost app, window, elements+ids, focus)
      2. model.decide(task, tools, observation) → one tool call {name, args}
      3. safety gate (per-app approval + risk tier) → maybe confirm
      4. execute tool → result
      5. observe (auto read_screen) → feed back
      repeat until finish / ask_user / caps hit / kill switch
```

The model only ever emits a tool call. It cannot act outside the registered tool
set. Every risky action is gated (see Safety).

## Components

### 1. Command Mode trigger
- New `HotkeyService.Slot` `.command` (third slot beside `.dictation`,
  `.editMode`); default push-and-hold chord, user-configurable.
- New `DictationDestination.command` case.
- `AppState.beginCommandModeFlow` / `finishCommandMode` — a clone of the existing
  `beginEditModeRecordingFlow` / `finishEditModeSession`. Captures frontmost
  bundle id at start.

### 2. Agent brain (new model role + tool-calling)
- `LocalLLMModelCatalog` gains an **agent-model** entry (the bigger model),
  downloaded on demand via the existing `LocalLLMModelManager` + llama-server.
- **Tool-calling is new plumbing** — the current LLM layer is strictly
  text→text (no `tools`/`response_format`). Add constrained tool-calls via
  llama.cpp grammar / server tool support (or a parsed ReAct-style JSON loop).
- Model is **chosen by eval, not now** (see Testing). Candidates: a larger/
  higher-precision Gemma; strong tool-use models (Qwen family, Llama-3.x). Bar:
  reliable tool-calling, reasoning over AX text, fits RAM alongside ASR,
  acceptable latency.

### 3. Tools (registry + executors)
`AgentTool` protocol + registry; each tool = name, JSON arg schema, **risk tier**,
`execute()`. v1 set:

| tool | does | rail | status |
|---|---|---|---|
| `read_screen()` | AX tree → compact text | AX traversal | new |
| `open_app(name)` | launch / switch app | NSWorkspace | new |
| `focus(element_id)` | put cursor in a field | AX | new |
| `click(element_id)` | press button/menu/link | `AXUIElementPerformAction` | new |
| `type_text(text)` | type into focused field | `TextInsertionService` | reuse |
| `press_keys("cmd+t")` | send a shortcut | CGEvent | extend |
| `run_applescript(src)` | escape hatch | NSAppleScript | new, gated, off by default |
| `finish(summary)` / `ask_user(q)` | end / ask | loop control | new |

### 4. Perception (screen reader)
- New `ScreenReader` service: traverse the focused app's AX tree, filter to
  actionable + informative elements, assign **stable ids**, cap size, emit
  compact text (role · label/value (truncated) · id), plus frontmost app, window
  title, focused element + selection.
- Challenge = small-and-useful: prune decorative/huge containers, cap element
  count, keep ids stable within a task. Native apps clean; Electron/web messy.

### 5. Safety
- **Per-app approval** on first touch ("Allow once / Always / Deny"), persisted.
- **Risk tiers:** read = free; benign (open app, type in field) = auto; risky/
  irreversible (send, delete, post, buy, submitting `press_keys`, any
  `run_applescript`) = **confirm first** with a plain preview; timeout = no.
- **Injection defense:** screen text is treated as data, not instructions; goals
  come only from the spoken task; risky actions always need user OK. *Mitigated,
  not solved* — confirmation is the backstop.
- **Bounds:** max steps + wall-clock timeout + stuck-detection (same state twice
  → stop/ask). **Kill switch:** Esc halts instantly.
- **Sharp edges:** `run_applescript` shows the script, always confirms, opt-in.
  Agent never clicks OS security/permission/password prompts (detect + hand
  back). Sensitive apps (password managers, banking) denylisted by default.

### 6. UI / live feedback
- Floating indicator (reuse KIS-156 infra) shows the live step log ("Opening
  Mail… Clicking Reply…") and the kill switch.
- Settings page: enable Command Mode, download the agent model, set the hotkey,
  manage per-app permissions, toggle the script tool.

### 7. Permissions
- Accessibility: already granted (reused; Permiso onboarding).
- **Automation / Apple Events:** new, prompted per-app by macOS (TCC), needed
  for `run_applescript` and some app control.
- Screen Recording: **not** requested (AX-only).

## Data flow

Task text → agent loop. Each turn: `ScreenReader` → observation → model → tool
call → `ActionApprovalService` gate → tool executor → result → next observation.
Nothing leaves the device; the model client points at the local llama-server.

## Error handling & edge cases

- Unparseable/failed tool call → retry once, then `ask_user` or abort with a
  clear message. Never a silent wrong action.
- Target element id stale (UI changed) → re-`read_screen`; if still missing,
  ask/abort.
- Model loops with no progress → stuck-detection stops it.
- App won't launch / not installed → report plainly.
- Denied approval → stop, tell the user.

## Testing

- **Pure units:** `ScreenReader` (synthetic AX tree → assert compact summary +
  stable ids), risk-tier classification, loop bounds, approval logic, tool-arg
  validation.
- **Fake-model loop:** scripted tool-call sequence → assert loop executes,
  observes, stops, honors gates. Deterministic.
- **Injection tests:** observations laced with fake instructions → assert the
  agent ignores them and never auto-runs a risky action.
- **Integration:** a few real tests against a known app (open TextEdit, type,
  read back), app-hosted per project convention.
- **Evals:** extend `evals/` with a Command-Mode set (spoken task → expected
  tool sequence / end state) to pick the agent model and tune the prompt.

## Reuse map (existing files)

- `AppState.swift` — Phase/`DictationDestination`, Edit-Mode flow template,
  hotkey wiring, frontmost-bundle capture.
- `Services/HotkeyService.swift` — add the `.command` slot.
- `Services/TextInsertionService.swift` — `type_text` executor; extend CGEvent
  for `press_keys`.
- `Services/MagicFormatCoordinator.swift` / `LLMPostProcessor.swift` — provider
  pattern to extend with tool-calling for the agent client.
- `Services/LocalLLMModelManager.swift` / `LocalLLMModelCatalog` — add the agent
  model + a second llama-server lifecycle.
- Floating indicator (KIS-156) — live log + kill switch.

## Sequencing (increments — each its own PR)

1. **Skeleton loop, no new model.** Command Mode plumbing (hotkey slot,
   `DictationDestination.command`, flow) + agent-loop runner + tool registry +
   `read_screen`, `open_app`, `type_text`, `finish` + reuse the existing local
   LLM emitting constrained JSON. Prove "speak 'open Safari and type hello' →
   it happens" end-to-end, behind a feature flag. Pure-unit + fake-model tests.
2. **Tool-calling + agent model.** New model catalog entry + download + second
   llama-server + real tool-calling client. Model chosen via the eval set.
3. **Perception depth.** `ScreenReader` filtering/ids/capping; `click`/`focus`
   over real AX trees.
4. **Safety UX.** Per-app approvals, risk-tier confirmations, kill switch, live
   log, denylist, OS-prompt detection.
5. **Script escape hatch.** `run_applescript` + Automation permission + gating.
6. **Polish + settings + onboarding + broader tool/app coverage.**

## Risks & open questions

- **Model capability** — the whole feature rests on a local model being a
  reliable tool-caller. Resolve early via evals in increment 2; if no local
  model clears the bar, revisit (bigger model / selectable cloud opt-in).
- **RAM/latency** — running the agent model alongside ASR (+ optional cleanup).
  Measure; consider load-on-demand and unloading between tasks.
- **AX coverage** — Electron/web apps limit reach; scope expectations honestly.
- **Injection** — unsolved industry-wide; confirmation gating is the backstop.
- **Irreversibility** — most GUI actions can't be undone; hence confirm-before-risky.
