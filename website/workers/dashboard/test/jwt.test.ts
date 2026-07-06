import { describe, expect, test } from "bun:test";
import { checkClaims, decodeJwt, validateAccessJwt } from "../src/worker/jwt";

function b64url(obj: unknown): string {
  return btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function makeToken(header: unknown, payload: unknown): string {
  return `${b64url(header)}.${b64url(payload)}.AAAA`;
}

const NOW = 1_700_000_000_000;
const future = Math.floor(NOW / 1000) + 3600;
const past = Math.floor(NOW / 1000) - 3600;

describe("decodeJwt", () => {
  test("rejects non-three-part tokens", () => {
    expect(decodeJwt("a.b")).toBeNull();
    expect(decodeJwt("garbage")).toBeNull();
  });

  test("decodes header and payload", () => {
    const decoded = decodeJwt(makeToken({ kid: "k1", alg: "RS256" }, { aud: "my-aud", exp: future }));
    expect(decoded?.header.kid).toBe("k1");
    expect(decoded?.payload.aud).toBe("my-aud");
  });
});

describe("checkClaims", () => {
  test("rejects expired", () => {
    expect(checkClaims({ aud: "a", exp: past }, "a", NOW)).toBe("expired");
  });
  test("rejects aud mismatch", () => {
    expect(checkClaims({ aud: "other", exp: future }, "a", NOW)).toBe("aud_mismatch");
  });
  test("accepts valid claims (array aud)", () => {
    expect(checkClaims({ aud: ["x", "a"], exp: future }, "a", NOW)).toBeNull();
  });
});

describe("validateAccessJwt", () => {
  const opts = { aud: "my-aud", teamDomain: "team.cloudflareaccess.com", nowMs: NOW };

  test("missing token", async () => {
    expect((await validateAccessJwt(null, opts)).reason).toBe("missing_token");
  });

  test("malformed token", async () => {
    expect((await validateAccessJwt("not-a-jwt", opts)).reason).toBe("malformed");
  });

  test("expired token rejected before crypto", async () => {
    const token = makeToken({ kid: "k1" }, { aud: "my-aud", exp: past });
    const result = await validateAccessJwt(token, { ...opts, getJwks: async () => ({ keys: [] }) });
    expect(result.reason).toBe("expired");
  });

  test("unknown kid rejected", async () => {
    const token = makeToken({ kid: "missing" }, { aud: "my-aud", exp: future });
    const result = await validateAccessJwt(token, { ...opts, getJwks: async () => ({ keys: [] }) });
    expect(result.reason).toBe("unknown_kid");
  });
});
