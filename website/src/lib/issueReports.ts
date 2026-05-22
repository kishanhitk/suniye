export const issueReportTypes = [
  "dictation",
  "hotkey",
  "transcription",
  "textInsertion",
  "magicFormat",
  "modelDownload",
  "permissions",
  "update",
  "other",
] as const;

export type IssueReportType = (typeof issueReportTypes)[number];

export interface IssueReportPayload {
  schemaVersion: 1;
  reportId: string;
  issueType: IssueReportType;
  title: string;
  description: string;
  contactEmail?: string;
  includeDiagnostics: boolean;
  app: {
    version: string;
    build?: string;
    macOSVersion: string;
    architecture: string;
  };
  state: {
    phase: string;
    lastError?: string;
    updateStatus?: string;
  };
  permissions: {
    microphone: boolean;
    accessibility: boolean;
  };
  model: {
    selectedModelId: string;
    selectedModelName: string;
    selectedModelInstalled: boolean;
    installedModelIds: string[];
  };
  settings: {
    autoSubmitEnabled: boolean;
    echoCancellationEnabled: boolean;
    soundFeedbackEnabled: boolean;
    hideFloatingIndicatorWhenIdle: boolean;
    llmEnabled: boolean;
    llmHasAPIKey: boolean;
  };
}

export interface IssueReportEndpointConfig {
  linearApiKey?: string;
  linearTeamId?: string;
  linearReportLabelId?: string;
  linearReportProjectId?: string;
  linearReportStateId?: string;
}

export interface IssueReportSuccess {
  success: true;
  reportId: string;
  issueId: string;
  issueIdentifier: string;
  issueUrl: string;
}

export interface IssueReportFailure {
  success: false;
  error: {
    code: string;
    message: string;
  };
}

export type IssueReportResponse = IssueReportSuccess | IssueReportFailure;

interface LinearGraphQLResponse<T> {
  data?: T;
  errors?: Array<{ message?: string; extensions?: { code?: string } }>;
}

interface LinearFileUploadResponse {
  fileUpload: {
    success: boolean;
    uploadFile?: {
      uploadUrl: string;
      assetUrl: string;
      headers: Array<{ key: string; value: string }>;
    };
  };
}

interface LinearIssueCreateResponse {
  issueCreate: {
    success: boolean;
    issue?: {
      id: string;
      identifier: string;
      url: string;
    };
  };
}

interface LinearAttachmentCreateResponse {
  attachmentCreate: {
    success: boolean;
  };
}

export const maxDiagnosticsBytes = 10 * 1024 * 1024;
const maxRequestBytes = maxDiagnosticsBytes + 128 * 1024;

export function jsonResponse(payload: IssueReportResponse, status = payload.success ? 200 : 400): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

export async function handleIssueReportRequest(
  request: Request,
  config: IssueReportEndpointConfig,
  fetcher: typeof fetch = fetch
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse(errorResponse("method_not_allowed", "Use POST for issue reports."), 405);
  }

  if (!config.linearApiKey || !config.linearTeamId) {
    return jsonResponse(errorResponse("server_not_configured", "Issue reporting is not configured."), 503);
  }

  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.toLowerCase().includes("multipart/form-data")) {
    return jsonResponse(errorResponse("invalid_content_type", "Expected multipart/form-data."), 415);
  }

  const contentLength = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > maxRequestBytes) {
    return jsonResponse(errorResponse("request_too_large", "Issue report is too large."), 413);
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return jsonResponse(errorResponse("invalid_form", "Could not read the report form."), 400);
  }

  const payloadPart = form.get("payload");
  if (typeof payloadPart !== "string") {
    return jsonResponse(errorResponse("missing_payload", "Missing report payload."), 400);
  }

  let payload: IssueReportPayload;
  try {
    payload = JSON.parse(payloadPart) as IssueReportPayload;
  } catch {
    return jsonResponse(errorResponse("invalid_payload_json", "Report payload is not valid JSON."), 400);
  }

  const validationErrors = validatePayload(payload);
  if (validationErrors.length > 0) {
    return jsonResponse(
      errorResponse("invalid_payload", validationErrors.join(" ")),
      400
    );
  }

  const diagnosticsPart = form.get("diagnostics");
  const diagnosticsFile = diagnosticsPart instanceof File && diagnosticsPart.size > 0 ? diagnosticsPart : undefined;
  const diagnosticsError = validateDiagnosticsFile(payload, diagnosticsFile);
  if (diagnosticsError) {
    return jsonResponse(errorResponse("invalid_diagnostics", diagnosticsError), 400);
  }

  try {
    const diagnosticsAssetUrl = diagnosticsFile
      ? await uploadFileToLinear(diagnosticsFile, config, fetcher)
      : undefined;

    const issue = await createLinearIssue(payload, diagnosticsAssetUrl, config, fetcher);

    if (diagnosticsAssetUrl) {
      await createLinearAttachment(issue.id, diagnosticsAssetUrl, payload, config, fetcher);
    }

    return jsonResponse({
      success: true,
      reportId: payload.reportId,
      issueId: issue.id,
      issueIdentifier: issue.identifier,
      issueUrl: issue.url,
    });
  } catch (error) {
    console.error("Issue report submission failed", error);
    return jsonResponse(
      errorResponse("linear_submission_failed", "Could not send the report right now."),
      502
    );
  }
}

