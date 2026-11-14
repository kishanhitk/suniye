# Meetings

Suniye records a call or a meeting in the room. After the recording stops, it writes the transcript and then the summary. Capture, transcription and summary run on the Mac.

## Privacy

- No audio, transcript, notes or summary leaves the Mac.
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

Suniye does not tell the other people in a call that you record it. Some places need the consent of every person in a call: you are responsible for telling them. While a meeting records, **Copy Notice** in the ··· menu copies a sentence for the chat: "I’m recording this call to take notes. The recording stays on my computer."

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

A call ends when the call app releases the microphone, or holds it with its audio output off for 2 minutes. The card shows "Recording stops in 30 s." with **Stop Now** and **Keep Recording**. The recording keeps nothing after the moment the call ended.

Call detection reads the Core Audio process list. It reads nothing while no input device runs, nothing during a dictation, every second while an app waits for its delay, and every 5 s otherwise. It opens no audio device.

## Stop

- The pill, the menu bar or the meeting page: **Stop**.
- The call-ended card.
- 15 minutes with no speech on any track. The speech detector checks the audio in 10 s windows.
- 4 hours of recorded time.
- Sleep, or a closed lid with no external display.
- A full disk.
- **Quit Suniye** asks first. A logout, restart or shutdown stops and saves with no question.

After a quit or a crash during a recording, the next launch writes the transcript with no click. After a quit or a crash while the transcript is written, the meeting shows **Finish Transcript**.

## Transcript

- No speech recognition runs while the meeting records. The meeting page shows the notes, the meters and the warnings.
- After the stop, the speech model of dictation writes the transcript from the audio files. The meeting page shows "Finishing the transcript…" with the minutes done.
- A dictation goes first: the transcript waits while you dictate.
- The audio goes to the model in pieces of 2 to 12 s, cut at pauses.
- The audio files go when the transcript is final.

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
- A template's "## " headings are the sections of the summary. A section named Overview or Summary is a short paragraph; every other section is a list.
- The transcript is read in parts of at most about 4,000 tokens. The model gets each part, and your notes, with a request for at most three items for each section. Suniye joins the items in meeting order, your notes first, and drops exact repeats; the model then writes only the title and the overview. No last step can drop an item.
- The built-in sections (Decisions, Action items, Dates and numbers, Open questions) have fixed rules for what goes in them. A template that you wrote or edited goes to each part as a guide to its sections.
- The built-in templates have a **Dates and numbers** section for the dates and numbers that fit no other section.
- A template with no list section is summarized by the model in one step, or from notes on the parts when the transcript is long. So is a template so long that a part would hold less than 1,000 tokens of transcript.
- **Regenerate** writes the summary again, with the same or another template.

## Files

`~/Library/Application Support/Suniye/meetings/<meeting id>/` (`meetings-preview` for Suniye Preview)

| File | Content |
|---|---|
| `meeting.json` | Title, times, tracks, pauses, call app, status |
| `segments.jsonl` | Transcript lines |
| `notes.txt` | Your notes |
| `summary.md` | The summary |
| `you.wav`, `them.wav` | 16 kHz audio while the meeting records and until the transcript is final |

**Settings → General → Meetings** shows the space on disk and **Reveal in Finder**.
