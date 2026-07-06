// Types are erased at build time, so the React app imports them directly from
// the Worker — no runtime coupling, no hand-mirroring to drift out of sync.
export type { Breakdown, FilterDim, Filters, LatencySummary, StatsResponse, TimePoint } from "../worker/types";
