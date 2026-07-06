// Dashboard stats: builds sampling-correct Analytics Engine SQL and merges with
// the D1 install registry. Pure and injectable — the AE runner and D1 runner are
// passed in, so this is fully unit-testable without hitting Cloudflare.
//
// Column mapping mirrors the ingest field->slot registry (workers/ingest):
//   blob1 = event name, blob3 = app_version, blob4 = channel, blob5 = asr_model,
//   blob7 = language, blob10 = cleanup_fallback_reason, blob11 = target_category,
//   blob14 = reason/type/backend (+device arch), blob16 = kind/feature (+chip),
//   blob17 = model (+mac_model), blob18 = from/to_version (+os_version),
//   blob19 = country;  double1 = event_ts (ms), double2 = word_count,
//   double5 = lat_end_to_end, double6 = lat_asr_processing, double7 = lat_llm_total,
//   double14 = load_ms, double16 = was_llm_polished, double17 = bools (shared),
//   double18 = rung (+cpu_cores), double19 = ram_gb, double20 = edit_rate_bucket.
//
// CRITICAL: time is bucketed on the client event_ts (double1), NEVER on the AE
// ingestion `timestamp`, so offline-queued events land on the day they happened.
// Counts use SUM(_sample_interval); a raw COUNT would undercount at scale.
//
// SECURITY: the AE SQL API takes RAW SQL (no bind params). Every interpolated
// value is either a server-computed number or a `safeLabel`-sanitized string
// (SafeLabel charset [A-Za-z0-9._-]{1,64} — cannot contain quotes, whitespace,
// or comment/statement characters, so it cannot escape a quoted literal).
// D1 queries use bind params throughout.

import type { BlockedPanels, Breakdown, FilterDim, Filters, LatencySummary, StatsResponse, TimePoint } from "./types";

const DAY_MS = 86_400_000;

export type AeRunner = (sql: string) => Promise<Array<Record<string, unknown>>>;
export type D1Runner = (sql: string, binds: unknown[]) => Promise<Array<Record<string, unknown>>>;

// ---- filter sanitization + event-aware WHERE fragments ----

const LABEL_RE = /^[A-Za-z0-9._-]{1,64}$/;

/** Accepts only SafeLabel-shaped values; anything else is rejected (null). */
export function safeLabel(value: unknown): string | null {
  return typeof value === "string" && LABEL_RE.test(value) ? value : null;
}

/**
 * Any finite number is interpolation-safe (String(n) is digits/./-/e+), and we
 * must NOT round: a fractional option value (D1 DISTINCT can offer one) would
 * silently match zero rows if truncated.
 */
