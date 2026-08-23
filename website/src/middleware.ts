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
  const pageUrl = absoluteUrl(context.url.pathname);

  if (isNotFound) {
    // A missing page is a 404 whatever the client accepts; 406 would hide that.
    if (preferred === "markdown") {
      return markdownResponse(notFoundMarkdown(context.url.pathname), pageUrl, 404);
    }
  } else if (preferred === null) {
    return notAcceptableResponse();
  } else if (preferred === "markdown") {
    const doc = await markdownFor(pattern, context.params);
    if (doc) {
      return markdownResponse(doc.body, pageUrl, doc.status);
    }
    // No document for these params (e.g. unknown blog slug): let the page
    // itself answer, which is where the 404 comes from.
  }

  const rendered = await next();
  // Rendered responses may carry immutable headers; re-wrap so Vary can be set.
  const response = new Response(rendered.body, rendered);
  varyOnAccept(response.headers);
  response.headers.set("Link", alternateLinkHeader(pageUrl, MARKDOWN_TYPE));
  return response;
});
