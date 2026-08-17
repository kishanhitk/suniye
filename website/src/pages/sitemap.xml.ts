import { buildSitemapXml } from "../lib/seo";

export async function GET(): Promise<Response> {
  return new Response(await buildSitemapXml(), {
    headers: { "Content-Type": "application/xml; charset=utf-8" },
  });
}
