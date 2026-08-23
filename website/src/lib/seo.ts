import {
  SITE_URL,
  SITE_NAME,
  SITE_DESCRIPTION,
  SITE_PAGES,
  GITHUB_URL,
  DOWNLOAD_URL,
  GITHUB_ISSUES_URL,
  ORGANIZATION_COUNTRY_CODE,
  absoluteUrl,
} from "./site";

export interface SitemapEntry {
  path: string;
  lastmod?: Date;
}

/**
 * Static pages have no real "last changed" date to report, so they carry no
 * <lastmod> rather than a fabricated one. Callers add dated entries (blog
 * posts) where a genuine freshness signal exists.
 */
export function buildSitemapXml(extraEntries: readonly SitemapEntry[] = []): string {
  const entries: SitemapEntry[] = [...SITE_PAGES.map(({ path }) => ({ path })), ...extraEntries];
  const urls = entries
    .map(({ path, lastmod }) => {
      const loc = `    <loc>${absoluteUrl(path)}</loc>`;
      const mod = lastmod ? `\n    <lastmod>${lastmod.toISOString().slice(0, 10)}</lastmod>` : "";
      return `  <url>\n${loc}${mod}\n  </url>`;
    })
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`;
}

export function softwareApplicationSchema() {
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: SITE_NAME,
    operatingSystem: "macOS",
    applicationCategory: "UtilitiesApplication",
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    url: SITE_URL,
    downloadUrl: DOWNLOAD_URL,
    description: SITE_DESCRIPTION,
    softwareHelp: GITHUB_URL,
    license: "https://opensource.org/license/mit",
  };
}

/**
 * The project as a publisher and how to reach it. Suniye is an open-source
 * project run by one person, not a company: the address is a country and
 * nothing more specific, and contact goes through GitHub rather than a
 * personal email or phone.
 */
export function organizationSchema() {
  return {
    "@context": "https://schema.org",
    "@type": "Organization",
    "@id": `${SITE_URL}/#organization`,
    name: SITE_NAME,
    url: SITE_URL,
    logo: absoluteUrl("/suniye-icon.png"),
    description: SITE_DESCRIPTION,
    sameAs: [GITHUB_URL],
    contactPoint: [
      {
        "@type": "ContactPoint",
        contactType: "customer support",
        url: GITHUB_ISSUES_URL,
        availableLanguage: "English",
      },
    ],
    address: {
      "@type": "PostalAddress",
      addressCountry: ORGANIZATION_COUNTRY_CODE,
    },
  };
}

export function webSiteSchema() {
  return {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: SITE_NAME,
    url: SITE_URL,
    description: SITE_DESCRIPTION,
    inLanguage: "en",
    publisher: { "@id": `${SITE_URL}/#organization` },
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
    author: { "@type": "Organization", name: SITE_NAME, url: SITE_URL },
    publisher: { "@type": "Organization", name: SITE_NAME, url: SITE_URL },
    mainEntityOfPage: absoluteUrl(`/blogs/${post.slug}`),
  };
}

/** Home > Blog > Post trail, so eligible SERPs can render it as a breadcrumb. */
export function breadcrumbSchema(crumbs: { name: string; path: string }[]) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: crumbs.map((c, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: c.name,
      item: absoluteUrl(c.path),
    })),
  };
}
