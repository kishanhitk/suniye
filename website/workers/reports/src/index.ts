import { handleIssueReportRequest, issueReportConfigFromEnv } from "./issueReports";
import type { IssueReportEnv } from "./issueReports";

// Standalone issue-report Worker. Routes /api/issue-reports to the pure
// handler; everything else 404s.
export default {
  async fetch(request: Request, env: IssueReportEnv): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/api/issue-reports") {
      return handleIssueReportRequest(request, issueReportConfigFromEnv(env));
    }
    return new Response("Not found", { status: 404 });
  },
};
