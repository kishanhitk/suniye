# Always-listening Computer Use UX plan

Date: 2026-08-13

Status: proposed UX only. This document does not specify implementation architecture, models,
APIs, or code.

## Goal

Let the user start, continue, correct, or stop a Computer Use task by speaking from anywhere on
the Mac. Suniye should not need to be open or in front. The experience should feel like one
continuous conversation, not a sequence of unrelated voice commands.

Always listening is optional and off by default.

## Core product rules

- Voice Activation is an explicit mode that the user turns on or off.
- The default wake phrase is **“Hey Suniye.”** The phrase is shown wherever Voice Activation is
  configured so the user does not need to remember it.
- Hearing only the wake phrase does not create a chat message.
- Speech after wake-up becomes a normal user turn in the current Computer Use conversation.
- The user does not need to name an app or describe how to perform the task. Requests such as
  “check my battery health,” “make the screen brighter,” and “open my latest invoice” are valid.
- Every later voice turn continues the current conversation until the user explicitly starts a
  new conversation or clears it.
- There are no mandatory command phrases beyond the wake phrase. “Stop,” “wait,” “not that,”
  “use Chrome instead,” and similar speech are understood as natural conversational turns rather
  than matched against an exact command list.
- The existing physical stop controls remain available. Escape and the visible Stop control are
  the fastest unambiguous ways to cancel an active run.

## Entry points

### Settings

Computer Use settings contain a **Voice Activation** section with:

- an on/off toggle;
- the current wake phrase, and the spoken off-switch phrase (“Hey Suniye, stop listening”);
- a short **Try wake phrase** flow;
- an optional global shortcut to toggle Voice Activation;
- a sound-feedback toggle;
- the selected microphone and a shortcut to microphone settings;
- a **Voice Output** subsection: an on/off toggle (off by default) and a voice picker. Speech is
  generated on-device by default (Chatterbox). An optional cloud provider (Fish Audio) with its
  own API key is available for maximum expressiveness; choosing it explains that response text is
  sent to that provider.

Turning Voice Activation on for the first time explains, with concrete numbers, how listening
works: audio is processed on the Mac in a rolling in-memory buffer of at most 35 seconds, is
never written to disk, and nothing leaves the machine while Suniye waits for the wake phrase.
The user must confirm this once. This is an enablement notice, not a repeated approval before
each task.

### Menu bar

The Suniye menu shows the current Voice Activation state and provides one-click actions to:

- turn Voice Activation on or off;
- open the current Computer Use conversation;
- stop the current task when one is running.

### Global shortcut

The optional shortcut toggles Voice Activation. It does not start a new conversation and does not
require the Computer Use screen to be open.

## User-visible states

### 1. Off

Voice Activation is disabled. Suniye does not wait for a wake phrase.

The menu bar says **Voice Activation Off**. Turning it on moves to Ready.

### 2. Ready

Suniye is waiting for “Hey Suniye.” The menu bar uses a quiet, persistent listening indicator so
the user can always tell that the mode is active.

No conversation entry is created while Suniye is merely waiting. Ambient speech must not appear
in Computer Use history.

### 3. Listening

After the wake phrase, Suniye gives brief visual feedback and, if enabled, a subtle sound. A small
floating indicator appears near the current screen edge with:

- **Listening…**;
- a live voice-level animation;
- a Cancel control.

The user speaks naturally and does not hold a key. Suniye automatically recognizes when the user
has finished the turn. The indicator briefly shows the captured transcript before submission so
obvious recognition mistakes are visible.

If no meaningful speech follows the wake phrase, the indicator closes and Suniye returns to Ready
without creating a chat turn.

### 4. Working

The floating indicator changes to a compact generic working state. It does not show internal
transport details. It contains:

- a short shimmering status label. It starts as **Working…** and updates with a brief,
  plain-language description of the current step (for example **Opening Chrome…** or
  **Checking your last 5 emails…**). The agent is instructed to keep emitting these
  one-line statuses as it works; each names the user-visible action, never internal
  transport, provider, or tool-call details;
- a Stop control;
- an **Open conversation** action.

The Computer Use screen does not open automatically. If the user opens it, the spoken request,
tool activity, and assistant response appear in the existing chat UI.

### 5. Listening during a task

While Computer Use is working, Suniye remains available for another spoken turn. The user says
“Hey Suniye” and then speaks a correction, clarification, follow-up, or request to stop.

Examples:

- “Wait, use Safari instead.”
- “No, I meant the latest invoice.”
- “Don’t send it yet.”
- “Stop.”

The new transcript appears as another user message in the same conversation. Suniye acknowledges
that it heard the intervention and applies it before the agent chooses another action. If one
atomic action is already in progress, that action finishes first; the correction then governs the
next decision.

Suniye does not use an exact local phrase matcher for spoken stop or correction commands. The
meaning comes from the full spoken turn and conversation context. Escape and the visible Stop
control remain immediate cancellation controls when the user does not want semantic
interpretation.

