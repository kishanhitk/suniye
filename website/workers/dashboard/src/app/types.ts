// Mirror of the worker's StatsResponse (kept in sync manually — the frontend is
// a separate build target from the Worker).
export interface TimePoint { day: string; value: number; }
export interface Breakdown { label: string; value: number; }
export interface LatencySummary { stage: string; p50: number; p95: number; }

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
