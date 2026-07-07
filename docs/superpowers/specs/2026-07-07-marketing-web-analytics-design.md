# Marketing-Page Web Analytics — Design

- **Linear:** _TBD_ (marketing-site web analytics; sibling of KIS-164 app analytics)
- **Date:** 2026-07-07
- **Status:** Design — approved in brainstorming, pending spec review

## 1. Goal

Add **detailed, first-party web analytics to the Suniye marketing site** (`website/`, Astro SSR on the `suniye` Cloudflare Worker) so we can answer, for the landing page:

1. **Conversion funnel** — how many visitors land, how many click Download, split by target (DMG vs Homebrew vs zip), and the drop-off between.
2. **Traffic & sources** — visitor/pageview counts, referrer channel (search/social/direct/referral), country, device class.
3. **Content engagement** — which pages/sections hold attention: scroll depth, demo-video plays, CTA/outbound clicks.
4. **Campaign attribution** — UTM tagging so launches/posts can be tied to traffic and conversions.

…**without cookies, a consent banner, PII, or any third-party tracker** — consistent with the privacy posture the site already advertises, and reusing the Cloudflare Analytics Engine + dashboard infrastructure we already operate for app analytics (KIS-164/167).

### Non-goals
- No cross-site tracking, no advertising pixels, no third-party analytics script.
- No per-person identity, no persistent visitor ID, no session replay/heatmaps.
- No new paid service. Analytics Engine + the existing dashboard Worker are free/already-running.
- Not a rewrite of the app analytics pipeline; the web pipeline is **separate** (own dataset) but mirrors its shape.

## 2. Principles

1. **Cookieless and consent-banner-free.** No cookies, no `localStorage` identity. Unique visitors are counted via a **server-side daily-rotating salted hash of `IP + User-Agent`** (the Plausible/Fathom model). Raw IP is never stored — only the hash, in the AE index. The salt rotates every UTC day, so there is **zero cross-day linkage** and nothing that singles out a person over time. Legal posture: aggregate, non-identifying measurement — no consent required — but the disclosure still ships (§6).
2. **First-party only.** The beacon posts **same-origin** to `/api/track` on the marketing Worker. No third-party requests, no data leaving Cloudflare. The one page whose privacy copy promises "no third-party trackers" will not load one.
3. **No PII, structurally.** A closed, typed event schema (fixed event names + a small set of scalar props). Referrer is reduced to **host only** server-side; the full URL/query string is never stored. UTM values are marketing metadata, not personal data.
4. **Fail silent, never block rendering.** The beacon is fire-and-forget (`navigator.sendBeacon`, `fetch` keepalive fallback). Any failure is swallowed; it never affects the page. The API route always returns `204` (even on validation failure) so the beacon can't be used to probe.
5. **Mirror the app pipeline's contracts.** Same event envelope (`event_ts`, `session_id`, `name`, `props`), same AE positional-slot discipline (committed field→slot registry), same query idioms (`SUM(_sample_interval)`, `COUNT(DISTINCT index1)`). New code follows existing code.

## 3. Architecture

```
┌──────────────────────────┐  navigator.sendBeacon (POST /api/track, same-origin)
│ Browser                  │  JSON batch: {events:[{event_ts,session_id,name,props}]}
│  beacon.ts (~1.5 KB)     │────────────────────────────────────────────┐
│  - pageview on load      │                                            ▼
│  - download/cta/outbound │            ┌───────────────────────────────────────────┐
│  - scroll thresholds     │            │ Astro API route  src/pages/api/track.ts     │
│  - video_play            │            │ (runs on the suniye SSR Worker)             │
│  - sessionStorage sid    │◀───204─────│  - validate (closed schema, size caps)      │
└──────────────────────────┘            │  - enrich: country (request.cf.country),    │
                                        │    referrer_host (Referer header),          │
                                        │    visitor_hash = SHA-256(daily_salt|ip|ua) │
                                        │  - WEB_EVENTS.writeDataPoint(...)           │
                                        └───────────────────┬─────────────────────────┘
                                                            │ writeDataPoint
                                                            ▼
                                             ┌────────────────────────────┐
                                             │ Analytics Engine            │
                                             │ dataset: suniye_web         │
                                             │ ~90d, 20 blob/20 dbl/1 idx  │
                                             └──────────────┬─────────────┘
                                                            │ AE SQL API
                                                            ▼
                                             ┌────────────────────────────┐
                                             │ Dashboard Worker (existing) │
                                             │  new "Web" tab              │
                                             │  JWT-gated, live refresh     │
                                             └────────────────────────────┘
```

