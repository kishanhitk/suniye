import type { APIContext } from "astro";
import { handleAppcastRequest } from "../lib/appcast";

export const prerender = false;

export async function GET({ request }: APIContext): Promise<Response> {
  return handleAppcastRequest(request);
}

export async function HEAD({ request }: APIContext): Promise<Response> {
  return handleAppcastRequest(request);
}

export async function ALL({ request }: APIContext): Promise<Response> {
  return handleAppcastRequest(request);
}