export function safeNum(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * Where each filter dimension lives, and where it does NOT apply:
 * - `unavailableOn`: events whose native field occupies the shared slot — the
 *   device dim only survives in blob20 JSON there, so it can't be filtered.
 * - `dictationOnly`: the dim is a dictation_completed prop; it has no meaning on
 *   any other event.
 * - `star`: safe on the event-unscoped active-installs query (its slot is either
 *   dedicated or only occupied on rare non-queried events).
 */
const DIM_SPECS: Record<FilterDim, {
  ae: string;
  numeric?: boolean;
  d1?: string;
  unavailableOn?: string[];
  dictationOnly?: boolean;
  star?: boolean;
}> = {
  version:   { ae: "blob3",  d1: "app_version", star: true },
  channel:   { ae: "blob4",  d1: "channel", star: true },
  country:   { ae: "blob19", d1: "country", star: true },
  ram:       { ae: "double19", numeric: true, d1: "ram_gb", star: true },
  chip:      { ae: "blob16", d1: "chip", star: true,
               unavailableOn: ["permission_transition", "model_changed", "model_download", "feature_toggled", "update_action"] },
  os:        { ae: "blob18", d1: "os_version", star: true, unavailableOn: ["update_action"] },
  mac_model: { ae: "blob17", d1: "mac_model", unavailableOn: ["model_load", "model_changed", "model_download"] },
  arch:      { ae: "blob14", // not in D1 (installs has no arch column)
               unavailableOn: ["error", "audio_backend_used", "dictation_blocked", "dictation_cancelled", "onboarding_step", "audio_capture_interrupted"] },
  cpu_cores: { ae: "double18", numeric: true, d1: "cpu_cores", unavailableOn: ["audio_backend_used"] },
  asr_model: { ae: "blob5",  dictationOnly: true },
  language:  { ae: "blob7",  dictationOnly: true },
  target:    { ae: "blob11", dictationOnly: true },
};

/**
 * Always-false AE guard: blob1 (the event name) is never empty, so this returns
 * zero rows. Used when a selected dim isn't recorded for the queried event —
 * an honest empty beats silently-unfiltered data.
 */
const AE_NEVER = " AND blob1 = ''";

/**
 * The active filters that survive sanitization, with their specs. Invalid
 * values are dropped entirely (a stale or malformed option must not blank the
 * dashboard). Single source for the where-builders and blocked-panel checks.
 */
function sanitizedEntries(
  filters: Filters | undefined
): Array<[FilterDim, (typeof DIM_SPECS)[FilterDim], string | number]> {
  if (!filters) return [];
  const out: Array<[FilterDim, (typeof DIM_SPECS)[FilterDim], string | number]> = [];
  for (const [dim, raw] of Object.entries(filters) as Array<[FilterDim, string]>) {
    const spec = DIM_SPECS[dim];
    if (!spec || raw === undefined || raw === "") continue;
    const value = spec.numeric ? safeNum(raw) : safeLabel(raw);
    if (value !== null) out.push([dim, spec, value]);
  }
  return out;
}

/**
 * First active dim that can't apply to `event` ("*" = the event-unscoped
 * active-installs query). The dashboard surfaces this as an explicit
 * "not recorded under {dim}" state instead of a fake zero.
 */
export function blockedDim(filters: Filters | undefined, event: string): FilterDim | null {
  for (const [dim, spec] of sanitizedEntries(filters)) {
    const unavailable =
      (spec.dictationOnly && event !== "dictation_completed") ||
      (event === "*" ? !spec.star : (spec.unavailableOn?.includes(event) ?? false));
    if (unavailable) return dim;
  }
  return null;
}

/** Same, for the D1 install registry (dims that aren't columns there). */
export function blockedDimD1(filters: Filters | undefined): FilterDim | null {
  for (const [dim, spec] of sanitizedEntries(filters)) {
    if (!spec.d1) return dim;
  }
  return null;
}

/**
 * Builds the `AND …` fragment for one AE query, scoped to `event`. A dim that
 * can't apply to this event yields AE_NEVER (honest zero rows, reported to the
 * FE via the response's `blocked` map).
 */
export function whereFiltersAE(filters: Filters | undefined, event: string): string {
  if (blockedDim(filters, event)) return AE_NEVER;
  let out = "";
  for (const [, spec, value] of sanitizedEntries(filters)) {
    out += spec.numeric ? ` AND ${spec.ae} = ${value}` : ` AND ${spec.ae} = '${value}'`;
  }
  return out;
}

/** D1 (installs) filter fragment — bind params, never interpolation. */
export function whereFiltersD1(filters: Filters | undefined): { sql: string; binds: unknown[] } {
  if (blockedDimD1(filters)) return { sql: " AND 1 = 0", binds: [] };
  let sql = "";
  const binds: unknown[] = [];
  for (const [, spec, value] of sanitizedEntries(filters)) {
    sql += ` AND ${spec.d1} = ?`;
    binds.push(value);
  }
  return { sql, binds };
}

/** Sanitized copy of the incoming filters (what the response echoes back). */
export function sanitizeFilters(filters: Filters | undefined): Filters {
  const out: Filters = {};
  for (const [dim, , value] of sanitizedEntries(filters)) {
    out[dim] = String(value);
  }
  return out;
}

// ---- AE SQL builders (exported for tests) ----
// Every builder takes an optional pre-built `where` fragment (leading " AND …")
// from whereFiltersAE, scoped to the same event the query filters on.

export const sql = {
  wordsPerDay: (ds: string, cutoffMs: number, where = "") =>
    `SELECT toStartOfInterval(toDateTime(double1 / 1000), INTERVAL '1' DAY) AS day, SUM(double2 * _sample_interval) AS value ` +
    `FROM ${ds} WHERE blob1 = 'dictation_completed' AND double1 >= ${cutoffMs}${where} GROUP BY day ORDER BY day`,

  // COUNT(DISTINCT) is exact only at the default sample_rate = 1. Under sampling
  // it counts distinct installs among sampled rows and undercounts the true
  // population — unlike SUM counts, it can't be corrected via _sample_interval.
  // Event-unscoped ("*"): only star-safe dims may filter it.
  activeInstallsPerDay: (ds: string, cutoffMs: number, where = "") =>
    `SELECT toStartOfInterval(toDateTime(double1 / 1000), INTERVAL '1' DAY) AS day, COUNT(DISTINCT index1) AS value ` +
    `FROM ${ds} WHERE double1 >= ${cutoffMs}${where} GROUP BY day ORDER BY day`,

  breakdown: (ds: string, col: string, whereEvent: string, cutoffMs: number, where = "") =>
    `SELECT ${col} AS label, SUM(_sample_interval) AS value FROM ${ds} ` +
    `WHERE ${whereEvent} AND double1 >= ${cutoffMs}${where} GROUP BY label ORDER BY value DESC LIMIT 20`,

  magicFormatAdoption: (ds: string, cutoffMs: number, where = "") =>
    `SELECT SUM(double16 * _sample_interval) AS polished, SUM(_sample_interval) AS total ` +
    `FROM ${ds} WHERE blob1 = 'dictation_completed' AND double1 >= ${cutoffMs}${where}`,

  // Each latency stage is scoped to its own `> 0` filter. The latency fields are
  // optional and buildDataPoint leaves missing doubles as 0, so a shared filter
  // would fold zero rows into whichever stage happens to be absent, biasing its
  // quantile toward zero.
  latency: (ds: string, cutoffMs: number, where = "") =>
    `SELECT quantileWeighted(0.5, double5, _sample_interval) AS e2e_p50, quantileWeighted(0.95, double5, _sample_interval) AS e2e_p95 ` +
    `FROM ${ds} WHERE blob1 = 'dictation_completed' AND double5 > 0 AND double1 >= ${cutoffMs}${where}`,

  asrLatency: (ds: string, cutoffMs: number, where = "") =>
    `SELECT quantileWeighted(0.5, double6, _sample_interval) AS asr_p50, quantileWeighted(0.95, double6, _sample_interval) AS asr_p95 ` +
    `FROM ${ds} WHERE blob1 = 'dictation_completed' AND double6 > 0 AND double1 >= ${cutoffMs}${where}`,

  // LLM latency is measured only on polished dictations. Filtering on
  // was_llm_polished (double16) + double7 > 0 keeps non-polished zero rows out of
  // the quantile — otherwise p50/p95 are dragged toward zero whenever a large
  // share of dictations skip Magic Format.
  llmLatency: (ds: string, cutoffMs: number, where = "") =>
    `SELECT quantileWeighted(0.5, double7, _sample_interval) AS llm_p50, quantileWeighted(0.95, double7, _sample_interval) AS llm_p95 ` +
    `FROM ${ds} WHERE blob1 = 'dictation_completed' AND double16 = 1 AND double7 > 0 AND double1 >= ${cutoffMs}${where}`,

  eventCount: (ds: string, event: string, cutoffMs: number, where = "") =>
    `SELECT SUM(_sample_interval) AS value FROM ${ds} WHERE blob1 = '${event}' AND double1 >= ${cutoffMs}${where}`,

  // Audio backend the capture ladder settled on (blob14 for audio_backend_used),
  // plus the share of captures that fell back to a lower rung (double17 =
  // fallback_occurred). Rate is sampling-correct (weighted numerator/denominator).
  audioBackends: (ds: string, cutoffMs: number, where = "") =>
    `SELECT blob14 AS label, SUM(_sample_interval) AS value FROM ${ds} ` +
    `WHERE blob1 = 'audio_backend_used' AND double1 >= ${cutoffMs}${where} GROUP BY label ORDER BY value DESC LIMIT 20`,

  audioFallbackRate: (ds: string, cutoffMs: number, where = "") =>
    `SELECT SUM(double17 * _sample_interval) AS fell_back, SUM(_sample_interval) AS total ` +
    `FROM ${ds} WHERE blob1 = 'audio_backend_used' AND double1 >= ${cutoffMs}${where}`,

  // Post-insertion edit rate (double20, a coarse % bucket) — an ASR/cleanup
  // accuracy proxy. Median over dictations the user actually edited.
  editRate: (ds: string, cutoffMs: number, where = "") =>
    `SELECT quantileWeighted(0.5, double20, _sample_interval) AS median ` +
    `FROM ${ds} WHERE blob1 = 'dictation_edited' AND double20 > 0 AND double1 >= ${cutoffMs}${where}`,

  // Cold model-load latency (double14 = load_ms). Keep-alive evictions are also
  // emitted as model_load but with load_ms 0 (evicted_by_keepalive rides only the
  // blob20 props JSON, so double14 > 0 is the discriminator for a real load).
  modelLoadLatency: (ds: string, cutoffMs: number, where = "") =>
    `SELECT quantileWeighted(0.5, double14, _sample_interval) AS p50, quantileWeighted(0.95, double14, _sample_interval) AS p95 ` +
    `FROM ${ds} WHERE blob1 = 'model_load' AND double14 > 0 AND double1 >= ${cutoffMs}${where}`,

  keepAliveEvictions: (ds: string, cutoffMs: number, where = "") =>
    `SELECT SUM(_sample_interval) AS value FROM ${ds} ` +
    `WHERE blob1 = 'model_load' AND double14 = 0 AND double1 >= ${cutoffMs}${where}`,
};

// ---- helpers ----

function num(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : 0;
}

function toTimePoints(rows: Array<Record<string, unknown>>): TimePoint[] {
  // `day` comes back as a datetime string (e.g. "2026-07-06 00:00:00").
  return rows.map((r) => ({ day: String(r.day ?? "").slice(0, 10), value: num(r.value) }));
}

function toBreakdown(rows: Array<Record<string, unknown>>): Breakdown[] {
  return rows.map((r) => ({ label: String(r.label ?? "unknown") || "unknown", value: num(r.value) }));
}

/** Await a record of promises into a record of results — named, not positional. */
async function allOf<T extends Record<string, Promise<unknown>>>(
  promises: T
): Promise<{ [K in keyof T]: Awaited<T[K]> }> {
  const entries = Object.entries(promises);
  const values = await Promise.all(entries.map(([, p]) => p));
  return Object.fromEntries(entries.map(([key], i) => [key, values[i]])) as { [K in keyof T]: Awaited<T[K]> };
}

// ---- main ----

export async function buildStats(
  ae: AeRunner,
  d1: D1Runner,
  opts: { rangeDays: number; nowMs: number; datasetName?: string; filters?: Filters }
): Promise<StatsResponse> {
  const ds = opts.datasetName ?? "suniye_events";
  const cutoffMs = opts.nowMs - opts.rangeDays * DAY_MS;
  const cutoffDay = new Date(cutoffMs).toISOString().slice(0, 10);
  const filters = opts.filters;

  // Per-event filter fragments (a dim unavailable on an event yields an honest
  // always-false guard for that event's queries — never unfiltered data).
  const w = (event: string) => whereFiltersAE(filters, event);
  const d1Filter = whereFiltersD1(filters);

  // Each query is isolated: one failing (bad SQL, empty dataset) degrades that
  // one card to empty rather than blanking the whole dashboard, and logs why.
  const safeAe: AeRunner = async (q) => {
    try { return await ae(q); } catch (e) { console.error("ae query failed:", String(e).slice(0, 300)); return []; }
  };
  const safeD1: D1Runner = async (q, b) => {
    try { return await d1(q, b); } catch (e) { console.error("d1 query failed:", String(e).slice(0, 300)); return []; }
  };

  // One parallel wave — every query is independent; serial waves would triple
  // the dashboard's load latency. Named results, not positional destructuring.
  const [aeRows, d1Rows, filterOptions] = await Promise.all([
    allOf({
      words: safeAe(sql.wordsPerDay(ds, cutoffMs, w("dictation_completed"))),
      active: safeAe(sql.activeInstallsPerDay(ds, cutoffMs, w("*"))),
      asrModels: safeAe(sql.breakdown(ds, "blob5", "blob1 = 'dictation_completed'", cutoffMs, w("dictation_completed"))),
      mf: safeAe(sql.magicFormatAdoption(ds, cutoffMs, w("dictation_completed"))),
      lat: safeAe(sql.latency(ds, cutoffMs, w("dictation_completed"))),
      asrLat: safeAe(sql.asrLatency(ds, cutoffMs, w("dictation_completed"))),
      llmLat: safeAe(sql.llmLatency(ds, cutoffMs, w("dictation_completed"))),
      fallbacks: safeAe(sql.breakdown(ds, "blob10", "blob1 = 'dictation_completed'", cutoffMs, w("dictation_completed"))),
      errors: safeAe(sql.breakdown(ds, "blob14", "blob1 = 'error'", cutoffMs, w("error"))),
      launches: safeAe(sql.eventCount(ds, "app_launch", cutoffMs, w("app_launch"))),
      sessionEnds: safeAe(sql.eventCount(ds, "session_end", cutoffMs, w("session_end"))),
      audio: safeAe(sql.audioBackends(ds, cutoffMs, w("audio_backend_used"))),
      audioRate: safeAe(sql.audioFallbackRate(ds, cutoffMs, w("audio_backend_used"))),
      editRate: safeAe(sql.editRate(ds, cutoffMs, w("dictation_edited"))),
      modelLoad: safeAe(sql.modelLoadLatency(ds, cutoffMs, w("model_load"))),
      evictions: safeAe(sql.keepAliveEvictions(ds, cutoffMs, w("model_load"))),
      dictCount: safeAe(sql.eventCount(ds, "dictation_completed", cutoffMs, w("dictation_completed"))),
      editedCount: safeAe(sql.eventCount(ds, "dictation_edited", cutoffMs, w("dictation_edited"))),
    }),
    // totalInstalls is all-time by definition; the breakdowns honor the selected
    // range (installs active in the window) so the range toggle affects every
    // card. All install queries honor the active filters (bind params).
    allOf({
      total: safeD1(`SELECT COUNT(*) AS n FROM installs WHERE 1 = 1${d1Filter.sql}`, d1Filter.binds),
      newInstalls: safeD1(`SELECT first_seen AS day, COUNT(*) AS value FROM installs WHERE first_seen >= ?${d1Filter.sql} GROUP BY first_seen ORDER BY first_seen`, [cutoffDay, ...d1Filter.binds]),
      chips: safeD1(`SELECT chip AS label, COUNT(*) AS value FROM installs WHERE last_seen >= ?${d1Filter.sql} GROUP BY chip ORDER BY value DESC LIMIT 20`, [cutoffDay, ...d1Filter.binds]),
      rams: safeD1(`SELECT ram_gb AS label, COUNT(*) AS value FROM installs WHERE last_seen >= ?${d1Filter.sql} GROUP BY ram_gb ORDER BY value DESC LIMIT 20`, [cutoffDay, ...d1Filter.binds]),
      countries: safeD1(`SELECT country AS label, COUNT(*) AS value FROM installs WHERE last_seen >= ?${d1Filter.sql} GROUP BY country ORDER BY value DESC LIMIT 20`, [cutoffDay, ...d1Filter.binds]),
    }),
    loadFilterOptions(safeAe, safeD1, ds, cutoffMs, cutoffDay),
  ]);

  const mf = aeRows.mf[0] ?? {};
  const mfTotal = num(mf.total);
  const magicFormatAdoptionPct = mfTotal > 0 ? (num(mf.polished) / mfTotal) * 100 : 0;

  const lat = aeRows.lat[0] ?? {};
  const asrLat = aeRows.asrLat[0] ?? {};
  const llmLat = aeRows.llmLat[0] ?? {};
  const modelLoad = aeRows.modelLoad[0] ?? {};
  const latency: LatencySummary[] = [
    { stage: "end_to_end", p50: num(lat.e2e_p50), p95: num(lat.e2e_p95) },
    { stage: "asr", p50: num(asrLat.asr_p50), p95: num(asrLat.asr_p95) },
    { stage: "magic_format", p50: num(llmLat.llm_p50), p95: num(llmLat.llm_p95) },
    { stage: "model_load", p50: num(modelLoad.p50), p95: num(modelLoad.p95) },
  ];

  const launches = num(aeRows.launches[0]?.value);
  const sessionEnds = num(aeRows.sessionEnds[0]?.value);
  const crashProxyRatePct = launches > 0 ? Math.max(0, (1 - sessionEnds / launches) * 100) : 0;

  const audioRate = aeRows.audioRate[0] ?? {};
  const audioTotal = num(audioRate.total);
  const audioFallbackRatePct = audioTotal > 0 ? (num(audioRate.fell_back) / audioTotal) * 100 : 0;

  const dictCount = num(aeRows.dictCount[0]?.value);
  const editedCount = num(aeRows.editedCount[0]?.value);

  // Which panels the active filters can't honor. The FE renders explicit
  // "not recorded under {dim}" states from this — a blocked query returns zero
  // rows, and a zero must never masquerade as a healthy metric (e.g. a
  // "100% crash-free" fleet under a dictation-only filter).
  const blocked: BlockedPanels = {};
  const block = (panel: keyof BlockedPanels, dim: FilterDim | null) => {
    if (dim) blocked[panel] = dim;
  };
  block("activeInstalls", blockedDim(filters, "*"));
  block("audio", blockedDim(filters, "audio_backend_used"));
  block("errors", blockedDim(filters, "error"));
  block("edits", blockedDim(filters, "dictation_edited"));
  block("crash", blockedDim(filters, "app_launch") ?? blockedDim(filters, "session_end"));
  block("modelLoad", blockedDim(filters, "model_load"));
  block("installs", blockedDimD1(filters));

  return {
    rangeDays: opts.rangeDays,
    appliedFilters: sanitizeFilters(filters),
    blocked,
    wordsPerDay: toTimePoints(aeRows.words),
    activeInstallsPerDay: toTimePoints(aeRows.active),
    newInstallsPerDay: d1Rows.newInstalls.map((r) => ({ day: String(r.day), value: num(r.value) })),
    totalInstalls: num(d1Rows.total[0]?.n),
    asrModelBreakdown: toBreakdown(aeRows.asrModels),
    chipBreakdown: toBreakdown(d1Rows.chips),
    ramBreakdown: toBreakdown(d1Rows.rams),
    countryBreakdown: toBreakdown(d1Rows.countries),
    magicFormatAdoptionPct,
    fallbackReasons: toBreakdown(aeRows.fallbacks),
    latency,
    errorsByType: toBreakdown(aeRows.errors),
    crashProxyRatePct,
    audioBackends: toBreakdown(aeRows.audio),
    audioFallbackRatePct,
    editRateMedianPct: num(aeRows.editRate[0]?.median),
    editedSharePct: dictCount > 0 ? (editedCount / dictCount) * 100 : 0,
    keepAliveEvictions: num(aeRows.evictions[0]?.value),
    segmentEventCount: dictCount,
    filterOptions,
  };
}

/**
 * Available values per filter dimension: install-registry dims from D1 DISTINCT,
 * dictation dims from AE breakdowns. Range-scoped but NOT filter-scoped, so the
 * option lists stay stable while a filter is active.
 */
async function loadFilterOptions(
  ae: AeRunner,
  d1: D1Runner,
  ds: string,
  cutoffMs: number,
  cutoffDay: string
): Promise<Partial<Record<FilterDim, Array<string | number>>>> {
  const d1Dims: Array<[FilterDim, string]> = [
    ["version", "app_version"], ["channel", "channel"], ["chip", "chip"],
    ["ram", "ram_gb"], ["os", "os_version"], ["mac_model", "mac_model"],
    ["country", "country"], ["cpu_cores", "cpu_cores"],
  ];
  const aeDims: Array<[FilterDim, string]> = [
    ["asr_model", "blob5"], ["language", "blob7"], ["target", "blob11"],
    // arch isn't in D1; on dictation_completed its aliased slot (blob14) has no
    // native occupant, so the breakdown yields exactly the arch values.
    ["arch", "blob14"],
  ];

  const [d1Results, aeResults] = await Promise.all([
    Promise.all(d1Dims.map(([, col]) =>
      d1(`SELECT DISTINCT ${col} AS v FROM installs WHERE last_seen >= ? AND ${col} IS NOT NULL ORDER BY v`, [cutoffDay])
    )),
    Promise.all(aeDims.map(([, col]) =>
      ae(sql.breakdown(ds, col, "blob1 = 'dictation_completed'", cutoffMs))
    )),
  ]);

  const out: Partial<Record<FilterDim, Array<string | number>>> = {};
  d1Dims.forEach(([dim], i) => {
    const values = d1Results[i].map((r) => r.v).filter((v): v is string | number => v !== null && v !== undefined && v !== "");
    if (values.length > 0) out[dim] = values;
  });
  aeDims.forEach(([dim], i) => {
    const values = aeResults[i].map((r) => String(r.label ?? "")).filter((v) => v !== "");
    if (values.length > 0) out[dim] = values;
  });
  return out;
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
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`AE SQL ${res.status}: ${body.slice(0, 400)} :: ${query.slice(0, 200)}`);
    }
    const json = (await res.json()) as { data?: Array<Record<string, unknown>> };
    return json.data ?? [];
  };
}
