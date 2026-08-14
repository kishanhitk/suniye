import { handleIssueReportRequest, issueReportConfigFromEnv } from "./issueReports";
import type { IssueReportEnv } from "./issueReports";

export default {
  async fetch(request: Request, env: IssueReportEnv): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/api/issue-reports") {
      return handleIssueReportRequest(request, issueReportConfigFromEnv(env));
    }
    return new Response("Not found", { status: 404 });
  },
};
