import type { TimePoint } from "../types";

/** Tiny inline trend — decoration for a KeyFigure, hidden from readers. */
export function Sparkline({ data, width = 72, height = 20 }: { data: TimePoint[]; width?: number; height?: number }) {
  if (data.length < 2) return null;
  const max = Math.max(...data.map((p) => p.value), 1);
  const step = width / (data.length - 1);
  const points = data
    .map((p, i) => `${(i * step).toFixed(1)},${(height - (p.value / max) * (height - 2) - 1).toFixed(1)}`)
    .join(" ");
  return (
    <svg width={width} height={height} aria-hidden className="text-accent">
      <polyline points={points} fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  );
}
