# Competitive landscape: voice-driven computer use

Date: 2026-08-13
Status: Research. Compiled from three web-research passes (dictation apps, computer-use
agents, voice-driven assistants). Source caveats are listed at the end.
Related documents: `always-listening-ux-plan.md`, `always-listening-implementation-plan.md`.

## 1. Summary

The market splits into three layers. Suniye competes in all three after KIS-168/169:

1. **Dictation apps** (Suniye today): crowded. Wake words and spoken replies are rare.
2. **Computer-use agents** (KIS-168): every large vendor runs the agent in a cloud VM or a
   browser sandbox. Local control of the user's own Mac is nearly empty as a product
   category.
3. **Voice-driven assistants** (KIS-169): the intersection. No shipping product combines
   always-listening wake word, local computer control, spoken replies, and a local-first
   privacy posture. The closest matches are open-source prototypes.

The combination Suniye is building — on-device wake word, accessibility-tree agent on the
user's own machine, user's own model key, local TTS replies, open source — has no direct
competitor as of August 2026.

## 2. Cross-layer feature matrix

Products most relevant to KIS-169. WW = wake word. Local control = clicks and types in real
desktop apps on the user's machine.

| Product | WW / always-listening | Barge-in | Local computer control | Speaks back | Local vs cloud | Open source | Price |
|---|---|---|---|---|---|---|---|
| **Suniye (planned)** | Yes ("Hey Suniye") | Yes | Yes (a11y tree) | Yes (local Chatterbox) | Local ASR/WW/TTS; user-key model | Yes (MIT) | Free |
| Apple Siri AI (macOS 27, ~Sep 2026) | Yes | **No** | Yes (App Intents, Apple apps) | Yes (expressive, M3+) | On-device + Private Cloud Compute + Gemini backend | No | Free w/ hardware |
| ChatGPT Voice + Agent (Jul 2026) | No (VAD in app) | Yes (over-eager) | **No** (agent = cloud VM, browser only) | Yes | Cloud | No | $20–200/mo |
| Claude Voice + Cowork Dispatch | No | Yes | Yes (local desktop, per-action approval) | Yes (voice mode separate from control) | Cloud models, local actuator | No | Pro $20+ |
| Gemini Mac app + Spark | No desktop WW | Yes (toggle) | Yes (a11y + screen access) | Yes (Gemini Live) | Cloud | No | $4.99–99.99/mo |
| Microsoft Copilot (Win11) | Yes ("Hey Copilot", opt-in) | Yes | Isolated Agent Workspace only (RDP child session) | Yes | Local spotter, cloud answers | No | Free–$30/seat |
| Ace (General Agents) | No | Not documented | Yes (pixels + clicks) | No | Local actuation, **cloud model API** | No | Research preview |
| Talon Voice | Yes (always-on + sleep/wake phrases) | n/a (deterministic) | Yes (grammar-based) | No | Fully local | Core closed | Free / Patreon |
| Spokenly | No | n/a | Yes (Shortcuts, MCP, app launch) | Yes (agent questions) | Local ASR, BYOK cloud | No | Free |
| Super Voice Mode | No (hold key) | — | Via connected LLMs | Yes (on-device) | Local ASR | No | $11/mo |
| Wispr Flow | Yes ("Hey Flow") | — | No (text transforms only) | No | Cloud | No | $12/mo |
| Samuel (OSS prototype) | Yes ("Hey Samuel") | Yes | Yes (a11y tree + computer-use fallback) | Yes (<500 ms, OpenAI Realtime) | Cloud reasoning, local memory | Yes | BYO key |

## 3. Layer 1: dictation apps

Full matrix and citations are in the research pass output; condensed findings:

