import { describe, expect, test } from "bun:test";
import {
  handleIssueReportRequest,
  makeLinearIssueDescription,
  type IssueReportPayload,
} from "../src/lib/issueReports";

const validPayload: IssueReportPayload = {
  schemaVersion: 1,
  reportId: "report-123",
  issueType: "dictation",
  title: "Dictation failed",
  description: "Recording finishes but no text appears in the focused app.",
  contactEmail: "user@example.com",
  includeDiagnostics: true,
  app: {
    version: "v0.0.8",
    build: "8",
    macOSVersion: "15.5",
    architecture: "arm64",
  },
  state: {
    phase: "ready",
    lastError: "Accessibility permission not granted",
    updateStatus: "upToDate",
  },
  permissions: {
    microphone: true,
    accessibility: false,
  },
  model: {
    selectedModelId: "parakeetV3",
    selectedModelName: "Parakeet v3",
    selectedModelInstalled: true,
    installedModelIds: ["parakeetV3"],
  },
  settings: {
    autoSubmitEnabled: false,
    echoCancellationEnabled: true,
    soundFeedbackEnabled: true,
    hideFloatingIndicatorWhenIdle: false,
    llmEnabled: false,
    llmHasAPIKey: false,
  },
};

describe("issue report endpoint", () => {
  test("rejects non-POST requests", async () => {
    const response = await handleIssueReportRequest(
      new Request("https://suniye.test/api/issue-reports"),
      { linearApiKey: "linear", linearTeamId: "team" },
      failingFetch
    );

    expect(response.status).toBe(405);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "method_not_allowed" },
    });
  });

  test("rejects missing Linear configuration", async () => {
    const response = await handleIssueReportRequest(
      makeMultipartRequest(validPayload, makeZipFile()),
      {},
      failingFetch
    );

    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "server_not_configured" },
    });
  });

  test("rejects invalid payloads", async () => {
    const response = await handleIssueReportRequest(
      makeMultipartRequest({ ...validPayload, title: "No" }, makeZipFile()),
      { linearApiKey: "linear", linearTeamId: "team" },
      failingFetch
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "invalid_payload" },
    });
  });

  test("rejects missing diagnostics when requested", async () => {
    const response = await handleIssueReportRequest(
      makeMultipartRequest(validPayload, undefined),
      { linearApiKey: "linear", linearTeamId: "team" },
      failingFetch
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "invalid_diagnostics" },
    });
  });

  test("rejects oversized requests before parsing form data", async () => {
    const response = await handleIssueReportRequest(
      new Request("https://suniye.test/api/issue-reports", {
        method: "POST",
        headers: {
          "Content-Type": "multipart/form-data; boundary=test",
          "Content-Length": String(11 * 1024 * 1024),
        },
      }),
      { linearApiKey: "linear", linearTeamId: "team" },
      failingFetch
    );

    expect(response.status).toBe(413);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "request_too_large" },
    });
  });

  test("creates Linear upload, issue, and attachment", async () => {
    const calls: Array<{ url: string; body?: string; method?: string }> = [];
    const fetcher = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
      const url = String(input);
      calls.push({
        url,
        method: init?.method,
        body: typeof init?.body === "string" ? init.body : undefined,
      });

      if (url === "https://api.linear.app/graphql") {
        const body = JSON.parse(String(init?.body));
        if (body.query.includes("FileUpload")) {
          return Response.json({
            data: {
              fileUpload: {
                success: true,
                uploadFile: {
                  uploadUrl: "https://upload.linear.test/diagnostics",
                  assetUrl: "https://uploads.linear.app/private/diagnostics.zip",
                  headers: [{ key: "x-upload-token", value: "upload-token" }],
                },
              },
            },
          });
        }
        if (body.query.includes("IssueCreate")) {
          expect(body.variables.input.labelIds).toEqual(["label"]);
          return Response.json({
            data: {
              issueCreate: {
                success: true,
                issue: {
                  id: "issue-id",
                  identifier: "KIS-128",
                  url: "https://linear.app/kishan/issue/KIS-128/report",
                },
              },
            },
          });
        }
        if (body.query.includes("AttachmentCreate")) {
          return Response.json({
            data: {
              attachmentCreate: {
                success: true,
              },
            },
          });
        }
      }

      if (url === "https://upload.linear.test/diagnostics") {
        return new Response(null, { status: 200 });
      }

      throw new Error(`Unexpected fetch ${url}`);
    };

    const response = await handleIssueReportRequest(
      makeMultipartRequest(validPayload, makeZipFile()),
      {
        linearApiKey: "linear",
        linearTeamId: "team",
        linearReportLabelId: "label",
      },
      fetcher
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      reportId: "report-123",
      issueId: "issue-id",
      issueIdentifier: "KIS-128",
      issueUrl: "https://linear.app/kishan/issue/KIS-128/report",
    });
    expect(calls.map((call) => call.url)).toEqual([
      "https://api.linear.app/graphql",
      "https://upload.linear.test/diagnostics",
      "https://api.linear.app/graphql",
      "https://api.linear.app/graphql",
    ]);
  });
});

describe("Linear issue description", () => {
  test("includes user report and metadata", () => {
    const description = makeLinearIssueDescription(
      validPayload,
      "https://uploads.linear.app/private/diagnostics.zip"
    );

    expect(description).toContain("Recording finishes but no text appears");
    expect(description).toContain("- Report ID: report-123");
    expect(description).toContain("- Accessibility permission: missing");
    expect(description).toContain("[Download diagnostics.zip]");
  });
});

function makeMultipartRequest(payload: unknown, diagnostics?: File): Request {
  const form = new FormData();
  form.set("payload", JSON.stringify(payload));
  if (diagnostics) {
    form.set("diagnostics", diagnostics);
  }
  return new Request("https://suniye.test/api/issue-reports", {
    method: "POST",
    body: form,
  });
}

function makeZipFile(size = 24): File {
  return new File([new Uint8Array(size)], "diagnostics.zip", {
    type: "application/zip",
  });
}

async function failingFetch(): Promise<Response> {
  throw new Error("fetch should not be called");
}
