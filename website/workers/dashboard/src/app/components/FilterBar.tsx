import { useEffect, useRef, useState } from "react";
import type { FilterDim, Filters, StatsResponse } from "../types";
import { CHIP_KEY, DIM_GROUPS } from "./filterMeta";
import { FilterMenu } from "./FilterMenu";
import { formatCount } from "../lib/utils";

/** Stable dimension order for rendering active chips. */
const ORDER: FilterDim[] = DIM_GROUPS.flatMap((g) => g.dims);

/**
 * The segment bar. Active filters render as removable monospace chips that read
 * like a query line (chip=apple-m3-pro · ram=36); everything else is added via
 * a searchable "+ add filter" menu. Press `f` anywhere to open it.
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
  const [open, setOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);

  const activeDims = ORDER.filter((dim) => filters[dim]);
  const anyAddable = ORDER.some((dim) => (options[dim]?.length ?? 0) > 0 && !filters[dim]);
  const active = activeDims.length > 0;

  // `f` opens the menu (ignored while typing in a field).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "f" || e.metaKey || e.ctrlKey || e.altKey) return;
      const el = e.target as HTMLElement;
      if (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable) return;
      if (!anyAddable) return;
      e.preventDefault();
      setOpen(true);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [anyAddable]);

  // Nothing active and nothing to add (no data yet) → hide the bar.
  if (!active && !anyAddable) return null;

  return (
    <div className="border-t border-line py-4">
      <div className="flex flex-wrap items-center gap-2">
        {activeDims.map((dim) => (
          <span key={dim} className="inline-flex items-center overflow-hidden rounded-md border border-accent font-mono text-xs">
            <span className="py-1 pl-2 pr-1 text-ink">{CHIP_KEY[dim]}={filters[dim]}</span>
            <button
              aria-label={`Remove ${CHIP_KEY[dim]} filter`}
              onClick={() => onChange(dim, null)}
              className="px-1.5 py-1 text-muted hover:text-accent"
            >
              ×
            </button>
          </span>
        ))}

        {anyAddable && (
          <div className="relative">
            <button
              ref={triggerRef}
              onClick={() => setOpen((o) => !o)}
              aria-haspopup="listbox"
              aria-expanded={open}
              className="rounded-md border border-dashed border-line px-2 py-1.5 font-mono text-xs text-muted hover:text-ink"
            >
              + add filter
            </button>
            {open && (
              <FilterMenu
                options={options}
                filters={filters}
                onSelect={(dim, value) => onChange(dim, value)}
                onClose={() => setOpen(false)}
              />
            )}
          </div>
        )}

        {active && (
          <button onClick={onClear} className="rounded-md px-2 py-1.5 font-mono text-xs text-accent hover:bg-surface">
            clear
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
