import { BREW_INSTALL, DOWNLOAD_URL, GITHUB_URL, SITE_URL } from "../site";

// The homepage's copy, shared by index.astro and the page's Markdown variant
// so an agent reading text/markdown sees exactly what a browser sees.

export const HERO = {
  headline: "Speak freely.",
  lead: "Suniye is dictation built for privacy and speed: the models run on your Mac, so nothing is uploaded and the words land as fast as you say them.",
  requirements: "Apple Silicon · macOS 14+ · Open source",
} as const;

export const PRICES = {
  headline: "Voice typing that costs nothing. Not even your voice.",
  lead: "Popular dictation apps charge $8 to $15 a month and send every word you say to their servers. Suniye is free, and it runs entirely on your Mac.",
  chartTitle: "What unlimited dictation costs",
  source:
    "Pro plans for one person, billed annually: Wispr Flow $12 a month, Willow $12, Aqua Voice $8. From each app's pricing page, October 2026.",
} as const;

export interface PlanPrice {
  app: string;
  /** Dollars a month on the annual Pro plan. */
  monthly: number;
}

// From each app's pricing page in October 2026. Re-check them before changing
// the copy around them: these are the page's only claims about other apps.
export const PLAN_PRICES: readonly PlanPrice[] = [
  { app: "Wispr Flow", monthly: 12 },
  { app: "Willow", monthly: 12 },
  { app: "Aqua Voice", monthly: 8 },
];

/** The periods the price chart switches between, in years. */
export const PRICE_YEARS = [1, 3, 5] as const;

export function planCost(plan: PlanPrice, years: number): number {
  return plan.monthly * 12 * years;
}

export function formatDollars(amount: number): string {
  return `$${amount.toLocaleString("en-US")}`;
}

export function costPeriod(years: number): string {
  return years === 1 ? "in a year" : `over ${years} years`;
}

export function yearsLabel(years: number): string {
  return years === 1 ? "1 year" : `${years} years`;
}

export interface Claim {
  label: string;
  figure: string;
  caption: string;
  detail: string;
  /** "fast" sets the figure in the green a latency readout uses for a fast request. */
  tone: "accent" | "fast";
}

export const CLAIMS: readonly Claim[] = [
  {
    label: "Private",
    figure: "0 bytes",
    caption: "of your audio uploaded, ever.",
    detail:
      "Security badges describe how a company guards your recordings once it has them. Suniye never has them: the speech model runs on your own Mac. The code is public, so you can check.",
    tone: "accent",
  },
  {
    label: "Fast",
    figure: "177 ms",
    caption: "median speech-to-text.",
    detail:
      "Measured with Apple's built-in engine. There is no upload and no queue, so hotel Wi-Fi and a train tunnel make no difference.",
    tone: "fast",
  },
  {
    label: "Free",
    figure: "$0",
    caption: "a month, with no word limit.",
    detail: "No subscription, no trial, no account. Suniye is open source under the MIT license.",
    tone: "accent",
  },
];

export const SWITCHING = {
  headline: "Switching costs you nothing you use.",
  lead: "Everything you lean on in a dictation app, done on your Mac.",
} as const;

export interface Habit {
  habit: string;
  feature: string;
  detail: string;
}

export const HABITS: readonly Habit[] = [
  { habit: "Turn a ramble into tidy text", feature: "Magic Format", detail: "Follows corrections, writes numbers, makes lists" },
  { habit: "Get names and jargon right", feature: "Vocabulary", detail: "Add a word once, spelled your way" },
  { habit: "Sound right in each app", feature: "Per-app styles", detail: "Terse in chat, composed in mail" },
  { habit: "Fix a sentence by saying so", feature: "Edit Mode", detail: "Select text, say what to change" },
  { habit: "Find what you said last week", feature: "Transcripts", detail: "Searchable, and kept only on your Mac" },
];

export const CLOSING = "Your voice, your machine.";

function priceTable(): string {
  const header = `| App | ${PRICE_YEARS.map(yearsLabel).join(" | ")} |`;
  const divider = `| --- | ${PRICE_YEARS.map(() => "---").join(" | ")} |`;
  const rows = PLAN_PRICES.map(
    (plan) => `| ${plan.app} | ${PRICE_YEARS.map((years) => formatDollars(planCost(plan, years))).join(" | ")} |`,
  );
  const suniye = `| Suniye | ${PRICE_YEARS.map(() => formatDollars(0)).join(" | ")} |`;
  return [header, divider, ...rows, suniye].join("\n");
}

export function homeMarkdown(): string {
  const claims = CLAIMS.map((c) => `- **${c.figure}** ${c.caption} ${c.detail}`).join("\n");
  const habits = HABITS.map((h) => `| ${h.habit} | ${h.feature} — ${h.detail} |`).join("\n");

  return `# Suniye — Private Dictation for macOS

${HERO.headline} ${HERO.lead}

${HERO.requirements}

- Download for macOS: ${DOWNLOAD_URL}
- Homebrew: \`${BREW_INSTALL}\`
- Source code: ${GITHUB_URL}

## ${PRICES.headline}

${PRICES.lead}

### ${PRICES.chartTitle}

${priceTable()}

${PRICES.source}

## Private, fast, free

${claims}

## ${SWITCHING.headline}

${SWITCHING.lead}

| What you do | In Suniye |
| --- | --- |
${habits}

## ${CLOSING}

Download for macOS: ${DOWNLOAD_URL}

More: [About](${SITE_URL}/about) · [Contact](${SITE_URL}/contact) · [Blog](${SITE_URL}/blogs) · [Changelog](${SITE_URL}/changelog) · [Privacy](${SITE_URL}/privacy) · [llms.txt](${SITE_URL}/llms.txt)
`;
}
