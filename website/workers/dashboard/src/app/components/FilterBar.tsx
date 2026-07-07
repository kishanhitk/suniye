import { useState } from "react";
import type { FilterDim, Filters, StatsResponse } from "../types";
import { formatCount } from "../lib/utils";

const LABELS: Record<FilterDim, string> = {
  version: "version", channel: "channel", country: "country", ram: "ram gb",
  chip: "chip", os: "macos", mac_model: "model id", arch: "arch", cpu_cores: "cores",
  asr_model: "asr model", cleanup_model: "llm model", language: "language", target: "target app",
};

/** Display order for the filter chips + the "add filter" menu. */
const ORDER: FilterDim[] = [
  "version", "channel", "chip", "ram", "os", "mac_model", "arch", "cpu_cores",
  "asr_model", "cleanup_model", "language", "target", "country",
];

/**
 * The segment bar: every panel below re-scopes to the selected slice. With a
 * dozen+ filterable dims, showing them all as a row of dropdowns is noise — so
 * only ACTIVE filters render as chips; the rest live behind "+ add filter".
 * Native selects, so keyboard + screen-reader support come for free.
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
  // Dims the user has revealed but not yet given a value (kept local — the parent
  // only tracks dims with an actual value).
  const [revealed, setRevealed] = useState<FilterDim[]>([]);

  const hasOptions = (dim: FilterDim) => (options[dim]?.length ?? 0) > 0;
  const shown = ORDER.filter((dim) => filters[dim] || revealed.includes(dim));
  const addable = ORDER.filter((dim) => !filters[dim] && !revealed.includes(dim) && hasOptions(dim));
  const active = Object.keys(filters).length > 0;

  const remove = (dim: FilterDim) => {
    onChange(dim, null);
    setRevealed((r) => r.filter((d) => d !== dim));
  };
  const clearAll = () => {
    onClear();
    setRevealed([]);
  };

  // No filters applied and nothing to add (no data yet) → hide the bar entirely.
  if (shown.length === 0 && addable.length === 0) return null;

  return (
    <div className="border-t border-line py-4">
      <div className="flex flex-wrap items-center gap-2">
        {shown.map((dim) => {
          const label = LABELS[dim];
          const value = filters[dim] ?? "";
          const values = (options[dim] ?? []).map(String);
          // An active value that fell out of the option list (range change, stale
          // data) must stay visible — it still filters the queries.
          if (value && !values.includes(value)) values.unshift(value);
          return (
            <span
              key={dim}
              className={`inline-flex items-center overflow-hidden rounded-md border ${value ? "border-accent" : "border-line"}`}
            >
              <select
                aria-label={`Filter by ${label}`}
                value={value}
                onChange={(e) => onChange(dim, e.target.value || null)}
                className={`bg-paper py-1.5 pl-2 pr-1 font-mono text-xs ${value ? "text-ink" : "text-muted"}`}
              >
                <option value="">{label}: all</option>
                {values.map((option) => (
                  <option key={option} value={option}>{label}: {option}</option>
                ))}
              </select>
              <button
                aria-label={`Remove ${label} filter`}
                onClick={() => remove(dim)}
                className="px-1.5 py-1.5 font-mono text-xs text-muted hover:text-accent"
              >
                ×
              </button>
            </span>
          );
        })}

        {addable.length > 0 && (
          <select
            aria-label="Add a filter"
            value=""
            onChange={(e) => { if (e.target.value) setRevealed((r) => [...r, e.target.value as FilterDim]); }}
            className="rounded-md border border-dashed border-line bg-paper px-2 py-1.5 font-mono text-xs text-muted hover:text-ink"
          >
            <option value="">+ add filter</option>
            {addable.map((dim) => (
              <option key={dim} value={dim}>{LABELS[dim]}</option>
            ))}
          </select>
        )}

        {active && (
          <button
            onClick={clearAll}
            className="rounded-md px-2 py-1.5 font-mono text-xs text-accent hover:bg-surface"
          >
            clear all
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
