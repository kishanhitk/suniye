import { Area, AreaChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { TimePoint } from "../types";

// shadcn-style area chart: soft vertical gradient fill, hairline axes, minimal
// chrome. https://ui.shadcn.com/charts/area
export function AreaTrend({ data, color = "var(--color-chart-1)" }: { data: TimePoint[]; color?: string }) {
  const gradientId = `grad-${color.replace(/[^a-z0-9]/gi, "")}`;
  return (
    <ResponsiveContainer width="100%" height={200}>
      <AreaChart data={data} margin={{ top: 8, right: 8, left: -18, bottom: 0 }}>
        <defs>
          <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor={color} stopOpacity={0.4} />
            <stop offset="95%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        <XAxis
          dataKey="day"
          tickFormatter={(d: string) => d.slice(5)}
          fontSize={11}
          stroke="var(--color-muted)"
          tickLine={false}
          axisLine={false}
          minTickGap={24}
        />
        <YAxis fontSize={11} stroke="var(--color-muted)" tickLine={false} axisLine={false} width={40} />
        <Tooltip
          contentStyle={{
            background: "var(--color-card)",
            border: "1px solid var(--color-border)",
            borderRadius: 8,
            fontSize: 12,
          }}
          labelStyle={{ color: "var(--color-muted)" }}
        />
        <Area type="monotone" dataKey="value" stroke={color} strokeWidth={2} fill={`url(#${gradientId})`} />
      </AreaChart>
    </ResponsiveContainer>
  );
}
