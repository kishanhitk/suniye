import { cn } from "../lib/utils";

/** An honest empty: says what's missing, not just a blank. */
export function EmptyState({ message, className }: { message: string; className?: string }) {
  return (
    <div className={cn("flex min-h-16 items-center", className)}>
      <p className="text-sm text-muted">{message}</p>
    </div>
  );
}
