import type { Breakdown } from "../types";
import { formatNumber } from "../lib/utils";

export function BreakdownList({ items }: { items: Breakdown[] }) {
  const max = Math.max(1, ...items.map((i) => i.value));
  if (items.length === 0) {
    return <p className="mt-3 text-xs" style={{ color: "var(--color-muted)" }}>No data yet</p>;
  }
  return (
    <div className="mt-3 space-y-2">
      {items.map((item) => (
        <div key={item.label} className="space-y-1">
          <div className="flex justify-between font-mono text-xs">
            <span className="text-foreground/80">{item.label || "unknown"}</span>
            <span style={{ color: "var(--color-muted)" }}>{formatNumber(item.value)}</span>
          </div>
          <div className="h-1.5 overflow-hidden rounded-full" style={{ background: "var(--color-border)" }}>
            <div
              className="h-full rounded-full"
              style={{ width: `${(item.value / max) * 100}%`, background: "var(--color-chart-1)" }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}
