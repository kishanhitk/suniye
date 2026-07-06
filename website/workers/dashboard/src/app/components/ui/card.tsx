import type { ReactNode } from "react";
import { cn } from "../../lib/utils";

export function Card({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <div className={cn("rounded-xl border bg-card p-5 shadow-sm", className)} style={{ borderColor: "var(--color-border)" }}>
      {children}
    </div>
  );
}

export function CardTitle({ children }: { children: ReactNode }) {
  return <h3 className="text-sm font-medium text-foreground/90">{children}</h3>;
}

export function CardSubtitle({ children }: { children: ReactNode }) {
  return <p className="mt-0.5 text-xs" style={{ color: "var(--color-muted)" }}>{children}</p>;
}
