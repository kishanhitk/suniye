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
// or comment/statement characters, so it cannot escape a quoted literal). The
// same guarantee lets D1 *filter* values be interpolated too (which sidesteps
// D1's 100-bound-parameter cap that a broad multi-select would otherwise hit);
// structural/range values (cutoff dates) still go through bind params.

import { FILTER_DIMS } from "./types";
import type { BlockedPanels, Breakdown, FilterDim, FilterOption, Filters, LatencySummary, StatsResponse, TimePoint } from "./types";

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
 * - `eventUnscopedSafe`: the dim sits on a DEDICATED AE slot, so it can be applied
 *   to the event-unscoped active-installs query without a slot collision. Dims on
 *   shared slots omit this and block that query instead (honest empty).
 */
const DIM_SPECS: Record<FilterDim, {
  ae: string;
  numeric?: boolean;
  d1?: string;
  unavailableOn?: string[];
  dictationOnly?: boolean;
  eventUnscopedSafe?: boolean;
}> = {
  version:   { ae: "blob3",  d1: "app_version", eventUnscopedSafe: true },
  channel:   { ae: "blob4",  d1: "channel", eventUnscopedSafe: true },
  country:   { ae: "blob19", d1: "country", eventUnscopedSafe: true },
  ram:       { ae: "double19", numeric: true, d1: "ram_gb", eventUnscopedSafe: true },
  // chip/os live on SHARED slots (blob16=kind/feature, blob18=from/to_version on
  // some events), so they are NOT eventUnscopedSafe: on the event-unscoped
  // active-installs query they'd exclude installs whose only in-day events used
  // the slot for its other meaning → silent undercount. Omitting the flag makes
  // active-installs block under these filters (honest empty) instead.
  chip:      { ae: "blob16", d1: "chip",
               unavailableOn: ["permission_transition", "model_changed", "model_download", "feature_toggled", "update_action"] },
  os:        { ae: "blob18", d1: "os_version", unavailableOn: ["update_action"] },
  mac_model: { ae: "blob17", d1: "mac_model", unavailableOn: ["model_load", "model_changed", "model_download", "llm_generation"] },
  arch:      { ae: "blob14", // not in D1 (installs has no arch column)
               unavailableOn: ["error", "audio_backend_used", "dictation_blocked", "dictation_cancelled", "onboarding_step", "audio_capture_interrupted"] },
  cpu_cores: { ae: "double18", numeric: true, d1: "cpu_cores", unavailableOn: ["audio_backend_used"] },
  asr_model:     { ae: "blob5",  dictationOnly: true },
  cleanup_model: { ae: "blob9",  dictationOnly: true },
  language:      { ae: "blob7",  dictationOnly: true },
  target:        { ae: "blob11", dictationOnly: true },
};

/**
 * Always-false AE guard: blob1 (the event name) is never empty, so this returns
 * zero rows. Used when a selected dim isn't recorded for the queried event —
 * an honest empty beats silently-unfiltered data.
 */
const AE_NEVER = " AND blob1 = ''";

type DimSpec = (typeof DIM_SPECS)[FilterDim];

/**
 * The active filters that survive sanitization, with their specs. Each dim maps
 * to its list of valid selected values (OR within a dim). Invalid values are
 * dropped element-wise (a stale/malformed option must not blank the dashboard);
 * a dim with no surviving values drops out entirely. Single source of truth for
 * the where-builders and blocked-panel checks. Duplicates are collapsed.
 */
function sanitizedEntries(
  filters: Filters | undefined
): Array<[FilterDim, DimSpec, Array<string | number>]> {
  if (!filters) return [];
  const out: Array<[FilterDim, DimSpec, Array<string | number>]> = [];
  for (const [dim, raw] of Object.entries(filters) as Array<[FilterDim, string[] | string | undefined]>) {
    const spec = DIM_SPECS[dim];
    if (!spec || raw === undefined) continue;
    // Tolerate a bare string (e.g. a hand-built URL) as a one-element set.
    const rawValues = Array.isArray(raw) ? raw : [raw];
    const values: Array<string | number> = [];
    for (const rv of rawValues) {
      const value = spec.numeric ? safeNum(rv) : safeLabel(rv);
      if (value !== null && !values.includes(value)) values.push(value);
    }
    if (values.length > 0) out.push([dim, spec, values]);
  }
  return out;
}

