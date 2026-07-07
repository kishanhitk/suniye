import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { FilterDim, FilterOption, Filters, StatsResponse } from "../types";
import { DIM_GROUPS, DIM_LABEL } from "./filterMeta";
import { formatNumber } from "../lib/utils";

type Row =
  | { kind: "header"; label: string }
  | { kind: "dim"; dim: FilterDim; selCount: number; sel: number }
  | { kind: "value"; dim: FilterDim; option: FilterOption; selected: boolean; showDim: boolean; sel: number };

/**
 * The add/edit-filter popover. Browse dimensions by group, or type to jump to a
 * value across all dimensions (collapsing the pick-dimension-then-value two-step).
 * Each value carries a live facet count (dictations in the current slice), and a
 * dimension holds a *set* of values — toggling checks/unchecks in place and keeps
 * the menu open, so several values (and dimensions) can be set in one session.
 * Keyboard-first: ↑/↓ move, ↵ toggles / drills, Esc/Backspace steps back.
 */
export function FilterMenu({
  options,
  filters,
  triggerRef,
  initialDrill = null,
  onToggle,
  onClose,
}: {
  options: StatsResponse["filterOptions"];
  filters: Filters;
  /** The filter-bar region whose clicks must NOT close the menu (chips + trigger). */
  triggerRef: React.RefObject<HTMLElement | null>;
  /** Open drilled straight into this dimension (e.g. when editing a chip). */
  initialDrill?: FilterDim | null;
  onToggle: (dim: FilterDim, value: string) => void;
  onClose: () => void;
}) {
  const [query, setQuery] = useState("");
  const [drill, setDrill] = useState<FilterDim | null>(initialDrill);
  const [highlight, setHighlight] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const q = query.trim().toLowerCase();

  useEffect(() => { inputRef.current?.focus(); }, []);

  // Close on outside click (the filter bar itself is excluded, so clicking a chip
  // or the trigger re-drills/toggles the menu rather than closing then reopening).
  useEffect(() => {
    const onDown = (e: MouseEvent) => {
      const target = e.target as Node;
      if (rootRef.current?.contains(target) || triggerRef.current?.contains(target)) return;
      onClose();
    };
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [onClose, triggerRef]);

  const { rows, count } = useMemo(() => {
    const has = (dim: FilterDim) => (options[dim]?.length ?? 0) > 0;
    const selectedIn = (dim: FilterDim) => filters[dim] ?? [];
    const rows: Row[] = [];
    let sel = 0;
    const valueRow = (dim: FilterDim, option: FilterOption, showDim: boolean) =>
      rows.push({ kind: "value", dim, option, selected: selectedIn(dim).includes(String(option.value)), showDim, sel: sel++ });
    const dimRow = (dim: FilterDim) =>
      rows.push({ kind: "dim", dim, selCount: selectedIn(dim).length, sel: sel++ });

    if (drill) {
      for (const opt of options[drill] ?? []) {
        if (!q || String(opt.value).toLowerCase().includes(q)) valueRow(drill, opt, false);
      }
    } else if (q) {
      // Value matches across every dimension, then dimension-name matches to drill.
      for (const { dims } of DIM_GROUPS) for (const dim of dims) {
        if (!has(dim)) continue;
        for (const opt of options[dim] ?? []) if (String(opt.value).toLowerCase().includes(q)) valueRow(dim, opt, true);
      }
      for (const { dims } of DIM_GROUPS) for (const dim of dims) {
        if (has(dim) && DIM_LABEL[dim].includes(q)) dimRow(dim);
      }
    } else {
      for (const group of DIM_GROUPS) {
        const dims = group.dims.filter(has);
        if (dims.length === 0) continue;
        rows.push({ kind: "header", label: group.label });
        dims.forEach(dimRow);
      }
    }
    return { rows, count: sel };
  }, [options, filters, drill, q]);

  // Keep the highlight in range whenever the list changes.
  useLayoutEffect(() => { setHighlight((h) => Math.min(Math.max(h, 0), Math.max(count - 1, 0))); }, [count]);

  const selectable = rows.filter((r): r is Extract<Row, { sel: number }> => r.kind !== "header");
  const choose = (row: Extract<Row, { sel: number }>) => {
    if (row.kind === "dim") { setDrill(row.dim); setQuery(""); setHighlight(0); }
    else onToggle(row.dim, String(row.option.value)); // toggle in place — menu stays open
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowDown") { e.preventDefault(); setHighlight((h) => Math.min(h + 1, count - 1)); }
    else if (e.key === "ArrowUp") { e.preventDefault(); setHighlight((h) => Math.max(h - 1, 0)); }
    else if (e.key === "Enter") { e.preventDefault(); const it = selectable[highlight]; if (it) choose(it); }
    else if (e.key === "Escape") { e.preventDefault(); if (drill) { setDrill(null); setQuery(""); } else onClose(); }
    else if (e.key === "Backspace" && !query && drill) { e.preventDefault(); setDrill(null); }
  };

  return (
    <div ref={rootRef} className="absolute left-0 top-full z-20 mt-1 w-80 overflow-hidden rounded-lg border border-line bg-paper shadow-md">
      <input
        ref={inputRef}
        value={query}
        onChange={(e) => { setQuery(e.target.value); setHighlight(0); }}
        onKeyDown={onKeyDown}
        placeholder={drill ? `${DIM_LABEL[drill]}…` : "filter by dimension or value…"}
        role="combobox"
        aria-label="Filter by dimension or value"
        aria-expanded
        aria-controls="filter-listbox"
        aria-activedescendant={count > 0 ? `filter-opt-${highlight}` : undefined}
        className="w-full border-b border-line bg-transparent px-3 py-2 font-mono text-xs text-ink outline-none placeholder:text-muted"
      />
      {drill && (
        <button
          onClick={() => { setDrill(null); setQuery(""); setHighlight(0); }}
          className="flex w-full items-center gap-1 border-b border-line px-3 py-1.5 font-mono text-[11px] text-muted hover:text-ink"
        >
          ‹ all dimensions
        </button>
      )}
      <ul id="filter-listbox" role="listbox" aria-multiselectable className="max-h-72 overflow-y-auto py-1">
        {count === 0 && <li className="px-3 py-2 font-mono text-xs text-muted">no matches</li>}
        {rows.map((row, i) => {
          if (row.kind === "header") {
            return <li key={`h-${row.label}`} className="px-3 pb-1 pt-2 font-mono text-[10px] uppercase tracking-[0.16em] text-muted">{row.label}</li>;
          }
          const on = row.sel === highlight;
          const base = `flex cursor-pointer items-center justify-between gap-3 px-3 py-1.5 font-mono text-xs ${on ? "bg-surface" : ""}`;
          if (row.kind === "dim") {
            return (
              <li
                key={`d-${row.dim}`}
                id={`filter-opt-${row.sel}`}
                role="option"
                aria-selected={row.selCount > 0}
                onMouseEnter={() => setHighlight(row.sel)}
                onClick={() => choose(row)}
                className={`${base} text-ink`}
              >
                <span>{DIM_LABEL[row.dim]}</span>
                <span className="flex items-center gap-1.5 text-muted">
                  {row.selCount > 0 && <span className="tabular-nums text-accent">{row.selCount}</span>}
                  ›
                </span>
              </li>
            );
          }
          const { option, selected, showDim } = row;
          return (
            <li
              key={`v-${row.dim}-${option.value}`}
              id={`filter-opt-${row.sel}`}
              role="option"
              aria-selected={selected}
              onMouseEnter={() => setHighlight(row.sel)}
              onClick={() => choose(row)}
              className={`${base} text-ink`}
            >
              <span className="flex min-w-0 items-center gap-2">
                <span className={`h-3 w-3 shrink-0 rounded-[3px] border ${selected ? "border-accent bg-accent" : "border-line"}`} aria-hidden />
                <span className="truncate">{showDim ? `${DIM_LABEL[row.dim]} = ${option.value}` : String(option.value)}</span>
              </span>
              <span className="shrink-0 tabular-nums text-muted">{formatNumber(option.count)}</span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
