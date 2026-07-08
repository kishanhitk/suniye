import { buildWebDataPoint } from "./datapoint";
import { validateWebBatch, type AnalyticsEngineDataset } from "./schema";
import { dailyVisitorHash, utcDate } from "./visitor";

export interface TrackEnv {
  WEB_EVENTS?: AnalyticsEngineDataset;
  SECRET_SALT?: string;
}

const MAX_BODY = 16 * 1024;
const noContent = () => new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } });

function referrerHost(request: Request): string {
  const ref = request.headers.get("Referer");
  if (!ref) return "";
  try {
    return new URL(ref).hostname;
  } catch {
    return "";
  }
}

/**
 * Same-origin analytics ingest. ALWAYS returns 204 for POST (even on bad input
 * or missing binding) so the beacon can't be used to probe. Raw IP/UA are read
 * only to compute the daily visitor hash, then discarded.
 */
export async function handleTrackRequest(request: Request, env: TrackEnv, nowMs: number = Date.now()): Promise<Response> {
  if (request.method !== "POST") return new Response("Use POST", { status: 405 });

  const text = await request.text().catch(() => "");
  if (text.length > MAX_BODY) return noContent();

  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return noContent();
  }

  const batch = validateWebBatch(raw);
  if (typeof batch === "string" || !env.WEB_EVENTS) return noContent();

  const country = request.headers.get("CF-IPCountry")
    ?? (request as unknown as { cf?: { country?: string } }).cf?.country
    ?? "";
  const ip = request.headers.get("CF-Connecting-IP") ?? "";
  const ua = request.headers.get("User-Agent") ?? "";
  const visitorHash = await dailyVisitorHash(ip, ua, utcDate(nowMs), env.SECRET_SALT ?? "");
  const enrich = { referrerHost: referrerHost(request), country, visitorHash };

  for (const event of batch.events) {
    try {
      env.WEB_EVENTS.writeDataPoint(buildWebDataPoint(event, enrich));
    } catch (error) {
      console.error("web writeDataPoint failed", error);
    }
  }
  return noContent();
}
