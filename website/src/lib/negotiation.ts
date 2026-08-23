// Accept-header negotiation between the two representations every content
// page has: HTML for browsers, Markdown for agents (acceptmarkdown.com).
// RFC 9110 §12.5.1: rank by q-value, tie-break by specificity, q=0 excludes.

import { absoluteUrl } from "./site";

export type Representation = "html" | "markdown";

export const MARKDOWN_TYPE = "text/markdown";
export const HTML_TYPE = "text/html";

interface AcceptEntry {
  type: string;
  subtype: string;
  q: number;
}

function parseAccept(header: string): AcceptEntry[] {
  return header
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean)
    .flatMap((part) => {
      const [mediaRange, ...params] = part.split(";").map((p) => p.trim());
      const [type, subtype] = mediaRange.toLowerCase().split("/");
      if (!type || !subtype) return [];
      let q = 1;
      for (const param of params) {
        const [key, value] = param.split("=").map((p) => p.trim());
        if (key?.toLowerCase() === "q" && value !== undefined) {
          const parsed = Number.parseFloat(value);
          // An unparseable q is ignored rather than read as q=0, which would
          // turn a typo into a 406.
          if (Number.isFinite(parsed)) q = Math.min(1, Math.max(0, parsed));
        }
      }
      return [{ type, subtype, q }];
    });
}

interface Match {
  q: number;
  /** 3 = exact type, 2 = `text/*`, 1 = `*\/*`, 0 = no entry applies. */
  specificity: number;
}

/** How the client rates `mediaType`: the q-value of its most specific matching entry. */
function match(entries: readonly AcceptEntry[], mediaType: string): Match {
  const [type, subtype] = mediaType.split("/");
  let best: Match = { q: 0, specificity: 0 };
  for (const entry of entries) {
    let specificity: number;
    if (entry.type === type && entry.subtype === subtype) specificity = 3;
    else if (entry.type === type && entry.subtype === "*") specificity = 2;
    else if (entry.type === "*" && entry.subtype === "*") specificity = 1;
    else continue;
    if (specificity > best.specificity) best = { q: entry.q, specificity };
  }
  return best;
}

/**
 * Picks the representation to serve. Higher q wins; at equal q the type the
 * client named more specifically wins, so `text/markdown, *\/*` gets
 * Markdown; at a full tie HTML wins, so browsers (which list `text/html` and
 * `*\/*`) and clients with no Accept header get HTML. `null` means the client
 * accepts neither, which callers answer with 406.
 */
export function negotiate(acceptHeader: string | null): Representation | null {
  if (acceptHeader === null || acceptHeader.trim() === "") return "html";
  const entries = parseAccept(acceptHeader);
  if (entries.length === 0) return "html";
  const html = match(entries, HTML_TYPE);
  const markdown = match(entries, MARKDOWN_TYPE);
  if (html.q === 0 && markdown.q === 0) return null;
  if (markdown.q !== html.q) return markdown.q > html.q ? "markdown" : "html";
  return markdown.specificity > html.specificity ? "markdown" : "html";
}

/** Adds `Accept` to the response's Vary list without duplicating it. */
export function varyOnAccept(headers: Headers): void {
  const existing = headers.get("Vary");
  if (!existing) {
    headers.set("Vary", "Accept");
    return;
  }
  const tokens = existing.split(",").map((t) => t.trim().toLowerCase());
  if (!tokens.includes("accept") && !tokens.includes("*")) {
    headers.set("Vary", `${existing}, Accept`);
  }
}

/**
 * RFC 8288 `Link` header advertising the other representation of the same
 * URL, plus llms.txt as the document that describes the site to agents.
 */
export function alternateLinkHeader(pageUrl: string, alternateType: string): string {
  return `<${pageUrl}>; rel="alternate"; type="${alternateType}", <${absoluteUrl("/llms.txt")}>; rel="describedby"; type="text/plain"`;
}

export function markdownResponse(body: string, pageUrl: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": `${MARKDOWN_TYPE}; charset=utf-8`,
      Vary: "Accept",
      Link: alternateLinkHeader(pageUrl, HTML_TYPE),
    },
  });
}

export function notAcceptableResponse(): Response {
  return new Response(`This resource is available as ${HTML_TYPE} or ${MARKDOWN_TYPE}.\n`, {
    status: 406,
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      Vary: "Accept",
    },
  });
}
