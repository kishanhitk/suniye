import { SITE_URL } from "../site";

// The privacy page's copy, shared by privacy.astro and its Markdown variant.
// Prose paragraphs use Markdown emphasis; the HTML page renders that emphasis
// with `emphasisToHtml` so both representations carry the same stress.

export const PRIVACY_META = {
  title: "Suniye Privacy — What the App Collects",
  description:
    "Suniye's analytics are pseudonymous and opt-out. No audio, no transcribed text, no names — just counts, timings, and coarse hardware that help improve the app.",
} as const;

export const PRIVACY_HEADLINE = "What Suniye collects";

export const PRIVACY_INTRO =
  "Suniye runs entirely on your Mac. To improve it, the app sends a small amount of **pseudonymous usage data** — counts, timings, and hardware class. **No audio and no text ever leave your device.** It's on by default and you can turn it off any time in **Settings → Privacy**.";

export const COLLECTED: readonly (readonly [term: string, detail: string])[] = [
  ["How much you dictate", "Word and character counts per dictation — never the words themselves."],
  ["Timing", "How long each pipeline stage takes (speech recognition, AI cleanup, insertion) so we can make it faster."],
  ["Your Mac", "Hardware class — Mac model identifier (e.g. Mac15,3, not a serial), chip, CPU core counts, architecture (Apple Silicon / Intel), memory tier, and macOS version — so we know which on-device models run well on which hardware."],
  ["Language", "The interface language and the language coverage of the speech model you pick (e.g. “english”, “multilingual”) — a code only, never what you said."],
  ["What you use", "Which speech model is selected, whether AI cleanup is on, and other feature toggles — as on/off flags and counts."],
  ["Where text lands", "A coarse category of the target app (email, editor, browser, terminal, …) — never the specific app or its identifier."],
  ["Reliability", "Error types (no messages) and a coarse country. The country is derived from your connection's IP — the IP itself is never stored, but the country is kept as coarse metadata."],
];

export const NEVER_COLLECTED: readonly string[] = [
  "Your audio",
  "Any transcribed or corrected text",
  "Words you learn / custom vocabulary",
  "Your IP address",
  "Serial numbers or hardware IDs",
  "Your name, email, hostname, or username",
  "Precise location",
  "Which specific apps you use",
  "Anything you type",
];

export const HOW_IT_STAYS_PRIVATE: readonly string[] = [
  "Each install gets a random identifier so we can count returning users, but it maps to no name, email, or device serial — it can't identify you and isn't shared with anyone. This makes the data **pseudonymous**: we can see trends, never people. We collect it on a legitimate-interest basis, disclose it here, and let you opt out.",
  "Data is stored on our own Cloudflare infrastructure — never sold, never shared with third-party trackers. We keep one small record per install (its random id, the days it was first and last seen, coarse hardware — Mac model, chip, CPU cores, memory tier, macOS version — and coarse country). All per-event usage data — word counts, timings, feature flags, target-app category, error types, language, and the rest of the list above — is kept for about 90 days, after which only aggregate counts remain.",
  "Turn it off: **Settings → Privacy → Share Anonymous Analytics**. When off, nothing is sent and any queued data is discarded.",
];

export const WEBSITE_ANALYTICS =
  "This website measures aggregate, non-identifying usage — page visits, where visitors come from, and download clicks — to understand what's working. It uses **no cookies** and shows **no consent banner** because it stores no personal data and loads no third-party trackers. Unique visitors are counted with a daily-rotating, one-way hash; your IP address is never stored, and referrers are reduced to the site host only. The data lives on our own Cloudflare infrastructure and is retained about 90 days.";

function escapeHtml(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/** Renders `**strong**` spans as <strong>; everything else is escaped text. */
export function emphasisToHtml(text: string, strongClass = "text-ink"): string {
  return escapeHtml(text).replace(/\*\*(.+?)\*\*/g, `<strong class="${strongClass}">$1</strong>`);
}

export function privacyMarkdown(): string {
  const collected = COLLECTED.map(([term, detail]) => `- **${term}** — ${detail}`).join("\n");
  const never = NEVER_COLLECTED.map((item) => `- ${item}`).join("\n");
  return `# ${PRIVACY_HEADLINE}

${PRIVACY_INTRO}

## What we collect

${collected}

## What we never collect

${never}

## How it stays private

${HOW_IT_STAYS_PRIVATE.join("\n\n")}

## Website analytics

${WEBSITE_ANALYTICS}

---

Questions about this policy: [Contact](${SITE_URL}/contact). Home: ${SITE_URL}/
`;
}
