import { handleIngestRequest, ingestConfigFromEnv } from "./ingest";
import type { IngestEnv } from "./types";

// Public, secret-free analytics ingest Worker. Routes /api/v1/events to the
// pure handler; everything else 404s.
export default {
  async fetch(request: Request, env: IngestEnv): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/api/v1/events") {
      return handleIngestRequest(request, env, ingestConfigFromEnv(env));
    }
    return new Response("Not found", { status: 404 });
  },
};