/**
 * One dim's SQL predicate against `col`: `= v` for a single value, `IN (…)` for a
 * set. Every value is already safeLabel/safeNum-sanitized, so interpolation is
 * injection-safe — the same guarantee the raw AE SQL relies on, reused for D1's
 * filter columns so a large multi-select can't exceed D1's bind-parameter cap.
 */
function inClause(col: string, numeric: boolean | undefined, values: Array<string | number>): string {
  const lit = (v: string | number) => (numeric ? String(v) : `'${v}'`);
  if (values.length === 1) return ` AND ${col} = ${lit(values[0])}`;
  return ` AND ${col} IN (${values.map(lit).join(", ")})`;
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
      (event === "*" ? !spec.eventUnscopedSafe : (spec.unavailableOn?.includes(event) ?? false));
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
  for (const [, spec, values] of sanitizedEntries(filters)) {
    out += inClause(spec.ae, spec.numeric, values);
  }
  return out;
}

/**
 * D1 (installs) filter fragment. Filter values are interpolated (not bound) using
 * the same safeLabel/safeNum guarantee as the AE path — so an arbitrarily large
 * multi-select can't blow D1's 100-bound-parameter ceiling and silently empty the
 * install cards. `binds` stays in the return shape for the range/date params the
 * install queries still bind. blockedDimD1 guarantees every dim here has a `d1`.
 */
export function whereFiltersD1(filters: Filters | undefined): { sql: string; binds: unknown[] } {
  if (blockedDimD1(filters)) return { sql: " AND 1 = 0", binds: [] };
  let sql = "";
  for (const [, spec, values] of sanitizedEntries(filters)) {
    sql += inClause(spec.d1!, spec.numeric, values);
  }
  return { sql, binds: [] };
}

/** Sanitized copy of the incoming filters (what the response echoes back). */
export function sanitizeFilters(filters: Filters | undefined): Filters {
  const out: Filters = {};
  for (const [dim, , values] of sanitizedEntries(filters)) {
    out[dim] = values.map(String);
  }
  return out;
}

/** The active filters with one dimension dropped — the base for its facet counts
 *  (a dim's own selection must not constrain its own value list). */
