import type { WebDataPoint, WebEvent, WebPropValue } from "./schema";

export interface WebEnrichment {
  referrerHost: string;
  country: string;
  visitorHash: string;
}

const s = (p: Record<string, WebPropValue>, key: string): string | null =>
  typeof p[key] === "string" ? (p[key] as string) : null;
const firstS = (p: Record<string, WebPropValue>, ...keys: string[]): string | null => {
  for (const k of keys) if (typeof p[k] === "string") return p[k] as string;
  return null;
};
const n = (p: Record<string, WebPropValue>, key: string): number | undefined =>
  typeof p[key] === "number" ? (p[key] as number) : undefined;

/**
 * One Analytics Engine data point per event. Slots are POSITIONAL and
 * append-only (see plan Global Constraints). blob1 is always the event name;
 * blob20 always carries the full props JSON so a field is never lost before it
 * earns a slot. doubles are built dense from double1; scroll depth rides double2.
 */
export function buildWebDataPoint(event: WebEvent, enrich: WebEnrichment): WebDataPoint {
  const p = event.props;
  const blobs: (string | null)[] = [
    event.name,                                   // blob1
    s(p, "path"),                                 // blob2
    enrich.referrerHost || null,                  // blob3
    s(p, "utm_source"),                           // blob4
    s(p, "utm_medium"),                           // blob5
    s(p, "utm_campaign"),                         // blob6
    enrich.country || null,                       // blob7
    s(p, "device"),                               // blob8
    firstS(p, "target", "cta", "host"),           // blob9 (primary value, mutually exclusive per event)
    event.session_id,                             // blob10
    s(p, "viewport"),                             // blob11
    null, null, null, null, null, null, null, null, // blob12..19 reserved
    JSON.stringify(p),                            // blob20 backstop
  ];
  const doubles: number[] = [event.event_ts]; // double1
  const depth = n(p, "depth");
  if (depth !== undefined) doubles[1] = depth; // double2 (dense: only set when present)
  return { indexes: [enrich.visitorHash], blobs, doubles };
}
