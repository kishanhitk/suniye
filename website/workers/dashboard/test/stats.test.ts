import { describe, expect, test } from "bun:test";
import {
  blockedDim, blockedDimD1, buildStats, safeLabel, safeNum, sql, whereFiltersAE, whereFiltersD1,
  type AeRunner, type D1Runner,
} from "../src/worker/stats";
import type { Filters } from "../src/worker/types";

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

  test("LLM latency is scoped to polished dictations so non-polished zeros don't bias it", () => {
    const q = sql.llmLatency("ds", 0);
    expect(q).toContain("quantileWeighted(0.5, double7, _sample_interval)");
    expect(q).toContain("double16 = 1"); // was_llm_polished only
    expect(q).toContain("double7 > 0");
    // e2e/asr live in their own query and must not be filtered by polishing.
    expect(sql.latency("ds", 0)).not.toContain("double16");
  });

  test("each latency stage is filtered on its own column so missing stages don't bias it", () => {
    // e2e query is scoped to double5, never folding in double6/double7 zero rows.
    expect(sql.latency("ds", 0)).toContain("double5 > 0");
    expect(sql.latency("ds", 0)).not.toContain("double6");
    // ASR has its own double6 > 0 query.
    const q = sql.asrLatency("ds", 0);
    expect(q).toContain("quantileWeighted(0.5, double6, _sample_interval)");
    expect(q).toContain("double6 > 0");
  });

  test("model-load latency and evictions split on the load_ms discriminator", () => {
    expect(sql.modelLoadLatency("ds", 0)).toContain("double14 > 0"); // real loads only
    expect(sql.keepAliveEvictions("ds", 0)).toContain("double14 = 0"); // evictions carry load_ms 0
  });

  test("active installs uses COUNT(DISTINCT index1)", () => {
    expect(sql.activeInstallsPerDay("ds", 0)).toContain("COUNT(DISTINCT index1)");
  });

  test("breakdown sums the sample interval", () => {
    expect(sql.breakdown("ds", "blob5", "blob1 = 'dictation_completed'", 0)).toContain("SUM(_sample_interval)");
  });

  test("builders inject the filter fragment before GROUP BY", () => {
    const q = sql.wordsPerDay("ds", 1000, " AND blob16 = 'apple-m3-pro'");
    expect(q).toContain("double1 >= 1000 AND blob16 = 'apple-m3-pro' GROUP BY day");
  });
});

describe("filter sanitization", () => {
  test("safeLabel accepts SafeLabel-shaped values only", () => {
    expect(safeLabel("apple-m3-pro")).toBe("apple-m3-pro");
    expect(safeLabel("1.2.3")).toBe("1.2.3");
    expect(safeLabel("nemo_transducer")).toBe("nemo_transducer"); // snake_case is in the charset
    expect(safeLabel("x' OR '1'='1")).toBeNull();
    expect(safeLabel("a;DROP TABLE installs")).toBeNull();
    expect(safeLabel("two words")).toBeNull();
    expect(safeLabel("x".repeat(65))).toBeNull();
    expect(safeLabel(42)).toBeNull();
  });

  test("safeNum keeps fractional values and rejects non-finite", () => {
    expect(safeNum("36")).toBe(36);
    expect(safeNum("36.9")).toBe(36.9); // never truncate — a fractional option must still match its rows
    expect(safeNum("abc")).toBeNull();
    expect(safeNum("Infinity")).toBeNull();
  });
});

describe("whereFiltersAE (event-aware)", () => {
  test("tier-1 dims emit clauses on any event", () => {
    const w = whereFiltersAE({ version: "0.0.51", ram: "36" }, "dictation_completed");
    expect(w).toContain("AND blob3 = '0.0.51'");
    expect(w).toContain("AND double19 = 36");
  });

  test("injection payloads are dropped, not interpolated", () => {
    const w = whereFiltersAE({ chip: "x' OR '1'='1" } as Filters, "dictation_completed");
    expect(w).toBe("");
  });

  test("device dims land on their aliased slots for dictation panels", () => {
    const w = whereFiltersAE({ chip: "apple-m3-pro", os: "15.5", mac_model: "mac15-3" }, "dictation_completed");
    expect(w).toContain("AND blob16 = 'apple-m3-pro'");
    expect(w).toContain("AND blob18 = '15.5'");
    expect(w).toContain("AND blob17 = 'mac15-3'");
  });

  test("a dim whose slot is occupied on the event yields an always-false guard", () => {
    // audio_backend_used: blob14 = backend, double18 = rung
    expect(whereFiltersAE({ arch: "arm64" }, "audio_backend_used")).toBe(" AND blob1 = ''");
    expect(whereFiltersAE({ cpu_cores: "12" }, "audio_backend_used")).toBe(" AND blob1 = ''");
    // model_load: blob17 = model
    expect(whereFiltersAE({ mac_model: "mac15-3" }, "model_load")).toBe(" AND blob1 = ''");
    // error: blob14 = type
    expect(whereFiltersAE({ arch: "arm64" }, "error")).toBe(" AND blob1 = ''");
  });

  test("dictation-scoped dims only apply to dictation_completed", () => {
    expect(whereFiltersAE({ asr_model: "parakeet-v3" }, "dictation_completed")).toBe(" AND blob5 = 'parakeet-v3'");
    expect(whereFiltersAE({ asr_model: "parakeet-v3" }, "error")).toBe(" AND blob1 = ''");
    expect(whereFiltersAE({ asr_model: "parakeet-v3" }, "*")).toBe(" AND blob1 = ''");
  });

  test("the event-unscoped query only accepts star-safe dims", () => {
    expect(whereFiltersAE({ chip: "apple-m3-pro" }, "*")).toBe(" AND blob16 = 'apple-m3-pro'");
    expect(whereFiltersAE({ mac_model: "mac15-3" }, "*")).toBe(" AND blob1 = ''");
  });
});

