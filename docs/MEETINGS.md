# Meetings

Suniye records a call or a meeting in the room. After the recording stops, it writes the transcript and then the summary. Capture and transcription run on the Mac. The summary runs on the Mac unless you choose a hosted summary model.

## Privacy

- No audio leaves the Mac.
- No transcript, notes or summary leaves the Mac while **Summary model** is Automatic, the default.
- With **Summary model** set to ChatGPT or API endpoint, the transcript text and your notes go to that service after each meeting, to write the summary. See [Summary model](#summary-model).
- The audio stays on the Mac until the transcript is ready, or up to 30 days when you choose it (see [Meeting audio](#meeting-audio)).
- Anonymous counts go to analytics when that setting is on: how a recording starts and stops, its length in whole minutes, the tracks, the number of transcript lines and summary parts, the times, the kind of summary model (never a model name or an address), the kind of a summary failure, the result of a ChatGPT sign-in, the answers to the call cards, the part of a meeting's text that you edit (title, transcript or summary, once for each part in a visit of the page), and the first play of its audio in a visit. The [privacy page](https://suniye.app/privacy) lists them.

## Tracks

| Track | Source | Needs |
|---|---|---|
| You | The microphone that dictation uses | Microphone access |
| Them | The sound of every other app on the Mac | macOS 14.4 or later, and System Audio Recording access (macOS asks at the first recording) |

- Other sounds that play on the Mac go into "Them" too: music, videos, notification sounds.
- The mute button of the call app does not mute Suniye. When you mute yourself in the call, Suniye still records your microphone.
- During a Suniye dictation, the "You" track records silence: the dictated words do not go into the meeting. The call app still sends your voice to the call unless you mute it there.
- On macOS before 14.4, Suniye records the microphone only, and the transcript has no speaker labels.
- On speakers, the microphone also hears the call. Suniye removes "You" lines that repeat a "Them" line. Headphones give the best transcript.

## Start

- Menu bar: **Record Meeting**.
- Meetings page: **Record Meeting**.
- A call (see [Calls](#calls)).

Suniye does not tell the other people in a call that you record it. Some places need the consent of every person in a call: you are responsible for telling them.

## Calls

Suniye finds a call from the apps that hold the microphone:

| App | A call after |
|---|---|
| Zoom, Microsoft Teams, FaceTime, Slack, Webex, Discord, WhatsApp, Skype, Telegram | 2 s |
| A browser whose window title names Google Meet, Zoom, Microsoft Teams, Webex, Jitsi or Whereby | 2 s |
| Any other browser | 20 s, and only the offer, never an automatic start |

**Settings → Meetings → When a call starts**:

- **Ask** (default): a card asks "Record this Zoom call?". It closes after 20 s. Its ··· menu has **Never Ask for Zoom** and **Meeting Settings…**.
- **Record Automatically**: the recording starts, and the card shows **Cancel** for 5 s. Cancel deletes the recording.
- **Do Nothing**: no offer and no automatic start. A meeting that records still follows its call: the call-ended card and the no-sound warning work as with the other choices.

**Never ask for** lists the apps that get no offer.

A call ends when the call app releases the microphone, or holds it with its audio output off for 2 minutes. Then a card shows:

- A recording that started by itself: "Recording stops in 30 s." with **Stop Now** and **Keep Recording**. With no click, it stops after 30 s. It keeps nothing after the moment the call ended.
- A recording that you started: "Suniye is still recording." with **Stop Recording** and **Keep Recording**. The recording goes on until you choose. **Stop Recording** stops it at that moment and keeps the talk after the call.

Call detection reads the Core Audio process list. It reads nothing while no input device runs, nothing during a dictation, every second while an app waits for its delay, and every 5 s otherwise. It opens no audio device.

## Stop

- The pill, the menu bar or the meeting page: **Stop**.
- The call-ended card.
- 15 minutes with no speech on any track. The speech detector checks the audio in 10 s windows.
- 4 hours of recorded time.
- Sleep, or a closed lid with no external display.
- A full disk.
- **Quit Suniye** asks first: "Quitting stops the recording. Finish the transcript when you open Suniye again." A logout, restart or shutdown stops and saves with no question.

After a quit or a crash, the next launch writes no transcript by itself: it does not load a speech model and run for minutes with no click. A recording that a quit or a crash stopped shows on the list with **Finish Transcript** and **Delete**, and its row has a "Not finished" tag. A transcript that a quit or a crash cut short shows **Finish Transcript**.

## Transcript

- While the meeting records, the meeting page has two tabs: **Notes** (first) and **Transcript**. The Transcript tab shows the lines a few seconds after the speech, with "You" and "Them". It follows new lines while it is scrolled to the end. The lines have no copy, edit, player or time links until the meeting ends.
- A shown line never changes, moves or goes during the call. A line shows when no earlier line can still come: the transcript of each track has reached its start. When the call plays on speakers, a "You" line also waits until the "Them" lines near it are written; a "You" line that repeats them (the microphone heard the call) never shows.
- The words of a dictation are not in the transcript: the microphone track gets silence while the dictation records.
- Lines are saved as they show. After a quit or a crash, **Finish Transcript** starts after the last saved line.
- When the transcript model cannot load at the start, the Transcript tab says "The transcript comes after you stop." with the cause, and the stop tries the model again.
- The pill shows a red dot, the recorded time and one level meter for the louder track. **Settings → Indicator → Show meeting time** (on by default) shows or hides the time.
- After the stop, the transcript model writes the rest of the transcript from the audio files: the audio after the last saved line of each track. The meeting page shows "Finishing the transcript…" with the minutes done. Lines shown during the call stay, except a "You" line that the echo filter drops because the call moved to speakers, and lines after the end of a call that a recording followed.
- **Settings → Meetings → Transcript model**:
  - **Same as Dictation** (default): the dictation model, on the dictation engine.
  - A model you pick, the dictation model too: it loads on an engine of its own when the meeting starts and unloads after the transcript, so a switch of the dictation model does not change it. Dictation keeps its model. The Mac holds both models in memory for the whole meeting.
  - The meeting uses the transcript model that was set when it started.
- A dictation goes first: from the key-down to the end of the dictation, no piece of audio decodes. Cohere Transcribe, Qwen3-ASR and Apple Speech stop the piece that decodes at the key-down, and it decodes again after the dictation. A sherpa-onnx model (Parakeet and the other downloaded ONNX models) finishes it.
- While a transcript model you picked is loaded, the key-down also warms the dictation model with a short decode of silence. While the transcript model runs, macOS takes back the memory pages of the idle dictation model, and the dictation would wait for them: 44,000 page faults and 100 ms more for a 1 s Parakeet dictation after 20 s of Cohere Transcribe. sherpa-onnx models and Cohere Transcribe warm up; Apple Speech and Qwen3-ASR run outside the app.
- One transcript at a time: when two meetings wait for a transcript, the second one starts after the first one ends, with the transcript model that was set when it was asked for. Until then its page shows "Waiting for another transcript…". A meeting that starts while another transcript is written shows its live lines after that transcript ends. A transcript asked for during a recording (Finish Transcript, Transcribe Again) starts after that recording's transcript.
- Picking a model that is not on the Mac downloads it. It becomes the transcript model when the download is done.
- When the transcript model is not on the Mac at the stop, the meeting shows that cause and **Finish Transcript**.
- The audio goes to the model in pieces of 2 to 12 s, cut at pauses.
- The audio files go when the transcript is final, or later when you keep them (see [Meeting audio](#meeting-audio)).

Measured on 14 Nov 2026 with one hour of a real meeting: AMI Meeting Corpus IN1016, 60.1 min, 4 people in a room. "You" is one person's headset and "Them" the other three; each headset is silent outside its speaker's annotated speech. The dictation model is Parakeet TDT 0.6B v3.

Limits of this measurement: one meeting, in English, with four speakers; each track holds only its own speakers' speech; talk that overlaps in the Them track counts as errors.

| Transcript model | Pass for 60.1 min | Load | Peak memory of the app | One 6 s dictation: alone → during the pass | Word error rate |
|---|---|---|---|---|---|
| Parakeet TDT 0.6B v3 (Same as dictation) | 5.4 min (9% of the meeting length) | none: already loaded | 1.85 GB | 488 ms → 406 ms | 33.1% |
| Cohere Transcribe | 11.7 min (19% of the meeting length) | 10.3 s | 4.43 GB | 409 ms → 455 ms (at most 611) | 25.4% |
| Qwen3-ASR 1.7B | 12.6 min (21% of the meeting length) | 17.8 s | 1.64 GB app + 2.85 GB helper | 361 ms → 358 ms (at most 368) | 18.8% |
| Apple Speech | 2.8 min (5% of the meeting length) | 0.2 s | 1.85 GB | 367 ms → 329 ms (at most 489) | 22.6% |

- Peak memory is the whole app with the dictation model loaded (about 1.8 GB). Apple Speech runs in a macOS service, so its model is not in the app's number. Qwen3-ASR runs in its llama-server helper; the helper's number includes its mapped model file (measured on 5 minutes of the same audio).
- After the pass, the app with Cohere Transcribe stays 0.57 GB above its level with only the dictation model.
- The dictation column for a model other than the dictation model is the median of 4 dictations during the pass, with the hold from the key-down (measured on 15 minutes of the same meeting for Cohere Transcribe and Qwen3-ASR). Before the hold, a 6 s dictation took 961 to 1,178 ms beside Cohere Transcribe and 546 to 761 ms beside Qwen3-ASR.
- The longest piece of audio decodes in 1.91 s on Cohere Transcribe, 2.55 s on Qwen3-ASR and 0.52 s on Apple Speech, so the piece in flight at the key-down ends while you speak.
- Word error rate: each track against the AMI reference words, lowercase, with no punctuation, no filler words and digits as words. Overlapping talk in the Them track counts as errors.

## Meeting audio

**Settings → Meetings → Keep meeting audio**:

- **Until the Transcript Is Ready** (default): the audio goes when the transcript is final.
- **7 Days** or **30 Days**: the audio goes that long after the end of the meeting.

Suniye checks at launch and after each transcript, with no timer. A change of the setting applies at the next check, so a wrong click deletes nothing at once. A meeting with no finished transcript keeps its audio for **Finish Transcript**, and the meeting whose audio plays keeps it until the next check. **Delete Meeting** deletes the audio at once.

### Play

While the audio is on the Mac and the transcript is finished, the Transcript tab has a player above the lines: play or pause, a position bar, and the time as the lines show it.

- A click on the time of a line plays from there. Space plays and pauses while no text that you can edit has the keyboard.
- The lines that play get a light band: two lines when two people talk at once, and between lines the line that started last. The transcript scrolls to the band until you scroll; play, a click on a time or a move of the position bar starts it again.
- The playback pauses when you open another tab or start a dictation, and it does not start again by itself. It stops when you leave the meeting page, when a recording starts and when you delete the meeting. Play is off while a meeting or a dictation records.
- The audio files hold no paused time: the playback goes from the moment of a pause to the moment of the resume, and the time jumps by the length of the pause.
- Playback only sends sound to the output and opens no input, so call detection does not see it.

While the audio is on the Mac, **Transcribe Again…** in the meeting's ··· menu writes the transcript again with the current **Transcript model**. Suniye asks first. The current transcript stays until the new one is complete: a failure or a quit keeps it. The notes and the summary stay; **Regenerate** writes the summary again. A new transcript replaces your edits to the transcript; the question says so.

## Summary

| Model | Needs |
|---|---|
| The local model (Gemma) | The Magic Format local model download, Apple Silicon |
| Apple Intelligence | macOS 26 with Apple Intelligence on |

- Suniye uses the local model when it is installed, and Apple Intelligence only when it is not. This is **Summary model: Automatic**.
- The summary can miss facts. The transcript has all the words.

### Summary model

**Settings → Meetings → Summary model**.

| Choice | Model | Where the text goes |
|---|---|---|
| Automatic (default) | The local model, else Apple Intelligence | Nowhere |
| ChatGPT | Your ChatGPT plan, default GPT-6.1 Sol | OpenAI |
| API endpoint | The Magic Format endpoint and key, with a model ID for summaries | That service |

- A hosted model (ChatGPT, API endpoint) gets the transcript text and your notes. It never gets audio.
- Suniye uses a hosted model only after you choose it and agree in its sheet. Automatic never uses one.
- A hosted model writes the summary from the whole transcript in one request, for a meeting up to about 4 hours of talk. A longer one goes to notes on parts first.
- A dictation does not stop a hosted summary.
- A meeting that waits for its summary uses the choice at the time it starts.

ChatGPT:

- **Continue with ChatGPT** opens the browser for Sign in with ChatGPT. Suniye registers itself with your account and keeps the sign-in in the macOS Keychain.
- Summaries use your ChatGPT plan. A Plus plan has one five-hour limit for all apps. **Manage usage** opens ChatGPT Settings → Usage.
- **Model** lists the models of your account.
- **Disconnect** deletes the sign-in from the Mac, asks OpenAI to end it, and sets **Summary model** to Automatic. When OpenAI does not confirm, remove the access in ChatGPT Settings → Security and login → Sign in with ChatGPT.
- A sign-in that you do not use for 30 days ends. Connect again.
- Suniye and Suniye Preview have separate sign-ins.

API endpoint:

- The endpoint and the key are the ones of Magic Format (**Edit Endpoint…**). The model ID is for summaries only.
- You agree for one endpoint host. After a change of the host, open the sheet and agree again.
- A free Gemini API key lets Google use the text to train its models. Use a paid key for meetings.
- A local server (Ollama, LM Studio) with a small context can cut a long transcript with no error. Suniye plans a hosted request for a context of 128,000 tokens.

When a hosted summary fails, the meeting page shows the cause. Suniye does not switch to another model by itself. **Summarize on this Mac** writes that one summary with the Automatic rule and leaves the setting as it is.

| Cause | Buttons |
|---|---|
| No connection, the service took too long, the service returned an error, the answer was cut short or empty | Try Again, Summarize on this Mac |
| The API key was rejected, the summary model is not set up | Meeting Settings…, Summarize on this Mac |
| Connect ChatGPT again, the account cannot use its plan in Suniye | Meeting Settings…, Summarize on this Mac |
| The ChatGPT plan limit is reached | Manage Usage, Try Again, Summarize on this Mac |

After a plan limit, Suniye sends no new ChatGPT request until you click Try Again, open the ChatGPT sheet, or start Suniye again.

Measured limits, 14 Nov 2026: synthetic meetings of 45 and 120 minutes, two sets, each with 6 planted facts in talk that is mostly filler, General template.

| Model | Facts in the summary, of 6 | Filler items | Filler items under Decisions |
|---|---|---|---|
| The local model | Set A: 4 to 5. Set B: 1 to 2. | 0 to 1 | 0 |
| Apple Intelligence | 4 to 5 | 14 to 79 | 0 to 38 |

The local model on llama.cpp `7e960f40` with the drafter ([LOCAL_GEMMA.md](LOCAL_GEMMA.md)), 21 Nov 2026, same meetings, one run: set A 4 and 4, set B 2 and 1. Before, on llama.cpp `06938ac1`: set A 4 and 4, set B 2 and 2. The summary of a 120-minute meeting takes 18 to 23 s, down from 51 to 58 s.

- Templates: General, 1:1, Stand-up, Interview, and your own (**Settings → Meetings → Summary templates**).
- You can rename and edit a built-in template. **Reset to Default** brings back its shipped name and text.
- When you delete the template that is the **Default template**, General is the default again.
- A template's "## " headings are the sections of the summary. A section named Overview or Summary is a short paragraph; every other section is a list.
- On the Mac, the transcript is read in parts of at most about 4,000 tokens. The model gets each part, and your notes, with a request for at most three items for each section. Suniye joins the items in meeting order, your notes first, and drops exact repeats; the model then writes only the title and the overview. No last step can drop an item.
- The built-in sections (Decisions, Action items, Dates and numbers, Open questions) have fixed rules for what goes in them. A template that you wrote or edited goes to each part as a guide to its sections.
- The built-in templates have a **Dates and numbers** section for the dates and numbers that fit no other section.
- A template with no list section is summarized by the model in one step, or from notes on the parts when the transcript is long. So is a template so long that a part would hold less than 1,000 tokens of transcript.
- **Regenerate** (the arrow at the right of the tabs, on the Summary tab) opens the templates; the current one has a checkmark. The template that you pick writes the summary again, with the model of **Summary model**. Another template also becomes the **Default template**. A summary that you edited is replaced only after you answer "Replace your edited summary?".

## Edit

- The title: click it to edit it in place. Return or a click elsewhere keeps the new title; Esc drops it. An empty title goes back to the old one. A title that you set stays when a new summary is written.
- A transcript line: click its text to edit it; its time and speaker stay. Return or Esc ends the edit. A line that you empty goes when the edit ends. ⌘Z undoes typing while the page is open.
- The summary and the notes are Markdown with a live preview: `#` and `##` headings, `**bold**`, `*italic*`, `-` and `1.` lists. The marks show only on the line or the span that holds the caret. Return in an item starts a new item; Return in an empty item ends the list. ⌘F opens the find bar.
- A link or a web address in the summary or the notes opens in the browser when you click it, also while you edit. A click at its first or last letter puts the caret next to it.
- While a transcript or a summary is written, the transcript and the summary cannot be edited.
- The Notes tab puts the caret in the notes when it opens, also while the meeting records. The notes can be edited at all times. An empty Notes tab shows the empty editor.
- The editor is MarkdownEngine `0.15.0` from the fork `kishanhitk/swift-markdown-engine` (commit `c80c69c`). The fork adds one change: a closed editor removes its view observers, so it does not stay in memory.
- Copy, Export as Markdown, Search and Regenerate use the edited text.
- The meetings list and Search read the summary and the notes as plain text: no list numbers, no bold, italic, code or link marks. Search leaves out the headings of the summary and finds the headings of the notes. Each line shows as it does in the editor.
- A quit, a tab change or leaving the meeting page saves the text that you typed.

## Files

`~/Library/Application Support/Suniye/meetings/<meeting id>/` (`meetings-preview` for Suniye Preview)

| File | Content |
|---|---|
| `meeting.json` | Title, times, tracks, pauses, call app, status |
| `segments.jsonl` | Transcript lines |
| `segments-draft.jsonl` | The new lines while Transcribe Again runs; they replace `segments.jsonl` when they are complete |
| `notes.txt` | Your notes, as Markdown |
| `summary.md` | The summary |
| `you.wav`, `them.wav` | 16 kHz audio while the meeting records, and after the transcript as long as **Keep meeting audio** says |

**Settings → Meetings → Meeting files** shows the space on disk and **Show in Finder**.
