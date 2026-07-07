import { validateAccessJwt } from "./jwt";
import { buildStats, makeAeRunner, type D1Runner } from "./stats";
import { FILTER_DIMS, type DashboardEnv, type Filters } from "./types";

// Access-gated dashboard Worker. Validates the Access JWT for every request
// (defense in depth — the origin is publicly routable), then serves the stats
// API or the built React app.
export default {
  async fetch(request: Request, env: DashboardEnv): Promise<Response> {
    const url = new URL(request.url);

    const authed = await authorize(request, env);
    if (!authed) return new Response("Unauthorized", { status: 401 });

    if (url.pathname === "/api/stats") {
      return handleStats(request, env);
    }
    if (env.ASSETS) return env.ASSETS.fetch(request);
    return new Response("Not found", { status: 404 });
  },
};

async function authorize(request: Request, env: DashboardEnv): Promise<boolean> {
  // Local dev escape hatch (never set in production).
  if ((env as { DASHBOARD_ALLOW_INSECURE?: string }).DASHBOARD_ALLOW_INSECURE === "1") return true;
  if (!env.CF_ACCESS_AUD || !env.CF_ACCESS_TEAM_DOMAIN) return false;

  const result = await validateAccessJwt(request.headers.get("Cf-Access-Jwt-Assertion"), {
    aud: env.CF_ACCESS_AUD,
    teamDomain: env.CF_ACCESS_TEAM_DOMAIN,
    nowMs: Date.now(),
  });
  return result.valid;
}

async function handleStats(request: Request, env: DashboardEnv): Promise<Response> {
  if (!env.CF_ACCOUNT_ID || !env.AE_API_TOKEN || !env.INSTALLS_DB) {
    return json({ error: "not_configured" }, 503);
  }

  const params = new URL(request.url).searchParams;
  const rangeDays = clampRange(Number(params.get("range") ?? "30"));
  // Multi-value per dim: repeated params (?chip=m1&chip=m3) → a set (OR within a
  // dim). Values are sanitized in stats.ts (safeLabel/safeNum) before any SQL.
  const filters: Filters = {};
  for (const dim of FILTER_DIMS) {
    const values = params.getAll(dim).filter((v) => v !== "");
    if (values.length > 0) filters[dim] = values;
  }

  const ae = makeAeRunner(env.CF_ACCOUNT_ID, env.AE_API_TOKEN);
  const d1: D1Runner = async (query, binds) => {
    const stmt = env.INSTALLS_DB!.prepare(query);
    const bound = binds.length ? stmt.bind(...binds) : stmt;
    const { results } = await bound.all();
    return results as Array<Record<string, unknown>>;
  };

  try {
    const stats = await buildStats(ae, d1, { rangeDays, nowMs: Date.now(), datasetName: env.AE_DATASET, filters });
    return json(stats, 200);
  } catch (error) {
    console.error("stats failed", error);
    return json({ error: "stats_failed" }, 502);
  }
}

function clampRange(value: number): number {
  if (!Number.isFinite(value)) return 30;
  return Math.min(90, Math.max(7, Math.round(value)));
}

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
