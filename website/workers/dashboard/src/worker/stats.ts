// Dashboard stats: builds sampling-correct Analytics Engine SQL and merges with
// the D1 install registry. Pure and injectable — the AE runner and D1 runner are
// passed in, so this is fully unit-testable without hitting Cloudflare.
//
// Column mapping mirrors the ingest field->slot registry (workers/ingest):
//   blob1 = event name, blob5 = asr_model, blob14 = reason/type, blob15 = code,
//   blob19 = country;  double1 = event_ts (ms), double2 = word_count,
//   double5 = lat_end_to_end, double6 = lat_asr_processing, double7 = lat_llm_total,
//   double16 = was_llm_polished, double17 = clean_exit (session_end).
//
// CRITICAL: time is bucketed on the client event_ts (double1), NEVER on the AE
// ingestion `timestamp`, so offline-queued events land on the day they happened.
// Counts use SUM(_sample_interval); a raw COUNT would undercount at scale.

import type { Breakdown, LatencySummary, StatsResponse, TimePoint } from "./types";

const DAY_MS = 86_400_000;

export type AeRunner = (sql: string) => Promise<Array<Record<string, unknown>>>;
export type D1Runner = (sql: string, binds: unknown[]) => Promise<Array<Record<string, unknown>>>;

// ---- AE SQL builders (exported for tests) ----
// NB: the AE SQL API takes raw SQL (no bind params). Every interpolated value
// here is a server-computed number or a hardcoded literal — never request data.

export const sql = {
  wordsPerDay: (ds: string, cutoffMs: number) =>
    `SELECT intDiv(toUInt64(double1), ${DAY_MS}) AS day_ms, SUM(double2 * _sample_interval) AS value ` +
    `FROM ${ds} WHERE blob1 = 'dictation_completed' AND double1 >= ${cutoffMs} GROUP BY day_ms ORDER BY day_ms`,

  activeInstallsPerDay: (ds: string, cutoffMs: number) =>
    `SELECT intDiv(toUInt64(double1), ${DAY_MS}) AS day_ms, COUNT(DISTINCT index1) AS value ` +
    `FROM ${ds} WHERE double1 >= ${cutoffMs} GROUP BY day_ms ORDER BY day_ms`,

  breakdown: (ds: string, col: string, whereEvent: string, cutoffMs: number) =>
    `SELECT ${col} AS label, SUM(_sample_interval) AS value FROM ${ds} ` +
    `WHERE ${whereEvent} AND double1 >= ${cutoffMs} GROUP BY label ORDER BY value DESC LIMIT 20`,

  magicFormatAdoption: (ds: string, cutoffMs: number) =>
    `SELECT SUM(double16 * _sample_interval) AS polished, SUM(_sample_interval) AS total ` +
    `FROM ${ds} WHERE blob1 = 'dictation_completed' AND double1 >= ${cutoffMs}`,

  latency: (ds: string, cutoffMs: number) =>
    `SELECT ` +
    `quantile(0.5)(double5) AS e2e_p50, quantile(0.95)(double5) AS e2e_p95, ` +
    `quantile(0.5)(double6) AS asr_p50, quantile(0.95)(double6) AS asr_p95, ` +
    `quantile(0.5)(double7) AS llm_p50, quantile(0.95)(double7) AS llm_p95 ` +
    `FROM ${ds} WHERE blob1 = 'dictation_completed' AND double5 > 0 AND double1 >= ${cutoffMs}`,

  eventCount: (ds: string, event: string, cutoffMs: number) =>
    `SELECT SUM(_sample_interval) AS value FROM ${ds} WHERE blob1 = '${event}' AND double1 >= ${cutoffMs}`,
};

// ---- helpers ----

function num(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : 0;
}

function dayMsToDate(dayMs: unknown): string {
  return new Date(num(dayMs) * DAY_MS).toISOString().slice(0, 10);
}

function toTimePoints(rows: Array<Record<string, unknown>>): TimePoint[] {
  return rows.map((r) => ({ day: dayMsToDate(r.day_ms), value: num(r.value) }));
}

function toBreakdown(rows: Array<Record<string, unknown>>): Breakdown[] {
  return rows.map((r) => ({ label: String(r.label ?? "unknown") || "unknown", value: num(r.value) }));
}

// ---- main ----

