import type { ReactNode } from "react";
import { cn } from "../lib/utils";

/**
 * A ledger section: hairline top rule + a tracked mono eyebrow. Sections are
 * ruled, not boxed — the page reads as one continuous receipt.
 */
export function Section({
  eyebrow,
  note,
  children,
  className,
}: {
  eyebrow: string;
  /** Optional right-aligned annotation (e.g. a unit or caveat). */
  note?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={cn("border-t border-line py-6", className)}>
      <div className="mb-4 flex items-baseline justify-between gap-4">
        <h2 className="font-mono text-[11px] uppercase tracking-[0.16em] text-muted">{eyebrow}</h2>
        {note && <p className="font-mono text-[11px] text-muted">{note}</p>}
      </div>
      {children}
    </section>
  );
}