function filtersExcept(filters: Filters | undefined, drop: FilterDim): Filters {
  if (!filters) return {};
  const out: Filters = {};
  for (const [dim, values] of Object.entries(filters) as Array<[FilterDim, string[]]>) {
    if (dim !== drop) out[dim] = values;
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
  // Event-unscoped ("*"): only eventUnscopedSafe (dedicated-slot) dims may filter it.
  activeInstallsPerDay: (ds: string, cutoffMs: number, where = "") =>
    `SELECT toStartOfInterval(toDateTime(double1 / 1000), INTERVAL '1' DAY) AS day, COUNT(DISTINCT index1) AS value ` +
    `FROM ${ds} WHERE double1 >= ${cutoffMs}${where} GROUP BY day ORDER BY day`,

  breakdown: (ds: string, col: string, whereEvent: string, cutoffMs: number, where = "", limit = 20) =>
    `SELECT ${col} AS label, SUM(_sample_interval) AS value FROM ${ds} ` +
    `WHERE ${whereEvent} AND double1 >= ${cutoffMs}${where} GROUP BY label ORDER BY value DESC LIMIT ${limit}`,

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
  // accuracy proxy. Median over dictations the user actually edited (> 0).
  editRate: (ds: string, cutoffMs: number, where = "") =>
    `SELECT quantileWeighted(0.5, double20, _sample_interval) AS median ` +
    `FROM ${ds} WHERE blob1 = 'dictation_edited' AND double20 > 0 AND double1 >= ${cutoffMs}${where}`,

  // Edited share is derived from the dictation_edited stream ALONE: it fires once
  // per finalized edit session (bucket 0 = verbatim/unedited), so edited/finalized
  // is a coherent, bounded ratio. Dividing by dictation_completed instead would
  // exceed 100% — that stream is lagged (finalize-on-next-dictation) and stamped
  // at a later time, so the two populations differ across the window edges.
  editedCount: (ds: string, cutoffMs: number, where = "") =>
    `SELECT SUM(_sample_interval) AS value FROM ${ds} ` +
    `WHERE blob1 = 'dictation_edited' AND double20 > 0 AND double1 >= ${cutoffMs}${where}`,

  // Cold model-load latency (double14 = load_ms). Keep-alive evictions are also
  // emitted as model_load but with load_ms 0 (evicted_by_keepalive rides only the
  // blob20 props JSON, so double14 > 0 is the discriminator for a real load).
  modelLoadLatency: (ds: string, cutoffMs: number, where = "") =>
    `SELECT quantileWeighted(0.5, double14, _sample_interval) AS p50, quantileWeighted(0.95, double14, _sample_interval) AS p95 ` +
    `FROM ${ds} WHERE blob1 = 'model_load' AND double14 > 0 AND double1 >= ${cutoffMs}${where}`,

  keepAliveEvictions: (ds: string, cutoffMs: number, where = "") =>
    `SELECT SUM(_sample_interval) AS value FROM ${ds} ` +
    `WHERE blob1 = 'model_load' AND double14 = 0 AND double1 >= ${cutoffMs}${where}`,

  // Local-LLM prompt processing per user-facing generation (double14 = prefill_ms
  // on llm_generation) and the share served from the KV cache (double17 =
  // cache_hit). A prefill of ~2.4k tokens on the critical path vs ~40 is exactly
  // what the prewarm probe is meant to move off it.
  llmPrefillLatency: (ds: string, cutoffMs: number, where = "") =>
    `SELECT quantileWeighted(0.5, double14, _sample_interval) AS p50, quantileWeighted(0.95, double14, _sample_interval) AS p95 ` +
    `FROM ${ds} WHERE blob1 = 'llm_generation' AND double14 > 0 AND double1 >= ${cutoffMs}${where}`,

  llmCacheHitRate: (ds: string, cutoffMs: number, where = "") =>
    `SELECT SUM(double17 * _sample_interval) AS hits, SUM(_sample_interval) AS total ` +
    `FROM ${ds} WHERE blob1 = 'llm_generation' AND double1 >= ${cutoffMs}${where}`,
};

// ---- helpers ----

function num(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : 0;
}

/**
 * A percentage that is null (→ "—" on the FE) when there's no data, so an empty
 * window can never read as a real 0%. The invariant lives here, once, instead of
 * being hand-rolled at each KPI (which is exactly how one site got missed).
 */
function ratio(numerator: number, denominator: number): number | null {
  return denominator > 0 ? (numerator / denominator) * 100 : null;
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
      // Only dictations that ACTUALLY fell back: cleanup_fallback_reason (blob10)
      // is empty for a successful polish, an MF-off dictation, or any event
      // before v0.0.51 (where the reason was hardcoded nil). Without this filter
      // those all collapse into a meaningless "unknown" bucket.
      fallbacks: safeAe(sql.breakdown(ds, "blob10", "blob1 = 'dictation_completed' AND blob10 != ''", cutoffMs, w("dictation_completed"))),
      errors: safeAe(sql.breakdown(ds, "blob14", "blob1 = 'error'", cutoffMs, w("error"))),
      launches: safeAe(sql.eventCount(ds, "app_launch", cutoffMs, w("app_launch"))),
      sessionEnds: safeAe(sql.eventCount(ds, "session_end", cutoffMs, w("session_end"))),
      audio: safeAe(sql.audioBackends(ds, cutoffMs, w("audio_backend_used"))),
      audioRate: safeAe(sql.audioFallbackRate(ds, cutoffMs, w("audio_backend_used"))),
      editRate: safeAe(sql.editRate(ds, cutoffMs, w("dictation_edited"))),
      modelLoad: safeAe(sql.modelLoadLatency(ds, cutoffMs, w("model_load"))),
      evictions: safeAe(sql.keepAliveEvictions(ds, cutoffMs, w("model_load"))),
      llmPrefill: safeAe(sql.llmPrefillLatency(ds, cutoffMs, w("llm_generation"))),
      llmCache: safeAe(sql.llmCacheHitRate(ds, cutoffMs, w("llm_generation"))),
      dictCount: safeAe(sql.eventCount(ds, "dictation_completed", cutoffMs, w("dictation_completed"))),
      editFinalized: safeAe(sql.eventCount(ds, "dictation_edited", cutoffMs, w("dictation_edited"))),
      editChanged: safeAe(sql.editedCount(ds, cutoffMs, w("dictation_edited"))),
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
    loadFilterOptions(safeAe, ds, cutoffMs, filters),
  ]);

  const mf = aeRows.mf[0] ?? {};
  const magicFormatAdoptionPct = ratio(num(mf.polished), num(mf.total));

  const lat = aeRows.lat[0] ?? {};
  const asrLat = aeRows.asrLat[0] ?? {};
  const llmLat = aeRows.llmLat[0] ?? {};
  const modelLoad = aeRows.modelLoad[0] ?? {};
  const llmPrefill = aeRows.llmPrefill[0] ?? {};
  const latency: LatencySummary[] = [
    { stage: "end_to_end", p50: num(lat.e2e_p50), p95: num(lat.e2e_p95) },
    { stage: "asr", p50: num(asrLat.asr_p50), p95: num(asrLat.asr_p95) },
    { stage: "magic_format", p50: num(llmLat.llm_p50), p95: num(llmLat.llm_p95) },
    { stage: "llm_prefill", p50: num(llmPrefill.p50), p95: num(llmPrefill.p95) },
    { stage: "model_load", p50: num(modelLoad.p50), p95: num(modelLoad.p95) },
  ];
  const llmCache = aeRows.llmCache[0] ?? {};
  const llmCacheHitRatePct = ratio(num(llmCache.hits), num(llmCache.total));

  // Crash-free is a proxy: clean session_ends / launches. Needs BOTH streams —
  // null (→ "—") when either is absent, so an empty window can't read as a fake
  // "100% crash-free". Returned as crash-FREE directly (the one concept the FE
  // shows) rather than a crash rate the FE would have to invert. Note: the most
  // recent launches have no session_end yet, so it slightly understates near
  // "now" — inherent to the proxy at low volume.
  const launches = num(aeRows.launches[0]?.value);
  const sessionEnds = num(aeRows.sessionEnds[0]?.value);
  const crashFreeRatePct = launches > 0 && sessionEnds > 0
    ? Math.min(100, (sessionEnds / launches) * 100)
    : null;

  const audioRate = aeRows.audioRate[0] ?? {};
  const audioTotal = num(audioRate.total);
  const audioFallbackRatePct = audioTotal > 0 ? (num(audioRate.fell_back) / audioTotal) * 100 : 0;

  const dictCount = num(aeRows.dictCount[0]?.value);
  // "of finalized dictations, how many were edited" — same stream, bounded ≤ 100%.
  const editFinalized = num(aeRows.editFinalized[0]?.value);
  const editChanged = num(aeRows.editChanged[0]?.value);

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
    crashFreeRatePct,
    audioBackends: toBreakdown(aeRows.audio),
    audioFallbackRatePct,
    editRateMedianPct: num(aeRows.editRate[0]?.median),
    editedSharePct: ratio(editChanged, editFinalized),
    keepAliveEvictions: num(aeRows.evictions[0]?.value),
    llmCacheHitRatePct,
    segmentEventCount: dictCount,
    filterOptions,
  };
}

