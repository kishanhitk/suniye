// Cache-API-backed IP rate limiter, ported from the website's issue-report
// endpoint. The raw IP is read transiently to derive a SHA-256 key and is never
// stored or logged. Budget is analytics-sized (batches), not bug-report-sized.

import type { RateLimitConfig, RateLimitStore } from "./types";

export const defaultMaxRequests = 120; // batched uploads per IP-hash...
export const defaultWindowSeconds = 10 * 60; // ...per 10 minutes

export async function checkRateLimit(
  request: Request,
  config: RateLimitConfig | false | undefined,
  makeResponse: (code: string, message: string, status: number) => Response
): Promise<Response | undefined> {
  if (config === false) return undefined;

  const store = config?.store ?? defaultRateLimitStore();
  if (!store) {
    console.error("Analytics rate limiter is not available.");
    return config?.failureMode === "open"
      ? undefined
      : makeResponse("rate_limiter_unavailable", "Analytics is temporarily unavailable.", 503);
  }

  const maxRequests = config?.maxRequests ?? defaultMaxRequests;
  const windowSeconds = config?.windowSeconds ?? defaultWindowSeconds;
  const now = Math.floor(Date.now() / 1000);
  const key = await makeRateLimitKey(request);

  try {
    return await withRateLimitKeyLock(key, async () => {
      const current = parseRecord(await store.get(key), now, windowSeconds);
      if (current.count >= maxRequests) {
        return makeResponse("rate_limited", "Too many requests.", 429);
      }
      await store.put(
        key,
        JSON.stringify({ count: current.count + 1, resetAt: current.resetAt }),
        Math.max(1, current.resetAt - now)
      );
      return undefined;
    });
  } catch (error) {
    console.error("Analytics rate limiter failed", error);
    return config?.failureMode === "open"
      ? undefined
      : makeResponse("rate_limiter_unavailable", "Analytics is temporarily unavailable.", 503);
  }
}

function defaultRateLimitStore(): RateLimitStore | undefined {
  const cache = (globalThis as typeof globalThis & { caches?: CacheStorage }).caches?.default;
  if (!cache) return undefined;
  return {
    async get(key) {
      const response = await cache.match(cacheRequest(key));
      return response ? response.text() : null;
    },
    async put(key, value, ttlSeconds) {
      await cache.put(cacheRequest(key), new Response(value, {
        headers: { "Cache-Control": `public, max-age=${ttlSeconds}` },
      }));
    },
  };
}

const keyLocks = new Map<string, Promise<void>>();

async function withRateLimitKeyLock<T>(key: string, operation: () => Promise<T>): Promise<T> {
  const previous = keyLocks.get(key) ?? Promise.resolve();
  let release: () => void = () => {};
  const current = new Promise<void>((resolve) => { release = resolve; });
  const next = previous.catch(() => undefined).then(() => current);
  keyLocks.set(key, next);
  await previous.catch(() => undefined);
  try {
    return await operation();
  } finally {
    release();
    if (keyLocks.get(key) === next) keyLocks.delete(key);
  }
}

function cacheRequest(key: string): Request {
  // Distinct namespace from the issue-report limiter.
  return new Request(`https://suniye-rate-limit.invalid/ingest/${encodeURIComponent(key)}`);
}

export async function makeRateLimitKey(request: Request): Promise<string> {
  const ip = request.headers.get("CF-Connecting-IP")
    ?? request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim()
    ?? "unknown";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ip));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

function parseRecord(value: string | null, now: number, windowSeconds: number): { count: number; resetAt: number } {
  if (!value) return { count: 0, resetAt: now + windowSeconds };
  try {
    const parsed = JSON.parse(value) as { count?: unknown; resetAt?: unknown };
    if (typeof parsed.count !== "number" || typeof parsed.resetAt !== "number" || parsed.resetAt <= now) {
      return { count: 0, resetAt: now + windowSeconds };
    }
    return { count: parsed.count, resetAt: parsed.resetAt };
  } catch {
    return { count: 0, resetAt: now + windowSeconds };
  }
}
