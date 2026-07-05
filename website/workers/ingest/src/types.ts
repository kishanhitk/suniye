// Wire types for the analytics ingest endpoint. These mirror the Swift
// `SuniyeAnalytics` package's `AnalyticsBatch`/`EncodedEvent` exactly. Values in
// `props` are only ever scalars (number | boolean | controlled string) — the
// client makes free text structurally impossible, and the ingest validator
// enforces the same on the server side.

export type PropValue = string | number | boolean;

export interface WireEvent {
  event_id: string;
  event_ts: number; // client epoch ms — time-series are bucketed on THIS, never ingestion time
  session_id: string;
  name: string;
  props: Record<string, PropValue>;
}

export interface WireBatch {
  schema_version: number;
  install_id: string;
  app_version: string;
  build: string;
  channel: string;
  is_debug: boolean;
  sent_at: number;
  events: WireEvent[];
}

/** Directive returned to the client (kill switch / sampling). */
export interface IngestDirective {
  disabled?: boolean;
  sample_rate?: number;
}

export interface IngestConfig {
  /** Server-side kill switch: when true, accept-and-drop and tell clients to stop. */
  disabled?: boolean;
  /** Optional global sample rate pushed to clients (0..1). */
  sampleRate?: number;
  rateLimit?: RateLimitConfig | false;
}

export interface RateLimitConfig {
  store?: RateLimitStore;
  maxRequests?: number;
  windowSeconds?: number;
  failureMode?: "open" | "closed";
}

export interface RateLimitStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, ttlSeconds: number): Promise<void>;
}

/** Minimal shapes of the Cloudflare bindings this Worker uses. */
export interface AnalyticsEngineDataset {
  writeDataPoint(point: { indexes?: string[]; blobs?: (string | null)[]; doubles?: number[] }): void;
}

export interface D1Database {
  prepare(query: string): D1PreparedStatement;
}
export interface D1PreparedStatement {
  bind(...values: unknown[]): D1PreparedStatement;
  run(): Promise<unknown>;
}

export interface IngestEnv {
  EVENTS?: AnalyticsEngineDataset;
  INSTALLS_DB?: D1Database;
  ANALYTICS_DISABLED?: string; // "1" to kill-switch server-side
  ANALYTICS_SAMPLE_RATE?: string;
}
