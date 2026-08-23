---
title: "About Suniye"
description: "Suniye is a free, open-source dictation app for macOS built by one developer. Speech recognition runs on your Mac, so nothing you say leaves it. Here is why it exists and how the project is run."
---

## What Suniye is

Suniye is a dictation app for macOS. You hold a key, talk, and let go; the words appear wherever your cursor is — Mail, Slack, a code editor, a browser form. The speech models run on your own Mac, so your voice is never uploaded. It is free, open source under the MIT license, and has no account, subscription, or third-party tracking.

The name is Hindi: *suniye* (सुनिये) means "please listen".

## Why it exists

Most dictation apps for the Mac are thin clients for someone else's speech API. Your audio travels to a server and the text travels back. That round trip is both the delay you feel and the reason you have to trust a privacy policy. On-device speech recognition has become good enough — and Apple Silicon fast enough — that the round trip is no longer necessary. Suniye is built on that premise: the transcription happens on the machine you are already sitting at, so there is nothing to upload and nothing for anyone to keep.

## Who builds it

Suniye is built and maintained by one developer. There is no company behind it. Development happens in the open on [GitHub](https://github.com/kishanhitk/suniye), where every commit, release, and issue is public. The project started in February 2026 and ships new releases often; each one is listed on the [changelog](/changelog).

## How it works, briefly

- **Speech recognition** runs locally through one of several bundled model options — Apple's built-in speech engine, NVIDIA Parakeet, Whisper, SenseVoice, Moonshine, or Cohere Transcribe — so you can trade download size for accuracy and language coverage.
- **Magic Format**, the optional cleanup step, fixes punctuation, numbers, and lists using Apple Intelligence or a small language model on your Mac. It is off by default, and it only ever sees text, never audio. There is also an opt-in setting to send that text to an OpenAI-compatible provider you configure yourself; nothing goes online unless you choose that.
- **Insertion** uses macOS accessibility APIs to place text at your cursor in any app, leaving your clipboard as it was.

## What the project collects

The app sends a small amount of pseudonymous usage data — counts, timings, and a coarse hardware class — to help decide which models run well on which Macs. It never sends audio, transcripts, or anything that identifies you, and you can switch it off in Settings → Privacy. The full list is on the [privacy page](/privacy).

## Status

Suniye is in alpha. It works well for daily dictation, but expect rough edges, and please report them — see [contact](/contact) for where.
