import { describe, expect, test } from "bun:test";
import worker from "../src/index";
import type { IssueReportEnv } from "../src/issueReports";

const env: IssueReportEnv = { LINEAR_API_KEY: "key", LINEAR_TEAM_ID: "team" };

describe("worker entry", () => {
  test("routes /api/issue-reports to the handler", async () => {
    const response = await worker.fetch(new Request("https://suniye.app/api/issue-reports"), env);
    expect(response.status).toBe(405);
    const body = (await response.json()) as { error?: { code?: string } };
    expect(body.error?.code).toBe("method_not_allowed");
  });

  test("404s unknown paths", async () => {
    const response = await worker.fetch(new Request("https://suniye.app/api/other"), env);
    expect(response.status).toBe(404);
  });
});
