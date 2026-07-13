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

  test("one query failing does not blank the whole response (per-query isolation)", async () => {
    const ae = async (sql: string) => {
      if (/blob1 = 'scroll_depth'/.test(sql)) throw new Error("boom: bad AE query");
      if (/COUNT\(DISTINCT index1\)[\s\S]*blob1 = 'pageview'/.test(sql)) return [{ value: 500 }];
      if (/SUM\(_sample_interval\)[\s\S]*blob1 = 'pageview'/.test(sql)) return [{ value: 800 }];
      if (/SUM\(_sample_interval\)[\s\S]*blob1 = 'download_click'/.test(sql)) return [{ value: 40 }];
      return [];
    };
    const stats = await buildWebStats(ae, { rangeDays: 30, nowMs: 1_700_000_000_000, datasetName: "suniye_web" });
    // The scroll-depth panel degrades to empty instead of throwing…
    expect(stats.scrollDepth).toEqual([]);
    // …while every other field still resolves normally.
    expect(stats.visitors).toBe(500);
    expect(stats.pageviews).toBe(800);
    expect(stats.downloads).toBe(40);
  });

  test("scroll depth is ordered numerically (25, 50, 75, 100), not lexically", async () => {
    const { ae, seen } = fakeAe([
      [/blob1 = 'scroll_depth'/, [
        { label: "100", value: 10 },
        { label: "25", value: 40 },
        { label: "50", value: 30 },
        { label: "75", value: 20 },
      ]],
    ]);
    await buildWebStats(ae, { rangeDays: 30, nowMs: 1_700_000_000_000, datasetName: "suniye_web" });
    const scrollSql = seen.find((s) => /blob1 = 'scroll_depth'/.test(s));
    expect(scrollSql).toBeDefined();
    expect(scrollSql).toMatch(/ORDER BY double2/);
    expect(scrollSql).not.toMatch(/ORDER BY label/);
  });

  test("surfaces cta_click as ctaClicks + topCtas, filtered on blob1 = 'cta_click'", async () => {
    const { ae, seen } = fakeAe([
      // blob9-breakdown rule first: it's the more specific pattern, and the
      // headline-count rule below would otherwise also match its SQL (both
      // contain "SUM(_sample_interval) ... blob1 = 'cta_click'").
      [/^SELECT blob9 AS label[\s\S]*blob1 = 'cta_click'/, [
        { label: "get-started", value: 50 },
        { label: "download-hero", value: 27 },
      ]],
      [/^SELECT SUM\(_sample_interval\)[\s\S]*blob1 = 'cta_click'/, [{ value: 77 }]],
    ]);
    const stats = await buildWebStats(ae, { rangeDays: 30, nowMs: 1_700_000_000_000, datasetName: "suniye_web" });
    expect(stats.ctaClicks).toBe(77);
    expect(stats.topCtas).toEqual([
      { label: "get-started", value: 50 },
      { label: "download-hero", value: 27 },
    ]);
    expect(seen.some((s) => /blob1 = 'cta_click'/.test(s) && /SUM\(_sample_interval\) AS value/.test(s))).toBe(true);
    expect(seen.some((s) => /blob9 AS label/.test(s) && /blob1 = 'cta_click'/.test(s))).toBe(true);
  });
});
