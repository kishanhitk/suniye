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

  test("drops an unknown event even when its props are malformed, keeping valid events", () => {
    const bad = ev({ name: "future_event", props: (() => { const p: Record<string, string> = {}; for (let i = 0; i < 13; i++) p["k" + i] = "v"; return p; })() });
    const out = validateWebBatch({ sent_at: 1, events: [bad, ev()] });
    expect(typeof out).not.toBe("string");
    expect((out as any).events).toHaveLength(1);
    expect((out as any).events[0].name).toBe("pageview");
  });

  test("exposes the closed name set", () => {
    expect(WEB_EVENT_NAMES).toContain("download_click");
    expect(WEB_EVENT_NAMES).toHaveLength(6);
  });
});
