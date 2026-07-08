import type { APIContext } from "astro";
import { env } from "cloudflare:workers";
import { handleTrackRequest, type TrackEnv } from "../../lib/webAnalytics/track";

export const prerender = false;

export async function POST({ request }: APIContext): Promise<Response> {
  return handleTrackRequest(request, env as unknown as TrackEnv);
}

export async function ALL({ request }: APIContext): Promise<Response> {
  return handleTrackRequest(request, env as unknown as TrackEnv);
}
