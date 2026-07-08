# Marketing-Page Web Analytics — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add first-party, cookieless web analytics to the Suniye marketing site — a same-origin `/api/track` beacon writing to a `suniye_web` Analytics Engine dataset, surfaced as a new "Web" tab in the existing dashboard Worker.

**Architecture:** A tiny client beacon posts batched events same-origin to an Astro API route on the `suniye` SSR Worker. The route validates a closed event schema, enriches server-side (country, referrer host, a daily-rotating salted visitor hash), and writes one Analytics Engine data point per event. The existing dashboard Worker gains a `/api/web-stats` endpoint and a React "Web" view that query the new dataset with the same sampling-correct SQL idioms as the app analytics.

**Tech Stack:** Astro 6 SSR + `@astrojs/cloudflare`, Cloudflare Workers, Analytics Engine (ClickHouse-style SQL), Bun test runner, React (dashboard SPA), TypeScript.

## Global Constraints

- **Cookieless:** no cookies, no `localStorage` identity. Session id lives only in `sessionStorage`. (spec §2.1)
- **No PII stored:** raw IP/UA used transiently to compute the visitor hash, then discarded. Referrer reduced to **host only**. (spec §2.3, §5)
- **First-party only:** beacon posts same-origin to `/api/track`; no third-party requests. (spec §2.2)
- **Fail silent:** the beacon never throws into the page; the API route returns **204 for every POST**, even on invalid input. (spec §2.4)
- **AE positional slots are append-only:** never move/repurpose a slot; `blob1` = event name; `blob20` = full props JSON backstop. (spec §4)
- **AE SQL takes RAW SQL (no bind params):** every interpolated value must be a server-computed number or passed through `safeLabel`/`safeNum`. (existing `stats.ts` contract)
- **Time is bucketed on client `event_ts` (`double1`), never AE ingestion time.** Counts use `SUM(_sample_interval)`, uniques use `COUNT(DISTINCT index1)`. (existing `stats.ts` contract)
- **Test runner:** `bun test`; test files `import { describe, expect, test } from "bun:test"`.
- **Working dir:** worktree `.claude/worktrees/web-analytics`, branch `web-analytics-marketing`. All paths below are relative to `website/` unless noted.

---

### Task 1: Web event schema + validation

**Files:**
- Create: `website/src/lib/webAnalytics/schema.ts`
- Test: `website/tests/webAnalytics.schema.test.ts`

**Interfaces:**
- Produces:
  - `type WebPropValue = string | number | boolean`
  - `interface WebEvent { event_id: string; event_ts: number; session_id: string; name: string; props: Record<string, WebPropValue> }`
  - `interface WebBatch { sent_at: number; events: WebEvent[] }`
  - `const WEB_EVENT_NAMES = ["pageview","download_click","cta_click","scroll_depth","video_play","outbound_click"] as const`
  - `type WebEventName = (typeof WEB_EVENT_NAMES)[number]`
  - `interface WebDataPoint { indexes?: string[]; blobs?: (string | null)[]; doubles?: number[] }`
  - `interface AnalyticsEngineDataset { writeDataPoint(point: WebDataPoint): void }`
  - `function validateWebBatch(raw: unknown): WebBatch | string` — returns the batch with **only known event names kept and each event's props shallow-copied**, or an error message string.

- [ ] **Step 1: Write the failing test**

```ts
// website/tests/webAnalytics.schema.test.ts
import { describe, expect, test } from "bun:test";
import { validateWebBatch, WEB_EVENT_NAMES } from "../src/lib/webAnalytics/schema";

function ev(over: Partial<Record<string, unknown>> = {}) {
  return { event_id: "e1", event_ts: 1_700_000_000_000, session_id: "s1", name: "pageview", props: { path: "/" }, ...over };
}

describe("validateWebBatch", () => {
  test("accepts a well-formed batch", () => {
    const out = validateWebBatch({ sent_at: 1, events: [ev()] });
    expect(typeof out).not.toBe("string");
    expect((out as any).events).toHaveLength(1);
  });

  test("drops unknown event names but keeps known ones", () => {
    const out = validateWebBatch({ sent_at: 1, events: [ev({ name: "bogus" }), ev()] });
    expect((out as any).events).toHaveLength(1);
    expect((out as any).events[0].name).toBe("pageview");
  });

  test("rejects non-object", () => {
    expect(typeof validateWebBatch(null)).toBe("string");
    expect(typeof validateWebBatch([])).toBe("string");
  });

  test("rejects missing/oversized fields", () => {
    expect(typeof validateWebBatch({ sent_at: 1, events: [ev({ event_id: "" })] })).toBe("string");
    expect(typeof validateWebBatch({ sent_at: 1, events: [ev({ session_id: "x".repeat(101) })] })).toBe("string");
  });

  test("rejects too many events", () => {
    const events = Array.from({ length: 21 }, () => ev());
    expect(typeof validateWebBatch({ sent_at: 1, events })).toBe("string");
  });

  test("rejects non-scalar / oversized props and too many keys", () => {
    expect(typeof validateWebBatch({ sent_at: 1, events: [ev({ props: { path: { nested: 1 } } })] })).toBe("string");
    expect(typeof validateWebBatch({ sent_at: 1, events: [ev({ props: { path: "x".repeat(257) } })] })).toBe("string");
    const props: Record<string, string> = {};
    for (let i = 0; i < 13; i++) props["k" + i] = "v";
    expect(typeof validateWebBatch({ sent_at: 1, events: [ev({ props })] })).toBe("string");
  });

  test("exposes the closed name set", () => {
    expect(WEB_EVENT_NAMES).toContain("download_click");
    expect(WEB_EVENT_NAMES).toHaveLength(6);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd website && bun test tests/webAnalytics.schema.test.ts`
Expected: FAIL — cannot find module `../src/lib/webAnalytics/schema`.

- [ ] **Step 3: Write minimal implementation**

