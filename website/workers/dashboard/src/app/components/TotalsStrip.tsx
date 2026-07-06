import type { ReactNode } from "react";
import { cn } from "../lib/utils";

/**
 * The receipt's subtotal line: a `dl` of key figures in tabular Fragment Mono.
 * This strip is the page's signature — everything below explains these numbers.
 */
export function TotalsStrip({ children }: { children: ReactNode }) {
  return <dl className="grid grid-cols-2 gap-x-8 gap-y-6 md:grid-cols-4">{children}</dl>;
}

export function KeyFigure({
  label,
  value,
  detail,
  accent = false,
  extra,
}: {
  label: string;
  value: string;
  /** Small mono annotation under the figure (Δ, "+N new", …). */
  detail?: string;
  accent?: boolean;
  /** Inline decoration next to the detail (e.g. a sparkline). */
  extra?: ReactNode;
}) {
  return (
    <div>
      <dt className="font-mono text-[11px] uppercase tracking-[0.16em] text-muted">{label}</dt>
      <dd className={cn("mt-1.5 font-mono text-[1.75rem] leading-none tabular-nums", accent ? "text-accent" : "text-ink")}>
        {value}
      </dd>
      {(detail || extra) && (
        <dd className="mt-2 flex items-center gap-2 font-mono text-[11px] tabular-nums text-muted">
          {extra}
          {detail && <span>{detail}</span>}
        </dd>
      )}
    </div>
  );
}
