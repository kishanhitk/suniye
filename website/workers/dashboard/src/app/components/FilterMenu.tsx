import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { FilterDim, Filters, StatsResponse } from "../types";
import { DIM_GROUPS, DIM_LABEL } from "./filterMeta";

type Item =
  | { kind: "header"; label: string }
  | { kind: "dim"; dim: FilterDim; sel: number }
  | { kind: "value"; dim: FilterDim; value: string; sel: number };

/**
 * The "add filter" popover. Browse dimensions by group, or type to jump straight
 * to a value across all dimensions (collapsing the pick-dimension-then-value
 * two-step). Keyboard-first: ↑/↓ move, ↵ selects, Esc/Backspace steps back.
 * Stays open after adding so several filters can be set in one session.
 */
export function FilterMenu({
  options,
  filters,
  onSelect,
  onClose,
}: {
  options: StatsResponse["filterOptions"];
  filters: Filters;
  onSelect: (dim: FilterDim, value: string) => void;
  onClose: () => void;
}) {
  const [query, setQuery] = useState("");
  const [drill, setDrill] = useState<FilterDim | null>(null);
  const [highlight, setHighlight] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const q = query.trim().toLowerCase();

  useEffect(() => { inputRef.current?.focus(); }, []);

  // Close on outside click.
  useEffect(() => {
    const onDown = (e: MouseEvent) => {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) onClose();
    };
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [onClose]);

  const { items, count } = useMemo(() => {
    const addable = (dim: FilterDim) => (options[dim]?.length ?? 0) > 0 && !filters[dim];
    const items: Item[] = [];
    let sel = 0;
    const dimRow = (dim: FilterDim) => items.push({ kind: "dim", dim, sel: sel++ });
    const valRow = (dim: FilterDim, value: string) => items.push({ kind: "value", dim, value, sel: sel++ });

    if (drill) {
      for (const v of (options[drill] ?? []).map(String)) {
        if (!q || v.toLowerCase().includes(q)) valRow(drill, v);
      }
    } else if (q) {
      for (const { dims } of DIM_GROUPS) for (const dim of dims) {
        if (!addable(dim)) continue;
        for (const v of (options[dim] ?? []).map(String)) if (v.toLowerCase().includes(q)) valRow(dim, v);
      }
      for (const { dims } of DIM_GROUPS) for (const dim of dims) {
        if (addable(dim) && DIM_LABEL[dim].includes(q)) dimRow(dim);
      }
    } else {
      for (const group of DIM_GROUPS) {
        const groupDims = group.dims.filter(addable);
        if (groupDims.length === 0) continue;
        items.push({ kind: "header", label: group.label });
        groupDims.forEach(dimRow);
      }
    }
    return { items, count: sel };
  }, [options, filters, drill, q]);

  // Keep the highlight in range whenever the list changes.
  useLayoutEffect(() => { setHighlight((h) => Math.min(Math.max(h, 0), Math.max(count - 1, 0))); }, [count]);

  const selectable = items.filter((i): i is Extract<Item, { sel: number }> => i.kind !== "header");
  const choose = (item: Extract<Item, { sel: number }>) => {
    if (item.kind === "dim") { setDrill(item.dim); setQuery(""); setHighlight(0); }
    else { onSelect(item.dim, item.value); setDrill(null); setQuery(""); setHighlight(0); }
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowDown") { e.preventDefault(); setHighlight((h) => Math.min(h + 1, count - 1)); }
    else if (e.key === "ArrowUp") { e.preventDefault(); setHighlight((h) => Math.max(h - 1, 0)); }
    else if (e.key === "Enter") { e.preventDefault(); const it = selectable[highlight]; if (it) choose(it); }
    else if (e.key === "Escape") { e.preventDefault(); if (drill) { setDrill(null); setQuery(""); } else onClose(); }
    else if (e.key === "Backspace" && !query && drill) { e.preventDefault(); setDrill(null); }
  };

  return (
    <div ref={rootRef} className="absolute left-0 top-full z-20 mt-1 w-72 overflow-hidden rounded-lg border border-line bg-paper shadow-md">
      <input
        ref={inputRef}
        value={query}
        onChange={(e) => { setQuery(e.target.value); setHighlight(0); }}
        onKeyDown={onKeyDown}
        placeholder={drill ? `${DIM_LABEL[drill]}…` : "filter by dimension or value…"}
        aria-label="Filter by dimension or value"
        className="w-full border-b border-line bg-transparent px-3 py-2 font-mono text-xs text-ink outline-none placeholder:text-muted"
      />
      <ul role="listbox" className="max-h-72 overflow-y-auto py-1">
        {count === 0 && <li className="px-3 py-2 font-mono text-xs text-muted">no matches</li>}
        {items.map((item, i) => {
          if (item.kind === "header") {
            return <li key={`h-${item.label}`} className="px-3 pb-1 pt-2 font-mono text-[10px] uppercase tracking-[0.16em] text-muted">{item.label}</li>;
          }
          const on = item.sel === highlight;
          return (
            <li
              key={item.kind === "value" ? `v-${item.dim}-${item.value}` : `d-${item.dim}-${i}`}
              role="option"
              aria-selected={on}
              onMouseEnter={() => setHighlight(item.sel)}
              onClick={() => choose(item)}
              className={`flex cursor-pointer items-center justify-between gap-3 px-3 py-1.5 font-mono text-xs ${on ? "bg-surface text-ink" : "text-ink"}`}
            >
              {item.kind === "dim" ? (
                <><span>{DIM_LABEL[item.dim]}</span><span className="text-muted">›</span></>
              ) : (
                <>
                  <span className="truncate">{drill ? item.value : `${DIM_LABEL[item.dim]} = ${item.value}`}</span>
                  {on && <span className="text-accent">↵</span>}
                </>
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