export function validatePayload(payload: IssueReportPayload): string[] {
  const errors: string[] = [];
  if (payload?.schemaVersion !== 1) {
    errors.push("Unsupported schema version.");
  }
  if (!isReasonableText(payload?.reportId, 8, 100)) {
    errors.push("Report ID is required.");
  }
  if (!issueReportTypes.includes(payload?.issueType)) {
    errors.push("Issue type is invalid.");
  }
  if (!isReasonableText(payload?.title, 3, 160)) {
    errors.push("Title must be 3-160 characters.");
  }
  if (!isReasonableText(payload?.description, 10, 10_000)) {
    errors.push("Description must be 10-10000 characters.");
  }
  if (payload?.contactEmail && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(payload.contactEmail)) {
    errors.push("Contact email is invalid.");
  }
  if (!payload?.app || !payload?.state || !payload?.permissions || !payload?.model || !payload?.settings) {
    errors.push("Required metadata is missing.");
  }
  return errors;
}

export function validateDiagnosticsFile(
  payload: IssueReportPayload,
  diagnosticsFile?: File
): string | undefined {
  if (!payload.includeDiagnostics && diagnosticsFile) {
    return "Diagnostics were attached even though includeDiagnostics is false.";
  }
  if (payload.includeDiagnostics && !diagnosticsFile) {
    return "Diagnostics file is missing.";
  }
  if (!diagnosticsFile) {
    return undefined;
  }
  if (!diagnosticsFile.name.toLowerCase().endsWith(".zip")) {
    return "Diagnostics must be a zip file.";
  }
  if (diagnosticsFile.size > maxDiagnosticsBytes) {
    return "Diagnostics file is too large.";
  }
  return undefined;
}

export function makeLinearIssueDescription(payload: IssueReportPayload, diagnosticsAssetUrl?: string): string {
  const email = payload.contactEmail?.trim() || "Not provided";
  const installedModels = payload.model.installedModelIds.length > 0
    ? payload.model.installedModelIds.join(", ")
    : "None";

  return [
    `User report from Suniye.`,
    ``,
    `## User description`,
    trimForMarkdown(payload.description, 10_000),
    ``,
    `## Metadata`,
    `- Report ID: ${payload.reportId}`,
    `- Type: ${payload.issueType}`,
    `- Contact: ${email}`,
    `- App: ${payload.app.version}${payload.app.build ? ` (${payload.app.build})` : ""}`,
    `- macOS: ${payload.app.macOSVersion}`,
    `- Architecture: ${payload.app.architecture}`,
    `- Phase: ${payload.state.phase}`,
    `- Last error: ${payload.state.lastError || "None"}`,
    `- Update status: ${payload.state.updateStatus || "Unknown"}`,
    `- Microphone permission: ${payload.permissions.microphone ? "granted" : "missing"}`,
    `- Accessibility permission: ${payload.permissions.accessibility ? "granted" : "missing"}`,
    `- Selected model: ${payload.model.selectedModelName} (${payload.model.selectedModelId})`,
    `- Selected model installed: ${payload.model.selectedModelInstalled ? "yes" : "no"}`,
    `- Installed models: ${installedModels}`,
    `- Magic Format enabled: ${payload.settings.llmEnabled ? "yes" : "no"}`,
    `- Magic Format API key present: ${payload.settings.llmHasAPIKey ? "yes" : "no"}`,
    ``,
    `## Diagnostics`,
    diagnosticsAssetUrl ? `[Download diagnostics.zip](${diagnosticsAssetUrl})` : "Not included.",
  ].join("\n");
}

