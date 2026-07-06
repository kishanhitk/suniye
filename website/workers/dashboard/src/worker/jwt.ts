// Validates the Cloudflare Access JWT (`Cf-Access-Jwt-Assertion`). The dashboard
// origin is publicly routable, so we verify the token in the Worker rather than
// trusting that Access fronted the request. Verification = signature (RS256 via
// the team JWKS) + `aud` + `exp`.

export interface AccessJwtResult {
  valid: boolean;
  email?: string;
  reason?: string;
}

interface Jwk {
  kid: string;
  kty: string;
  n: string;
  e: string;
  alg?: string;
}

interface DecodedJwt {
  header: { kid?: string; alg?: string };
  payload: { aud?: string | string[]; exp?: number; email?: string; iss?: string };
  signingInput: string;
  signature: Uint8Array;
}

export function base64UrlToBytes(input: string): Uint8Array {
  const pad = input.length % 4 === 0 ? "" : "=".repeat(4 - (input.length % 4));
  const b64 = input.replace(/-/g, "+").replace(/_/g, "/") + pad;
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeJson(part: string): Record<string, unknown> {
  return JSON.parse(new TextDecoder().decode(base64UrlToBytes(part)));
}

export function decodeJwt(token: string): DecodedJwt | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    return {
      header: decodeJson(parts[0]) as DecodedJwt["header"],
      payload: decodeJson(parts[1]) as DecodedJwt["payload"],
      signingInput: `${parts[0]}.${parts[1]}`,
      signature: base64UrlToBytes(parts[2]),
    };
  } catch {
    return null;
  }
}

/** Returns a rejection reason, or null if claims are acceptable. */
export function checkClaims(
  payload: DecodedJwt["payload"],
  aud: string,
  nowMs: number
): string | null {
  if (!payload.exp || payload.exp * 1000 <= nowMs) return "expired";
  const auds = Array.isArray(payload.aud) ? payload.aud : payload.aud ? [payload.aud] : [];
  if (!auds.includes(aud)) return "aud_mismatch";
  return null;
}

export interface ValidateOptions {
  aud: string;
  teamDomain: string; // e.g. myteam.cloudflareaccess.com
  nowMs: number;
  getJwks?: () => Promise<{ keys: Jwk[] }>;
  fetcher?: typeof fetch;
}

export async function validateAccessJwt(token: string | null, opts: ValidateOptions): Promise<AccessJwtResult> {
  if (!token) return { valid: false, reason: "missing_token" };

  const decoded = decodeJwt(token);
  if (!decoded) return { valid: false, reason: "malformed" };

  const claimError = checkClaims(decoded.payload, opts.aud, opts.nowMs);
  if (claimError) return { valid: false, reason: claimError };

  const jwks = await (opts.getJwks ?? defaultGetJwks(opts.teamDomain, opts.fetcher))();
  const jwk = jwks.keys.find((k) => k.kid === decoded.header.kid);
  if (!jwk) return { valid: false, reason: "unknown_kid" };

  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
  const verified = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    decoded.signature,
    new TextEncoder().encode(decoded.signingInput)
  );
  if (!verified) return { valid: false, reason: "bad_signature" };

  return { valid: true, email: decoded.payload.email };
}

interface JwksCacheEntry {
  keys: Jwk[];
  fetchedAt: number;
}
const jwksCache = new Map<string, JwksCacheEntry>();
const JWKS_TTL_MS = 60 * 60 * 1000; // certs rotate slowly; 1h is safe
const JWKS_TIMEOUT_MS = 5000;

function defaultGetJwks(teamDomain: string, fetcher: typeof fetch = fetch) {
  return async () => {
    const cached = jwksCache.get(teamDomain);
    if (cached && Date.now() - cached.fetchedAt < JWKS_TTL_MS) {
      return { keys: cached.keys };
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), JWKS_TIMEOUT_MS);
    try {
      const res = await fetcher(`https://${teamDomain}/cdn-cgi/access/certs`, { signal: controller.signal });
      if (!res.ok) throw new Error(`JWKS ${res.status}`);
      const jwks = (await res.json()) as { keys: Jwk[] };
      // Only cache a well-formed, non-empty key set. Caching `{keys: undefined}`
      // or `[]` would hard-fail every request for the full TTL (a 200 with a bad
      // body, or a momentarily-empty rotation) — treat those as a cache miss.
      if (!Array.isArray(jwks.keys) || jwks.keys.length === 0) {
        throw new Error("JWKS response has no keys");
      }
      jwksCache.set(teamDomain, { keys: jwks.keys, fetchedAt: Date.now() });
      return jwks;
    } finally {
      clearTimeout(timer);
    }
  };
}