**Components (each independently testable):**
- `website/src/lib/webAnalytics/schema.ts` — the closed event schema + validation (pure; unit-tested).
- `website/src/lib/webAnalytics/datapoint.ts` — event → AE data point (field→slot registry; pure; unit-tested).
- `website/src/lib/webAnalytics/visitor.ts` — `dailyVisitorHash(ip, ua, dateUTC, salt)` (pure; unit-tested).
- `website/src/pages/api/track.ts` — thin HTTP shell: parse → validate → enrich → `writeDataPoint` → `204`.
- `website/src/components/analytics/beacon.ts` (+ a small Astro component that inlines it in the base layout) — the client tracker.
- `website/workers/dashboard/src/worker/webStats.ts` — AE queries for the web dataset.
- `website/workers/dashboard/src/app/` — a "Web" tab/view rendering the web stats.

## 4. Event schema

Envelope (identical to app analytics): `{ event_id, event_ts, session_id, name, props }`.
`session_id` is an ephemeral id in `sessionStorage` (dies on tab close) used only to stitch a single visit's funnel — not a cookie, not cross-session.

| `name` | Client props | Server-added | Serves |
|---|---|---|---|
| `pageview` | `path`, `utm_source?`, `utm_medium?`, `utm_campaign?`, `device` (`mobile`\|`desktop`), `viewport` (`sm`\|`md`\|`lg`) | `referrer_host`, `country`, `visitor_hash` | traffic, sources, attribution |
| `download_click` | `target` (`dmg`\|`homebrew`\|`zip`), `path` | ” | **funnel** |
| `cta_click` | `cta` (e.g. `hero_download`,`nav_download`,`quarantine_help`), `path` | ” | funnel, engagement |
| `scroll_depth` | `depth` (`25`\|`50`\|`75`\|`100`), `path` | ” | engagement |
| `video_play` | `path` | ” | engagement (hero demo) |
| `outbound_click` | `host` (`github`\|`homebrew-tap`\|…), `path` | ” | engagement |

Validation caps (reject → still `204`): ≤ 20 events/batch, `name` ∈ fixed set, ≤ 12 prop keys, scalar values only, string prop ≤ 256 chars, batch body ≤ 16 KB. Unknown event names and unknown prop keys are dropped (forward-compatible).

### AE field → slot registry (committed, append-only)

