import type { FaqItem } from "../seo";
import { BREW_INSTALL, DOWNLOAD_URL, GITHUB_URL, GITHUB_RELEASES_URL, QUARANTINE_CMD, SITE_URL } from "../site";

// The homepage's copy, shared by index.astro and the page's Markdown variant
// so an agent reading text/markdown sees exactly what a browser sees.

export const HERO = {
  headline: "Speak freely.",
  lead: "Suniye is dictation built for privacy and speed: the models run on your Mac, so nothing is uploaded and the words land as fast as you say them.",
  requirements: "Apple Silicon · macOS 14+ · Open source",
} as const;

// The whole argument in two paths. Deliberately structural rather than
// benchmarked: "no round trip" is true by construction, a millisecond figure
// would need a measurement this page can't show.
export const CLOUD_PATH = [
  "You speak",
  "Your audio is uploaded",
  "A server transcribes it",
  "The text travels back",
] as const;
export const LOCAL_PATH = ["You speak", "Your Mac transcribes it", "The text is at your cursor"] as const;

export const ARGUMENT = {
  headline: "Every other dictation app sends your voice away.",
  lead: "They are built on someone else's API, so your audio has to travel there and back before a single word appears. That round trip is the wait — and the privacy question.",
  cloudNote: "Needs a connection. Your voice sits, however briefly, on a disk you don't own.",
  localNote: "Works on a plane. Nothing to upload, so there is nothing to keep.",
  latency: "177ms",
  latencyNote: "Median speech–to–text with Apple's built-in engine. A network round trip alone often costs more than that.",
} as const;

export const INTERFACE = {
  headline: "Hold a key. Talk. Let go.",
  lead: "Default is Fn/Globe; make it any shortcut you like. There is nothing else to learn.",
} as const;

export interface SpeechModel {
  name: string;
  langs: string;
  size: string;
  tag: string | null;
}

// Mirrors the in-app catalog (ASRModelCatalog.swift). Kept behind a disclosure:
// the fact that you get a choice is the point, the twelve rows are reference.
export const MODELS: readonly SpeechModel[] = [
  { name: "Apple Speech", langs: "Follows your system language", size: "Built in", tag: "macOS 26+" },
  { name: "Parakeet TDT 0.6B v3", langs: "25 European languages", size: "~680 MB", tag: "Recommended" },
  { name: "Parakeet TDT 0.6B v2", langs: "English", size: "~482 MB", tag: null },
  { name: "SenseVoice", langs: "Chinese · English · Japanese · Korean · Cantonese", size: "~240 MB", tag: null },
  { name: "Moonshine Base", langs: "English", size: "~285 MB", tag: null },
  { name: "Whisper Large v3 Turbo", langs: "Multilingual", size: "~564 MB", tag: null },
  { name: "Whisper Distil Large v3", langs: "Multilingual", size: "~529 MB", tag: null },
  { name: "Whisper Large v3", langs: "Multilingual", size: "~1.7 GB", tag: null },
  { name: "Whisper Small (English)", langs: "English", size: "~636 MB", tag: null },
  { name: "Whisper Base (English)", langs: "English", size: "~209 MB", tag: null },
  { name: "Whisper Tiny (English)", langs: "English", size: "~118 MB", tag: null },
  { name: "Cohere Transcribe", langs: "14 languages", size: "~2.9 GB", tag: "Highest accuracy" },
];

export const MODELS_SECTION = {
  headline: "Twelve ways to listen.",
  lead: "From a 118 MB model that keeps up on any Mac to a 1.7 GB one that catches everything — plus Apple's built-in engine, which downloads nothing at all. Switch whenever you like; they all run locally.",
} as const;

export interface CleanupExample {
  label: string;
  said: string;
  wrote: string;
}

