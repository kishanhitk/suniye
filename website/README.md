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

The `LINEAR_*` values below and any other secrets are configured as Worker secrets
in the Cloudflare dashboard (or via `wrangler secret put`), not committed here.

## Issue report endpoint

The Cloudflare deployment hosts `POST /api/issue-reports`, which creates Linear issues from Suniye's in-app reporter. Configure these Cloudflare values before enabling the feature in production:

```bash
LINEAR_API_KEY          # secret
LINEAR_TEAM_ID          # required, team UUID
LINEAR_REPORT_LABEL_ID  # optional
LINEAR_REPORT_PROJECT_ID # optional
LINEAR_REPORT_STATE_ID # optional
```

The endpoint applies a server-side Cloudflare Cache API rate limit before any Linear calls. The default limit is 6 POST requests per 10 minutes per IP and user-agent pair.

## Sparkle appcast endpoint

The Cloudflare deployment hosts Sparkle update feeds:

- `GET /appcast.xml` proxies the `appcast.xml` asset from the latest stable GitHub release.
- `GET /appcast-tip.xml` proxies the mutable `appcast.xml` asset from the `tip` prerelease.

Both endpoints apply short edge cache headers so installed apps can keep using stable `https://suniye.kishans.in/...` feed URLs.
