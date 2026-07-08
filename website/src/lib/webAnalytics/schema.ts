export type WebPropValue = string | number | boolean;

export interface WebEvent {
  event_id: string;
  event_ts: number; // client epoch ms — time-series bucket on THIS, never ingestion time
  session_id: string;
  name: string;
  props: Record<string, WebPropValue>;
}

export interface WebBatch {
  sent_at: number;
  events: WebEvent[];
}

export interface WebDataPoint {
  indexes?: string[];
  blobs?: (string | null)[];
  doubles?: number[];
}

export interface AnalyticsEngineDataset {
  writeDataPoint(point: WebDataPoint): void;
}

export const WEB_EVENT_NAMES = [
  "pageview",
  "download_click",
  "cta_click",
  "scroll_depth",
  "video_play",
  "outbound_click",
] as const;
export type WebEventName = (typeof WEB_EVENT_NAMES)[number];

const MAX_EVENTS = 20;
const MAX_PROPS_KEYS = 12;
const MAX_STR = 256;
const NAME_SET = new Set<string>(WEB_EVENT_NAMES);

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}
function nonEmptyStr(v: unknown, max: number): v is string {
  return typeof v === "string" && v.length > 0 && v.length <= max;
}

/**
 * Returns a cleaned batch (unknown event names dropped, props shallow-copied to
 * strip prototype pollution) or an error message string. Never throws.
 */
export function validateWebBatch(raw: unknown): WebBatch | string {
  if (!isObject(raw)) return "batch must be an object";
  if (typeof raw.sent_at !== "number" || !Number.isFinite(raw.sent_at)) return "sent_at must be a number";
  if (!Array.isArray(raw.events)) return "events must be an array";
  if (raw.events.length > MAX_EVENTS) return "too many events";

  const events: WebEvent[] = [];
  for (const item of raw.events) {
    if (!isObject(item)) return "event must be an object";
    if (!nonEmptyStr(item.event_id, 100)) return "event_id required";
    if (typeof item.event_ts !== "number" || !Number.isFinite(item.event_ts)) return "event_ts must be a number";
    if (!nonEmptyStr(item.session_id, 100)) return "session_id required";
    if (!nonEmptyStr(item.name, 64)) return "name required";
    if (!NAME_SET.has(item.name)) continue; // forward-compatible: drop unknown events
    if (!isObject(item.props)) return "props must be an object";

    const keys = Object.keys(item.props);
    if (keys.length > MAX_PROPS_KEYS) return "too many props";
    const props: Record<string, WebPropValue> = {};
    for (const k of keys) {
      const val = (item.props as Record<string, unknown>)[k];
      const t = typeof val;
      if (t !== "string" && t !== "number" && t !== "boolean") return "props values must be scalars";
      if (t === "string" && (val as string).length > MAX_STR) return "prop value too long";
      props[k] = val as WebPropValue;
    }

    events.push({ event_id: item.event_id, event_ts: item.event_ts, session_id: item.session_id, name: item.name, props });
  }

  return { sent_at: raw.sent_at, events };
}
