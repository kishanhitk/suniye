# Meetings

Suniye records a call or a meeting in the room. After the recording stops, it writes the transcript and then the summary. Capture, transcription and summary run on the Mac.

## Privacy

- No audio, transcript, notes or summary leaves the Mac.
- The audio stays on the Mac until the transcript is ready, or up to 30 days when you choose it (see [Meeting audio](#meeting-audio)).
- Anonymous counts go to analytics when that setting is on: how a recording starts and stops, its length in whole minutes, the tracks, the number of transcript lines and summary parts, the times, and the answers to the call cards. The [privacy page](https://suniye.app/privacy) lists them.

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

**Settings → General → Meetings → When a call starts**:

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

- No speech recognition runs while the meeting records. The meeting page shows the notes, the meters and the warnings.
- The pill shows a red dot, the recorded time and one level meter for the louder track. **Settings → General → Indicator → Show meeting time** (on by default) shows or hides the time.
- After the stop, the transcript model writes the transcript from the audio files. The meeting page shows "Finishing the transcript…" with the minutes done.
- **Settings → General → Meetings → Transcript model**:
  - **Same as dictation** (default): the dictation model, on the dictation engine.
  - A model you pick, the dictation model too: it loads for the transcript on an engine of its own and unloads after it, so a switch of the dictation model does not change it. Dictation keeps its model. The Mac holds both models in memory while the transcript is written.
- A dictation goes first: from the key-down to the end of the dictation, no piece of audio starts decoding. The piece that decodes at the key-down finishes.
- One transcript at a time: when two meetings wait for a transcript, the second one starts after the first one ends, with the transcript model that was set when it was asked for. Until then its page shows "Waiting for another transcript…".
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

**Settings → General → Meetings → Keep meeting audio**:

- **Until the transcript is ready** (default): the audio goes when the transcript is final.
- **7 days** or **30 days**: the audio goes that long after the end of the meeting.

Suniye checks at launch and after each transcript, with no timer. A change of the setting applies at the next check, so a wrong click deletes nothing at once. A meeting with no finished transcript keeps its audio for **Finish Transcript**. **Delete Meeting** deletes the audio at once.

While the audio is on the Mac, **Transcribe Again…** in the meeting's ··· menu writes the transcript again with the current **Transcript model**. Suniye asks first. The current transcript stays until the new one is complete: a failure or a quit keeps it. The notes and the summary stay; **Regenerate** writes the summary again. A new transcript replaces your edits to the transcript; the question says so.

## Summary

| Model | Needs |
|---|---|
| The local model (Gemma) | The Magic Format local model download, Apple Silicon |
| Apple Intelligence | macOS 26 with Apple Intelligence on |

- Suniye uses the local model when it is installed, and Apple Intelligence only when it is not.
- The summary can miss facts. The transcript has all the words.

Measured limits, 14 Nov 2026: synthetic meetings of 45 and 120 minutes, two sets, each with 6 planted facts in talk that is mostly filler, General template.

| Model | Facts in the summary, of 6 | Filler items | Filler items under Decisions |
|---|---|---|---|
| The local model | Set A: 4 to 5. Set B: 1 to 2. | 0 to 1 | 0 |
| Apple Intelligence | 4 to 5 | 14 to 79 | 0 to 38 |

- Templates: General, 1:1, Stand-up, Interview, and your own (**Settings → General → Meetings → Summary templates**).
- You can rename and edit a built-in template. **Reset to Default** brings back its shipped name and text.
- When you delete the template that is the **Default template**, General is the default again.
- A template's "## " headings are the sections of the summary. A section named Overview or Summary is a short paragraph; every other section is a list.
- The transcript is read in parts of at most about 4,000 tokens. The model gets each part, and your notes, with a request for at most three items for each section. Suniye joins the items in meeting order, your notes first, and drops exact repeats; the model then writes only the title and the overview. No last step can drop an item.
- The built-in sections (Decisions, Action items, Dates and numbers, Open questions) have fixed rules for what goes in them. A template that you wrote or edited goes to each part as a guide to its sections.
- The built-in templates have a **Dates and numbers** section for the dates and numbers that fit no other section.
- A template with no list section is summarized by the model in one step, or from notes on the parts when the transcript is long. So is a template so long that a part would hold less than 1,000 tokens of transcript.
- **Regenerate** (the arrow at the right of the tabs, on the Summary tab) opens the templates; the current one has a checkmark. The template that you pick writes the summary again. Another template also becomes the **Default template**.

## Edit

- The title: click it to edit it in place. Return or a click elsewhere keeps the new title; Esc drops it. An empty title goes back to the old one. A title that you set stays when a new summary is written.
- A transcript line: click its text to edit it; its time and speaker stay. Return or Esc ends the edit. A line that you empty goes when the edit ends. ⌘Z undoes typing while the page is open.
- While a transcript or a summary is written, the transcript cannot be edited.
- Copy, Export as Markdown, Search and Regenerate use the edited text.
- A quit, a tab change or leaving the meeting page saves the text that you typed.

## Files

`~/Library/Application Support/Suniye/meetings/<meeting id>/` (`meetings-preview` for Suniye Preview)

| File | Content |
|---|---|
| `meeting.json` | Title, times, tracks, pauses, call app, status |
| `segments.jsonl` | Transcript lines |
| `segments-draft.jsonl` | The new lines while Transcribe Again runs; they replace `segments.jsonl` when they are complete |
| `notes.txt` | Your notes |
| `summary.md` | The summary |
| `you.wav`, `them.wav` | 16 kHz audio while the meeting records, and after the transcript as long as **Keep meeting audio** says |

**Settings → General → Meetings** shows the space on disk and **Reveal in Finder**.