// Straight from the Magic Format eval suite (evals/magic_format_cases.json and
// magic_format_advanced_cases.json) — the cases the shipped prompt is scored
// against, so the page can't claim behaviour the model doesn't have.
export const CLEANUPS: readonly CleanupExample[] = [
  {
    label: "It follows the correction, not the words",
    said: "get flowers on monday buy roses no no wait actually get lilies",
    wrote: "Get lilies on Monday.",
  },
  {
    label: "Spoken numbers become written ones",
    said: "the workshop is from eight forty five to eleven thirty and the budget is fifteen thousand dollars",
    wrote: "The workshop is from 8:45 to 11:30 and the budget is $15,000.",
  },
  {
    label: "Say it as a list and it arrives as one",
    said: "do these in order first check the logs second restart the app third send me the result",
    wrote: "Do these in order:\n1. Check the logs\n2. Restart the app\n3. Send me the result",
  },
];

export const MAGIC_FORMAT = {
  headline: "Speak like a person. Paste like an editor.",
  lead: "Magic Format cleans the transcript before it lands — on your Mac, using Apple Intelligence or a local model. Optional, and off until you turn it on.",
} as const;

export interface ToneExample {
  app: string;
  prompt: string;
  out: string;
}

// The point of per-app prompts: one sentence, three destinations, three registers.
// These are illustrative of a prompt you would write, not measured output.
export const TONES: readonly ToneExample[] = [
  { app: "Slack", prompt: "Terse. No greeting, no sign-off.", out: "Deploy is blocked on the cert renewal — ETA tomorrow." },
  { app: "Mail", prompt: "Full sentences, polite, sign off.", out: "Hi,\n\nThe deploy is blocked on the certificate renewal. I expect it to clear tomorrow.\n\nThanks!" },
  { app: "Notes", prompt: "Keep it raw. Just fix punctuation.", out: "deploy blocked — cert renewal, should clear tomorrow" },
];

export const SURFACES = ["Mail", "Slack", "Notes", "Messages", "Xcode", "VS Code", "Safari", "Chrome", "Notion", "Obsidian", "Terminal", "Figma"] as const;

export const WHERE_IT_WORKS = {
  headline: "One key, every text field.",
  lead: "No plugin, no per-app setup. The text lands at your cursor and your clipboard is left exactly as you had it.",
  tonesHeadline: "The same thought, in the right register.",
  tonesLead: "Give an app its own Magic Format prompt and Suniye uses it whenever you dictate there. Terse in chat, composed in mail, untouched in notes.",
} as const;

export const PROOF_POINTS = ["MIT licensed", "62 releases since February", "No account", "Apple Silicon & Intel", "Free, forever"] as const;

export const INSTALL = {
  headline: "Two ways in.",
  brewNote: "Homebrew clears the macOS quarantine for you. It will ask you to trust the tap first — that is Homebrew 6 asking about any third-party tap, not something specific to Suniye.",
  requirements: "macOS 14 (Sonoma) or later. Dictation works on Intel and Apple Silicon; the on-device cleanup model needs Apple Silicon.",
  status: "Alpha — expect rough edges",
} as const;

export const FAQS: readonly FaqItem[] = [
  {
    q: "Is my dictation really private?",
    a: "Your voice is captured and turned into text entirely on your Mac — the audio never touches the internet. Suniye does send a small amount of pseudonymous usage data (counts and timings, never your words), which you can switch off in Settings → Privacy; the privacy page lists exactly what is collected. Otherwise it goes online only to check for updates and to download a model the first time.",
  },
  {
    q: "Does the optional AI cleanup see my audio?",
    a: "Never. Cleanup only ever works on the text. By default it runs on your Mac, using Apple Intelligence or a local model. Only if you deliberately turn on the online option does your text reach a provider you chose — and it is off by default.",
  },
  {
    q: "Does it work offline?",
    a: "Yes. Once a model is downloaded, dictation needs no connection at all — including on a plane. The only things that use the network are update checks, the opt-out usage stats, and the online cleanup provider if you enable it.",
  },
  {
    q: "What languages can it understand?",
    a: "It depends on the model you pick. Some cover 25 European languages, others handle Chinese, Japanese, Korean, English and Cantonese, and the largest understand a broad mix. Several English-only models are smaller and faster.",
  },
  {
    q: "Why does macOS say the app is damaged?",
    a: "Only the direct .dmg download is affected. Suniye is not signed with a paid Apple Developer certificate, so macOS quarantines it on first launch. Run xattr -rd com.apple.quarantine /Applications/Suniye.app once to clear it — Suniye also offers the command right after you download the .dmg. Installing with Homebrew avoids it entirely, since brew clears the quarantine for you.",
  },
  {
    q: "How fast is it, really?",
    a: "Median speech to text is 177 ms with Apple's built-in engine — fast enough that the text is usually there before you have finished letting go of the key. Downloaded models trade a little speed for accuracy, and the first dictation after launch waits for the model to load. Turning on Magic Format adds about a second, since a second model then rewrites the transcript.",
  },
  {
    q: "Is it free?",
    a: "Completely. Free and open source under the MIT license. No subscription, no account, no third-party tracking.",
  },
];