```ts
// website/src/lib/webAnalytics/schema.ts
export type WebPropValue = string | number | boolean;

export interface WebEvent {
  event_id: string;
  event_ts: number; // client epoch ms — time-series bucket on THIS, never ingestion time
  session_id: string;
  name: string;
  props: Record<string, WebPropValue>;
}

export interface WebBatch {
  sent_at: number;
  events: WebEvent[];
}

export interface WebDataPoint {
  indexes?: string[];
  blobs?: (string | null)[];
  doubles?: number[];
}

export interface AnalyticsEngineDataset {
  writeDataPoint(point: WebDataPoint): void;
}

export const WEB_EVENT_NAMES = [
  "pageview",
  "download_click",
  "cta_click",
  "scroll_depth",
  "video_play",
  "outbound_click",
] as const;
export type WebEventName = (typeof WEB_EVENT_NAMES)[number];

const MAX_EVENTS = 20;
const MAX_PROPS_KEYS = 12;
const MAX_STR = 256;
const NAME_SET = new Set<string>(WEB_EVENT_NAMES);

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}
function nonEmptyStr(v: unknown, max: number): v is string {
  return typeof v === "string" && v.length > 0 && v.length <= max;
}

/**
 * Returns a cleaned batch (unknown event names dropped, props shallow-copied to
 * strip prototype pollution) or an error message string. Never throws.
 */
export function validateWebBatch(raw: unknown): WebBatch | string {
  if (!isObject(raw)) return "batch must be an object";
  if (typeof raw.sent_at !== "number" || !Number.isFinite(raw.sent_at)) return "sent_at must be a number";
  if (!Array.isArray(raw.events)) return "events must be an array";
  if (raw.events.length > MAX_EVENTS) return "too many events";

  const events: WebEvent[] = [];
  for (const item of raw.events) {
    if (!isObject(item)) return "event must be an object";
    if (!nonEmptyStr(item.event_id, 100)) return "event_id required";
    if (typeof item.event_ts !== "number" || !Number.isFinite(item.event_ts)) return "event_ts must be a number";
    if (!nonEmptyStr(item.session_id, 100)) return "session_id required";
    if (!nonEmptyStr(item.name, 64)) return "name required";
    if (!isObject(item.props)) return "props must be an object";

    const keys = Object.keys(item.props);
    if (keys.length > MAX_PROPS_KEYS) return "too many props";
    const props: Record<string, WebPropValue> = {};
    for (const k of keys) {
      const val = (item.props as Record<string, unknown>)[k];
      const t = typeof val;
      if (t !== "string" && t !== "number" && t !== "boolean") return "props values must be scalars";
      if (t === "string" && (val as string).length > MAX_STR) return "prop value too long";
      props[k] = val as WebPropValue;
    }

    if (!NAME_SET.has(item.name)) continue; // forward-compatible: drop unknown events
    events.push({ event_id: item.event_id, event_ts: item.event_ts, session_id: item.session_id, name: item.name, props });
  }

  return { sent_at: raw.sent_at, events };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd website && bun test tests/webAnalytics.schema.test.ts`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add website/src/lib/webAnalytics/schema.ts website/tests/webAnalytics.schema.test.ts
git commit -m "feat(web-analytics): closed web event schema + validation"
```

---

### Task 2: Daily-rotating visitor hash

**Files:**
- Create: `website/src/lib/webAnalytics/visitor.ts`
- Test: `website/tests/webAnalytics.visitor.test.ts`

**Interfaces:**
- Produces: `async function dailyVisitorHash(ip: string, ua: string, dateUTC: string, salt: string): Promise<string>` — hex SHA-256 of `salt + "|" + dateUTC + "|" + ip + "|" + ua`. `dateUTC` is `YYYY-MM-DD`.
- Produces: `function utcDate(nowMs: number): string` — `YYYY-MM-DD` in UTC.
- Consumes: WebCrypto `crypto.subtle` (available in Workers + Bun).

- [ ] **Step 1: Write the failing test**

```ts
// website/tests/webAnalytics.visitor.test.ts
import { describe, expect, test } from "bun:test";
import { dailyVisitorHash, utcDate } from "../src/lib/webAnalytics/visitor";

