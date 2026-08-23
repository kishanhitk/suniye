import { getCollection, getEntry } from "astro:content";
import { authoredMarkdown } from "./content/authored";
import { homeMarkdown } from "./content/home";
import { privacyMarkdown } from "./content/privacy";
import { RELEASES_CACHE_POLICY, changelogMarkdown, fetchReleases, type CachePolicy } from "./releases";
import { SITE_NAME, SITE_PAGES, SITE_URL, absoluteUrl } from "./site";

// The Markdown representation of every content route, keyed by Astro route
// pattern. The middleware consults this when a client prefers text/markdown.

export interface MarkdownDocument {
  body: string;
  status: number;
  /** Astro cache policy for this document, when the page's own route caches too. */
  cache?: CachePolicy;
}

type Builder = (params: Record<string, string | undefined>) => Promise<MarkdownDocument | null>;

function ok(body: string): MarkdownDocument {
  return { body, status: 200 };
}

function dateOnly(d: Date): string {
  return d.toISOString().slice(0, 10);
}

async function publishedPosts() {
  return (await getCollection("blog", ({ data }) => !data.draft)).sort(
    (a, b) => b.data.publishDate.valueOf() - a.data.publishDate.valueOf(),
  );
}

export function siteIndexMarkdown(): string {
  return SITE_PAGES.map((p) => `- [${p.title}](${absoluteUrl(p.path)}) — ${p.summary}`).join("\n");
}

export function notFoundMarkdown(pathname: string): string {
  return `# 404 — Not found

There is no page at \`${pathname}\` on ${SITE_NAME}.

## Where to look instead

${siteIndexMarkdown()}

- [Sitemap](${absoluteUrl("/sitemap.xml")}) — every indexable URL
- [llms.txt](${absoluteUrl("/llms.txt")}) — what Suniye is, when to use it, and how agents should read this site

Every page above also answers \`Accept: text/markdown\` with a Markdown version of itself.
`;
}

const builders: Record<string, Builder> = {
  "/": async () => ok(homeMarkdown()),
  "/privacy": async () => ok(privacyMarkdown()),
  "/changelog": async () => ({ ...ok(changelogMarkdown(await fetchReleases())), cache: RELEASES_CACHE_POLICY }),
  "/about": async () => pageMarkdown("about"),
  "/contact": async () => pageMarkdown("contact"),
  "/blogs": async () => {
    const posts = await publishedPosts();
    const list = posts
      .map(
        (p) =>
          `- [${p.data.title}](${absoluteUrl(`/blogs/${p.id}`)}) — ${p.data.description} (${dateOnly(p.data.publishDate)}, ${p.data.category})`,
      )
      .join("\n");
    return ok(`# Suniye Blog

Comparisons and guides on dictation for macOS, from the team building Suniye.

${list}

RSS feed: ${absoluteUrl("/rss.xml")} · Home: ${SITE_URL}/
`);
  },
  "/blogs/[slug]": async ({ slug }) => {
    if (!slug) return null;
    const post = await getEntry("blog", slug);
    if (!post || post.data.draft || !post.body) return null;
    const dates = [`Published ${dateOnly(post.data.publishDate)}`, post.data.updatedDate && `updated ${dateOnly(post.data.updatedDate)}`]
      .filter(Boolean)
      .join(", ");
    return ok(`# ${post.data.title}

${post.data.description}

_${dates}. Canonical: ${absoluteUrl(`/blogs/${post.id}`)}_

${authoredMarkdown(post.body)}

---

All posts: ${absoluteUrl("/blogs")} · Home: ${SITE_URL}/
`);
  },
};

async function pageMarkdown(id: "about" | "contact"): Promise<MarkdownDocument | null> {
  const entry = await getEntry("pages", id);
  if (!entry?.body) return null;
  return ok(`# ${entry.data.title}

${entry.data.description}

${authoredMarkdown(entry.body)}

---

Home: ${SITE_URL}/ · Canonical: ${absoluteUrl(`/${id}`)}
`);
}

export function hasMarkdown(routePattern: string): boolean {
  return routePattern in builders;
}

export async function markdownFor(
  routePattern: string,
  params: Record<string, string | undefined>,
): Promise<MarkdownDocument | null> {
  const builder = builders[routePattern];
  return builder ? builder(params) : null;
}