- **Always-listening is rare.** Only Talon, macOS Voice Control, and Wispr Flow ("Hey
  Flow") have it. Superwhisper, VoiceInk, MacWhisper, Aqua Voice, Willow, and
  BetterDictation are hold-key or toggle only.
- **Agent modes are thin.** Talon and macOS Voice Control are deterministic grammar
  systems. Spokenly has a real agent mode (app launch, Apple Shortcuts, MCP server) with
  TTS for agent questions. Super Voice Mode connects dictation to Claude, Codex, Cursor,
  Ollama, and local LLMs with spoken replies. Wispr Flow's "Command Mode" rewrites text
  only, although its marketing suggests more.
- **TTS speak-back is nearly absent.** Only Spokenly and Super Voice Mode ship it.
- **Open source + local-first is held only by VoiceInk** (GPL v3, whisper.cpp, ~4.3k
  stars). Its LLM formatting is cloud BYOK; it has no agent mode, wake word, or TTS.
- **Privacy contrast is available.** Aqua Voice and Willow are cloud-default. Wispr Flow
  invalidated its SOC 2 Type II and ISO 27001 certifications in March 2026 and has an
  unverified report of periodic active-window screenshot uploads.

## 4. Layer 2: computer-use agents

- **Large vendors do not control the user's machine.** OpenAI's agent mode (formerly
  Operator) runs in a hosted cloud VM and cannot touch local apps or files. Google's
  Gemini Computer Use model is browser-optimized with no OS-level control (Project Mariner
  shut down May 2026). Amazon Nova Act is a cloud browser service. Microsoft Copilot
  Studio's computer use (GA May 2026) runs on Windows 365 cloud PCs.
- **Local-machine actuation exists in three places.** Ace by General Agents (native Mac,
  pixels and clicks, but model inference goes through their cloud API, so it is not
  private). Open Interpreter's OS mode (CLI-first, experimental). Simular Agent S3 (an
  open-source developer framework, 72.6% on OSWorld — above the ~72.4% human baseline).
  Anthropic Cowork's "Dispatch" (GA April 2026) also actuates the local desktop with
  per-action approval, folder-scoped inside the Claude app.
- **Accessibility trees outperform pixels.** Agent S3 (a11y + pixels) posts 72.6% OSWorld;
  OpenAI's pixel-based CUA posts 38.1%. DOM-based Browser Use posts 89.1% WebVoyager.
  Suniye's accessibility-tree mechanism is the measurably better-performing approach.
- **OSWorld is the benchmark to cite.** Browser-only agents cannot post a score on it,
  which separates "browser agents" from "computer agents" in positioning.
- **Interruption is weakly done.** Ace has no documented interrupt UX. OpenAI offers
  stop/takeover. Claude asks permission before new apps. Mid-run spoken correction, as
  specified in the KIS-169 UX plan, is not shipped by anyone.
- **Vendor risk is a documented buyer objection.** Vercept "Vy" was acquired by Anthropic
  and shut down in March 2026. Rewind/Limitless was acquired by Meta and its Mac app shut
  down in December 2025. Independence and open source are positioning assets here.

## 5. Layer 3: voice-driven assistants

- **Siri AI** (macOS 27, GA ~September 2026) is the platform incumbent: wake word,
  App Intents control of Apple apps, multi-step chaining, expressive voices (M3+, 12 GB).
  Two exploitable weaknesses: **no barge-in** (the most-cited reviewer complaint) and a
  trust problem (heavy queries route to a Gemini backend that Apple does not advertise).
  App Intents control does not extend to arbitrary third-party apps the way an
  accessibility-tree agent does.
- **ChatGPT Voice** (July 2026) can voice-drive Codex and agents, but the agent itself is
  a cloud VM that cannot touch the local machine. Its over-eager voice-activity detection
  (interruptions from coughs and pauses, no push-to-talk) is the top complaint.
- **Claude** keeps voice and computer control separate: voice mode converses; Cowork
  Dispatch controls the desktop; voice does not trigger the agent.
- **Microsoft Copilot** has the settled wake-word privacy convention: on-device spotter,
  a 10-second in-memory buffer that is never stored, audio leaves the machine only after
  the wake word. "Hey Copilot" is opt-in and off by default. Its Copilot Actions run in an
  isolated workspace, not the user's session.
