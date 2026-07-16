// FIELD -> SLOT REGISTRY  (the real schema-migration mechanism)
//
// Analytics Engine columns are POSITIONAL and unnamed: `blob1..blob20`,
// `double1..double20`, and a single `index1`. A `schema_version` integer is not
// enough on its own — the meaning of each slot lives here.
//
// RULES (append-only, forever):
//   1. Never move or repurpose a slot. To add a field, append it to the next
//      free slot (or append a key to a shared slot's alias list — see below).
//   2. Keep this in sync with the Swift `AnalyticsEvent` prop keys.
//
// DEVICE CONTEXT: the batch envelope carries a `device` block (chip, ram_gb,
// mac_model, os_version, cpu_cores, arch). `buildDataPoint` merges it into every
// event's prop map so any metric can be sliced by hardware. Device keys are
// appended LAST on their shared slots (blob14/16/17/18, double18) so a native
// per-event field always wins its slot; device dims fill the slot only on events
// that don't use it (e.g. chip=blob16 on dictation, but blob16=kind on
// model_changed → chip rides blob20 there). ram_gb has its own slot (double19).
// Device is also fully in D1 on app_launch (joined by install_id).
//
// `blob20` always carries the full compact props JSON (event props + device) as a
// backstop, so a field is never lost before it earns a dedicated slot.

import type { PropValue, WireBatch, WireEvent } from "./types";

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
  () => undefined,                                // blob2 = session_id — set explicitly (event top-level field, not props)
  () => undefined,                                // blob3 = app_version — set explicitly (batch envelope, not props)
  () => undefined,                                // blob4 = channel — set explicitly (batch envelope, not props)
  str("asr_model"),                               // blob5
  str("asr_family"),                              // blob6
  str("language"),                                // blob7
  str("cleanup_provider"),                        // blob8
  str("cleanup_model"),                           // blob9
  str("cleanup_fallback_reason"),                 // blob10
  str("target_category"),                         // blob11
  str("insertion_method"),                        // blob12
  str("source"),                                  // blob13
  firstStr("reason", "stage", "step", "type", "backend", "arch"),   // blob14 - categorical detail A (+ device arch)
  firstStr("code", "outcome"),                    // blob15 - categorical detail B
  firstStr("kind", "feature", "chip"),            // blob16 (+ device chip)
  firstStr("model", "mac_model"),                 // blob17 (+ device mac_model)
  firstStr("from_version", "to_version", "os_version"),   // blob18 (+ device os_version)
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
  firstNum("count", "event_count", "queue_depth", "upload_failures", "evicted_by_ttl", "attempt"), // double15 (+ onboarding_practice_result attempt)
  boolNum("was_llm_polished"),                    // double16
  // `resumed` (onboarding_step) and `practiced` (onboarding_outcome) are appended:
  // neither event carries an earlier alias of this slot, so they surface here;
  // the JSON backstop keeps them recoverable everywhere else.
  boolNum("granted", "enabled", "clean_exit", "fallback_occurred", "first_launch", "resumed", "practiced"),     // double17
  firstNum("rung", "cpu_cores"),                  // double18 (+ device cpu_cores)
  num("ram_gb"),                                  // double19 (device ram_gb, now on every event)
  num("edit_rate_bucket"),                        // double20 - post-insertion edit rate (dictation_edited)
];
// NB: doubles are full (20/20). Newer numeric fields must alias a generic slot
// (append to a firstNum list) or live in the blob20 props JSON. Audio-quality
// fields (audio_backend, input_sample_rate, aec_effective, …) and device
// perf_cores/eff_cores intentionally ride only in props JSON.
//
// analytics_health carries four numerics (queue_depth, upload_failures,
// evicted_by_ttl, evicted_by_size); double15's firstNum surfaces only
// queue_depth (the current-backlog gauge). The three counters ride the blob20
// props JSON — this is self-observability telemetry, not a dashboard query, so
// none needs a dedicated slot. Promote one to a shared slot if we ever build
// alerting on it.

export interface DataPoint {
  indexes: string[];
  blobs: (string | null)[];
  doubles: number[];
}

/**
 * Builds one Analytics Engine data point from a wire event + its batch envelope.
 * `install_id` is index1; the event name is blob1; `country` (server-derived) is
 * blob19. The batch's `device` block is merged into the prop map (event props win
 * any collision) so hardware dims fill their aliased slots and the blob20 JSON.
 * session_id / app_version / channel are set explicitly (they live on the event
 * top-level / batch envelope, not in props — reading them from props left
 * blob2/3/4 null on every row historically).
 */
export function buildDataPoint(event: WireEvent, batch: WireBatch, country: string): DataPoint {
  const p: Record<string, PropValue> = { ...(batch.device ?? {}), ...(event.props ?? {}) };

  const blobs: (string | null)[] = new Array(20).fill(null);
  blobs[0] = event.name;                          // blob1
  BLOB_FIELDS.forEach((pick, i) => {
    blobs[i + 1] = pick(p) ?? null;               // blob2..blob18
  });
  blobs[1] = event.session_id || null;            // blob2 - event top-level field
  blobs[2] = batch.app_version || null;           // blob3 - batch envelope
  blobs[3] = batch.channel || null;               // blob4 - batch envelope
  blobs[18] = country || null;                    // blob19 - server-derived country
  blobs[19] = JSON.stringify(p);                  // blob20 - full props + device backstop

  const doubles: number[] = new Array(20).fill(0);
  DOUBLE_FIELDS.forEach((pick, i) => {
    const value = pick(p);
    if (value !== undefined && Number.isFinite(value)) doubles[i] = value;
  });
  doubles[0] = event.event_ts; // double1 = client event timestamp (time-series bucket key)

  return { indexes: [batch.install_id], blobs, doubles };
}
