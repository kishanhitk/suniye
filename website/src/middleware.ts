import { defineMiddleware } from "astro:middleware";
import { hasMarkdown, markdownFor, notFoundMarkdown } from "./lib/markdown";
import {
  MARKDOWN_TYPE,
  alternateLinkHeader,
  markdownResponse,
  negotiate,
  notAcceptableResponse,
  varyOnAccept,
} from "./lib/negotiation";
import { absoluteUrl } from "./lib/site";

const NOT_FOUND_ROUTE = "/404";

// Serves each content page as Markdown when the client ranks text/markdown
// above text/html, and stamps `Vary: Accept` on both representations so no
// cache hands one audience the other's variant. Only on-demand routes reach
// here — every negotiable page opts out of prerendering for that reason.
export const onRequest = defineMiddleware(async (context, next) => {
  const pattern = context.routePattern;
  const isNotFound = pattern === NOT_FOUND_ROUTE;
  if (!isNotFound && !hasMarkdown(pattern)) {
    return next();
  }

  const preferred = negotiate(context.request.headers.get("accept"));
  // The HTML canonical has no trailing slash; the Markdown self-URL matches it.
  const pathname = context.url.pathname.replace(/(.)\/$/, "$1");
  const pageUrl = absoluteUrl(pathname);

  if (isNotFound) {
    // A missing page is a 404 whatever the client accepts; 406 would hide that.
    if (preferred === "markdown") {
      return markdownResponse(notFoundMarkdown(pathname), pageUrl, 404);
    }
  } else if (preferred === null && !pattern.includes("[")) {
    // A static route always exists, so there is nothing to build before 406.
    return notAcceptableResponse();
  } else if (preferred !== "html") {
    // A dynamic route with no such entry is a 404 (the page answers that),
    // not a 406, so the document is resolved before that decision.
    const doc = await markdownFor(pattern, context.params);
    if (doc) {
      if (preferred === null) {
        return notAcceptableResponse();
      }
      if (doc.cache && context.cache.enabled) {
        context.cache.set(doc.cache);
      }
      return markdownResponse(doc.body, pageUrl, doc.status);
    }
  }

  const rendered = await next();
  if (!isNotFound && rendered.body === null && (rendered.status === 404 || rendered.status === 500)) {
    // Astro re-renders a bodiless error response through the /404 or /500
    // route, where this middleware runs again; headers set here would
    // override that pass's (Astro merges the original response's headers on top).
    return rendered;
  }
  // Rendered responses may carry immutable headers; re-wrap so they can be set.
  const response = new Response(rendered.body, rendered);
  varyOnAccept(response.headers);
  response.headers.set("Link", alternateLinkHeader(pageUrl, MARKDOWN_TYPE));
  return response;
});
