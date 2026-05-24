import { describe, expect, test } from "bun:test";
import {
  handleIssueReportRequest,
  makeLinearIssueDescription,
  type IssueReportEndpointConfig,
  type IssueReportPayload,
} from "../src/lib/issueReports";
import {
  issueReportConfigFromPagesEnv,
  onRequest as handlePagesIssueReportRequest,
} from "../functions/api/issue-reports";

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
  test("Cloudflare Pages function rejects non-POST requests through the shared handler", async () => {
    const response = await handlePagesIssueReportRequest({
      request: new Request("https://suniye.test/api/issue-reports"),
      env: {
        LINEAR_API_KEY: "linear",
        LINEAR_TEAM_ID: "team",
      },
    });

    expect(response.status).toBe(405);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "method_not_allowed" },
    });
  });

  test("Cloudflare Pages function maps Linear bindings from context env", () => {
    expect(issueReportConfigFromPagesEnv({
      LINEAR_API_KEY: "linear",
      LINEAR_TEAM_ID: "team",
      LINEAR_REPORT_LABEL_ID: "label",
      LINEAR_REPORT_PROJECT_ID: "project",
      LINEAR_REPORT_STATE_ID: "state",
    })).toEqual({
      linearApiKey: "linear",
      linearTeamId: "team",
      linearReportLabelId: "label",
      linearReportProjectId: "project",
      linearReportStateId: "state",
    });
  });

  test("rejects non-POST requests", async () => {
    const response = await handleIssueReportRequest(
      new Request("https://suniye.test/api/issue-reports"),
      linearConfig(),
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
      { rateLimit: false },
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
      linearConfig(),
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
      linearConfig(),
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
      linearConfig(),
      failingFetch
    );

    expect(response.status).toBe(413);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "request_too_large" },
    });
  });

  test("rejects oversized streamed requests without Content-Length", async () => {
    const response = await handleIssueReportRequest(
      new Request("https://suniye.test/api/issue-reports", {
        method: "POST",
        headers: {
          "Content-Type": "multipart/form-data; boundary=test",
        },
        body: new Blob([new Uint8Array(11 * 1024 * 1024)]),
      }),
      linearConfig(),
      failingFetch
    );

    expect(response.status).toBe(413);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "request_too_large" },
    });
  });

  test("rejects rate-limited requests before parsing the form", async () => {
    const store = new MemoryRateLimitStore();
    await store.put("unused", "{}", 1);
    store.nextGetValue = JSON.stringify({
      count: 1,
      resetAt: Math.floor(Date.now() / 1000) + 60,
    });

    const response = await handleIssueReportRequest(
      new Request("https://suniye.test/api/issue-reports", {
        method: "POST",
        headers: {
          "Content-Type": "multipart/form-data; boundary=test",
          "CF-Connecting-IP": "203.0.113.1",
          "User-Agent": "Suniye/IssueReporter",
        },
      }),
      linearConfig({
        rateLimit: {
          store,
          maxRequests: 1,
          windowSeconds: 60,
        },
      }),
      failingFetch
    );

    expect(response.status).toBe(429);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "rate_limited" },
    });
  });

  test("rate limit key cannot be bypassed by rotating User-Agent", async () => {
    const store = new MemoryRateLimitStore();
    const config = linearConfig({
      rateLimit: {
        store,
        maxRequests: 1,
        windowSeconds: 60,
      },
    });

    const first = await handleIssueReportRequest(
      makeRateLimitedProbeRequest("203.0.113.2", "Suniye/1.0"),
      config,
      failingFetch
    );
    const second = await handleIssueReportRequest(
      makeRateLimitedProbeRequest("203.0.113.2", "DifferentAgent/1.0"),
      config,
      failingFetch
    );

    expect(first.status).toBe(415);
    expect(second.status).toBe(429);
  });

  test("serializes concurrent rate limit updates for the same key", async () => {
    const store = new MemoryRateLimitStore();
    store.getDelayMs = 10;
    store.putDelayMs = 10;

    const config = linearConfig({
      rateLimit: {
        store,
        maxRequests: 1,
        windowSeconds: 60,
      },
    });

    const responses = await Promise.all([
      handleIssueReportRequest(makeRateLimitedProbeRequest("203.0.113.3", "Suniye/1.0"), config, failingFetch),
      handleIssueReportRequest(makeRateLimitedProbeRequest("203.0.113.3", "DifferentAgent/1.0"), config, failingFetch),
    ]);

    expect(responses.map((response) => response.status).sort()).toEqual([415, 429]);
  });

  test("rejects malformed nested metadata as invalid payload", async () => {
    const response = await handleIssueReportRequest(
      makeMultipartRequest({
        ...validPayload,
        model: { ...validPayload.model, installedModelIds: "parakeetV3" },
      }, makeZipFile()),
      linearConfig(),
      failingFetch
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "invalid_payload" },
    });
  });

  test("creates Linear upload, issue, and attachment", async () => {
    const calls: Array<{ url: string; authorization?: string | null; body?: string; method?: string }> = [];
    const fetcher = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
      const url = String(input);
      calls.push({
        url,
        authorization: new Headers(init?.headers).get("Authorization"),
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
        ...linearConfig(),
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
    expect(
      calls
        .filter((call) => call.url === "https://api.linear.app/graphql")
        .map((call) => call.authorization)
    ).toEqual(["linear", "linear", "linear"]);
  });

  test("returns created issue when attachment creation fails", async () => {
    const fetcher = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
      const url = String(input);

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
                  headers: [],
                },
              },
            },
          });
        }
        if (body.query.includes("IssueCreate")) {
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
                success: false,
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
      linearConfig(),
      fetcher
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      success: true,
      issueId: "issue-id",
      issueIdentifier: "KIS-128",
    });
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

function linearConfig(overrides: Partial<IssueReportEndpointConfig> = {}): IssueReportEndpointConfig {
  return {
    linearApiKey: "linear",
    linearTeamId: "team",
    rateLimit: false,
    ...overrides,
  };
}

function makeRateLimitedProbeRequest(ip: string, userAgent: string): Request {
  return new Request("https://suniye.test/api/issue-reports", {
    method: "POST",
    headers: {
      "Content-Type": "text/plain",
      "CF-Connecting-IP": ip,
      "User-Agent": userAgent,
    },
    body: "probe",
  });
}

async function failingFetch(): Promise<Response> {
  throw new Error("fetch should not be called");
}

class MemoryRateLimitStore {
  nextGetValue: string | null = null;
  getDelayMs = 0;
  putDelayMs = 0;
  values = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    if (this.getDelayMs > 0) {
      await Bun.sleep(this.getDelayMs);
    }
    return this.nextGetValue ?? this.values.get(key) ?? null;
  }

  async put(key: string, value: string, _ttlSeconds?: number): Promise<void> {
    if (this.putDelayMs > 0) {
      await Bun.sleep(this.putDelayMs);
    }
    this.values.set(key, value);
  }
}
