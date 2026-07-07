import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AreaTrend } from "./components/AreaTrend";
import { BreakdownList } from "./components/BreakdownList";
import { EmptyState } from "./components/EmptyState";
import { FilterBar } from "./components/FilterBar";
import { LatencyBars } from "./components/LatencyBars";
import { MiniBars } from "./components/MiniBars";
import { Section } from "./components/Section";
import { Skeleton } from "./components/Skeleton";
import { KeyFigure, TotalsStrip } from "./components/TotalsStrip";
import { Sparkline } from "./components/Sparkline";
import { deltaPct, formatCount, formatPct, relativeTime } from "./lib/utils";
import type { FilterDim, Filters, StatsResponse } from "./types";

const RANGES = [7, 30, 90];

/** "Not recorded under {dim}" copy — the server decides WHICH panels are blocked. */
const notRecorded = (dim: FilterDim) => `Not recorded under the ${dim.replace("_", " ")} filter.`;

export default function App() {
  const [range, setRange] = useState(30);
  const [filters, setFilters] = useState<Filters>({});
  const [stats, setStats] = useState<StatsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [fetchedAt, setFetchedAt] = useState<number | null>(null);
  const [retryNonce, setRetryNonce] = useState(0);
  const rangeRefs = useRef<Array<HTMLButtonElement | null>>([]);

  // Re-render each minute so the "updated Xm ago" stamp stays honest.
  const [, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 60_000);
    return () => clearInterval(id);
  }, []);

  // `silent` = a background refresh (poll / tab-focus): update the data in place
  // without the loading skeleton or clobbering the view with a transient error.
  const fetchStats = useCallback(async (silent: boolean, signal: AbortSignal) => {
    if (!silent) {
      setLoading(true);
      setError(null);
    }
    const params = new URLSearchParams({ range: String(range) });
    for (const [dim, value] of Object.entries(filters)) {
      if (value) params.set(dim, value);
    }
    try {
      const r = await fetch(`/api/stats?${params}`, { signal });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const data = (await r.json()) as StatsResponse;
      setStats(data);
      setFetchedAt(Date.now());
      setError(null);
    } catch (e) {
      if (!signal.aborted && !silent) setError(String(e));
    } finally {
      if (!signal.aborted && !silent) setLoading(false);
    }
  }, [range, filters]);

  // Foreground load: on range / filter change and manual retry.
  useEffect(() => {
    const controller = new AbortController();
    fetchStats(false, controller.signal);
    return () => controller.abort();
  }, [fetchStats, retryNonce]);

  // Keep it live: silently refresh every 15s while the tab is visible, and
  // immediately on tab focus / visibility, so returning to the tab is current.
  useEffect(() => {
    const controller = new AbortController();
    const refresh = () => {
      if (document.visibilityState === "visible") fetchStats(true, controller.signal);
    };
    const id = window.setInterval(refresh, 15_000);
    document.addEventListener("visibilitychange", refresh);
    window.addEventListener("focus", refresh);
    return () => {
      window.clearInterval(id);
      controller.abort();
      document.removeEventListener("visibilitychange", refresh);
      window.removeEventListener("focus", refresh);
    };
  }, [fetchStats]);

  // Defensive: a stale/cached response without `blocked` must degrade to
  // "nothing blocked", never crash the whole dashboard.
  const blocked = stats?.blocked ?? {};

  const totalWords = useMemo(
    () => stats?.wordsPerDay.reduce((sum, p) => sum + p.value, 0) ?? 0,
    [stats]
  );
  const newInstalls = useMemo(
    () => stats?.newInstallsPerDay.reduce((sum, p) => sum + p.value, 0) ?? 0,
    [stats]
  );
  const wordsDelta = stats ? deltaPct(stats.wordsPerDay, stats.rangeDays) : null;

  const onRangeKeyDown = (event: React.KeyboardEvent, index: number) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    const next = (index + (event.key === "ArrowRight" ? 1 : -1) + RANGES.length) % RANGES.length;
    setRange(RANGES[next]);
    rangeRefs.current[next]?.focus();
  };

  return (
    <div className="mx-auto max-w-6xl px-6 pb-16">
      <header className="sticky top-0 z-10 -mx-6 border-b border-line bg-paper/95 px-6 py-4 backdrop-blur">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h1 className="font-mono text-sm uppercase tracking-[0.2em] text-ink">
            Suniye <span className="text-muted">·</span> Analytics
          </h1>
          <div className="flex items-center gap-4">
            <p className="hidden font-mono text-[11px] text-muted sm:block" aria-live="polite">
              {loading ? "updating…" : fetchedAt ? `updated ${relativeTime(fetchedAt)}` : "loading…"}
            </p>
            <div role="radiogroup" aria-label="Time range" className="flex rounded-lg border border-line p-0.5">
              {RANGES.map((r, i) => (
                <button
                  key={r}
                  ref={(el) => { rangeRefs.current[i] = el; }}
                  role="radio"
                  aria-checked={r === range}
                  tabIndex={r === range ? 0 : -1}
                  onClick={() => setRange(r)}
                  onKeyDown={(e) => onRangeKeyDown(e, i)}
                  className={
                    r === range
                      ? "rounded-md bg-ink px-3 py-1 font-mono text-xs text-paper"
                      : "rounded-md px-3 py-1 font-mono text-xs text-muted hover:text-ink"
                  }
                >
                  {r}d
                </button>
              ))}
            </div>
          </div>
        </div>
      </header>

      <main>
        {stats && (
          <FilterBar
            options={stats.filterOptions}
            filters={filters}
            segmentCount={loading ? null : stats.segmentEventCount}
            onChange={(dim, value) =>
              setFilters((prev) => {
                const next = { ...prev };
                if (value) next[dim] = value;
                else delete next[dim];
                return next;
              })
            }
            onClear={() => setFilters({})}
          />
        )}

        {error && (
          <div className="border-t border-line py-6" role="alert">
            <p className="text-sm text-ink">Couldn't load stats ({error}).</p>
            <button
              onClick={() => setRetryNonce((n) => n + 1)}
              className="mt-3 rounded-md border border-line px-3 py-1.5 font-mono text-xs text-ink hover:bg-surface"
            >
              Retry
            </button>
          </div>
        )}

        {!stats && !error && (
          // First load: reserve the page's shape so data doesn't shift the layout.
          <div className="space-y-6 pt-6" aria-hidden>
            <div className="grid grid-cols-2 gap-8 md:grid-cols-4">
              {[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-20" />)}
            </div>
            <Skeleton className="h-52" />
            <Skeleton className="h-40" />
            <Skeleton className="h-40" />
          </div>
        )}

        {stats && (
          <>
            <div className="border-t border-line py-7">
              <TotalsStrip>
                <KeyFigure
                  label="Words dictated"
                  value={formatCount(totalWords)}
                  accent
                  extra={<Sparkline data={stats.wordsPerDay} />}
                  detail={wordsDelta === null ? undefined : `${wordsDelta >= 0 ? "+" : ""}${wordsDelta.toFixed(0)}% vs prior half`}
                />
                <KeyFigure
                  label="Installs"
                  value={blocked.installs ? "—" : formatCount(stats.totalInstalls)}
                  detail={
                    blocked.installs
                      ? notRecorded(blocked.installs)
                      : newInstalls > 0 ? `+${formatCount(newInstalls)} new in window` : "all-time"
                  }
                />
                <KeyFigure
                  label="Magic Format"
                  value={stats.magicFormatAdoptionPct === null ? "—" : formatPct(stats.magicFormatAdoptionPct)}
                  detail={stats.magicFormatAdoptionPct === null ? "no dictations yet" : "of dictations polished"}
                />
                <KeyFigure
                  label="Crash-free"
                  value={blocked.crash || stats.crashFreeRatePct === null ? "—" : formatPct(stats.crashFreeRatePct, 1)}
                  detail={
                    blocked.crash ? notRecorded(blocked.crash)
                      : stats.crashFreeRatePct === null ? "not enough sessions yet"
                      : "clean session proxy"
                  }
                />
              </TotalsStrip>
            </div>

            <Section eyebrow="Usage" note="bucketed on device time · sampling-corrected">
              <div className="grid gap-8 md:grid-cols-3">
                <div>
                  <h3 className="mb-2 text-sm text-ink">Words / day</h3>
                  {stats.wordsPerDay.length > 0
                    ? <AreaTrend data={stats.wordsPerDay} tone="accent" label="Words dictated per day" />
                    : <EmptyState message="No dictations in this window yet." className="min-h-[200px]" />}
                </div>
                <div>
                  <h3 className="mb-2 text-sm text-ink">Active installs / day</h3>
                  {blocked.activeInstalls ? (
                    <EmptyState message={notRecorded(blocked.activeInstalls)} className="min-h-[200px]" />
                  ) : stats.activeInstallsPerDay.length > 0 ? (
                    <AreaTrend data={stats.activeInstallsPerDay} label="Active installs per day" />
                  ) : (
                    <EmptyState message="No activity in this window yet." className="min-h-[200px]" />
                  )}
                </div>
                <div>
                  <h3 className="mb-2 text-sm text-ink">New installs / day</h3>
                  {blocked.installs ? (
                    <EmptyState message={notRecorded(blocked.installs)} className="min-h-[200px]" />
                  ) : stats.newInstallsPerDay.length > 0 ? (
                    <MiniBars data={stats.newInstallsPerDay} />
                  ) : (
                    <EmptyState message="No new installs in this window." className="min-h-[200px]" />
                  )}
                </div>
              </div>
            </Section>

            <Section
              eyebrow="Pipeline latency"
              note={
                blocked.modelLoad
                  ? `model load ${notRecorded(blocked.modelLoad).toLowerCase()}`
                  : stats.keepAliveEvictions > 0
                    ? `${formatCount(stats.keepAliveEvictions)} keep-alive evictions`
                    : undefined
              }
            >
              <LatencyBars stages={stats.latency} />
            </Section>

            <Section eyebrow="Quality">
              <div className="grid gap-8 md:grid-cols-3">
                <div>
                  <h3 className="mb-2 text-sm text-ink">Magic Format fallbacks</h3>
                  <BreakdownList
                    items={stats.fallbackReasons}
                    emptyMessage="No fallbacks — every polish ran."
                  />
                </div>
                <div>
                  <h3 className="mb-2 text-sm text-ink">Edits after insertion</h3>
                  {blocked.edits ? (
                    <EmptyState message={notRecorded(blocked.edits)} />
                  ) : stats.editedSharePct === null ? (
                    <EmptyState message="No edited dictations in this window yet." />
                  ) : (
                    <>
                      <p className="font-mono text-2xl tabular-nums text-ink">{formatPct(stats.editedSharePct)}</p>
                      <p className="mt-1 font-mono text-[11px] text-muted">
                        of dictations were edited after insertion · median edit reshaped {formatPct(stats.editRateMedianPct)} of the text
                      </p>
                    </>
                  )}
                </div>
                <div>
                  <h3 className="mb-2 text-sm text-ink">Audio backend</h3>
                  {blocked.audio ? (
                    <EmptyState message={notRecorded(blocked.audio)} />
                  ) : (
                    <>
                      <BreakdownList items={stats.audioBackends} emptyMessage="No capture data in this window." />
                      {stats.audioBackends.length > 0 && (
                        <p className="mt-2 font-mono text-[11px] text-muted">
                          fell back to a lower rung on {formatPct(stats.audioFallbackRatePct, 1)} of captures
                        </p>
                      )}
                    </>
                  )}
                </div>
              </div>
            </Section>

            <Section eyebrow="Fleet" note="installs active in window">
              <div className="grid gap-8 sm:grid-cols-2 md:grid-cols-4">
                <div>
                  <h3 className="mb-2 text-sm text-ink">ASR model</h3>
                  <BreakdownList items={stats.asrModelBreakdown} />
                </div>
                {(
                  [
                    ["Chip", stats.chipBreakdown],
                    ["RAM (GB)", stats.ramBreakdown],
                    ["Country", stats.countryBreakdown],
                  ] as const
                ).map(([title, items]) => (
                  <div key={title}>
                    <h3 className="mb-2 text-sm text-ink">{title}</h3>
                    {blocked.installs
                      ? <EmptyState message={notRecorded(blocked.installs)} />
                      : <BreakdownList items={items} />}
                  </div>
                ))}
              </div>
            </Section>

            <Section eyebrow="Reliability">
              {blocked.errors ? (
                <EmptyState message={notRecorded(blocked.errors)} />
              ) : (
                <BreakdownList items={stats.errorsByType} emptyMessage="No errors in this window." />
              )}
            </Section>
          </>
        )}
      </main>
    </div>
  );
}