One exception exists for mode control. Turns such as “Hey Suniye, stop listening” turn Voice
Activation off through a small local intent check, not through the conversation. Mode control
must work when no model is configured and no task is running, so it cannot ride the semantic
path. The recognized phrasing is shown in Settings next to the wake phrase. This exception
covers turning listening off only; task control stays conversational.

This wake-gated interruption design is deliberate. Voice-activity-based interruption, where any
sound can barge in, is the top complaint against assistants that use it (false triggers from
coughs and pauses). Requiring the wake phrase for a new turn avoids that failure by
construction. Do not replace it with VAD-based barge-in.

### 6. Needs input

When the task cannot continue without the user, the floating indicator says **Needs your input**
and may play a subtle prompt sound. The user can answer by saying “Hey Suniye” and speaking the
missing information. The answer continues the same conversation.

Suniye must not repeatedly announce or speak sensitive information while waiting.

### 6a. Your turn (manual handoff)

Some blockers cannot be answered by voice: login screens, CAPTCHAs, two-factor prompts, and
anything involving a password. For these, the indicator switches to **Your turn** with a short
reason, for example “Your turn — finish signing in to Gmail.” The agent stops acting and does
not observe the screen while the handoff is active.

The user completes the step by hand, then resumes with “Hey Suniye, continue,” the Continue
control on the indicator, or a typed message. The run continues in the same conversation from a
fresh observation. If the user does nothing, the run stays parked; it does not time out into a
failure while a handoff is pending.

Suniye never asks the user to speak a password or code, and never displays one in the
indicator.

### 7. Completed or failed

The floating indicator briefly shows a concise result:

- **Done** with the final response; or
- **Couldn’t finish** with a short reason and an Open conversation action.

It then dismisses automatically. Voice Activation returns to Ready, and the current conversation
is preserved.

The next wake-up continues that conversation. A new conversation begins only when the user chooses
**New conversation** or **Clear conversation**.

## End-to-end flows

### Start a task from anywhere

1. Voice Activation is Ready.
2. The user says, “Hey Suniye.”
3. Suniye shows Listening.
4. The user says, “Check my battery health and tell me the result.”
5. Suniye detects the end of the turn and briefly shows the transcript.
6. The indicator changes to Working.
7. Computer Use performs the task without opening the Suniye window.
8. Suniye shows the result, then returns to Ready.

### Correct an active task

1. Computer Use is Working.
2. The user says, “Hey Suniye, use Chrome instead.”
3. The correction appears as a new user turn in the current conversation.
4. The active atomic action finishes if necessary.
5. Computer Use continues from a fresh view of the Mac using the correction.

### Stop an active task by voice

1. Computer Use is Working.
2. The user says, “Hey Suniye, stop.”
3. The spoken turn is added to the current conversation and interpreted in context.
4. Suniye stops before another action begins and shows **Stopped**.
5. Voice Activation returns to Ready and keeps the conversation.

For immediate non-conversational cancellation, the user presses Escape or clicks Stop.

### Turn Voice Activation off

The user turns it off from Settings, the menu bar, the configured toggle shortcut, or by saying
“Hey Suniye, stop listening.” The spoken route confirms with a brief indicator flash and a cue
sound, and works with no model configured. Any active Computer Use task remains visible and
controllable, but Suniye no longer waits for spoken turns. Turning off listening does not
silently erase or create a conversation.

## Conversation behavior

- Voice and typed messages share one Computer Use conversation.
- A wake phrase is never displayed as message content.
- The captured request appears as the user actually said it, with a lightweight opportunity to
  catch obvious transcription errors.
- Follow-ups inherit recent conversation context. Users should not need to repeat app names,
  files, or earlier corrections.
- Tool calls remain collapsed, minimal chat activity. Transport requests, raw provider payloads,
  and internal lifecycle events are not presented as normal conversation content.
- Opening or closing the Computer Use screen does not create, end, or replace the session.

## Feedback and visual language

The floating indicator is intentionally small. It communicates only the state the user needs:

- Ready is represented in the menu bar, not by a permanent floating panel.
- Listening uses a live voice-level animation.
- Working uses shimmering text with brief step status; it falls back to **Working…** when no
  clear step description exists.
- Needs input uses a distinct but non-alarming accent.
- Done, Stopped, and Couldn’t finish are brief terminal states.

There is one Stop control in any surface. The floating indicator must not show both an inline Stop
button and a second Stop action below the status.

Audio feedback is subtle and optional. Sounds distinguish wake-up, end of turn, needs input, and
completion without reading the task aloud.

## Spoken responses (Voice Output)

When Voice Output is enabled, Suniye speaks at turn boundaries — and only there:

- **Done**: the final response is read aloud.
- **Couldn't finish**: the short reason is read aloud.
- **Needs input**: the question is read aloud so the user can answer hands-free.

Rules:

