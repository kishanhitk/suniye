import type { Breakdown } from "../types";
import { formatNumber } from "../lib/utils";
import { EmptyState } from "./EmptyState";

/**
 * Ranked ledger rows: label · proportional bar · right-aligned tabular count.
 * Monochrome by design — rank is carried by order and bar length, not color.
 */
export function BreakdownList({ items, emptyMessage = "No data in this window yet." }: { items: Breakdown[]; emptyMessage?: string }) {
  if (items.length === 0) {
    return <EmptyState message={emptyMessage} />;
  }
  const max = Math.max(1, ...items.map((i) => i.value));
  return (
    <ul className="space-y-2.5">
      {items.map((item) => (
        <li key={item.label} className="grid grid-cols-[minmax(0,10rem)_1fr_3.5rem] items-center gap-3">
          <span className="truncate font-mono text-xs text-ink" title={item.label || "unknown"}>
            {item.label || "unknown"}
          </span>
          <div className="h-1.5 overflow-hidden rounded-full bg-surface">
            <div className="h-full rounded-full bg-ink/45" style={{ width: `${(item.value / max) * 100}%` }} />
          </div>
          <span className="text-right font-mono text-xs tabular-nums text-muted">{formatNumber(item.value)}</span>
        </li>
      ))}
    </ul>
  );
}