export async function buildStats(
  ae: AeRunner,
  d1: D1Runner,
  opts: { rangeDays: number; nowMs: number; datasetName?: string }
): Promise<StatsResponse> {
  const ds = opts.datasetName ?? "suniye_events";
  const cutoffMs = opts.nowMs - opts.rangeDays * DAY_MS;
  const cutoffDay = new Date(cutoffMs).toISOString().slice(0, 10);

  const [
    wordsRows, activeRows, asrRows, mfRows, latRows, fallbackRows, errorRows,
    launchRows, sessionEndRows,
  ] = await Promise.all([
    ae(sql.wordsPerDay(ds, cutoffMs)),
    ae(sql.activeInstallsPerDay(ds, cutoffMs)),
    ae(sql.breakdown(ds, "blob5", "blob1 = 'dictation_completed'", cutoffMs)),
    ae(sql.magicFormatAdoption(ds, cutoffMs)),
    ae(sql.latency(ds, cutoffMs)),
    ae(sql.breakdown(ds, "blob10", "blob1 = 'dictation_completed'", cutoffMs)),
    ae(sql.breakdown(ds, "blob14", "blob1 = 'error'", cutoffMs)),
    ae(sql.eventCount(ds, "app_launch", cutoffMs)),
    ae(sql.eventCount(ds, "session_end", cutoffMs)),
  ]);

  // totalInstalls is all-time by definition; the breakdowns honor the selected
  // range (installs active in the window) so the range toggle affects every card.
  const [totalRow, newRows, chipRows, ramRows, countryRows] = await Promise.all([
    d1("SELECT COUNT(*) AS n FROM installs", []),
    d1("SELECT first_seen AS day, COUNT(*) AS value FROM installs WHERE first_seen >= ? GROUP BY first_seen ORDER BY first_seen", [cutoffDay]),
    d1("SELECT chip AS label, COUNT(*) AS value FROM installs WHERE last_seen >= ? GROUP BY chip ORDER BY value DESC LIMIT 20", [cutoffDay]),
    d1("SELECT ram_gb AS label, COUNT(*) AS value FROM installs WHERE last_seen >= ? GROUP BY ram_gb ORDER BY value DESC LIMIT 20", [cutoffDay]),
    d1("SELECT country AS label, COUNT(*) AS value FROM installs WHERE last_seen >= ? GROUP BY country ORDER BY value DESC LIMIT 20", [cutoffDay]),
  ]);

  const mf = mfRows[0] ?? {};
  const mfTotal = num(mf.total);
  const magicFormatAdoptionPct = mfTotal > 0 ? (num(mf.polished) / mfTotal) * 100 : 0;

  const lat = latRows[0] ?? {};
  const latency: LatencySummary[] = [
    { stage: "end_to_end", p50: num(lat.e2e_p50), p95: num(lat.e2e_p95) },
    { stage: "asr", p50: num(lat.asr_p50), p95: num(lat.asr_p95) },
    { stage: "magic_format", p50: num(lat.llm_p50), p95: num(lat.llm_p95) },
  ];

  const launches = num(launchRows[0]?.value);
  const sessionEnds = num(sessionEndRows[0]?.value);
  const crashProxyRatePct = launches > 0 ? Math.max(0, (1 - sessionEnds / launches) * 100) : 0;

  return {
    rangeDays: opts.rangeDays,
    wordsPerDay: toTimePoints(wordsRows),
    activeInstallsPerDay: toTimePoints(activeRows),
    newInstallsPerDay: newRows.map((r) => ({ day: String(r.day), value: num(r.value) })),
    totalInstalls: num(totalRow[0]?.n),
    asrModelBreakdown: toBreakdown(asrRows),
    chipBreakdown: toBreakdown(chipRows),
    ramBreakdown: toBreakdown(ramRows),
    countryBreakdown: toBreakdown(countryRows),
    magicFormatAdoptionPct,
    fallbackReasons: toBreakdown(fallbackRows),
    latency,
    errorsByType: toBreakdown(errorRows),
    crashProxyRatePct,
  };
}

/** Real AE SQL API runner (POSTs raw SQL, returns the `data` array). */
export function makeAeRunner(accountId: string, token: string, fetcher: typeof fetch = fetch): AeRunner {
  const url = `https://api.cloudflare.com/client/v4/accounts/${accountId}/analytics_engine/sql`;
  return async (query: string) => {
    const res = await fetcher(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      body: query,
    });
    if (!res.ok) throw new Error(`AE SQL ${res.status}`);
    const json = (await res.json()) as { data?: Array<Record<string, unknown>> };
    return json.data ?? [];
  };
}
