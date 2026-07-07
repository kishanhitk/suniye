import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";
import type { TimePoint } from "../types";

export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

/** Computed once: charts skip entrance animation under reduced motion. */
export const prefersReducedMotion =
  typeof window !== "undefined" && !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

const countFormatter = new Intl.NumberFormat("en-US");

/** Full-precision count with thousands separators — the ledger figure style. */
export function formatCount(value: number): string {
  return countFormatter.format(Math.round(value));
}

/** Compact count for tight spots (axis ticks, breakdown rows). */
export function formatNumber(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}k`;
  return `${Math.round(value)}`;
}

/** Milliseconds, promoted to seconds past 10s so long values stay readable. */
export function formatMs(value: number): string {
  if (value >= 10_000) return `${(value / 1000).toFixed(1)}s`;
  return `${Math.round(value)}ms`;
}

export function formatPct(value: number, digits = 0): string {
  return `${value.toFixed(digits)}%`;
}

/** "just now" / "2m ago" / "1h ago" — for the header's updated stamp. */
export function relativeTime(fromMs: number, nowMs: number = Date.now()): string {
  const seconds = Math.max(0, Math.round((nowMs - fromMs) / 1000));
  if (seconds < 45) return "just now";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  return `${hours}h ago`;
}

/**
 * Percent change of a daily series: second half of the window vs the first,
 * split on the date midpoint (not the array midpoint — days with no data are
 * absent from the series). Null when the first half has no data to compare.
 */
export function deltaPct(points: TimePoint[], rangeDays: number, nowMs: number = Date.now()): number | null {
  if (points.length === 0) return null;
  const midDay = new Date(nowMs - (rangeDays / 2) * 86_400_000).toISOString().slice(0, 10);
  let first = 0;
  let second = 0;
  for (const p of points) {
    if (p.day < midDay) first += p.value;
    else second += p.value;
  }
  if (first <= 0) return null;
  return ((second - first) / first) * 100;
}