| Slot | Meaning |
|---|---|
| `double1` | `event_ts` (ms) — time bucketing |
| `double2` | `scroll_depth.depth` (else null) |
| `index1` | `visitor_hash` — the one AE index, for `COUNT(DISTINCT)` unique visitors |
| `blob1` | event `name` |
| `blob2` | `path` |
| `blob3` | `referrer_host` |
| `blob4`/`blob5`/`blob6` | `utm_source`/`utm_medium`/`utm_campaign` |
| `blob7` | `country` |
| `blob8` | `device` |
| `blob9` | `target` \| `cta` \| `host` (the event's primary value) |
| `blob10` | `session_id` |
| `blob11` | `viewport` |
| `blob20` | `JSON.stringify(props)` backstop |

Unique visitors = `COUNT(DISTINCT index1)`; sessions = `COUNT(DISTINCT blob10)`; event counts = `SUM(_sample_interval)`; conversion rate = `download_click count / pageview count` over the range.

## 5. Data flow & enrichment

1. Beacon sends a batch on `pagehide`/`visibilitychange` (and immediately for `download_click`, which precedes navigation, via `sendBeacon`).
2. `track.ts` reads `request.cf.country`, the `Referer` header (→ host only), and the connecting IP + UA.
3. `visitor_hash = SHA-256( dailySalt(dateUTC) + '|' + ip + '|' + ua )`. `dailySalt` = `SECRET_SALT + dateUTC` (secret from Worker env). Raw IP/UA are used only to compute the hash and then discarded.
4. Each valid event → one `writeDataPoint`. Invalid/oversized events are dropped silently; the route returns `204` regardless.

## 6. Privacy disclosure

`website/src/pages/privacy.astro` currently describes **only the app's** analytics. Add a short **"Website analytics"** section: what we count (aggregate pageviews, sources, download clicks), that it's cookieless with no consent banner, no PII, no third-party, hashed-and-rotated visitor counting, ~90-day retention, first-party on our own Cloudflare infra. This ships **with** the beacon (no build tracks before the disclosure exists).

## 7. Dashboard ("Web" tab)

Extend the existing dashboard Worker (reuse JWT auth, range picker, 15 s live refresh, chart components):
- **Headline:** unique visitors, pageviews, download clicks, **conversion rate** — with the range's trend line.
- **Funnel:** pageview → any CTA → download_click (DMG / Homebrew / zip breakdown).
- **Sources:** top referrer hosts, channel grouping (direct/search/social/referral), UTM campaign table.
- **Content:** top pages, scroll-depth histogram, video plays, outbound clicks.
- **Audience:** country, device/viewport.

New `webStats.ts` (queries `suniye_web`) beside the existing `stats.ts`; a **new `/web-stats` endpoint** on the dashboard Worker (kept separate from the app `/stats` endpoint rather than overloading it); a Web view in the React app. No new host, no new auth.

## 8. Configuration / bindings

- `website/wrangler.jsonc`: add `analytics_engine_datasets: [{ binding: "WEB_EVENTS", dataset: "suniye_web" }]` (the Astro CF adapter merges this). Add `SECRET_SALT` via `wrangler secret` (not in config).
- Dashboard Worker: reuse its existing AE read token; add the `suniye_web` dataset to its queries.

## 9. Testing

Mirror existing suites (`workers/ingest/test/ingest.test.ts`, `workers/dashboard/test/stats.test.ts`, `website/tests`):
- **schema.ts** — accepts valid events; rejects bad name/oversize/non-scalar; drops unknown keys.
- **datapoint.ts** — correct slot mapping for each event type; `blob20` backstop; null-safety.
- **visitor.ts** — deterministic within a UTC day, different across days (salt rotation), never emits raw IP.
- **track.ts** — always `204`; enrichment (country/referrer_host) applied; oversized batch dropped.
- **webStats.ts** — funnel/uniques/sources SQL builders produce expected queries; conversion-rate math.
- **beacon.ts** — batches; `sendBeacon`→`fetch` fallback; scroll-threshold fired once per level per pageview; no-op when `navigator.sendBeacon` and `fetch` both absent.

## 10. Rollout

1. Land ingest + schema + beacon behind nothing user-visible (the beacon is invisible), plus the privacy-page section, in one PR.
2. Deploy the marketing Worker (auto-provisions the AE dataset on first `writeDataPoint`).
3. Add the dashboard "Web" tab in the same or a follow-up PR.
4. Verify events flow (AE SQL API) and the funnel/conversion numbers look sane before relying on them.

## 11. Open questions / follow-ups

- **Bot filtering:** drop obvious bots by UA (or accept AE's noise)? Default: light UA denylist server-side, note the rest as unfiltered.
- **`Do Not Track`:** honor `navigator.doNotTrack`? Since we're already non-tracking, default is **not** to special-case it; revisit if desired.
- **SPA nav:** the site is MPA (per-page load), so `pageview` on load suffices; revisit if any client-side routing is added.
