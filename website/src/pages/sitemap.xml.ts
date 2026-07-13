import { buildSitemapXml } from "../lib/seo";

export async function GET(): Promise<Response> {
  return new Response(buildSitemapXml(), {
    headers: { "Content-Type": "application/xml; charset=utf-8" },
  });
}
