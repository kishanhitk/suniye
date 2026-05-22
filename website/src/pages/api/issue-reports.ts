import type { APIContext } from "astro";
import { env } from "cloudflare:workers";
import { handleIssueReportRequest } from "../../lib/issueReports";

export const prerender = false;

export async function POST({ request }: APIContext): Promise<Response> {
  return handleIssueReportRequest(request, {
    linearApiKey: env.LINEAR_API_KEY,
    linearTeamId: env.LINEAR_TEAM_ID,
    linearReportLabelId: env.LINEAR_REPORT_LABEL_ID,
    linearReportProjectId: env.LINEAR_REPORT_PROJECT_ID,
    linearReportStateId: env.LINEAR_REPORT_STATE_ID,
  });
}

export async function ALL({ request }: APIContext): Promise<Response> {
  return handleIssueReportRequest(request, {
    linearApiKey: env.LINEAR_API_KEY,
    linearTeamId: env.LINEAR_TEAM_ID,
    linearReportLabelId: env.LINEAR_REPORT_LABEL_ID,
    linearReportProjectId: env.LINEAR_REPORT_PROJECT_ID,
    linearReportStateId: env.LINEAR_REPORT_STATE_ID,
  });
}
