import type { APIContext } from "astro";
import { handleTipAppcastRequest } from "../lib/appcast";

export const prerender = false;

export async function GET({ request }: APIContext): Promise<Response> {
  return handleTipAppcastRequest(request);
}

export async function HEAD({ request }: APIContext): Promise<Response> {
  return handleTipAppcastRequest(request);
}

export async function ALL({ request }: APIContext): Promise<Response> {
  return handleTipAppcastRequest(request);
}
