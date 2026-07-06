// Shapes shared by the dashboard Worker and the React app.

export interface TimePoint {
  day: string; // YYYY-MM-DD
  value: number;
}

export interface Breakdown {
  label: string;
  value: number;
}

export interface LatencySummary {
  stage: string;
  p50: number;
  p95: number;
}

/**
 * Filterable dimensions. Values are matched against the AE slot / D1 column the
 * dimension lives in; dims are event-aware — a dim whose slot is occupied by a
 * native field on some event yields an honest empty result there, never
 * silently-unfiltered data (see whereFiltersAE in stats.ts).
 */
export const FILTER_DIMS = [
  "version", "channel", "country", "ram",
  "chip", "os", "mac_model", "arch", "cpu_cores",
  "asr_model", "language", "target",
] as const;
export type FilterDim = (typeof FILTER_DIMS)[number];
export type Filters = Partial<Record<FilterDim, string>>;

export interface StatsResponse {
  rangeDays: number;
  /** The filters actually applied (post-sanitization) — the FE's source of truth. */
  appliedFilters: Filters;
  wordsPerDay: TimePoint[];
  activeInstallsPerDay: TimePoint[];
  newInstallsPerDay: TimePoint[];
  totalInstalls: number;
  asrModelBreakdown: Breakdown[];
  chipBreakdown: Breakdown[];
  ramBreakdown: Breakdown[];
  countryBreakdown: Breakdown[];
  magicFormatAdoptionPct: number;
  fallbackReasons: Breakdown[];
  /** Per-stage p50/p95 incl. model_load (cold model start). */
  latency: LatencySummary[];
  errorsByType: Breakdown[];
  crashProxyRatePct: number;
  audioBackends: Breakdown[];
  audioFallbackRatePct: number;
  /** Median post-insertion edit-rate bucket (%) over edited dictations. */
  editRateMedianPct: number;
  /** Share of completed dictations the user then edited (%). */
  editedSharePct: number;
  keepAliveEvictions: number;
  /** dictation_completed count in the window under the active filters. */
  segmentEventCount: number;
  /** Available values per dimension (range-scoped, NOT filter-scoped). */
  filterOptions: Partial<Record<FilterDim, Array<string | number>>>;
}

/** Minimal D1 binding shape (read-only usage). */
export interface D1Result<T> {
  results: T[];
}
export interface D1Database {
  prepare(query: string): D1PreparedStatement;
}
export interface D1PreparedStatement {
  bind(...values: unknown[]): D1PreparedStatement;
  all<T = Record<string, unknown>>(): Promise<D1Result<T>>;
  first<T = Record<string, unknown>>(): Promise<T | null>;
}

export interface DashboardEnv {
  INSTALLS_DB?: D1Database;
  ASSETS?: { fetch(request: Request): Promise<Response> };
  CF_ACCOUNT_ID?: string;
  AE_API_TOKEN?: string;
  AE_DATASET?: string;
  CF_ACCESS_TEAM_DOMAIN?: string; // e.g. myteam.cloudflareaccess.com
  CF_ACCESS_AUD?: string;
}
