import { cn } from "../lib/utils";

/** Loading placeholder that reserves the final height — no layout shift. */
export function Skeleton({ className }: { className?: string }) {
  return <div aria-hidden className={cn("animate-pulse rounded-md bg-surface", className)} />;
}
