import { getCollection } from "astro:content";

export const SITE_URL = "https://suniye.app";

export const SITE_PAGES = ["/", "/changelog", "/privacy", "/blogs"] as const;

export async function buildSitemapXml(): Promise<string> {
  const posts = await getCollection("blog", ({ data }) => !data.draft);
  const paths: string[] = [
    ...SITE_PAGES,
    ...posts.map((p) => `/blogs/${p.id}`),
  ];
  const urls = paths.map(
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

export function blogPostingSchema(post: {
  title: string;
  description: string;
  publishDate: Date;
  updatedDate?: Date;
  slug: string;
}) {
  return {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    headline: post.title,
    description: post.description,
    datePublished: post.publishDate.toISOString(),
    dateModified: (post.updatedDate ?? post.publishDate).toISOString(),
    author: { "@type": "Organization", name: "Suniye", url: SITE_URL },
    publisher: { "@type": "Organization", name: "Suniye", url: SITE_URL },
    mainEntityOfPage: new URL(`/blogs/${post.slug}`, SITE_URL).toString(),
  };
}