describe("blocked-panel detection", () => {
  test("reports the first dim a panel's event cannot honor", () => {
    expect(blockedDim({ asr_model: "parakeet-v3" }, "app_launch")).toBe("asr_model");
    expect(blockedDim({ arch: "arm64" }, "error")).toBe("arch");
    expect(blockedDim({ mac_model: "mac15-3" }, "model_load")).toBe("mac_model");
    expect(blockedDim({ chip: "apple-m3-pro" }, "dictation_completed")).toBeNull();
    expect(blockedDimD1({ asr_model: "parakeet-v3" })).toBe("asr_model");
    expect(blockedDimD1({ chip: "apple-m3-pro" })).toBeNull();
    // Invalid values are dropped before the check — they never block.
    expect(blockedDim({ asr_model: "bad value!!" }, "app_launch")).toBeNull();
  });
});

describe("whereFiltersD1", () => {
  test("emits bind params, never interpolation", () => {
    const { sql: w, binds } = whereFiltersD1({ chip: "apple-m3-pro", ram: "36" });
    expect(w).toBe(" AND chip = ? AND ram_gb = ?");
    expect(binds).toEqual(["apple-m3-pro", 36]);
  });

  test("dims not in the install registry blank install cards honestly", () => {
    const { sql: w, binds } = whereFiltersD1({ asr_model: "parakeet-v3" });
    expect(w).toBe(" AND 1 = 0");
    expect(binds).toEqual([]);
  });
});

