import { useEffect, useState } from "react";
import { AreaTrend } from "./components/AreaTrend";
import { BreakdownList } from "./components/BreakdownList";
import { StatTile } from "./components/StatTile";
import { Card, CardSubtitle, CardTitle } from "./components/ui/card";
import { formatNumber } from "./lib/utils";
import type { StatsResponse } from "./types";

const RANGES = [7, 30, 90];

export default function App() {
  const [range, setRange] = useState(30);
  const [stats, setStats] = useState<StatsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetch(`/api/stats?range=${range}`)
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((data: StatsResponse) => !cancelled && setStats(data))
      .catch((e) => !cancelled && setError(String(e)))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [range]);

  const totalWords = stats?.wordsPerDay.reduce((sum, p) => sum + p.value, 0) ?? 0;

  return (
    <div className="mx-auto max-w-6xl px-6 py-10">
      <header className="mb-8 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Suniye Analytics</h1>
          <p className="mt-1 text-sm" style={{ color: "var(--color-muted)" }}>
            Anonymous usage — content stays on the device, only counts leave.
          </p>
        </div>
        <div className="flex gap-1 rounded-lg border p-1">
          {RANGES.map((r) => (
            <button
              key={r}
              onClick={() => setRange(r)}
              className="rounded-md px-3 py-1 font-mono text-xs transition-colors"
              style={{
                background: r === range ? "var(--color-primary)" : "transparent",
                color: r === range ? "#04120f" : "var(--color-muted)",
              }}
            >
              {r}d
            </button>
          ))}
        </div>
      </header>

      {loading && <p style={{ color: "var(--color-muted)" }}>Loading…</p>}
      {error && (
        <Card>
          <p className="text-sm text-red-400">Couldn't load stats: {error}</p>
        </Card>
      )}

      {stats && (
        <div className="space-y-5">
          <div className="grid grid-cols-2 gap-5 md:grid-cols-4">
            <StatTile label="Total installs" value={formatNumber(stats.totalInstalls)} />
            <StatTile label="Words dictated" value={formatNumber(totalWords)} />
            <StatTile label="Magic Format" value={stats.magicFormatAdoptionPct.toFixed(0)} suffix="%" />
            <StatTile label="Crash proxy" value={stats.crashProxyRatePct.toFixed(1)} suffix="%" />
          </div>

          <div className="grid gap-5 md:grid-cols-2">
            <Card>
              <CardTitle>Words dictated / day</CardTitle>
              <CardSubtitle>bucketed on device timestamp, sampling-corrected</CardSubtitle>
              <div className="mt-4">
                <AreaTrend data={stats.wordsPerDay} />
              </div>
            </Card>
            <Card>
              <CardTitle>Active installs / day</CardTitle>
              <CardSubtitle>distinct install ids</CardSubtitle>
              <div className="mt-4">
                <AreaTrend data={stats.activeInstallsPerDay} color="var(--color-chart-3)" />
              </div>
            </Card>
          </div>

          <div className="grid gap-5 md:grid-cols-3">
            <Card>
              <CardTitle>ASR model</CardTitle>
              <BreakdownList items={stats.asrModelBreakdown} />
            </Card>
            <Card>
              <CardTitle>Chip</CardTitle>
              <BreakdownList items={stats.chipBreakdown} />
            </Card>
            <Card>
              <CardTitle>RAM (GB)</CardTitle>
              <BreakdownList items={stats.ramBreakdown} />
            </Card>
          </div>

          <Card>
            <CardTitle>Pipeline latency (ms)</CardTitle>
            <CardSubtitle>p50 / p95 by stage — the number users feel is end_to_end</CardSubtitle>
            <div className="mt-4 grid grid-cols-3 gap-4">
              {stats.latency.map((l) => (
                <div key={l.stage} className="rounded-lg border p-3">
                  <div className="font-mono text-xs" style={{ color: "var(--color-muted)" }}>{l.stage}</div>
                  <div className="mt-1 font-mono">
                    <span className="text-lg font-semibold">{Math.round(l.p50)}</span>
                    <span className="text-xs" style={{ color: "var(--color-muted)" }}> / {Math.round(l.p95)}</span>
                  </div>
                </div>
              ))}
            </div>
          </Card>

          <div className="grid gap-5 md:grid-cols-2">
            <Card>
              <CardTitle>Countries</CardTitle>
              <BreakdownList items={stats.countryBreakdown} />
            </Card>
            <Card>
              <CardTitle>Errors by type</CardTitle>
              <BreakdownList items={stats.errorsByType} />
            </Card>
          </div>
        </div>
      )}
    </div>
  );
}
