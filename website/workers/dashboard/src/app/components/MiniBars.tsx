import type { TimePoint } from "../types";

/** Small per-day bar chart (new installs) — one bar per day with data. */
export function MiniBars({ data, height = 200 }: { data: TimePoint[]; height?: number }) {
  const max = Math.max(...data.map((p) => p.value), 1);
  return (
    <div className="flex items-end gap-1" style={{ height }} role="img" aria-label={`${data.length} days with new installs`}>
      {data.map((p) => (
        <div
          key={p.day}
          title={`${p.day}: ${p.value}`}
          className="min-w-2 flex-1 rounded-t-sm bg-ink/55"
          style={{ height: `${Math.max(4, (p.value / max) * 100)}%` }}
        />
      ))}
    </div>
  );
}