/**
 * Selectable values + live facet counts per dimension. Every dimension resolves
 * to a clean slot on dictation_completed (device dims via their aliased slots),
 * so a single breakdown per dim yields both its value list and a count. Each
 * dim's counts are computed under the OTHER active filters (self excluded) — so
 * the numbers reflect the current slice, yet a dimension never hides its own
 * sibling values. Unit is dictations throughout (matching segmentEventCount);
 * a value with no dictations under the current filters drops out of its list.
 */
async function loadFilterOptions(
  ae: AeRunner,
  ds: string,
  cutoffMs: number,
  filters: Filters | undefined
): Promise<Partial<Record<FilterDim, FilterOption[]>>> {
  const results = await Promise.all(
    FILTER_DIMS.map((dim) =>
      ae(sql.breakdown(
        ds, DIM_SPECS[dim].ae, "blob1 = 'dictation_completed'", cutoffMs,
        whereFiltersAE(filtersExcept(filters, dim), "dictation_completed"), 100,
      ))
    )
  );

  const out: Partial<Record<FilterDim, FilterOption[]>> = {};
  FILTER_DIMS.forEach((dim, i) => {
    const numeric = DIM_SPECS[dim].numeric;
    const opts: FilterOption[] = [];
    for (const r of results[i]) {
      const value = numeric ? num(r.label) : String(r.label ?? "");
      // Drop empty labels and non-positive numerics (0-ram/-cores are bad rows).
      if (numeric ? !(Number(value) > 0) : value === "") continue;
      opts.push({ value, count: num(r.value) });
    }
    if (opts.length > 0) out[dim] = opts;
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
