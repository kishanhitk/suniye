import type { APIContext } from "astro";
import { env } from "cloudflare:workers";
import { handleIssueReportRequest, issueReportConfigFromEnv } from "../../lib/issueReports";

export const prerender = false;

export async function POST({ request }: APIContext): Promise<Response> {
  return handleIssueReportRequest(request, issueReportConfigFromEnv(env));
}

export async function ALL({ request }: APIContext): Promise<Response> {
  return handleIssueReportRequest(request, issueReportConfigFromEnv(env));
}
