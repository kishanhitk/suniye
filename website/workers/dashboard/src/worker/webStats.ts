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
  ctaClicks: number;
  topCtas: Breakdown[];
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
  const ev = (name: string) => `blob1 = '${name}' AND double1 >= ${cutoff}`;

  // Each query is isolated: one failing (bad SQL, empty dataset) degrades
  // that one panel to empty instead of rejecting the whole response —
  // mirrors stats.ts's safeAe.
  const safeAe: AeRunner = async (sql: string) => {
    try { return await ae(sql); } catch (e) { console.error("web ae query failed:", String(e).slice(0, 300)); return []; }
  };
  const q = (sql: string) => safeAe(sql);

  const [
    visitorsRows, pageviewRows, downloadRows,
    seriesRows, sourcesRows, pagesRows, targetRows, scrollRows, countryRows, deviceRows, campaignRows,
    ctaClickRows, topCtaRows,
  ] = await Promise.all([
    q(`SELECT COUNT(DISTINCT index1) AS value FROM ${ds} WHERE ${ev("pageview")}`),
    q(`SELECT SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")}`),
    q(`SELECT SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("download_click")}`),
    q(`SELECT toStartOfInterval(toDateTime(double1 / 1000), INTERVAL '1' DAY) AS day, COUNT(DISTINCT index1) AS value FROM ${ds} WHERE ${ev("pageview")} GROUP BY day ORDER BY day`),
    q(`SELECT blob3 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")} AND blob3 != '' GROUP BY label ORDER BY value DESC LIMIT 20`),
    q(`SELECT blob2 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")} GROUP BY label ORDER BY value DESC LIMIT 20`),
    q(`SELECT blob9 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("download_click")} GROUP BY label ORDER BY value DESC LIMIT 10`),
    // toString(double2) keeps the label human-readable ("25", "50", …) but the
    // ORDER BY must use the numeric column — sorting the string label would
    // put "100" before "25" (lexical, not numeric).
    q(`SELECT toString(double2) AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("scroll_depth")} GROUP BY label, double2 ORDER BY double2`),
    q(`SELECT blob7 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")} AND blob7 != '' GROUP BY label ORDER BY value DESC LIMIT 20`),
    q(`SELECT blob8 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")} AND blob8 != '' GROUP BY label ORDER BY value DESC`),
    q(`SELECT blob6 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("pageview")} AND blob6 != '' GROUP BY label ORDER BY value DESC LIMIT 20`),
    q(`SELECT SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("cta_click")}`),
    q(`SELECT blob9 AS label, SUM(_sample_interval) AS value FROM ${ds} WHERE ${ev("cta_click")} GROUP BY label ORDER BY value DESC LIMIT 10`),
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
    ctaClicks: num(ctaClickRows),
    topCtas: breakdown(topCtaRows),
  };
}
