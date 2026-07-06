import type { FilterDim, Filters, StatsResponse } from "../types";
import { cn, formatCount } from "../lib/utils";

/** Display order + labels. Dims with no options (no data yet) don't render. */
const DIMS: Array<[FilterDim, string]> = [
  ["version", "version"],
  ["channel", "channel"],
  ["chip", "chip"],
  ["ram", "ram gb"],
  ["os", "macos"],
  ["mac_model", "model id"],
  ["cpu_cores", "cores"],
  ["asr_model", "asr model"],
  ["language", "language"],
  ["target", "target app"],
  ["country", "country"],
];

/**
 * The segment bar: every panel below re-scopes to the selected slice.
 * Native selects — keyboard- and screen-reader-correct for free.
 */
export function FilterBar({
  options,
  filters,
  segmentCount,
  onChange,
  onClear,
}: {
  options: StatsResponse["filterOptions"];
  filters: Filters;
  /** dictation_completed count inside the current segment (null while loading). */
  segmentCount: number | null;
  onChange: (dim: FilterDim, value: string | null) => void;
  onClear: () => void;
}) {
  const active = Object.keys(filters).length > 0;
  const dims = DIMS.filter(([dim]) => (options[dim]?.length ?? 0) > 0 || filters[dim]);

  if (dims.length === 0) return null;

  return (
    <div className="border-t border-line py-4">
      <div className="flex flex-wrap items-center gap-2">
        {dims.map(([dim, label]) => {
          const value = filters[dim] ?? "";
          const values = (options[dim] ?? []).map(String);
          // An active value that fell out of the option list (range change,
          // stale data) must stay visible — it still filters the queries.
          if (value && !values.includes(value)) values.unshift(value);
          return (
            <select
              key={dim}
              aria-label={`Filter by ${label}`}
              value={value}
              onChange={(e) => onChange(dim, e.target.value || null)}
              className={cn(
                "rounded-md border bg-paper px-2 py-1.5 font-mono text-xs",
                value ? "border-accent text-ink" : "border-line text-muted"
              )}
            >
              <option value="">{label}: all</option>
              {values.map((option) => (
                <option key={option} value={option}>
                  {label}: {option}
                </option>
              ))}
            </select>
          );
        })}
        {active && (
          <button
            onClick={onClear}
            className="rounded-md px-2 py-1.5 font-mono text-xs text-accent hover:bg-surface"
          >
            clear filters
          </button>
        )}
        <span className="ml-auto font-mono text-[11px] tabular-nums text-muted" aria-live="polite">
          {segmentCount === null ? "…" : `${formatCount(segmentCount)} dictations in this segment`}
        </span>
      </div>
      {active && (
        <p className="mt-2 font-mono text-[11px] text-muted">
          version + device filters cover data recorded by v0.0.51 and later
        </p>
      )}
    </div>
  );
}