- **Open-source prototypes already combine the pieces.** Samuel ("Hey Samuel" wake word,
  barge-in, sub-500 ms replies, accessibility tree, risk-gated actions, local memory;
  cloud reasoning). Mac "Agent!" (on-device hotword, auto-loop listening, 18 LLM
  providers). Fazm (local-first, argues cloud audio leaks spoken passwords and that
  200–500 ms of cloud latency "breaks direct control"). These validate the architecture
  but none is a polished consumer product.

## 6. UX patterns to adopt

These match or refine decisions already in the UX plan:

1. **On-device wake-word spotting with a bounded in-memory buffer.** The industry
   convention (Microsoft: 10 s, never stored). Suniye's plan already keeps all audio
   local; state the buffer bound explicitly in the privacy copy.
2. **Barge-in without false triggers.** Barge-in is the dividing line between assistants
   reviewers like and dislike, but ChatGPT shows the failure mode: over-eager VAD. The
   wake-word-gated interruption in the UX plan (a new turn requires "Hey Suniye") avoids
   this failure by construction.
3. **A sleep phrase.** Talon's "go to sleep" / "wake up" solves the
   forgot-it-was-listening failure mode. Consider "Hey Suniye, stop listening" as a
   natural-language route to the Off state, in addition to the menu bar and shortcut.
4. **Visible always-listening state.** Universal expectation; already in the plan
   (menu-bar indicator, macOS mic dot).
5. **Risk-gated approval for destructive actions.** The trusted pattern across Samuel,
   Copilot Actions, and Claude. Deferred in Suniye by product decision; the landscape
   confirms it will be expected at GA.
6. **Takeover for auth walls.** OpenAI's pause-and-hand-back for logins and CAPTCHAs is a
   proven answer to a problem Suniye will hit; worth adopting when it does.
7. **Sub-500 ms spoken-reply start** is the praised bar (Samuel via OpenAI Realtime).
   Chatterbox measures ~0.9 s per sentence locally; acceptable, but latency work has a
   target number.

## 7. Positioning

Claims the research supports:

- **The empty quadrant.** No product combines always-listening + local computer control +
  spoken replies + local-first privacy + open source. Nearest neighbors: Spokenly (no wake
  word, closed), Samuel (prototype, cloud reasoning), Ace (cloud model, no voice), Siri AI
  (Apple apps only, no barge-in, Gemini backend).
- **"Your agent runs on your Mac, not in someone's data center."** True against OpenAI,
  Google, Amazon, and Microsoft, and marketing-defensible against Ace (cloud model API).
- **Accessibility tree over pixels** is a reliability claim with public benchmark support.
- **Independence.** The Vy and Rewind shutdowns give the open-source, local-first pitch a
  concrete customer fear to answer.

Risks:

- **Sherlocking.** Siri AI ships with macOS 27 around September 2026. It is free,
  integrated, and will normalize voice-driven Mac control. Suniye's answers are barge-in,
  arbitrary-app control, privacy, and open source — these must stay visibly true.
- **Convergence on local actuation.** Claude Cowork, Gemini Spark, and Copilot Actions all
  moved onto the local desktop via accessibility APIs in 2026. The window in which "local
  agent" alone differentiates is closing; "local + voice + open" is the durable position.
- **Prompt injection is the category risk.** Anthropic reports 11.2% residual attack
  success after mitigations; Microsoft warns loudly about XPIA; a zero-click exploit
  (ShadowPrompt) was demonstrated against a browser agent. Local execution plus approval
  gates limit blast radius but do not remove the risk. This strengthens the case for the
  deferred safety work before GA.

## 8. Source reliability

- Vendor documentation and changelogs were used where reachable. OpenAI and Anthropic
  block automated fetching, so several 2026 product names (GPT-Live, Appshots, Cowork
  "Dispatch") rest on secondary outlets (TechCrunch, 9to5Mac, 9to5Google corroborate the
  core launches).
- Many dictation-app "reviews" are published by competing vendors (Spokenly, Voibe,
  MetaWhisp, and others) and carry bias. Pricing and feature specifics should be verified
  on each vendor's site before external use.
- Benchmark numbers (OSWorld, WebVoyager) trace to vendor model cards and papers and are
  higher confidence.
- The Wispr Flow screenshot-upload report is a single unverified user claim; do not use it
  in marketing.
