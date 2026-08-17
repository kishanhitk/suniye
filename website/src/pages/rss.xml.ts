import { getCollection } from "astro:content";
import { SITE_URL } from "../lib/seo";

// Hand-rolled rather than @astrojs/rss: the site already has one XML feed
// (sitemap.xml.ts) built this way with zero dependencies, and RSS is simple
// enough not to need a package for it.
function escapeXml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

export async function GET(): Promise<Response> {
  const posts = (await getCollection("blog", ({ data }) => !data.draft)).sort(
    (a, b) => b.data.publishDate.valueOf() - a.data.publishDate.valueOf(),
  );

  const items = posts.map((post) => {
    const url = new URL(`/blogs/${post.id}`, SITE_URL).toString();
    return [
      "  <item>",
      `    <title>${escapeXml(post.data.title)}</title>`,
      `    <link>${url}</link>`,
      `    <guid>${url}</guid>`,
      `    <pubDate>${post.data.publishDate.toUTCString()}</pubDate>`,
      `    <description>${escapeXml(post.data.description)}</description>`,
      "  </item>",
    ].join("\n");
  }).join("\n");

  const xml = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<rss version="2.0">',
    "<channel>",
    "  <title>Suniye Blog</title>",
    `  <link>${new URL("/blogs", SITE_URL).toString()}</link>`,
    "  <description>Comparisons and guides on dictation for macOS, from the team building Suniye.</description>",
    "  <language>en</language>",
    items,
    "</channel>",
    "</rss>",
  ].join("\n");

  return new Response(xml, { headers: { "Content-Type": "application/rss+xml; charset=utf-8" } });
}
