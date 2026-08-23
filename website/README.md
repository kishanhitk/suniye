# Suniye Marketing Site

This folder contains the Astro landing page for Suniye.

## Run locally

Install Node.js first, then:

```bash
cd website
npm install
npm run dev
```

## Build

```bash
cd website
npm run build
```

## Content negotiation for agents

Every content page (`/`, `/about`, `/contact`, `/privacy`, `/changelog`, the blog,
and the 404) answers `Accept: text/markdown` with a Markdown version of itself,
with `Vary: Accept` and an RFC 8288 `Link` header on both representations.
`src/middleware.ts` does the negotiation (`src/lib/negotiation.ts`) and
`src/lib/markdown.ts` maps each route pattern to a Markdown builder. The builders
render the same content modules the HTML pages use (`src/lib/content/*`,
`src/lib/releases.ts`, `src/content/pages/*.md`), so the two representations
cannot drift — new copy goes into those modules, not into the `.astro` template.

These pages are rendered on demand (`export const prerender = false`) on
purpose: a prerendered page is served straight from Workers Static Assets and
never reaches the middleware. Keep new content pages on demand and register
them in `src/lib/markdown.ts` and `SITE_PAGES` in `src/lib/site.ts` (which also
feeds the sitemap, the 404 page, and `/llms.txt`).

## Deploy

The site runs on **Cloudflare Workers** (Workers Static Assets + Astro on-demand
rendering via `@astrojs/cloudflare`). It auto-deploys on every push to `main`
through the Workers Builds Git integration; pushes to other branches get preview
URLs.

- **Build command:** `npm run build`
- **Deploy command:** `npx wrangler deploy --config ./dist/server/wrangler.json`
- **Root directory:** `website`

The adapter generates the full Worker config at `dist/server/wrangler.json` during
the build; `wrangler.jsonc` in this folder only injects the bits the adapter
leaves out (`nodejs_compat`, the Worker `name`). The `SESSION` KV namespace that
Astro's session store needs is auto-provisioned by `wrangler deploy` on first
deploy — no manual KV setup.

To deploy manually from your machine (after `wrangler login`):

```bash
cd website
npm run deploy
```

## Issue report endpoint

`POST https://suniye.app/api/issue-reports` creates Linear issues from Suniye's in-app
reporter. It is served by the standalone `suniye-reports` Worker (`workers/reports/`),
not the Astro site worker — the route `suniye.app/api/issue-reports*` takes that path
over from the site. It lives outside Astro so no CSRF origin check blocks the app's
multipart POSTs (native clients send no `Origin` header; that check silently broke
reporting between 2026-06-06 and 2026-08, see KIS-173).

Deploy and configure secrets (never committed):

```bash
cd website/workers/reports
npm run deploy
wrangler secret put LINEAR_API_KEY           # secret
wrangler secret put LINEAR_TEAM_ID           # required, team UUID
wrangler secret put LINEAR_REPORT_LABEL_ID   # optional
wrangler secret put LINEAR_REPORT_PROJECT_ID # optional
wrangler secret put LINEAR_REPORT_STATE_ID   # optional
```

After deploying this worker or the site worker, or changing domains/redirects, run the
smoke test. It sends the exact request shape the app sends (multipart, no `Origin`
header) and creates a real Linear issue; with `LINEAR_API_KEY` set it archives the
issue automatically:

```bash
cd website/workers/reports
LINEAR_API_KEY=... bun scripts/smoke.ts
```

The endpoint applies a server-side Cloudflare Cache API rate limit before any Linear
calls: 6 POST requests per 10 minutes per IP, best-effort and per data center (the
Cache API is not global), not a hard cap. The smoke test consumes one request.

Shipped app builds post to `https://suniye.kishans.in/api/issue-reports`; that path is
excluded from the old domain's 301 and 308-redirected to the new endpoint instead,
because clients downgrade POST to GET across a 301 but keep method and body on a 308.

## Sparkle appcast endpoint

The Cloudflare deployment hosts Sparkle update feeds:

- `GET /appcast.xml` proxies the `appcast.xml` asset from the latest stable GitHub release.
- `GET /appcast-tip.xml` proxies the mutable `appcast.xml` asset from the `tip` prerelease.

Both endpoints apply short edge cache headers so installed apps can keep using stable `https://suniye.kishans.in/...` feed URLs.
