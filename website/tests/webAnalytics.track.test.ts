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

  test("warns once (not per request) when SECRET_SALT is missing, and still writes + returns 204", async () => {
    const points: WebDataPoint[] = [];
    const env: TrackEnv = { WEB_EVENTS: { writeDataPoint: (p) => points.push(p) } }; // no SECRET_SALT
    const warnCalls: unknown[][] = [];
    const originalWarn = console.warn;
    console.warn = (...args: unknown[]) => warnCalls.push(args);
    try {
      const body = { sent_at: 1, events: [{ event_id: "a", event_ts: 1, session_id: "s", name: "pageview", props: { path: "/" } }] };
      const res1 = await handleTrackRequest(post(body), env);
      const res2 = await handleTrackRequest(post(body), env);
      expect(res1.status).toBe(204);
      expect(res2.status).toBe(204);
      expect(points).toHaveLength(2); // events still written despite the missing salt
      expect(points[0].indexes?.[0]).toMatch(/^[0-9a-f]{64}$/); // hash still computed (unsalted)
      expect(warnCalls.filter((c) => String(c[0]).includes("SECRET_SALT"))).toHaveLength(1); // warns once per isolate
    } finally {
      console.warn = originalWarn;
    }
  });
});