describe("dailyVisitorHash", () => {
  test("is deterministic for the same inputs", async () => {
    const a = await dailyVisitorHash("1.2.3.4", "UA", "2026-07-07", "salt");
    const b = await dailyVisitorHash("1.2.3.4", "UA", "2026-07-07", "salt");
    expect(a).toBe(b);
  });

  test("differs across day (salt rotation window)", async () => {
    const a = await dailyVisitorHash("1.2.3.4", "UA", "2026-07-07", "salt");
    const b = await dailyVisitorHash("1.2.3.4", "UA", "2026-07-08", "salt");
    expect(a).not.toBe(b);
  });

  test("differs across IP and never contains the raw IP", async () => {
    const a = await dailyVisitorHash("1.2.3.4", "UA", "2026-07-07", "salt");
    const b = await dailyVisitorHash("9.9.9.9", "UA", "2026-07-07", "salt");
    expect(a).not.toBe(b);
    expect(a).not.toContain("1.2.3.4");
    expect(a).toMatch(/^[0-9a-f]{64}$/);
  });

  test("utcDate formats YYYY-MM-DD in UTC", () => {
    expect(utcDate(Date.UTC(2026, 6, 7, 23, 30))).toBe("2026-07-07");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd website && bun test tests/webAnalytics.visitor.test.ts`
Expected: FAIL — cannot find module `../src/lib/webAnalytics/visitor`.

- [ ] **Step 3: Write minimal implementation**

```ts
// website/src/lib/webAnalytics/visitor.ts

/** YYYY-MM-DD in UTC. The salt window rotates on this boundary. */
export function utcDate(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}

/**
 * Cookieless unique-visitor id: hex SHA-256 over (secret salt | UTC date | ip | ua).
 * Because the date is in the hash and the salt is secret, the id cannot be linked
 * across days and cannot be reversed to the IP. Only this hash is ever stored.
 */
export async function dailyVisitorHash(ip: string, ua: string, dateUTC: string, salt: string): Promise<string> {
  const data = new TextEncoder().encode(`${salt}|${dateUTC}|${ip}|${ua}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd website && bun test tests/webAnalytics.visitor.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add website/src/lib/webAnalytics/visitor.ts website/tests/webAnalytics.visitor.test.ts
git commit -m "feat(web-analytics): cookieless daily-rotating visitor hash"
```

---

### Task 3: AE data-point builder (field → slot registry)

**Files:**
- Create: `website/src/lib/webAnalytics/datapoint.ts`
- Test: `website/tests/webAnalytics.datapoint.test.ts`

**Interfaces:**
- Consumes: `WebEvent`, `WebDataPoint` (Task 1).
- Produces:
  - `interface WebEnrichment { referrerHost: string; country: string; visitorHash: string }`
  - `function buildWebDataPoint(event: WebEvent, enrich: WebEnrichment): WebDataPoint`

**Slot registry (append-only):** `double1`=event_ts; `double2`=scroll depth (else omitted); `index1`=visitorHash; `blob1`=name; `blob2`=path; `blob3`=referrerHost; `blob4/5/6`=utm_source/medium/campaign; `blob7`=country; `blob8`=device; `blob9`=target|cta|host; `blob10`=session_id; `blob11`=viewport; `blob20`=JSON props. (Trailing nulls are fine; AE ignores unused slots.)

- [ ] **Step 1: Write the failing test**

```ts
// website/tests/webAnalytics.datapoint.test.ts
import { describe, expect, test } from "bun:test";
import { buildWebDataPoint } from "../src/lib/webAnalytics/datapoint";
import type { WebEvent } from "../src/lib/webAnalytics/schema";

const enrich = { referrerHost: "google.com", country: "US", visitorHash: "abc123" };
function ev(name: string, props: Record<string, unknown>, ts = 1_700_000_000_000): WebEvent {
  return { event_id: "e", event_ts: ts, session_id: "s1", name, props: props as any };
}

describe("buildWebDataPoint", () => {
  test("maps a pageview to the right slots", () => {
    const dp = buildWebDataPoint(
      ev("pageview", { path: "/", utm_source: "x", utm_medium: "social", utm_campaign: "launch", device: "desktop", viewport: "lg" }),
      enrich,
    );
    expect(dp.indexes).toEqual(["abc123"]);
    expect(dp.doubles?.[0]).toBe(1_700_000_000_000); // double1 = event_ts
    expect(dp.blobs?.[0]).toBe("pageview");   // blob1
    expect(dp.blobs?.[1]).toBe("/");          // blob2 path
    expect(dp.blobs?.[2]).toBe("google.com"); // blob3 referrer host
    expect(dp.blobs?.[3]).toBe("x");          // blob4 utm_source
    expect(dp.blobs?.[6]).toBe("US");         // blob7 country
    expect(dp.blobs?.[7]).toBe("desktop");    // blob8 device
    expect(dp.blobs?.[10]).toBe("lg");        // blob11 viewport
    expect(dp.blobs?.[9]).toBe("s1");         // blob10 session_id
    expect(dp.blobs?.[19]).toContain("\"path\":\"/\""); // blob20 backstop
  });

  test("maps download_click target to the primary-value slot (blob9)", () => {
    const dp = buildWebDataPoint(ev("download_click", { target: "dmg", path: "/" }), enrich);
    expect(dp.blobs?.[0]).toBe("download_click");
    expect(dp.blobs?.[8]).toBe("dmg"); // blob9
  });

  test("maps cta_click / outbound_click value into blob9", () => {
    expect(buildWebDataPoint(ev("cta_click", { cta: "hero_download", path: "/" }), enrich).blobs?.[8]).toBe("hero_download");
    expect(buildWebDataPoint(ev("outbound_click", { host: "github", path: "/" }), enrich).blobs?.[8]).toBe("github");
  });

  test("puts scroll depth in double2", () => {
    const dp = buildWebDataPoint(ev("scroll_depth", { depth: 75, path: "/" }), enrich);
    expect(dp.doubles?.[1]).toBe(75); // double2
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd website && bun test tests/webAnalytics.datapoint.test.ts`
Expected: FAIL — cannot find module `../src/lib/webAnalytics/datapoint`.

- [ ] **Step 3: Write minimal implementation**

```ts
// website/src/lib/webAnalytics/datapoint.ts
import type { WebDataPoint, WebEvent, WebPropValue } from "./schema";

export interface WebEnrichment {
  referrerHost: string;
  country: string;
  visitorHash: string;
}

const s = (p: Record<string, WebPropValue>, key: string): string | null =>
  typeof p[key] === "string" ? (p[key] as string) : null;
const firstS = (p: Record<string, WebPropValue>, ...keys: string[]): string | null => {
  for (const k of keys) if (typeof p[k] === "string") return p[k] as string;
  return null;
};
const n = (p: Record<string, WebPropValue>, key: string): number | undefined =>
  typeof p[key] === "number" ? (p[key] as number) : undefined;

/**
 * One Analytics Engine data point per event. Slots are POSITIONAL and
 * append-only (see plan Global Constraints). blob1 is always the event name;
 * blob20 always carries the full props JSON so a field is never lost before it
 * earns a slot. doubles are built dense from double1; scroll depth rides double2.
 */
export function buildWebDataPoint(event: WebEvent, enrich: WebEnrichment): WebDataPoint {
  const p = event.props;
  const blobs: (string | null)[] = [
    event.name,                                   // blob1
    s(p, "path"),                                 // blob2
    enrich.referrerHost || null,                  // blob3
    s(p, "utm_source"),                           // blob4
    s(p, "utm_medium"),                           // blob5
    s(p, "utm_campaign"),                         // blob6
    enrich.country || null,                       // blob7
    s(p, "device"),                               // blob8
    firstS(p, "target", "cta", "host"),           // blob9 (primary value, mutually exclusive per event)
    event.session_id,                             // blob10
    s(p, "viewport"),                             // blob11
    null, null, null, null, null, null, null, null, // blob12..19 reserved
    JSON.stringify(p),                            // blob20 backstop
  ];
  const doubles: number[] = [event.event_ts]; // double1
  const depth = n(p, "depth");
  if (depth !== undefined) doubles[1] = depth; // double2 (dense: only set when present)
  return { indexes: [enrich.visitorHash], blobs, doubles };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd website && bun test tests/webAnalytics.datapoint.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add website/src/lib/webAnalytics/datapoint.ts website/tests/webAnalytics.datapoint.test.ts
git commit -m "feat(web-analytics): AE data-point builder + slot registry"
```

---

### Task 4: Track endpoint (handler + Astro route + binding)

**Files:**
- Create: `website/src/lib/webAnalytics/track.ts`
- Create: `website/src/pages/api/track.ts`
- Modify: `website/wrangler.jsonc` (add `WEB_EVENTS` dataset binding)
- Test: `website/tests/webAnalytics.track.test.ts`

**Interfaces:**
- Consumes: `validateWebBatch` (T1), `buildWebDataPoint`+`WebEnrichment` (T3), `dailyVisitorHash`+`utcDate` (T2).
- Produces:
  - `interface TrackEnv { WEB_EVENTS?: AnalyticsEngineDataset; SECRET_SALT?: string }`
  - `async function handleTrackRequest(request: Request, env: TrackEnv, nowMs?: number): Promise<Response>` — **non-POST → 405; every POST → 204** (even on invalid input or missing binding). Writes one data point per valid event, enriched with country (`CF-IPCountry` / `request.cf.country`), referrer host (`Referer` header), and the daily visitor hash (`CF-Connecting-IP` + `User-Agent` + `SECRET_SALT`).

- [ ] **Step 1: Write the failing test**

```ts
// website/tests/webAnalytics.track.test.ts
import { describe, expect, test } from "bun:test";
import { handleTrackRequest, type TrackEnv } from "../src/lib/webAnalytics/track";
import type { WebDataPoint } from "../src/lib/webAnalytics/schema";

function mkEnv() {
  const points: WebDataPoint[] = [];
  const env: TrackEnv = { WEB_EVENTS: { writeDataPoint: (p) => points.push(p) }, SECRET_SALT: "s" };
  return { env, points };
}
function post(body: unknown, headers: Record<string, string> = {}) {
  return new Request("https://suniye.app/api/track", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "1.2.3.4", "User-Agent": "UA", "CF-IPCountry": "US", Referer: "https://www.google.com/search?q=x", ...headers },
    body: JSON.stringify(body),
  });
}

describe("handleTrackRequest", () => {
  test("writes one point per valid event and returns 204", async () => {
    const { env, points } = mkEnv();
    const res = await handleTrackRequest(post({ sent_at: 1, events: [
      { event_id: "a", event_ts: 1, session_id: "s", name: "pageview", props: { path: "/" } },
      { event_id: "b", event_ts: 2, session_id: "s", name: "download_click", props: { target: "dmg", path: "/" } },
    ] }), env);
    expect(res.status).toBe(204);
    expect(points).toHaveLength(2);
    expect(points[0].blobs?.[6]).toBe("US");          // country enrichment
    expect(points[0].blobs?.[2]).toBe("www.google.com"); // referrer host only
    expect(points[0].indexes?.[0]).toMatch(/^[0-9a-f]{64}$/); // visitor hash
  });

  test("returns 204 and writes nothing on invalid JSON", async () => {
    const { env, points } = mkEnv();
    const req = new Request("https://suniye.app/api/track", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{" });
    const res = await handleTrackRequest(req, env);
    expect(res.status).toBe(204);
    expect(points).toHaveLength(0);
  });

  test("returns 204 even when the binding is missing", async () => {
    const res = await handleTrackRequest(post({ sent_at: 1, events: [] }), { SECRET_SALT: "s" });
    expect(res.status).toBe(204);
  });

  test("rejects non-POST with 405", async () => {
    const res = await handleTrackRequest(new Request("https://suniye.app/api/track"), mkEnv().env);
    expect(res.status).toBe(405);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd website && bun test tests/webAnalytics.track.test.ts`
Expected: FAIL — cannot find module `../src/lib/webAnalytics/track`.

- [ ] **Step 3: Write minimal implementation**

```ts
// website/src/lib/webAnalytics/track.ts
import { buildWebDataPoint } from "./datapoint";
import { validateWebBatch, type AnalyticsEngineDataset } from "./schema";
import { dailyVisitorHash, utcDate } from "./visitor";

export interface TrackEnv {
  WEB_EVENTS?: AnalyticsEngineDataset;
  SECRET_SALT?: string;
}

const MAX_BODY = 16 * 1024;
const noContent = () => new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } });

function referrerHost(request: Request): string {
  const ref = request.headers.get("Referer");
  if (!ref) return "";
  try {
    return new URL(ref).hostname;
  } catch {
    return "";
  }
}

/**
 * Same-origin analytics ingest. ALWAYS returns 204 for POST (even on bad input
 * or missing binding) so the beacon can't be used to probe. Raw IP/UA are read
 * only to compute the daily visitor hash, then discarded.
 */
export async function handleTrackRequest(request: Request, env: TrackEnv, nowMs: number = Date.now()): Promise<Response> {
  if (request.method !== "POST") return new Response("Use POST", { status: 405 });

  const text = await request.text().catch(() => "");
  if (text.length > MAX_BODY) return noContent();

  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return noContent();
  }

  const batch = validateWebBatch(raw);
  if (typeof batch === "string" || !env.WEB_EVENTS) return noContent();

  const country = request.headers.get("CF-IPCountry")
    ?? (request as unknown as { cf?: { country?: string } }).cf?.country
    ?? "";
  const ip = request.headers.get("CF-Connecting-IP") ?? "";
  const ua = request.headers.get("User-Agent") ?? "";
  const visitorHash = await dailyVisitorHash(ip, ua, utcDate(nowMs), env.SECRET_SALT ?? "");
  const enrich = { referrerHost: referrerHost(request), country, visitorHash };

  for (const event of batch.events) {
    try {
      env.WEB_EVENTS.writeDataPoint(buildWebDataPoint(event, enrich));
    } catch (error) {
      console.error("web writeDataPoint failed", error);
    }
  }
  return noContent();
}
```

```ts
// website/src/pages/api/track.ts
import type { APIContext } from "astro";
import { env } from "cloudflare:workers";
import { handleTrackRequest, type TrackEnv } from "../../lib/webAnalytics/track";

export const prerender = false;

export async function POST({ request }: APIContext): Promise<Response> {
  return handleTrackRequest(request, env as unknown as TrackEnv);
}

export async function ALL({ request }: APIContext): Promise<Response> {
  return handleTrackRequest(request, env as unknown as TrackEnv);
}
```

Add the AE binding to `website/wrangler.jsonc` (inside the top-level object, after `"observability"`):

```jsonc
  "observability": { "enabled": true },
  // First-party web-analytics dataset (marketing site). Auto-provisions on first write.
  "analytics_engine_datasets": [{ "binding": "WEB_EVENTS", "dataset": "suniye_web" }]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd website && bun test tests/webAnalytics.track.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Verify the site still builds with the new route + binding**

Run: `cd website && bun run build`
Expected: build succeeds; `dist/server/wrangler.json` includes the `WEB_EVENTS` dataset (the adapter merges `wrangler.jsonc`).

- [ ] **Step 6: Commit**

```bash
git add website/src/lib/webAnalytics/track.ts website/src/pages/api/track.ts website/wrangler.jsonc website/tests/webAnalytics.track.test.ts
git commit -m "feat(web-analytics): same-origin /api/track ingest endpoint + WEB_EVENTS binding"
```

---

### Task 5: Beacon core (pure queue/batch logic)

**Files:**
- Create: `website/src/lib/webAnalytics/beaconCore.ts`
- Test: `website/tests/webAnalytics.beaconCore.test.ts`

**Interfaces:**
- Produces:
  - `interface BeaconEvent { name: string; props: Record<string, string | number | boolean> }`
  - `interface BeaconCoreDeps { sessionId: string; send: (body: string) => void; genId: () => string; now: () => number }`
  - `interface BeaconCore { track(ev: BeaconEvent): void; trackScrollDepth(depth: number, path: string): void; flush(): void }`
  - `function createBeaconCore(deps: BeaconCoreDeps): BeaconCore` — buffers events; `flush()` serializes `{ sent_at, events:[{event_id,event_ts,session_id,name,props}] }` and calls `send`, then clears; `trackScrollDepth` fires a given depth **at most once**; empty `flush()` is a no-op.

- [ ] **Step 1: Write the failing test**

```ts
// website/tests/webAnalytics.beaconCore.test.ts
import { describe, expect, test } from "bun:test";
import { createBeaconCore } from "../src/lib/webAnalytics/beaconCore";

function harness() {
  const sent: string[] = [];
  let id = 0;
  const core = createBeaconCore({ sessionId: "sess", send: (b) => sent.push(b), genId: () => "id" + id++, now: () => 42 });
  return { core, sent };
}

describe("createBeaconCore", () => {
  test("buffers then flushes a batch with envelope fields", () => {
    const { core, sent } = harness();
    core.track({ name: "pageview", props: { path: "/" } });
    core.track({ name: "cta_click", props: { cta: "hero_download", path: "/" } });
    expect(sent).toHaveLength(0);
    core.flush();
    expect(sent).toHaveLength(1);
    const batch = JSON.parse(sent[0]);
    expect(batch.events).toHaveLength(2);
    expect(batch.events[0]).toMatchObject({ name: "pageview", session_id: "sess", event_ts: 42, event_id: "id0" });
    expect(batch.sent_at).toBe(42);
  });

  test("flush clears the buffer (second flush is a no-op)", () => {
    const { core, sent } = harness();
    core.track({ name: "pageview", props: { path: "/" } });
    core.flush();
    core.flush();
    expect(sent).toHaveLength(1);
  });

  test("scroll depth fires each threshold at most once", () => {
    const { core, sent } = harness();
    core.trackScrollDepth(50, "/");
    core.trackScrollDepth(50, "/"); // duplicate — ignored
    core.trackScrollDepth(75, "/");
    core.flush();
    const batch = JSON.parse(sent[0]);
    expect(batch.events.map((e: any) => e.props.depth)).toEqual([50, 75]);
  });

  test("empty flush sends nothing", () => {
    const { core, sent } = harness();
    core.flush();
    expect(sent).toHaveLength(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd website && bun test tests/webAnalytics.beaconCore.test.ts`
Expected: FAIL — cannot find module `../src/lib/webAnalytics/beaconCore`.

- [ ] **Step 3: Write minimal implementation**

```ts
// website/src/lib/webAnalytics/beaconCore.ts
export interface BeaconEvent {
  name: string;
  props: Record<string, string | number | boolean>;
}

export interface BeaconCoreDeps {
  sessionId: string;
  send: (body: string) => void;
  genId: () => string;
  now: () => number;
}

export interface BeaconCore {
  track(ev: BeaconEvent): void;
  trackScrollDepth(depth: number, path: string): void;
  flush(): void;
}

/**
 * DOM-agnostic beacon buffer. Holds events until flush(), which serializes the
 * batch envelope and hands it to `send` (the DOM layer wires sendBeacon). Pure
 * and unit-testable; scroll thresholds are de-duplicated here.
 */
export function createBeaconCore(deps: BeaconCoreDeps): BeaconCore {
  const queue: Array<{ event_id: string; event_ts: number; session_id: string; name: string; props: Record<string, string | number | boolean> }> = [];
  const firedDepths = new Set<number>();

  function track(ev: BeaconEvent): void {
    queue.push({ event_id: deps.genId(), event_ts: deps.now(), session_id: deps.sessionId, name: ev.name, props: ev.props });
  }

  function trackScrollDepth(depth: number, path: string): void {
    if (firedDepths.has(depth)) return;
    firedDepths.add(depth);
    track({ name: "scroll_depth", props: { depth, path } });
  }

  function flush(): void {
    if (queue.length === 0) return;
    const events = queue.splice(0, queue.length);
    deps.send(JSON.stringify({ sent_at: deps.now(), events }));
  }

  return { track, trackScrollDepth, flush };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd website && bun test tests/webAnalytics.beaconCore.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add website/src/lib/webAnalytics/beaconCore.ts website/tests/webAnalytics.beaconCore.test.ts
git commit -m "feat(web-analytics): pure beacon buffer with scroll-depth dedup"
```

---

### Task 6: Beacon DOM wiring + layout include + tracked elements

**Files:**
- Create: `website/src/lib/webAnalytics/beacon.ts` (DOM wiring — `initBeacon()`)
- Create: `website/src/components/Beacon.astro` (bundles + runs the beacon)
- Modify: `website/src/layouts/Layout.astro` (include `<Beacon />` before `</body>`)
- Modify: `website/src/pages/index.astro` (add `data-track` attributes to Download link, Homebrew copy, GitHub link, demo video)

**Interfaces:**
- Consumes: `createBeaconCore` (T5).
- Produces: `function initBeacon(): void` — reads/creates a `sessionStorage` session id, sends a `pageview` (with path, UTM from `location.search`, device/viewport from `window`), wires click listeners via `[data-track]` delegation and scroll thresholds, and flushes via `navigator.sendBeacon` (fallback `fetch(..., {keepalive:true})`) on `visibilitychange`→hidden and `pagehide`. `download_click` flushes immediately (it precedes navigation).

**Note:** DOM wiring is verified by build + a manual network check, not bun unit tests (no DOM in the test env); the testable logic lives in Task 5.

- [ ] **Step 1: Write the DOM wiring module**

```ts
// website/src/lib/webAnalytics/beacon.ts
import { createBeaconCore, type BeaconCore } from "./beaconCore";

const ENDPOINT = "/api/track";
const SCROLL_THRESHOLDS = [25, 50, 75, 100];

function sessionId(): string {
  try {
    const k = "suniye_sid";
    let v = sessionStorage.getItem(k);
    if (!v) {
      v = crypto.randomUUID();
      sessionStorage.setItem(k, v);
    }
    return v;
  } catch {
    return crypto.randomUUID(); // private mode / storage blocked — ephemeral in-memory id
  }
}

function send(body: string): void {
  try {
    if (navigator.sendBeacon && navigator.sendBeacon(ENDPOINT, new Blob([body], { type: "application/json" }))) return;
  } catch {
    /* fall through */
  }
  fetch(ENDPOINT, { method: "POST", body, keepalive: true, headers: { "Content-Type": "application/json" } }).catch(() => {});
}

function pageviewProps(): Record<string, string> {
  const q = new URLSearchParams(location.search);
  const props: Record<string, string> = {
    path: location.pathname,
    device: window.matchMedia("(pointer: coarse)").matches ? "mobile" : "desktop",
    viewport: window.innerWidth < 640 ? "sm" : window.innerWidth < 1024 ? "md" : "lg",
  };
  for (const k of ["utm_source", "utm_medium", "utm_campaign"]) {
    const v = q.get(k);
    if (v) props[k] = v.slice(0, 256);
  }
  return props;
}

export function initBeacon(): void {
  if (typeof window === "undefined") return;
  const core: BeaconCore = createBeaconCore({
    sessionId: sessionId(),
    send,
    genId: () => crypto.randomUUID(),
    now: () => Date.now(),
  });

  core.track({ name: "pageview", props: pageviewProps() });

  // Click delegation: elements opt in via data-track="event:value".
  document.addEventListener(
    "click",
    (e) => {
      const el = (e.target as HTMLElement | null)?.closest?.("[data-track]") as HTMLElement | null;
      if (!el) return;
      const [name, value] = (el.dataset.track ?? "").split(":");
      if (!name) return;
      const key = name === "download_click" ? "target" : name === "outbound_click" ? "host" : "cta";
      core.track({ name, props: { [key]: value ?? "", path: location.pathname } });
      if (name === "download_click") core.flush(); // precedes navigation
    },
    { capture: true },
  );

  // Scroll depth.
  let ticking = false;
  const onScroll = () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      ticking = false;
      const doc = document.documentElement;
      const pct = ((window.scrollY + window.innerHeight) / doc.scrollHeight) * 100;
      for (const t of SCROLL_THRESHOLDS) if (pct >= t) core.trackScrollDepth(t, location.pathname);
    });
  };
  window.addEventListener("scroll", onScroll, { passive: true });

  // Demo video plays (any <video data-track-video>).
  document.querySelectorAll("video[data-track-video]").forEach((v) =>
    v.addEventListener("play", () => core.track({ name: "video_play", props: { path: location.pathname } }), { once: true }),
  );

  // Flush on the way out.
  const flush = () => core.flush();
  document.addEventListener("visibilitychange", () => document.visibilityState === "hidden" && flush());
  window.addEventListener("pagehide", flush);
}
```

- [ ] **Step 2: Create the Astro component that runs it**

```astro
---
// website/src/components/Beacon.astro
// First-party, cookieless analytics beacon (see docs/superpowers/specs/2026-07-07-marketing-web-analytics-design.md).
---
<script>
  import { initBeacon } from "../lib/webAnalytics/beacon";
  initBeacon();
</script>
```

- [ ] **Step 3: Include the beacon in the base layout**

In `website/src/layouts/Layout.astro`, add the import in the frontmatter and render `<Beacon />` just before `</body>`:

```astro
---
import Beacon from "../components/Beacon.astro";
// ...existing frontmatter...
---
<!-- ...existing markup... -->
  <body class="min-w-[320px] bg-bg font-body text-ink antialiased">
    <slot />
    <Beacon />
  </body>
```

- [ ] **Step 4: Tag the tracked elements in `index.astro`**

Add `data-track` (and `data-track-video` on the demo video, if present) to the key CTAs. Concretely:
- The DMG download link (`href={downloadUrl}`): add `data-track="download_click:dmg"`.
- The Homebrew `CopyField` / its wrapping element: add `data-track="download_click:homebrew"` on the clickable copy control.
- The GitHub link(s) (`href={githubUrl}`): add `data-track="outbound_click:github"`.
- Any primary hero CTA button: add `data-track="cta_click:hero_download"`; nav download: `data-track="cta_click:nav_download"`.
- If the hero has a `<video>` demo, add `data-track-video`.

Example for the download link:

```astro
<a href={downloadUrl} data-track="download_click:dmg" ...existing attrs>
```

- [ ] **Step 5: Verify build + no type errors**

Run: `cd website && bun run build`
Expected: build succeeds; the beacon script is emitted into the client bundle. (The Astro `<script>` import is bundled automatically.)

- [ ] **Step 6: Manual integration check**

Run: `cd website && bun run dev`, open the site, and in DevTools → Network confirm a `POST /api/track` fires on load (204) and on clicking Download. (Local `wrangler`/`astro dev` may not have the AE binding; the route still returns 204 — that's expected. Real writes verify after deploy.)

- [ ] **Step 7: Commit**

```bash
git add website/src/lib/webAnalytics/beacon.ts website/src/components/Beacon.astro website/src/layouts/Layout.astro website/src/pages/index.astro
git commit -m "feat(web-analytics): client beacon + tracked CTAs in the marketing layout"
```

---

### Task 7: Web-stats query builder

**Files:**
- Create: `website/workers/dashboard/src/worker/webStats.ts`
- Test: `website/workers/dashboard/test/webStats.test.ts`

**Interfaces:**
- Consumes: `AeRunner` type from `./stats` (`export type AeRunner = (sql: string) => Promise<Array<Record<string, unknown>>>`), and `safeLabel` from `./stats`.
- Produces:
  - `interface WebStatsResponse { rangeDays: number; visitors: number; pageviews: number; downloads: number; conversionPct: number; visitorsSeries: TimePoint[]; topSources: Breakdown[]; topPages: Breakdown[]; downloadsByTarget: Breakdown[]; scrollDepth: Breakdown[]; countries: Breakdown[]; devices: Breakdown[]; campaigns: Breakdown[] }` (reuse `TimePoint`/`Breakdown` from `./types`).
  - `async function buildWebStats(ae: AeRunner, opts: { rangeDays: number; nowMs: number; datasetName: string }): Promise<WebStatsResponse>`

**Query rules (from Global Constraints):** counts = `SUM(_sample_interval)`; uniques = `COUNT(DISTINCT index1)`; day bucket = `toStartOfInterval(toDateTime(double1 / 1000), INTERVAL '1' DAY)`; filter each event query by `blob1 = '<name>'` and `double1 >= <cutoffMs>`. Conversion = downloads / pageviews.

- [ ] **Step 1: Write the failing test**

```ts
// website/workers/dashboard/test/webStats.test.ts
import { describe, expect, test } from "bun:test";
import { buildWebStats } from "../src/worker/webStats";

// A canned AE runner: match on a SQL fragment, return rows.
function fakeAe(rules: Array<[RegExp, Array<Record<string, unknown>>]>) {
  const seen: string[] = [];
  const ae = async (sql: string) => {
    seen.push(sql);
    for (const [re, rows] of rules) if (re.test(sql)) return rows;
    return [];
  };
  return { ae, seen };
}

describe("buildWebStats", () => {
  test("computes headline + conversion and issues sampling-correct SQL", async () => {
    const { ae, seen } = fakeAe([
      [/COUNT\(DISTINCT index1\)[\s\S]*blob1 = 'pageview'/, [{ value: 500 }]], // visitors
      [/SUM\(_sample_interval\)[\s\S]*blob1 = 'pageview'/, [{ value: 800 }]],  // pageviews
      [/SUM\(_sample_interval\)[\s\S]*blob1 = 'download_click'/, [{ value: 40 }]], // downloads
    ]);
    const stats = await buildWebStats(ae, { rangeDays: 30, nowMs: 1_700_000_000_000, datasetName: "suniye_web" });
    expect(stats.visitors).toBe(500);
    expect(stats.pageviews).toBe(800);
    expect(stats.downloads).toBe(40);
    expect(stats.conversionPct).toBeCloseTo(5, 5); // 40/800
    expect(seen.some((s) => /toStartOfInterval\(toDateTime\(double1 \/ 1000\)/.test(s))).toBe(true);
    expect(seen.every((s) => /FROM suniye_web/.test(s))).toBe(true);
  });

  test("conversion is 0 when there are no pageviews (no divide-by-zero)", async () => {
    const { ae } = fakeAe([]); // everything returns []
    const stats = await buildWebStats(ae, { rangeDays: 7, nowMs: 1_700_000_000_000, datasetName: "suniye_web" });
    expect(stats.pageviews).toBe(0);
    expect(stats.conversionPct).toBe(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd website/workers/dashboard && bun test test/webStats.test.ts`
Expected: FAIL — cannot find module `../src/worker/webStats`.

- [ ] **Step 3: Write minimal implementation**

```ts
// website/workers/dashboard/src/worker/webStats.ts
import { safeLabel, type AeRunner } from "./stats";
import type { Breakdown, TimePoint } from "./types";

const DAY_MS = 86_400_000;

export interface WebStatsResponse {
  rangeDays: number;
  visitors: number;
  pageviews: number;
  downloads: number;
  conversionPct: number;
  visitorsSeries: TimePoint[];
  topSources: Breakdown[];
  topPages: Breakdown[];
  downloadsByTarget: Breakdown[];
  scrollDepth: Breakdown[];
  countries: Breakdown[];
  devices: Breakdown[];
  campaigns: Breakdown[];
}

const num = (rows: Array<Record<string, unknown>>, key = "value"): number => {
  const v = rows[0]?.[key];
  return typeof v === "number" ? v : Number(v ?? 0) || 0;
};
const breakdown = (rows: Array<Record<string, unknown>>): Breakdown[] =>
  rows
    .map((r) => ({ label: String(r.label ?? ""), value: Number(r.value ?? 0) || 0 }))
    .filter((r) => r.label !== "");
const series = (rows: Array<Record<string, unknown>>): TimePoint[] =>
  rows.map((r) => ({ day: String(r.day ?? "").slice(0, 10), value: Number(r.value ?? 0) || 0 }));

/**
 * Web analytics aggregates over the suniye_web AE dataset. Mirrors stats.ts:
 * counts via SUM(_sample_interval), uniques via COUNT(DISTINCT index1), day
 * bucketing on the client event_ts (double1). All literals here are the dataset
 * name (safeLabel-checked) and server-computed numbers — no user input reaches SQL.
 */
export async function buildWebStats(
  ae: AeRunner,
  opts: { rangeDays: number; nowMs: number; datasetName: string },
): Promise<WebStatsResponse> {
  const ds = safeLabel(opts.datasetName) ?? "suniye_web";
  const cutoff = opts.nowMs - opts.rangeDays * DAY_MS;
  const q = (sql: string) => ae(sql);
  const ev = (name: string) => `blob1 = '${name}' AND double1 >= ${cutoff}`;

  const [
    visitorsRows, pageviewRows, downloadRows,
    seriesRows, sourcesRows, pagesRows, targetRows, scrollRows, countryRows, deviceRows, campaignRows,
  ] = await Promise.all([
    q(`SELECT COUNT(DISTINCT index1) AS value FROM ${ds} WHERE ${ev("pageview")}`),
    q(`SELECT SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")}`),
    q(`SELECT SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("download_click")}`),
    q(`SELECT toStartOfInterval(toDateTime(double1 / 1000), INTERVAL '1' DAY) AS day, COUNT(DISTINCT index1) AS value FROM ${ds} WHERE ${ev("pageview")} GROUP BY day ORDER BY day`),
    q(`SELECT blob3 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")} AND blob3 != '' GROUP BY label ORDER BY value DESC LIMIT 20`),
    q(`SELECT blob2 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")} GROUP BY label ORDER BY value DESC LIMIT 20`),
    q(`SELECT blob9 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("download_click")} GROUP BY label ORDER BY value DESC LIMIT 10`),
    q(`SELECT toString(double2) AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("scroll_depth")} GROUP BY label ORDER BY label`),
    q(`SELECT blob7 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")} AND blob7 != '' GROUP BY label ORDER BY value DESC LIMIT 20`),
    q(`SELECT blob8 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")} AND blob8 != '' GROUP BY label ORDER BY value DESC`),
    q(`SELECT blob6 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")} AND blob6 != '' GROUP BY label ORDER BY value DESC LIMIT 20`),
  ]);

  const pageviews = num(pageviewRows);
  const downloads = num(downloadRows);
  return {
    rangeDays: opts.rangeDays,
    visitors: num(visitorsRows),
    pageviews,
    downloads,
    conversionPct: pageviews > 0 ? (downloads / pageviews) * 100 : 0,
    visitorsSeries: series(seriesRows),
    topSources: breakdown(sourcesRows),
    topPages: breakdown(pagesRows),
    downloadsByTarget: breakdown(targetRows),
    scrollDepth: breakdown(scrollRows),
    countries: breakdown(countryRows),
    devices: breakdown(deviceRows),
    campaigns: breakdown(campaignRows),
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd website/workers/dashboard && bun test test/webStats.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add website/workers/dashboard/src/worker/webStats.ts website/workers/dashboard/test/webStats.test.ts
git commit -m "feat(web-analytics): dashboard web-stats query builder"
```

---

### Task 8: Dashboard `/api/web-stats` endpoint + "Web" tab UI

**Files:**
- Modify: `website/workers/dashboard/src/worker/index.ts` (add `/api/web-stats` route)
- Modify: `website/workers/dashboard/src/worker/types.ts` (add optional `AE_WEB_DATASET` env)
- Create: `website/workers/dashboard/src/app/WebView.tsx` (the Web tab content)
- Modify: `website/workers/dashboard/src/app/App.tsx` (App/Web tab switch)
- Modify: `website/workers/dashboard/src/app/types.ts` (mirror `WebStatsResponse` for the client)

**Interfaces:**
- Consumes: `buildWebStats`, `WebStatsResponse` (T7); `makeAeRunner` (existing `stats.ts`); the existing `authorize` + `clampRange` in `index.ts`.
- Produces: `GET /api/web-stats?range=N` → `WebStatsResponse` JSON (Access-gated, reusing the app auth).

- [ ] **Step 1: Add the worker route**

In `website/workers/dashboard/src/worker/index.ts`, import and add a branch alongside `/api/stats`:

```ts
import { buildWebStats } from "./webStats";
// ...
    if (url.pathname === "/api/web-stats") {
      return handleWebStats(request, env);
    }
```

Add the handler (mirrors `handleStats`, minus D1/filters):

```ts
async function handleWebStats(request: Request, env: DashboardEnv): Promise<Response> {
  if (!env.CF_ACCOUNT_ID || !env.AE_API_TOKEN) return json({ error: "not_configured" }, 503);
  const rangeDays = clampRange(Number(new URL(request.url).searchParams.get("range") ?? "30"));
  const ae = makeAeRunner(env.CF_ACCOUNT_ID, env.AE_API_TOKEN);
  try {
    const stats = await buildWebStats(ae, {
      rangeDays,
      nowMs: Date.now(),
      datasetName: (env as { AE_WEB_DATASET?: string }).AE_WEB_DATASET ?? "suniye_web",
    });
    return json(stats, 200);
  } catch (error) {
    console.error("web stats failed", error);
    return json({ error: "stats_failed" }, 502);
  }
}
```

- [ ] **Step 2: Verify the worker still builds/tests**

Run: `cd website/workers/dashboard && bun test`
Expected: PASS (existing + new webStats tests; the route is thin and covered by T7's builder tests).

- [ ] **Step 3: Add the client types**

In `website/workers/dashboard/src/app/types.ts`, add a `WebStats` interface mirroring `WebStatsResponse` (same field names/types as T7).

```ts
export interface WebStats {
  rangeDays: number;
  visitors: number;
  pageviews: number;
  downloads: number;
  conversionPct: number;
  visitorsSeries: { day: string; value: number }[];
  topSources: { label: string; value: number }[];
  topPages: { label: string; value: number }[];
  downloadsByTarget: { label: string; value: number }[];
  scrollDepth: { label: string; value: number }[];
  countries: { label: string; value: number }[];
  devices: { label: string; value: number }[];
  campaigns: { label: string; value: number }[];
}
```

- [ ] **Step 4: Build the Web view**

Create `website/workers/dashboard/src/app/WebView.tsx` — fetches `/api/web-stats?range=<range>` and renders KPI tiles (visitors, pageviews, downloads, conversion %), the visitors series, funnel (pageview → download split by target), top sources/pages/campaigns, scroll-depth histogram, and geo/device breakdowns. **Reuse the existing dashboard chart/tile components** (import the same primitives `App.tsx` uses for the app view — match their props exactly). Accept `range` as a prop from `App.tsx` so the shared range picker drives both tabs.

```tsx
// website/workers/dashboard/src/app/WebView.tsx
import { useEffect, useState } from "react";
import type { WebStats } from "./types";
// import the same StatCard / BarList / LineChart primitives App.tsx uses.

export function WebView({ range }: { range: number }) {
  const [stats, setStats] = useState<WebStats | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    fetch(`/api/web-stats?range=${range}`)
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((d) => alive && setStats(d as WebStats))
      .catch((e) => alive && setError(String(e)));
    return () => {
      alive = false;
    };
  }, [range]);

  if (error) return <p className="text-sm text-red-500">Failed to load web stats: {error}</p>;
  if (!stats) return <p className="text-sm text-muted">Loading…</p>;

  // Render KPI row + charts using the SAME primitives as the app view.
  // (Exact JSX depends on the existing components; match their prop shapes.)
  return (
    <div className="space-y-8">
      {/* KPI tiles: visitors, pageviews, downloads, conversionPct */}
      {/* visitorsSeries line; downloadsByTarget + topSources + topPages + campaigns bar lists; scrollDepth histogram; countries + devices */}
    </div>
  );
}
```

- [ ] **Step 5: Add the tab switch in `App.tsx`**

Add a `tab` state (`"app" | "web"`), a two-button toggle near the range picker, and render `<WebView range={range} />` when `tab === "web"` (the existing app content when `"app"`). Keep the existing range picker shared across both.

```tsx
const [tab, setTab] = useState<"app" | "web">("app");
// near the header controls:
<div role="tablist" className="flex gap-1">
  <button role="tab" aria-selected={tab === "app"} onClick={() => setTab("app")}>App</button>
  <button role="tab" aria-selected={tab === "web"} onClick={() => setTab("web")}>Web</button>
</div>
// in the body:
{tab === "web" ? <WebView range={range} /> : (/* existing app dashboard JSX */)}
```

- [ ] **Step 6: Verify the dashboard builds**

Run: `cd website/workers/dashboard && bun run build` (or the repo's dashboard build script; check `package.json`).
Expected: build succeeds; no TypeScript errors; `WebStats` fields line up with `WebStatsResponse`.

- [ ] **Step 7: Commit**

```bash
git add website/workers/dashboard/src/worker/index.ts website/workers/dashboard/src/worker/types.ts website/workers/dashboard/src/app/WebView.tsx website/workers/dashboard/src/app/App.tsx website/workers/dashboard/src/app/types.ts
git commit -m "feat(web-analytics): dashboard /api/web-stats endpoint + Web tab"
```

---

### Task 9: Privacy-page disclosure

**Files:**
- Modify: `website/src/pages/privacy.astro` (add a "Website analytics" section)

**Interfaces:** none (content).

- [ ] **Step 1: Add the disclosure section**

In `website/src/pages/privacy.astro`, add a **"Website analytics"** section (matching the page's existing markup/typography) stating: this marketing site measures aggregate visits, traffic sources, and download clicks; it is **cookieless with no consent banner**; it stores **no personal data** and no third-party trackers; unique visitors are counted with a **daily-rotating, non-reversible hash** (raw IP is never stored); referrers are reduced to host only; data lives on our own Cloudflare infrastructure with ~90-day retention.

Example paragraph (adapt to the page's components/classes):

```astro
<section>
  <h2 class="...">Website analytics</h2>
  <p class="...">
    This website measures aggregate, non-identifying usage — page visits, where visitors
    come from, and download clicks — to see what's working. It uses <strong>no cookies</strong>
    and shows <strong>no consent banner</strong> because it stores no personal data and loads no
    third-party trackers. Unique visitors are counted with a daily-rotating, one-way hash; your
    IP address is never stored, and referrers are reduced to the site host only. The data lives on
    our own Cloudflare infrastructure and is retained about 90 days.
  </p>
</section>
```

- [ ] **Step 2: Verify build**

Run: `cd website && bun run build`
Expected: build succeeds; privacy page renders the new section.

- [ ] **Step 3: Commit**

```bash
git add website/src/pages/privacy.astro
git commit -m "docs(privacy): disclose first-party website analytics"
```

---

## Deployment notes (post-implementation, not a code task)

- Set the salt secret on the marketing Worker: `cd website && wrangler secret put SECRET_SALT` (any long random string).
- Deploy the marketing Worker: `cd website && bun run deploy`. The `suniye_web` dataset auto-provisions on the first `writeDataPoint`.
- The dashboard Worker already holds `CF_ACCOUNT_ID` + `AE_API_TOKEN`; optionally set `AE_WEB_DATASET=suniye_web` (defaults to that if unset). Redeploy the dashboard.
- Verify events land: query the AE SQL API for `SELECT COUNT() FROM suniye_web` after visiting the site, then open the dashboard "Web" tab.

## Self-review (author checklist — done)

- **Spec coverage:** §3 architecture → T4/T6/T8; §4 events+slots → T1/T3; §5 enrichment → T4; §6 privacy page → T9; §7 dashboard → T7/T8; §9 testing → tests in T1–T5,T7; visitor hash (§2.1) → T2. All covered.
- **Placeholders:** none (`WebView.tsx` render body intentionally defers exact JSX to the existing chart primitives, which the implementer must import and match — flagged explicitly, with the data contract fully specified in T7/T8-step-3). Every pure/testable unit has complete code.
- **Type consistency:** `WebEvent`/`WebBatch`/`WebDataPoint` (T1) reused in T3/T4/T5; `WebEnrichment` (T3) consumed in T4; `WebStatsResponse` (T7) mirrored as client `WebStats` (T8) field-for-field; `AeRunner`/`safeLabel` imported from `./stats` (verified exported).
