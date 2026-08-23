import { absoluteUrl } from "../site";

function absolutize(href: string): string {
  return href.startsWith("/") ? absoluteUrl(href) : href;
}

/**
 * Authored Markdown bodies become agent-ready: the inline HTML the posts use
 * (a styled download button, source links) turns into plain Markdown links,
 * any other tag is dropped, and site-relative links become absolute, since an
 * agent reads the body detached from the URL it came from.
 */
export function authoredMarkdown(body: string): string {
  return body
    .trim()
    .replace(/<a\s[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/g, (_, href: string, inner: string) => {
      const label = inner.replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
      return `[${label}](${absolutize(href)})`;
    })
    .replace(/<[^>]+>/g, "")
    .replace(/\]\((\/[^)\s]*)\)/g, (_, path: string) => `](${absoluteUrl(path)})`);
}
