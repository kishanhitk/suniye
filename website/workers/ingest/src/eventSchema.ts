// FIELD -> SLOT REGISTRY  (the real schema-migration mechanism)
//
// Analytics Engine columns are POSITIONAL and unnamed: `blob1..blob20`,
// `double1..double20`, and a single `index1`. A `schema_version` integer is not
// enough on its own — the meaning of each slot lives here.
//
// RULES (append-only, forever):
//   1. Never move or repurpose a slot. To add a field, append it to the next
//      free slot.
//   2. Keep this in sync with the Swift `AnalyticsEvent` prop keys.
//   3. Device details (mac_model, ram, cpu, os) are NOT here — they go to D1 on
//      app_launch and are joined by install_id, keeping AE rows small.
//
// `blob20` always carries the full compact props JSON as a backstop, so a newly
// added field is never lost before it earns a dedicated slot.

import type { PropValue, WireEvent } from "./types";

type StrPick = (p: Record<string, PropValue>) => string | undefined;
type NumPick = (p: Record<string, PropValue>) => number | undefined;

const str = (key: string): StrPick => (p) => (typeof p[key] === "string" ? (p[key] as string) : undefined);
const num = (key: string): NumPick => (p) => (typeof p[key] === "number" ? (p[key] as number) : undefined);
/** First present string among keys (for slots shared by mutually-exclusive fields across events). */
const firstStr = (...keys: string[]): StrPick => (p) => {
  for (const k of keys) if (typeof p[k] === "string") return p[k] as string;
  return undefined;
};
const firstNum = (...keys: string[]): NumPick => (p) => {
  for (const k of keys) if (typeof p[k] === "number") return p[k] as number;
  return undefined;
};
const boolNum = (...keys: string[]): NumPick => (p) => {
  for (const k of keys) if (typeof p[k] === "boolean") return (p[k] as boolean) ? 1 : 0;
  return undefined;
};

// blob1 is always the event name; blob2..19 are typed; blob20 is props JSON.
// Index in this array + 2 == blobN (so BLOB_FIELDS[0] -> blob2).
//
// SHARED SLOTS (blob14/15/16): a few slots are aliased across events whose fields
// are mutually exclusive — e.g. blob14 holds `reason` (dictation_blocked),
// `type` (error), `step` (onboarding), or `backend` (audio) depending on the
// event. This is SAFE ONLY because every dashboard query filters `blob1='<event>'`
// first, so the slot's meaning is unambiguous per query. Never read a shared slot
// across event types. If an event ever needs two aliased keys at once, give the
// second its own appended slot (the loser is otherwise recoverable only from the
// blob20 props backstop).
const BLOB_FIELDS: StrPick[] = [
  str("session_id"),                              // blob2
  str("app_version"),                             // blob3
  str("channel"),                                 // blob4
  str("asr_model"),                               // blob5
  str("asr_family"),                              // blob6
  str("language"),                                // blob7
  str("cleanup_provider"),                        // blob8
  str("cleanup_model"),                           // blob9
  str("cleanup_fallback_reason"),                 // blob10
  str("target_category"),                         // blob11
  str("insertion_method"),                        // blob12
  str("source"),                                  // blob13
  firstStr("reason", "stage", "step", "type", "backend"),   // blob14 - categorical detail A
  firstStr("code", "outcome"),                    // blob15 - categorical detail B
  firstStr("kind", "feature"),                    // blob16
  str("model"),                                   // blob17
  firstStr("from_version", "to_version"),         // blob18
];

// Index in this array + 1 == doubleN (DOUBLE_FIELDS[0] -> double1).
const DOUBLE_FIELDS: NumPick[] = [
  () => undefined,                                // double1 = event_ts, set explicitly from the top-level field (not props)
  num("word_count"),                              // double2
  num("char_count"),                              // double3
  num("audio_duration_ms"),                       // double4
  num("lat_end_to_end"),                          // double5
  num("lat_asr_processing"),                      // double6
  num("lat_llm_total"),                           // double7
  num("lat_asr_first_token"),                     // double8
  num("lat_llm_first_token"),                     // double9
  num("lat_trigger_to_capture"),                  // double10
  num("lat_stop_to_asr_start"),                   // double11
  num("lat_asr_to_llm"),                          // double12
  num("lat_insert"),                              // double13
  firstNum("load_ms", "duration_ms"),             // double14 - generic value_ms
  firstNum("count", "event_count", "queue_depth", "upload_failures", "evicted_by_ttl"), // double15
  boolNum("was_llm_polished"),                    // double16
  boolNum("granted", "enabled", "clean_exit", "fallback_occurred", "first_launch"),     // double17
  num("rung"),                                    // double18
  num("ram_gb"),                                  // double19
];

export interface DataPoint {
  indexes: string[];
  blobs: (string | null)[];
  doubles: number[];
}

/**
 * Builds one Analytics Engine data point from a wire event, using the fixed
 * slot registry above. `install_id` is index1; the event name is blob1;
 * `country` (server-derived) is appended after the props JSON backstop.
 */
export function buildDataPoint(event: WireEvent, installId: string, country: string): DataPoint {
  const p = event.props ?? {};

  const blobs: (string | null)[] = new Array(20).fill(null);
  blobs[0] = event.name;                          // blob1
  BLOB_FIELDS.forEach((pick, i) => {
    blobs[i + 1] = pick(p) ?? null;               // blob2..blob18
  });
  blobs[18] = country || null;                    // blob19 - server-derived country
  blobs[19] = JSON.stringify(p);                  // blob20 - full props backstop

  const doubles: number[] = new Array(19).fill(0);
  DOUBLE_FIELDS.forEach((pick, i) => {
    const value = pick(p);
    if (value !== undefined && Number.isFinite(value)) doubles[i] = value;
  });
  doubles[0] = event.event_ts; // double1 = client event timestamp (time-series bucket key)

  return { indexes: [installId], blobs, doubles };
}
