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

export interface StatsResponse {
  rangeDays: number;
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
  latency: LatencySummary[];
  errorsByType: Breakdown[];
  crashProxyRatePct: number;
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

/** Injectable so the AE SQL API can be faked in tests. */
export type SqlRunner = (sql: string) => Promise<Array<Record<string, unknown>>>;
