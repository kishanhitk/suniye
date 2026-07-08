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
