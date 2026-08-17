---
title: "The best open-source dictation apps for Mac"
description: "Suniye, Handy, and FluidVoice are the real open-source options for Mac dictation right now — what each one's license actually means, and how they differ."
publishDate: 2026-08-17
category: guide
---

This list is short on purpose. Most dictation apps — Wispr Flow, Superwhisper, and macOS's own built-in Dictation among them — are closed source, however private their processing actually is. "Open source" is a narrower, checkable claim than "private": it means you or anyone else can read the code that handles your voice, not just a policy that describes it. Right now, there are three real options for macOS.

## Suniye — MIT licensed

Suniye's entire pipeline — audio capture, the eleven local speech models it ships, and its optional AI cleanup step — is public source under the MIT license. MIT is permissive: anyone can use, modify, or embed the code, including in closed-source or commercial products, as long as the license notice stays attached. Free with no paid tier, macOS only.

<a href="/" class="btn-press not-prose inline-flex items-center gap-2 rounded-full bg-ink px-6 py-3 text-[15px] font-medium text-bg no-underline hover:bg-ink/85">
  <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.365 1.43c0 1.14-.47 2.2-1.22 2.98-.79.83-2.05 1.47-3.11 1.38-.13-1.1.42-2.25 1.15-3.02.8-.84 2.16-1.45 3.18-1.34zM20.7 17.02c-.55 1.26-.81 1.82-1.52 2.94-.99 1.55-2.39 3.48-4.12 3.5-1.54.01-1.93-1-4.02-.99-2.09.01-2.52 1.01-4.06.99-1.73-.02-3.06-1.76-4.05-3.31C.16 15.8-.13 10.7 1.55 8.03c1.18-1.9 3.05-3.01 4.8-3.01 1.79 0 2.91 1 4.39 1 1.43 0 2.3-1 4.37-1 1.57 0 3.23.85 4.42 2.32-3.88 2.13-3.25 7.68 1.17 9.68z"/></svg>
  Get Suniye now
</a>

## Handy — MIT licensed, the broadest reach

Handy is also MIT licensed and free, with zero cloud component by design — there's no server anywhere in its path. It runs on macOS, Windows, and Linux, making it the only cross-platform option among the three. It supports several local model families (Whisper, Parakeet, Moonshine) and adds developer-facing extras — CLI flags, a Raycast extension — that the other two don't have.

## FluidVoice — GPLv3, with built-in AI cleanup

FluidVoice is GPLv3 licensed, which is copyleft rather than permissive: modified versions that get distributed have to stay open source too, which protects against someone forking it into a closed product. It pairs local transcription with an optional cleanup model (Fluid-1) that tidies grammar and tone — functionally similar to what Suniye's Magic Format does, built into the app by default rather than as a choice of providers. macOS only, requires macOS 15 or later.

## What the license actually changes for you

As a user, day to day, the license mostly matters for one thing: whether you trust the "your audio stays local" claim more because you can verify it, or because a company's reputation is on the line if it's false. Both are real forms of trust — open source just makes it checkable rather than assumed.

It matters more if you're a developer. MIT (Suniye, Handy) lets you build on the code with almost no restriction. GPLv3 (FluidVoice) requires anything you distribute based on it to also be open source — worth knowing before you fork one for a commercial project.

<a href="/" class="btn-press not-prose inline-flex items-center gap-2 rounded-full bg-ink px-6 py-3 text-[15px] font-medium text-bg no-underline hover:bg-ink/85">
  <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.365 1.43c0 1.14-.47 2.2-1.22 2.98-.79.83-2.05 1.47-3.11 1.38-.13-1.1.42-2.25 1.15-3.02.8-.84 2.16-1.45 3.18-1.34zM20.7 17.02c-.55 1.26-.81 1.82-1.52 2.94-.99 1.55-2.39 3.48-4.12 3.5-1.54.01-1.93-1-4.02-.99-2.09.01-2.52 1.01-4.06.99-1.73-.02-3.06-1.76-4.05-3.31C.16 15.8-.13 10.7 1.55 8.03c1.18-1.9 3.05-3.01 4.8-3.01 1.79 0 2.91 1 4.39 1 1.43 0 2.3-1 4.37-1 1.57 0 3.23.85 4.42 2.32-3.88 2.13-3.25 7.68 1.17 9.68z"/></svg>
  Download Suniye for macOS
</a>
