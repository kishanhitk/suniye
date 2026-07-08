import { useEffect, useState } from "react";
import { AreaTrend } from "./components/AreaTrend";
import { BreakdownList } from "./components/BreakdownList";
import { EmptyState } from "./components/EmptyState";
import { Section } from "./components/Section";
import { Skeleton } from "./components/Skeleton";
import { KeyFigure, TotalsStrip } from "./components/TotalsStrip";
import { formatCount, formatPct } from "./lib/utils";
import type { WebStats } from "./types";

/**
 * The Web tab: first-party site analytics (visitors, downloads, funnel,
 * acquisition, engagement). Mirrors the App tab's ledger layout and reuses
 * its primitives — no bespoke chart components.
 */
export function WebView({ range }: { range: number }) {
  const [stats, setStats] = useState<WebStats | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    setError(null);
    fetch(`/api/web-stats?range=${range}`)
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((d) => alive && setStats(d as WebStats))
      .catch((e) => alive && setError(String(e)));
    return () => {
      alive = false;
    };
  }, [range]);

  if (error) {
    return (
      <div className="border-t border-line py-6" role="alert">
        <p className="text-sm text-ink">Couldn't load web stats ({error}).</p>
      </div>
    );
  }

  if (!stats) {
    return (
      <div className="space-y-6 pt-6" aria-hidden>
        <div className="grid grid-cols-2 gap-8 md:grid-cols-4">
          {[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-20" />)}
        </div>
        <Skeleton className="h-52" />
        <Skeleton className="h-40" />
        <Skeleton className="h-40" />
      </div>
    );
  }

  return (
    <>
      <div className="border-t border-line py-7">
        <TotalsStrip>
          <KeyFigure label="Visitors" value={formatCount(stats.visitors)} accent />
          <KeyFigure label="Pageviews" value={formatCount(stats.pageviews)} />
          <KeyFigure label="Downloads" value={formatCount(stats.downloads)} />
          <KeyFigure
            label="Conversion"
            value={formatPct(stats.conversionPct, 1)}
            detail="downloads / pageviews"
          />
        </TotalsStrip>
      </div>

      <Section eyebrow="Visitors" note="unique visitors per day">
        {stats.visitorsSeries.length > 0
          ? <AreaTrend data={stats.visitorsSeries} tone="accent" label="Unique visitors per day" />
          : <EmptyState message="No visits in this window yet." className="min-h-[200px]" />}
      </Section>

      <Section eyebrow="Acquisition">
        <div className="grid gap-8 md:grid-cols-3">
          <div>
            <h3 className="mb-2 text-sm text-ink">Top sources</h3>
            <BreakdownList items={stats.topSources} emptyMessage="No referrer data in this window." />
          </div>
          <div>
            <h3 className="mb-2 text-sm text-ink">Top pages</h3>
            <BreakdownList items={stats.topPages} emptyMessage="No pageviews in this window." />
          </div>
          <div>
            <h3 className="mb-2 text-sm text-ink">Campaigns</h3>
            <BreakdownList items={stats.campaigns} emptyMessage="No campaign-tagged visits in this window." />
          </div>
        </div>
      </Section>

      <Section eyebrow="Downloads" note="by target">
        <BreakdownList items={stats.downloadsByTarget} emptyMessage="No downloads in this window." />
      </Section>

      <Section eyebrow="Engagement" note="scroll depth">
        <BreakdownList items={stats.scrollDepth} emptyMessage="No scroll-depth data in this window." />
      </Section>

      <Section eyebrow="Audience">
        <div className="grid gap-8 sm:grid-cols-2">
          <div>
            <h3 className="mb-2 text-sm text-ink">Country</h3>
            <BreakdownList items={stats.countries} emptyMessage="No country data in this window." />
          </div>
          <div>
            <h3 className="mb-2 text-sm text-ink">Device</h3>
            <BreakdownList items={stats.devices} emptyMessage="No device data in this window." />
          </div>
        </div>
      </Section>
    </>
  );
}