async function uploadFileToLinear(
  file: File,
  config: IssueReportEndpointConfig,
  fetcher: typeof fetch
): Promise<string> {
  const uploadPayload = await linearGraphQL<LinearFileUploadResponse>(
    config,
    `mutation FileUpload($contentType: String!, $filename: String!, $size: Int!) {
      fileUpload(contentType: $contentType, filename: $filename, size: $size) {
        success
        uploadFile {
          uploadUrl
          assetUrl
          headers {
            key
            value
          }
        }
      }
    }`,
    {
      contentType: file.type || "application/zip",
      filename: file.name,
      size: file.size,
    },
    fetcher
  );

  const uploadFile = uploadPayload.fileUpload.uploadFile;
  if (!uploadPayload.fileUpload.success || !uploadFile) {
    throw new Error("Linear did not return an upload target.");
  }

  const headers = new Headers();
  headers.set("Content-Type", file.type || "application/zip");
  headers.set("Cache-Control", "public, max-age=31536000");
  for (const header of uploadFile.headers) {
    headers.set(header.key, header.value);
  }

  const uploadResponse = await fetcher(uploadFile.uploadUrl, {
    method: "PUT",
    headers,
    body: file,
  });

  if (!uploadResponse.ok) {
    throw new Error(`Linear file upload failed: ${uploadResponse.status}`);
  }

  return uploadFile.assetUrl;
}

async function createLinearIssue(
  payload: IssueReportPayload,
  diagnosticsAssetUrl: string | undefined,
  config: IssueReportEndpointConfig,
  fetcher: typeof fetch
): Promise<{ id: string; identifier: string; url: string }> {
  const input: Record<string, unknown> = {
    teamId: config.linearTeamId,
    title: `[User Report] ${trimForMarkdown(payload.title, 140)}`,
    description: makeLinearIssueDescription(payload, diagnosticsAssetUrl),
  };

  if (config.linearReportProjectId) {
    input.projectId = config.linearReportProjectId;
  }
  if (config.linearReportStateId) {
    input.stateId = config.linearReportStateId;
  }
  if (config.linearReportLabelId) {
    input.labelIds = [config.linearReportLabelId];
  }

  const response = await linearGraphQL<LinearIssueCreateResponse>(
    config,
    `mutation IssueCreate($input: IssueCreateInput!) {
      issueCreate(input: $input) {
        success
        issue {
          id
          identifier
          url
        }
      }
    }`,
    { input },
    fetcher
  );

  const issue = response.issueCreate.issue;
  if (!response.issueCreate.success || !issue) {
    throw new Error("Linear did not create an issue.");
  }

  return issue;
}

async function createLinearAttachment(
  issueId: string,
  diagnosticsAssetUrl: string,
  payload: IssueReportPayload,
  config: IssueReportEndpointConfig,
  fetcher: typeof fetch
): Promise<void> {
  const response = await linearGraphQL<LinearAttachmentCreateResponse>(
    config,
    `mutation AttachmentCreate($input: AttachmentCreateInput!) {
      attachmentCreate(input: $input) {
        success
      }
    }`,
    {
      input: {
        issueId,
        title: "Suniye diagnostics",
        subtitle: payload.reportId,
        url: diagnosticsAssetUrl,
        metadata: {
          title: "Suniye diagnostics",
          attributes: [
            { name: "Report ID", value: payload.reportId },
            { name: "App", value: payload.app.version },
            { name: "macOS", value: payload.app.macOSVersion },
            { name: "Issue type", value: payload.issueType },
          ],
        },
      },
    },
    fetcher
  );

  if (!response.attachmentCreate.success) {
    throw new Error("Linear did not create an attachment.");
  }
}

async function linearGraphQL<T>(
  config: IssueReportEndpointConfig,
  query: string,
  variables: Record<string, unknown>,
  fetcher: typeof fetch
): Promise<T> {
  const response = await fetcher("https://api.linear.app/graphql", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.linearApiKey}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({ query, variables }),
  });

  if (!response.ok) {
    throw new Error(`Linear GraphQL HTTP ${response.status}`);
  }

  const payload = await response.json() as LinearGraphQLResponse<T>;
  if (payload.errors?.length) {
    throw new Error(payload.errors.map((error) => error.message ?? "Linear error").join("; "));
  }
  if (!payload.data) {
    throw new Error("Linear response did not include data.");
  }

  return payload.data;
}

function errorResponse(code: string, message: string): IssueReportFailure {
  return {
    success: false,
    error: { code, message },
  };
}

function isReasonableText(value: unknown, minLength: number, maxLength: number): value is string {
  if (typeof value !== "string") {
    return false;
  }
  const trimmed = value.trim();
  return trimmed.length >= minLength && trimmed.length <= maxLength;
}

function trimForMarkdown(value: string, maxLength: number): string {
  const trimmed = value.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return `${trimmed.slice(0, maxLength - 1)}…`;
}
