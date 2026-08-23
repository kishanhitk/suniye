import { getCollection } from "astro:content";
import { buildSitemapXml } from "../lib/seo";

export async function GET(): Promise<Response> {
  const posts = await getCollection("blog", ({ data }) => !data.draft);
  // Posts carry a genuine freshness signal: publishDate, or updatedDate once one exists.
  const xml = buildSitemapXml(
    posts.map((p) => ({ path: `/blogs/${p.id}`, lastmod: p.data.updatedDate ?? p.data.publishDate })),
  );
  return new Response(xml, {
    headers: { "Content-Type": "application/xml; charset=utf-8" },
  });
}
