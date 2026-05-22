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
