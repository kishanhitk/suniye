// Accept-header negotiation between the two representations every content
// page has: HTML for browsers, Markdown for agents (acceptmarkdown.com).
// RFC 9110 §12.5.1: rank by q-value, tie-break by specificity, q=0 excludes.

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
          q = Number.isFinite(parsed) ? Math.min(1, Math.max(0, parsed)) : 0;
        }
      }
      return [{ type, subtype, q }];
    });
}

/** The q-value the client assigns to `mediaType`, via its most specific match. */
function quality(entries: readonly AcceptEntry[], mediaType: string): number {
  const [type, subtype] = mediaType.split("/");
  let best: { specificity: number; q: number } | undefined;
  for (const entry of entries) {
    let specificity: number;
    if (entry.type === type && entry.subtype === subtype) specificity = 3;
    else if (entry.type === type && entry.subtype === "*") specificity = 2;
    else if (entry.type === "*" && entry.subtype === "*") specificity = 1;
    else continue;
    if (!best || specificity > best.specificity) best = { specificity, q: entry.q };
  }
  return best?.q ?? 0;
}

/**
 * Picks the representation to serve. HTML wins ties, so browsers (which list
 * `text/html` and `*\/*`) and clients with no Accept header get HTML; an agent
 * has to rank `text/markdown` strictly above HTML to get Markdown. `null`
 * means the client accepts neither, which callers answer with 406.
 */
export function negotiate(acceptHeader: string | null): Representation | null {
  if (acceptHeader === null || acceptHeader.trim() === "") return "html";
  const entries = parseAccept(acceptHeader);
  if (entries.length === 0) return "html";
  const html = quality(entries, HTML_TYPE);
  const markdown = quality(entries, MARKDOWN_TYPE);
  if (html === 0 && markdown === 0) return null;
  return markdown > html ? "markdown" : "html";
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

export function markdownResponse(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": `${MARKDOWN_TYPE}; charset=utf-8`,
      Vary: "Accept",
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
