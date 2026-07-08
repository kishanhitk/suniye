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
