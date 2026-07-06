import { Area, AreaChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { TimePoint } from "../types";
import { prefersReducedMotion } from "../lib/utils";

/**
 * Ledger area chart: hairline axes, soft monochrome gradient, no chrome.
 * `tone="accent"` is reserved for the page's hero series (words/day).
 */
export function AreaTrend({ data, tone = "ink", label }: { data: TimePoint[]; tone?: "accent" | "ink"; label: string }) {
  const color = tone === "accent" ? "var(--color-accent)" : "var(--color-ink)";
  const gradientId = `grad-${tone}`;
  return (
    <div role="img" aria-label={label}>
      <ResponsiveContainer width="100%" height={200}>
        <AreaChart data={data} margin={{ top: 8, right: 8, left: -18, bottom: 0 }} accessibilityLayer={false}>
          <defs>
            <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor={color} stopOpacity={0.28} />
              <stop offset="95%" stopColor={color} stopOpacity={0} />
            </linearGradient>
          </defs>
          <XAxis
            dataKey="day"
            tickFormatter={(d: string) => d.slice(5)}
            fontSize={10}
            fontFamily="var(--font-mono)"
            stroke="var(--color-muted)"
            tickLine={false}
            axisLine={false}
            minTickGap={24}
          />
          <YAxis
            fontSize={10}
            fontFamily="var(--font-mono)"
            stroke="var(--color-muted)"
            tickLine={false}
            axisLine={false}
            width={40}
          />
          <Tooltip
            contentStyle={{
              background: "var(--color-paper)",
              border: "1px solid var(--color-line)",
              borderRadius: 8,
              fontSize: 12,
              fontFamily: "var(--font-mono)",
              color: "var(--color-ink)",
            }}
            labelStyle={{ color: "var(--color-muted)" }}
            cursor={{ stroke: "var(--color-line)" }}
          />
          <Area
            type="monotone"
            dataKey="value"
            stroke={color}
            strokeWidth={1.5}
            fill={`url(#${gradientId})`}
            isAnimationActive={!prefersReducedMotion}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
