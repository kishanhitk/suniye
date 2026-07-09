export const SITE_URL = "https://suniye.app";

export const SITE_PAGES = ["/", "/changelog", "/privacy"] as const;

export function buildSitemapXml(): string {
  const urls = SITE_PAGES.map(
    (path) => `  <url>\n    <loc>${new URL(path, SITE_URL).toString()}</loc>\n  </url>`,
  ).join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`;
}

export function softwareApplicationSchema() {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "Suniye",
    operatingSystem: "macOS",
    applicationCategory: "UtilitiesApplication",
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    url: SITE_URL,
    downloadUrl: "https://github.com/kishanhitk/suniye/releases/latest/download/Suniye.dmg",
    description:
      "Open-source, local-first dictation for macOS. Hold a key, speak, and your words appear at your cursor. No audio leaves your machine.",
    softwareHelp: "https://github.com/kishanhitk/suniye",
  };
}

/** Serialize a schema for a JSON-LD <script>; escapes "<" so text can't close the tag. */
export function jsonLdString(schema: unknown): string {
  return JSON.stringify(schema).replace(/</g, "\\u003c");
}

export interface FaqItem {
  q: string;
  a: string;
}

export function faqPageSchema(faqs: readonly FaqItem[]) {
  return {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqs.map((item) => ({
      "@type": "Question",
      name: item.q,
      acceptedAnswer: { "@type": "Answer", text: item.a },
    })),
  };
}