- Step statuses, tool activity, and intermediate thoughts are never spoken. The existing
  non-goal stands.
- Speech is **interruptible (barge-in)**: saying the wake phrase, pressing Escape, or starting
  any new turn stops playback immediately. Suniye must not wake itself from its own speech.
- The sensitive-information rule extends to speech: content the indicator must not display,
  the voice must not read aloud.
- Voice Output is off by default and independent of Voice Activation — either can be on alone.
- If speech synthesis fails or is slow, the visual result appears immediately regardless;
  speech is additive, never load-bearing.
- Latency budget: the visual result appears immediately; speech starts within 1 second of the
  terminal state, with 500 ms as the target. If synthesis has not started within 2 seconds,
  skip speech for that turn rather than speak late.

### Follow-up window (experimental, off by default)

A setting enables a short follow-up window after a task completes: for about 6 seconds after
the Done flash, Suniye listens for a follow-up without requiring the wake phrase again, so
"also check the charger" works as a natural continuation. The indicator stays visible in the
listening treatment for the duration of the window, so the user can always see that Suniye is
listening. Speech that does not arrive within the window, or silence, returns to Ready without
creating a turn. The window never opens after Stopped or after a failure. This behavior ships
behind a default-off setting until real-world use shows the false-capture rate is acceptable.

## Privacy and trust UX

- Voice Activation is off by default.
- Voice Output is on-device by default — spoken responses never leave the Mac. Only the optional
  cloud voice tier sends response text to its provider; selecting it states plainly what is sent
  (response text; never audio, never the wake stream), and it uses its own key.
- The microphone-in-use state is always visible in the menu bar and through normal macOS privacy
  indicators.
- Settings explain, in plain language, the difference between waiting for the wake phrase and
  recording a conversational turn.
- Speech heard before wake-up is not shown in chat or history. It exists only in a rolling
  in-memory buffer of at most 35 seconds and is never written to disk. The same bound appears in
  the enablement notice and in Settings.
- The transcript after wake-up is visibly associated with the current Computer Use conversation.
- Turning Voice Activation off has an immediate, visible effect.
- Microphone, Accessibility, and Screen Recording permission problems name the missing permission
  and offer a direct route to the relevant setting.

## Error and edge-case behavior

### False wake-up

If Suniye wakes accidentally but receives no meaningful request, it quietly returns to Ready. It
does not create an empty conversation turn or start Computer Use.

### Speech is unclear

If the transcript is too uncertain to act on safely, Suniye asks the user to repeat or clarify. It
does not guess an irreversible intent.

### Another turn arrives while listening

Suniye completes the current speech turn before accepting another wake-up. It never runs two
microphone captures or two Computer Use action loops concurrently.

### Another turn arrives while working

The new speech becomes a same-session intervention. It does not create a second task or a new
conversation.

### Provider or network failure

Suniye shows **Couldn’t finish** with a concise retry path. Voice Activation remains Ready, and the
conversation remains available for “try again” or a changed instruction.

### Missing permissions

Suniye captures the user’s request, explains which permission is missing, and keeps the request in
the current conversation. It does not repeatedly reopen System Settings or repeatedly ask for the
same permission.

### Mac sleeps or locks

Voice Activation visibly leaves Ready. On wake or unlock, it returns to its prior enabled state
only when microphone use can resume normally.

## Explicit non-goals for this UX

- Voice Activation does not make Suniye speak every tool call or intermediate thought.
- It does not automatically open the Computer Use screen.
- It does not start a new session for every transcript.
- It does not require the user to name a target application.
- It does not use a list of deterministic phrases for stop, correction, or task intent.
- It does not add per-action approval prompts.
- It does not replace the existing hold-to-talk Computer Use shortcut; that remains a deliberate,
  lower-ambient-listening alternative.

## UX acceptance criteria

The UX is ready for implementation when the following can be tested from a user’s perspective:

1. The user can turn Voice Activation on and off and always tell which state it is in.
2. “Hey Suniye” starts a natural task without opening the Suniye window.
3. The end of a spoken turn does not require a button or fixed pause ritual.
4. A second spoken turn corrects or continues the same task and conversation.
5. Natural stop language is handled as conversation, while Escape and Stop cancel immediately.
6. Completing a task returns to Ready without discarding the current conversation.
7. Ambient speech before wake-up does not appear in chat or history.
8. False wake-ups and empty speech do not create tasks.
9. Missing permissions and provider failures are recoverable without losing the spoken request.
10. The user can use the existing hold-to-talk route with Voice Activation disabled.
11. With Voice Output on, results and questions are spoken; speaking the wake phrase or pressing
    Escape interrupts playback instantly, and Suniye never wakes itself from its own speech.
12. When a task hits a login or CAPTCHA, the user can complete it by hand and resume with
    "Hey Suniye, continue" without losing the run or the conversation.
13. "Hey Suniye, stop listening" turns Voice Activation off, with visible confirmation, even
    when no model is configured.
