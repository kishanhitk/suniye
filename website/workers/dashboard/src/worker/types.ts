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
  "asr_model", "cleanup_model", "language", "target",
] as const;
export type FilterDim = (typeof FILTER_DIMS)[number];
/**
 * A dimension maps to a *set* of selected values (OR within a dimension), and
 * dimensions combine with AND — the standard faceted-filter model. An empty or
 * absent array means the dimension isn't constrained.
 */
export type Filters = Partial<Record<FilterDim, string[]>>;

/** One selectable filter value plus how much data it represents in-context. */
export interface FilterOption {
  value: string | number;
  /**
   * Dictations matching this value under the *other* active filters (this
   * dimension excluded), range-scoped — a live facet count so slicing is
   * informed, not blind. Zero when the combination has no data yet.
   */
  count: number;
}

/**
 * Panels whose underlying event cannot honor one of the active filters. The
 * value is the offending dim; the FE renders an explicit "not recorded under
 * {dim}" state instead of a fake zero. Server-computed from DIM_SPECS so the
 * FE never mirrors slot-availability knowledge.
 */
export interface BlockedPanels {
  activeInstalls?: FilterDim;
  audio?: FilterDim;
  errors?: FilterDim;
  edits?: FilterDim;
  crash?: FilterDim;
  modelLoad?: FilterDim;
  /** D1 install registry (installs tile, new-installs, fleet breakdowns). */
  installs?: FilterDim;
}

export interface StatsResponse {
  rangeDays: number;
  /** The filters actually applied (post-sanitization) — the FE's source of truth. */
  appliedFilters: Filters;
  blocked: BlockedPanels;
  wordsPerDay: TimePoint[];
  activeInstallsPerDay: TimePoint[];
  newInstallsPerDay: TimePoint[];
  totalInstalls: number;
  asrModelBreakdown: Breakdown[];
  chipBreakdown: Breakdown[];
  ramBreakdown: Breakdown[];
  countryBreakdown: Breakdown[];
  /** null when there are no dictations in the window (render "—", not "0%"). */
  magicFormatAdoptionPct: number | null;
  fallbackReasons: Breakdown[];
  /** Per-stage p50/p95 incl. model_load (cold model start) and llm_prefill (local LLM prompt processing). */
  latency: LatencySummary[];
  /**
   * Share of local-LLM generations (llm_generation) whose prompt prefix was
   * served from llama-server's KV cache (%) — i.e. the prewarm probe primed it.
   * null (→ "—") when the window has no local generations.
   */
  llmCacheHitRatePct: number | null;
  errorsByType: Breakdown[];
  /**
   * Clean-session proxy (session_ends / launches), as crash-FREE %. null when
   * either stream is absent in the window (render "—").
   */
  crashFreeRatePct: number | null;
  audioBackends: Breakdown[];
  audioFallbackRatePct: number;
  /** Median post-insertion edit-rate bucket (%) over edited dictations. */
  editRateMedianPct: number;
  /**
   * Share of *finalized* dictations that were edited (%), derived from the
   * dictation_edited stream alone (edited / finalized) so it's bounded ≤ 100.
   * null (→ "—") when no edit sessions have finalized in the window.
   */
  editedSharePct: number | null;
  keepAliveEvictions: number;
  /** dictation_completed count in the window under the active filters. */
  segmentEventCount: number;
  /**
   * Selectable values per dimension, each with a contextual facet count
   * (dictations under the other active filters). Ordered by count, so the most
   * common values lead. See FilterOption.
   */
  filterOptions: Partial<Record<FilterDim, FilterOption[]>>;
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
  AE_WEB_DATASET?: string;
  CF_ACCESS_TEAM_DOMAIN?: string; // e.g. myteam.cloudflareaccess.com
  CF_ACCESS_AUD?: string;
}