export const CLOSING = "Your voice, your machine.";

function numbered(steps: readonly string[]): string {
  return steps.map((step, i) => `${i + 1}. ${step}`).join("\n");
}

function quoteBlock(text: string): string {
  return text
    .split("\n")
    .map((line) => `> ${line}`)
    .join("\n");
}

export function homeMarkdown(): string {
  const modelRows = MODELS.map((m) => `| ${m.name} | ${m.langs} | ${m.size} | ${m.tag ?? ""} |`).join("\n");
  const cleanupBlocks = CLEANUPS.map(
    (c) => `**${c.label}**\n\nSaid: "${c.said}"\n\nWrote:\n\n${quoteBlock(c.wrote)}`,
  ).join("\n\n");
  const toneBlocks = TONES.map((t) => `**${t.app}** — prompt: "${t.prompt}"\n\n${quoteBlock(t.out)}`).join("\n\n");
  const faqBlocks = FAQS.map((f) => `### ${f.q}\n\n${f.a}`).join("\n\n");

  return `# Suniye — Private Dictation for macOS

${HERO.headline} ${HERO.lead}

${HERO.requirements}

- Download for macOS: ${DOWNLOAD_URL}
- Homebrew: \`${BREW_INSTALL}\`
- Source code: ${GITHUB_URL}

## ${ARGUMENT.headline}

${ARGUMENT.lead}

**Cloud dictation**

${numbered(CLOUD_PATH)}

${ARGUMENT.cloudNote}

**Suniye**

${numbered(LOCAL_PATH)}

${ARGUMENT.localNote}

**${ARGUMENT.latency}** — ${ARGUMENT.latencyNote}

## ${INTERFACE.headline}

${INTERFACE.lead}

## ${MAGIC_FORMAT.headline}

${MAGIC_FORMAT.lead}

${cleanupBlocks}

## ${WHERE_IT_WORKS.headline}

${WHERE_IT_WORKS.lead}

Works in ${SURFACES.join(", ")} … and anywhere else you type.

### ${WHERE_IT_WORKS.tonesHeadline}

${WHERE_IT_WORKS.tonesLead}

${toneBlocks}

## ${MODELS_SECTION.headline}

${MODELS_SECTION.lead}

| Model | Languages | Size | Note |
| --- | --- | --- | --- |
${modelRows}

${PROOF_POINTS.join(" · ")} — releases: ${GITHUB_RELEASES_URL}

## ${INSTALL.headline}

**Homebrew (recommended)**

\`\`\`sh
${BREW_INSTALL}
\`\`\`

${INSTALL.brewNote}

**Direct download:** ${DOWNLOAD_URL}

If macOS says the app is damaged after a direct download, clear the quarantine once:

\`\`\`sh
${QUARANTINE_CMD}
\`\`\`

**Build from source:** ${GITHUB_URL}#build-from-source

${INSTALL.requirements}

${INSTALL.status}

## FAQ

${faqBlocks}

## ${CLOSING}

Download for macOS: ${DOWNLOAD_URL}

More: [About](${SITE_URL}/about) · [Contact](${SITE_URL}/contact) · [Blog](${SITE_URL}/blogs) · [Changelog](${SITE_URL}/changelog) · [Privacy](${SITE_URL}/privacy) · [llms.txt](${SITE_URL}/llms.txt)
`;
}
