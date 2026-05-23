import {
  handleIssueReportRequest,
  type IssueReportEndpointConfig,
} from "../../src/lib/issueReports";

interface PagesFunctionContext {
  request: Request;
  env: Record<string, string | undefined>;
}

export function issueReportConfigFromPagesEnv(
  env: Record<string, string | undefined>
): IssueReportEndpointConfig {
  return {
    linearApiKey: env.LINEAR_API_KEY,
    linearTeamId: env.LINEAR_TEAM_ID,
    linearReportLabelId: env.LINEAR_REPORT_LABEL_ID,
    linearReportProjectId: env.LINEAR_REPORT_PROJECT_ID,
    linearReportStateId: env.LINEAR_REPORT_STATE_ID,
  };
}

export async function onRequest({ request, env }: PagesFunctionContext): Promise<Response> {
  return handleIssueReportRequest(
    request,
    issueReportConfigFromPagesEnv(env)
  );
}