describe("buildStats", () => {
  const aeQueries: string[] = [];
  const ae: AeRunner = async (q) => {
    aeQueries.push(q);
    if (q.includes("SUM(double2")) return [{ day: "2026-07-06 00:00:00", value: 100 }, { day: "2026-07-07 00:00:00", value: 150 }];
    if (q.includes("COUNT(DISTINCT index1)")) return [{ day: "2026-07-06 00:00:00", value: 5 }];
    if (q.includes("blob5 AS label")) return [{ label: "parakeet-v3", value: 42 }];
    if (q.includes("blob7 AS label")) return [{ label: "english", value: 42 }];
    if (q.includes("blob11 AS label")) return [{ label: "editor", value: 12 }];
    if (q.includes("blob10 AS label")) return [{ label: "timeout", value: 2 }];
    if (q.includes("blob14 AS label") && q.includes("'audio_backend_used'")) return [{ label: "core_audio", value: 40 }];
    if (q.includes("blob14 AS label") && q.includes("'error'")) return [{ label: "transcription", value: 3 }];
    if (q.includes("AS polished")) return [{ polished: 30, total: 50 }];
    if (q.includes("AS fell_back")) return [{ fell_back: 2, total: 40 }];
    if (q.includes("AS median")) return [{ median: 10 }];
    if (q.includes("llm_p50")) return [{ llm_p50: 100, llm_p95: 250 }]; // separate polished-only query
    if (q.includes("asr_p50")) return [{ asr_p50: 150, asr_p95: 300 }]; // separate double6>0 query
    if (q.includes("e2e_p50")) return [{ e2e_p50: 200, e2e_p95: 500 }];
    if (q.includes("double14, _sample_interval) AS p50")) return [{ p50: 800, p95: 1900 }];
    if (q.includes("double14 = 0")) return [{ value: 3 }];
    if (q.includes("'app_launch'")) return [{ value: 20 }];
    if (q.includes("'session_end'")) return [{ value: 16 }];
    if (q.includes("'dictation_completed'") && q.includes("SUM(_sample_interval) AS value")) return [{ value: 50 }];
    if (q.includes("'dictation_edited'") && q.includes("double20 > 0") && q.includes("SUM(_sample_interval) AS value")) return [{ value: 10 }]; // edited
    if (q.includes("'dictation_edited'") && q.includes("SUM(_sample_interval) AS value")) return [{ value: 40 }]; // finalized total
    return [];
  };

  const d1Binds: unknown[][] = [];
  const d1: D1Runner = async (q, binds) => {
    d1Binds.push(binds);
    if (q.includes("COUNT(*) AS n")) return [{ n: 12 }];
    if (q.includes("first_seen AS day")) return [{ day: "2026-07-01", value: 2 }];
    if (q.includes("chip AS label")) return [{ label: "apple-m3-pro", value: 8 }];
    if (q.includes("ram_gb AS label")) return [{ label: 36, value: 5 }];
    if (q.includes("country AS label")) return [{ label: "US", value: 9 }];
    if (q.includes("DISTINCT app_version")) return [{ v: "0.0.51" }];
    if (q.includes("DISTINCT chip")) return [{ v: "apple-m3-pro" }, { v: "apple-m5" }];
    if (q.includes("DISTINCT ram_gb")) return [{ v: 24 }, { v: 36 }];
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
    expect(stats.latency.find((l) => l.stage === "magic_format")?.p50).toBe(100);
    expect(stats.latency.find((l) => l.stage === "model_load")?.p50).toBe(800);
    expect(stats.errorsByType[0].label).toBe("transcription");
    // New signals
    expect(stats.audioBackends[0].label).toBe("core_audio");
    expect(stats.audioFallbackRatePct).toBeCloseTo(5, 5); // 2/40
    expect(stats.editRateMedianPct).toBe(10);
    expect(stats.editedSharePct).toBeCloseTo(25, 5); // 10 edited / 40 finalized — bounded, from one stream
    expect(stats.keepAliveEvictions).toBe(3);
    expect(stats.segmentEventCount).toBe(50);
    expect(stats.filterOptions.chip).toEqual(["apple-m3-pro", "apple-m5"]);
    expect(stats.filterOptions.asr_model).toEqual(["parakeet-v3"]);
  });

  test("threads sanitized filters into AE queries and D1 binds, and echoes them", async () => {
    aeQueries.length = 0;
    d1Binds.length = 0;
    const stats = await buildStats(ae, d1, {
      rangeDays: 30, nowMs: 1_700_000_000_000,
      filters: { chip: "apple-m3-pro", version: "0.0.51", asr_model: "bad value!!" },
    });

    expect(stats.appliedFilters).toEqual({ chip: "apple-m3-pro", version: "0.0.51" }); // invalid dropped
    expect(stats.blocked).toEqual({}); // chip/version apply everywhere
    const words = aeQueries.find((q) => q.includes("SUM(double2"))!;
    expect(words).toContain("AND blob16 = 'apple-m3-pro'");
    expect(words).toContain("AND blob3 = '0.0.51'");
    expect(words).not.toContain("bad value");
    // model_load queries keep chip (blob16 free there) but the fragment differs per event
    const evict = aeQueries.find((q) => q.includes("double14 = 0"))!;
    expect(evict).toContain("AND blob16 = 'apple-m3-pro'");
    // D1 breakdowns received the filter as binds
    expect(d1Binds.some((b) => b.includes("apple-m3-pro") && b.includes("0.0.51"))).toBe(true);
  });

  test("dictation-only filters mark every non-dictation panel as blocked", async () => {
    const stats = await buildStats(ae, d1, {
      rangeDays: 30, nowMs: 1_700_000_000_000, filters: { asr_model: "parakeet-v3" },
    });
    // A blocked query returns zero rows; the response must say WHY so the FE
    // never renders a fake "100% crash-free" or "0 installs".
    expect(stats.blocked.crash).toBe("asr_model");
    expect(stats.blocked.edits).toBe("asr_model");
    expect(stats.blocked.installs).toBe("asr_model");
    expect(stats.blocked.activeInstalls).toBe("asr_model");
    expect(stats.blocked.audio).toBe("asr_model");
    expect(stats.blocked.errors).toBe("asr_model");
    expect(stats.blocked.modelLoad).toBe("asr_model");
    // Dictation panels themselves stay live.
    expect(stats.segmentEventCount).toBe(50);
  });

  test("option lists are range-scoped but never filter-scoped", async () => {
    aeQueries.length = 0;
    await buildStats(ae, d1, {
      rangeDays: 30, nowMs: 1_700_000_000_000, filters: { chip: "apple-m3-pro" },
    });
    // The asr_model options query (blob5 breakdown) must NOT carry the chip filter.
    const optionQueries = aeQueries.filter((q) => q.includes("blob5 AS label"));
    expect(optionQueries.some((q) => !q.includes("apple-m3-pro"))).toBe(true);
  });

  test("handles empty data without dividing by zero", async () => {
    const empty: AeRunner = async () => [];
    const emptyD1: D1Runner = async () => [];
    const stats = await buildStats(empty, emptyD1, { rangeDays: 7, nowMs: 1_700_000_000_000 });
    expect(stats.magicFormatAdoptionPct).toBe(0);
    expect(stats.crashProxyRatePct).toBe(0);
    expect(stats.totalInstalls).toBe(0);
    expect(stats.audioFallbackRatePct).toBe(0);
    expect(stats.editedSharePct).toBe(0);
  });
});
