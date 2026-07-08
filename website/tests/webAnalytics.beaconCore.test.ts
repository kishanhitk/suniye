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
