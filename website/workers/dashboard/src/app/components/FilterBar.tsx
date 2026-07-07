import { useCallback, useEffect, useRef, useState } from "react";
import type { FilterDim, Filters, StatsResponse } from "../types";
import { CHIP_KEY, DIM_GROUPS } from "./filterMeta";
import { FilterMenu } from "./FilterMenu";
import { formatCount } from "../lib/utils";

/** Stable dimension order for rendering active chips. */
const ORDER: FilterDim[] = DIM_GROUPS.flatMap((g) => g.dims);

/** A chip reads like a query clause: `chip=apple-m3-pro` for one value, or
 *  `chip ∈ m1, m3` / `chip ∈ 4 values` for a set (OR within the dimension). */
function chipLabel(dim: FilterDim, values: string[]): string {
  const key = CHIP_KEY[dim];
  if (values.length === 1) return `${key}=${values[0]}`;
  if (values.length <= 3) return `${key} ∈ ${values.join(", ")}`;
  return `${key} ∈ ${values.length} values`;
}

/**
 * The segment bar. Active filters render as removable chips that read like a
 * query line; each chip opens the menu drilled into its dimension to add/remove
 * values. Everything else is added via the searchable "+ add filter" menu
 * (press `f` anywhere).
 */
export function FilterBar({
  options,
  filters,
  segmentCount,
  onToggle,
  onClearDim,
  onClear,
}: {
  options: StatsResponse["filterOptions"];
  filters: Filters;
  /** dictation_completed count inside the current segment (null while loading). */
  segmentCount: number | null;
  onToggle: (dim: FilterDim, value: string) => void;
  onClearDim: (dim: FilterDim) => void;
  onClear: () => void;
}) {
  // null = closed; { drill, id } = open (drill null → top level, or into a dim).
  // `id` bumps on every open so re-opening into the same dimension still remounts
  // the menu (fresh drill), even from an already-open menu.
  const [menu, setMenu] = useState<{ drill: FilterDim | null; id: number } | null>(null);
  const openIdRef = useRef(0);
  const barRef = useRef<HTMLDivElement>(null);

  const openMenu = useCallback((drill: FilterDim | null) => {
    openIdRef.current += 1;
    setMenu({ drill, id: openIdRef.current });
  }, []);

  const activeDims = ORDER.filter((dim) => (filters[dim]?.length ?? 0) > 0);
  const anyOptions = ORDER.some((dim) => (options[dim]?.length ?? 0) > 0);
  const active = activeDims.length > 0;

  // `f` opens the add menu (ignored while typing in a field).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "f" || e.metaKey || e.ctrlKey || e.altKey) return;
      const el = e.target as HTMLElement;
      if (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable) return;
      if (!anyOptions) return;
      e.preventDefault();
      openMenu(null);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [anyOptions, openMenu]);

  // Nothing active and nothing to add (no data yet) → hide the bar.
  if (!active && !anyOptions) return null;

  return (
    <div className="border-t border-line py-4">
      <div ref={barRef} className="flex flex-wrap items-center gap-2">
        {activeDims.map((dim) => {
          const values = filters[dim] ?? [];
          return (
            <span key={dim} className="inline-flex items-center overflow-hidden rounded-md border border-accent font-mono text-xs">
              <button
                onClick={() => openMenu(dim)}
                title="Edit filter"
                className="max-w-[15rem] truncate py-1 pl-2 pr-1 text-ink hover:bg-surface"
              >
                {chipLabel(dim, values)}
              </button>
              <button
                aria-label={`Remove ${CHIP_KEY[dim]} filter`}
                onClick={() => onClearDim(dim)}
                className="px-1.5 py-1 text-muted hover:text-accent"
              >
                ×
              </button>
            </span>
          );
        })}

        {anyOptions && (
          <div className="relative">
            <button
              onClick={() => (menu ? setMenu(null) : openMenu(null))}
              aria-haspopup="listbox"
              aria-expanded={!!menu}
              className="rounded-md border border-dashed border-line px-2 py-1.5 font-mono text-xs text-muted hover:text-ink"
            >
              + add filter
            </button>
            {menu && (
              <FilterMenu
                // Remount on every open (id bumps) so clicking a chip always
                // re-drills — even into the same dimension from an open menu.
                key={menu.id}
                options={options}
                filters={filters}
                triggerRef={barRef}
                initialDrill={menu.drill}
                onToggle={onToggle}
                onClose={() => setMenu(null)}
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
