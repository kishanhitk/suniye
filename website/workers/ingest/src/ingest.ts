// Analytics ingest handler. Pure and testable: given a Request + env + config,
// it validates the batch, writes one Analytics Engine data point per event,
// upserts the install registry (D1) once per session (on app_launch), and
// returns a directive the client caches. No secrets; the raw IP is only read
// transiently for rate-limiting and country, never stored.

import { buildDataPoint } from "./eventSchema";
import { checkRateLimit } from "./rateLimit";
import type {
  IngestConfig, IngestDirective, IngestEnv, PropValue, WireBatch, WireEvent,
} from "./types";

const MAX_BODY_BYTES = 128 * 1024;
const MAX_EVENTS_PER_BATCH = 250; // Analytics Engine allows 250 writeDataPoint/invocation
const MAX_PROPS_KEYS = 40; // typed slots are ~18; a healthy event has well under this
const MAX_PROPS_JSON_BYTES = 3 * 1024; // keeps blob20 backstop under AE's ~5 KB blob budget

export function ingestConfigFromEnv(env: IngestEnv): IngestConfig {
  const sampleRate = env.ANALYTICS_SAMPLE_RATE ? Number(env.ANALYTICS_SAMPLE_RATE) : undefined;
  return {
    disabled: env.ANALYTICS_DISABLED === "1",
    sampleRate: Number.isFinite(sampleRate) ? sampleRate : undefined,
  };
}

export async function handleIngestRequest(
  request: Request,
  env: IngestEnv,
  config: IngestConfig = {}
): Promise<Response> {
  if (request.method !== "POST") {
    return json(errorBody("method_not_allowed", "Use POST."), 405);
  }

  const limited = await checkRateLimit(request, config.rateLimit, (code, message, status) =>
    json(errorBody(code, message), status)
  );
  if (limited) return limited;

  const directive = makeDirective(config);

  // Server-side kill switch: accept-and-drop, tell the client to stop.
  if (config.disabled) {
    return json({ ...directive, disabled: true }, 200);
  }

  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    return json(errorBody("invalid_content_type", "Expected application/json."), 415);
  }

  const contentLength = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return json(errorBody("request_too_large", "Batch too large."), 413);
  }

  let raw: unknown;
  try {
    const text = await request.text();
    if (text.length > MAX_BODY_BYTES) {
      return json(errorBody("request_too_large", "Batch too large."), 413);
    }
    raw = JSON.parse(text);
  } catch {
    return json(errorBody("invalid_json", "Body is not valid JSON."), 400);
  }

  const batch = validateBatch(raw);
  if (typeof batch === "string") {
    return json(errorBody("invalid_payload", batch), 400);
  }

  // Debug/simulator batches are dropped (defense in depth; the client also drops).
  if (batch.is_debug) {
    return json(directive, 200);
  }

  if (!env.EVENTS) {
    return json(errorBody("server_not_configured", "Analytics storage is unavailable."), 503);
  }

  const country = request.headers.get("CF-IPCountry")
    ?? (request as unknown as { cf?: { country?: string } }).cf?.country
    ?? "";

  for (const event of batch.events) {
    try {
      env.EVENTS.writeDataPoint(buildDataPoint(event, batch.install_id, country));
    } catch (error) {
      console.error("writeDataPoint failed", error);
    }
    if (event.name === "app_launch") {
      await upsertInstall(env, batch, event, country);
    }
  }

  return json(directive, 200);
}

function makeDirective(config: IngestConfig): IngestDirective {
  const directive: IngestDirective = {};
  if (config.sampleRate !== undefined) directive.sample_rate = config.sampleRate;
  return directive;
}

async function upsertInstall(env: IngestEnv, batch: WireBatch, event: WireEvent, country: string): Promise<void> {
  if (!env.INSTALLS_DB) return;
  const p = event.props ?? {};
  const day = new Date(event.event_ts).toISOString().slice(0, 10);
  try {
    await env.INSTALLS_DB
      .prepare(
        `INSERT INTO installs
           (install_id, first_seen, last_seen, app_version, channel, os_version, mac_model, chip, ram_gb, cpu_cores, country)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(install_id) DO UPDATE SET
           last_seen = excluded.last_seen,
           app_version = excluded.app_version,
           channel = excluded.channel,
           os_version = excluded.os_version,
           mac_model = excluded.mac_model,
           chip = excluded.chip,
           ram_gb = excluded.ram_gb,
           cpu_cores = excluded.cpu_cores,
           country = excluded.country`
      )
      .bind(
        batch.install_id, day, day, batch.app_version, batch.channel,
        s(p.os_version), s(p.mac_model), s(p.chip), n(p.ram_gb), n(p.cpu_cores), country || null
      )
      .run();
  } catch (error) {
    console.error("install upsert failed", error);
  }
}

// ---- validation ----

function validateBatch(raw: unknown): WireBatch | string {
  if (!isObject(raw)) return "Batch must be an object.";
  if (raw.schema_version !== 1) return "Unsupported schema version.";
  if (!isNonEmptyString(raw.install_id, 200)) return "install_id is required.";
  if (!isNonEmptyString(raw.app_version, 100)) return "app_version is required.";
  if (!isNonEmptyString(raw.build, 100)) return "build is required.";
  if (!isNonEmptyString(raw.channel, 50)) return "channel is required.";
  if (typeof raw.sent_at !== "number" || !Number.isFinite(raw.sent_at)) return "sent_at must be a number.";
  if (typeof raw.is_debug !== "boolean") return "is_debug must be a boolean.";
  if (!Array.isArray(raw.events)) return "events must be an array.";
  if (raw.events.length === 0) return "events must not be empty.";
  if (raw.events.length > MAX_EVENTS_PER_BATCH) return "Too many events in one batch.";

  for (const event of raw.events) {
    const error = validateEvent(event);
    if (error) return error;
  }
  return raw as unknown as WireBatch;
}

function validateEvent(raw: unknown): string | undefined {
  if (!isObject(raw)) return "Event must be an object.";
  if (!isNonEmptyString(raw.event_id, 100)) return "event_id is required.";
  if (typeof raw.event_ts !== "number" || !Number.isFinite(raw.event_ts)) return "event_ts must be a number.";
  if (!isNonEmptyString(raw.session_id, 100)) return "session_id is required.";
  if (!isNonEmptyString(raw.name, 64)) return "event name is required.";
  if (!isObject(raw.props)) return "props must be an object.";
  const keys = Object.keys(raw.props);
  if (keys.length > MAX_PROPS_KEYS) return "too many props.";
  for (const value of Object.values(raw.props)) {
    const t = typeof value;
    if (t !== "string" && t !== "number" && t !== "boolean") return "props values must be scalars.";
    if (t === "string" && (value as string).length > 512) return "prop value too long.";
  }
  // blob20 carries JSON.stringify(props) as a backstop on top of ~18 typed blobs.
  // AE caps total blob bytes (~5 KB); an oversized props object would make
  // writeDataPoint throw and silently drop the ENTIRE event, typed slots included.
  if (JSON.stringify(raw.props).length > MAX_PROPS_JSON_BYTES) return "props too large.";
  return undefined;
}

// ---- helpers ----

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function isNonEmptyString(value: unknown, max: number): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= max;
}
function s(value: PropValue | undefined): string | null {
  return typeof value === "string" ? value : null;
}
function n(value: PropValue | undefined): number | null {
  return typeof value === "number" ? value : null;
}
function errorBody(code: string, message: string) {
  return { success: false as const, error: { code, message } };
}
function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
