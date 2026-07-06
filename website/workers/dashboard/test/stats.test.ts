import { describe, expect, test } from "bun:test";
import { buildStats, sql, type AeRunner, type D1Runner } from "../src/worker/stats";

describe("sql builders", () => {
  test("time-series bucket on client event_ts (double1), never ingestion timestamp", () => {
    const q = sql.wordsPerDay("suniye_events", 1000);
    expect(q).toContain("toDateTime(double1"); // buckets on client event_ts
    expect(q).not.toContain("ingestion");
    expect(q).not.toContain("toUInt64"); // unsupported by the AE SQL API
    expect(q).toContain("SUM(double2 * _sample_interval)"); // sampling-correct
    expect(q).toContain("blob1 = 'dictation_completed'");
  });

  test("latency uses AE-supported quantileWeighted, not parametric quantile", () => {
    const q = sql.latency("ds", 0);
    expect(q).toContain("quantileWeighted(0.5, double5, _sample_interval)"); // level, value, weight
    expect(q).not.toContain("quantile(0.5)(");
  });

  test("active installs uses COUNT(DISTINCT index1)", () => {
    expect(sql.activeInstallsPerDay("ds", 0)).toContain("COUNT(DISTINCT index1)");
  });

  test("breakdown sums the sample interval", () => {
    expect(sql.breakdown("ds", "blob5", "blob1 = 'dictation_completed'", 0)).toContain("SUM(_sample_interval)");
  });
});

describe("buildStats", () => {
  const ae: AeRunner = async (q) => {
    if (q.includes("SUM(double2")) return [{ day: "2026-07-06 00:00:00", value: 100 }, { day: "2026-07-07 00:00:00", value: 150 }];
    if (q.includes("COUNT(DISTINCT index1)")) return [{ day: "2026-07-06 00:00:00", value: 5 }];
    if (q.includes("blob5 AS label")) return [{ label: "parakeet-v3", value: 42 }];
    if (q.includes("blob10 AS label")) return [];
    if (q.includes("blob14 AS label")) return [{ label: "transcription", value: 3 }];
    if (q.includes("AS polished")) return [{ polished: 30, total: 50 }];
    if (q.includes("e2e_p50")) return [{ e2e_p50: 200, e2e_p95: 500, asr_p50: 150, asr_p95: 300, llm_p50: 100, llm_p95: 250 }];
    if (q.includes("'app_launch'")) return [{ value: 20 }];
    if (q.includes("'session_end'")) return [{ value: 16 }];
    return [];
  };

  const d1: D1Runner = async (q) => {
    if (q.includes("COUNT(*) AS n")) return [{ n: 12 }];
    if (q.includes("first_seen AS day")) return [{ day: "2026-07-01", value: 2 }];
    if (q.includes("chip AS label")) return [{ label: "apple-m3-pro", value: 8 }];
    if (q.includes("ram_gb AS label")) return [{ label: 36, value: 5 }];
    if (q.includes("country AS label")) return [{ label: "US", value: 9 }];
    return [];
  };

  test("assembles the full response", async () => {
    const stats = await buildStats(ae, d1, { rangeDays: 30, nowMs: 1_700_000_000_000 });

    expect(stats.rangeDays).toBe(30);
    expect(stats.totalInstalls).toBe(12);
    expect(stats.wordsPerDay).toHaveLength(2);
    expect(stats.wordsPerDay[0].value).toBe(100);
    expect(stats.wordsPerDay[0].day).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(stats.asrModelBreakdown[0].label).toBe("parakeet-v3");
    expect(stats.chipBreakdown[0].label).toBe("apple-m3-pro");
    expect(stats.magicFormatAdoptionPct).toBe(60);
    expect(stats.crashProxyRatePct).toBeCloseTo(20, 5); // 1 - 16/20
    expect(stats.latency.find((l) => l.stage === "end_to_end")?.p50).toBe(200);
    expect(stats.errorsByType[0].label).toBe("transcription");
  });

  test("handles empty data without dividing by zero", async () => {
    const empty: AeRunner = async () => [];
    const emptyD1: D1Runner = async () => [];
    const stats = await buildStats(empty, emptyD1, { rangeDays: 7, nowMs: 1_700_000_000_000 });
    expect(stats.magicFormatAdoptionPct).toBe(0);
    expect(stats.crashProxyRatePct).toBe(0);
    expect(stats.totalInstalls).toBe(0);
  });
});
