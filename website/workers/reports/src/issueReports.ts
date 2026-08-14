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
  rateLimit?: IssueReportRateLimitConfig | false;
}

/** The Cloudflare environment bindings the issue-report endpoint reads. */
export interface IssueReportEnv {
  LINEAR_API_KEY?: string;
  LINEAR_TEAM_ID?: string;
  LINEAR_REPORT_LABEL_ID?: string;
  LINEAR_REPORT_PROJECT_ID?: string;
  LINEAR_REPORT_STATE_ID?: string;
}

/** Maps Cloudflare env bindings to the endpoint config. Pure, so it's unit-testable. */
export function issueReportConfigFromEnv(env: IssueReportEnv): IssueReportEndpointConfig {
  return {
    linearApiKey: env.LINEAR_API_KEY,
    linearTeamId: env.LINEAR_TEAM_ID,
    linearReportLabelId: env.LINEAR_REPORT_LABEL_ID,
    linearReportProjectId: env.LINEAR_REPORT_PROJECT_ID,
    linearReportStateId: env.LINEAR_REPORT_STATE_ID,
  };
}

export interface IssueReportRateLimitConfig {
  store?: IssueReportRateLimitStore;
  maxRequests?: number;
  windowSeconds?: number;
  failureMode?: "open" | "closed";
}

export interface IssueReportRateLimitStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, ttlSeconds: number): Promise<void>;
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
const defaultRateLimitMaxRequests = 6;
const defaultRateLimitWindowSeconds = 10 * 60;

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

  const rateLimitResponse = await checkRateLimit(request, config.rateLimit);
  if (rateLimitResponse) {
    return rateLimitResponse;
  }

  if (!config.linearApiKey || !config.linearTeamId) {
    return jsonResponse(errorResponse("server_not_configured", "Issue reporting is not configured."), 503);
  }

  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.toLowerCase().includes("multipart/form-data")) {
    return jsonResponse(errorResponse("invalid_content_type", "Expected multipart/form-data."), 415);
  }

  const boundedRequest = await requestWithSizeLimit(request, maxRequestBytes);
  if (boundedRequest instanceof Response) {
    return boundedRequest;
  }

  let form: FormData;
  try {
    form = await boundedRequest.formData();
  } catch {
    return jsonResponse(errorResponse("invalid_form", "Could not read the report form."), 400);
  }

  const payloadPart = form.get("payload");
  if (typeof payloadPart !== "string") {
    return jsonResponse(errorResponse("missing_payload", "Missing report payload."), 400);
  }

  let payload: unknown;
  try {
    payload = JSON.parse(payloadPart);
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
  const issueReportPayload = payload as IssueReportPayload;

  // workers-types mistypes FormData.get() as string|null; unknown lets instanceof File narrow.
  const diagnosticsPart: unknown = form.get("diagnostics");
  const diagnosticsFile = diagnosticsPart instanceof File && diagnosticsPart.size > 0 ? diagnosticsPart : undefined;
  const diagnosticsError = validateDiagnosticsFile(issueReportPayload, diagnosticsFile);
  if (diagnosticsError) {
    return jsonResponse(errorResponse("invalid_diagnostics", diagnosticsError), 400);
  }

  try {
    const diagnosticsAssetUrl = diagnosticsFile
      ? await uploadFileToLinear(diagnosticsFile, config, fetcher)
      : undefined;

    const issue = await createLinearIssue(issueReportPayload, diagnosticsAssetUrl, config, fetcher);

    if (diagnosticsAssetUrl) {
      try {
        await createLinearAttachment(issue.id, diagnosticsAssetUrl, issueReportPayload, config, fetcher);
      } catch (error) {
        console.error("Issue report attachment creation failed", error);
      }
    }

    return jsonResponse({
      success: true,
      reportId: issueReportPayload.reportId,
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

export function validatePayload(payload: unknown): string[] {
  const errors: string[] = [];
  if (!isObject(payload)) {
    return ["Report payload must be an object."];
  }

  if (payload.schemaVersion !== 1) {
    errors.push("Unsupported schema version.");
  }
  if (!isReasonableText(payload.reportId, 8, 100)) {
    errors.push("Report ID is required.");
  }
  if (!issueReportTypes.includes(payload.issueType as IssueReportType)) {
    errors.push("Issue type is invalid.");
  }
  if (!isReasonableText(payload.title, 3, 160)) {
    errors.push("Title must be 3-160 characters.");
  }
  if (!isReasonableText(payload.description, 10, 10_000)) {
    errors.push("Description must be 10-10000 characters.");
  }
  if (payload.contactEmail !== undefined && typeof payload.contactEmail !== "string") {
    errors.push("Contact email is invalid.");
  } else if (payload.contactEmail && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(payload.contactEmail)) {
    errors.push("Contact email is invalid.");
  }
  if (typeof payload.includeDiagnostics !== "boolean") {
    errors.push("includeDiagnostics must be a boolean.");
  }

  validateAppMetadata(payload.app, errors);
  validateStateMetadata(payload.state, errors);
  validatePermissionMetadata(payload.permissions, errors);
  validateModelMetadata(payload.model, errors);
  validateSettingsMetadata(payload.settings, errors);

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
  if (!config.linearApiKey) {
    throw new Error("Linear API key is not configured.");
  }

  const response = await fetcher("https://api.linear.app/graphql", {
    method: "POST",
    headers: {
      Authorization: config.linearApiKey,
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

// Deliberate near-duplicate of workers/ingest/src/rateLimit.ts; the workers bundle independently.
async function checkRateLimit(
  request: Request,
  config: IssueReportRateLimitConfig | false | undefined
): Promise<Response | undefined> {
  if (config === false) {
    return undefined;
  }

  const store = config?.store ?? defaultRateLimitStore();
  if (!store) {
    console.error("Issue report rate limiter is not available.");
    return config?.failureMode === "open"
      ? undefined
      : jsonResponse(errorResponse("rate_limiter_unavailable", "Issue reporting is temporarily unavailable."), 503);
  }

  const maxRequests = config?.maxRequests ?? defaultRateLimitMaxRequests;
  const windowSeconds = config?.windowSeconds ?? defaultRateLimitWindowSeconds;
  const now = Math.floor(Date.now() / 1000);
  const key = await makeRateLimitKey(request);

  try {
    return await withRateLimitKeyLock(key, async () => {
      const current = parseRateLimitRecord(await store.get(key), now, windowSeconds);
      if (current.count >= maxRequests) {
        console.warn("Issue report rate limit exceeded", { key, resetAt: current.resetAt });
        return jsonResponse(errorResponse("rate_limited", "Too many issue reports. Please try again later."), 429);
      }

      await store.put(
        key,
        JSON.stringify({ count: current.count + 1, resetAt: current.resetAt }),
        Math.max(1, current.resetAt - now)
      );
      return undefined;
    });
  } catch (error) {
    console.error("Issue report rate limiter failed", error);
    return config?.failureMode === "open"
      ? undefined
      : jsonResponse(errorResponse("rate_limiter_unavailable", "Issue reporting is temporarily unavailable."), 503);
  }
}

async function requestWithSizeLimit(request: Request, maxBytes: number): Promise<Request | Response> {
  const contentLengthHeader = request.headers.get("Content-Length");
  if (contentLengthHeader) {
    const contentLength = Number(contentLengthHeader);
    if (Number.isFinite(contentLength) && contentLength > maxBytes) {
      return jsonResponse(errorResponse("request_too_large", "Issue report is too large."), 413);
    }
  }

  if (!request.body) {
    return request;
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let receivedBytes = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      if (!value) {
        continue;
      }

      receivedBytes += value.byteLength;
      if (receivedBytes > maxBytes) {
        await reader.cancel();
        return jsonResponse(errorResponse("request_too_large", "Issue report is too large."), 413);
      }

      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(receivedBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }

  const headers = new Headers(request.headers);
  headers.delete("Content-Length");

  return new Request(request.url, {
    method: request.method,
    headers,
    body,
  });
}

function defaultRateLimitStore(): IssueReportRateLimitStore | undefined {
  const cacheStorage = (globalThis as typeof globalThis & { caches?: CacheStorage }).caches;
  const cache = cacheStorage?.default;
  if (!cache) {
    return undefined;
  }

  return {
    async get(key: string): Promise<string | null> {
      const response = await cache.match(rateLimitCacheRequest(key));
      return response ? response.text() : null;
    },
    async put(key: string, value: string, ttlSeconds: number): Promise<void> {
      await cache.put(
        rateLimitCacheRequest(key),
        new Response(value, {
          headers: {
            "Cache-Control": `public, max-age=${ttlSeconds}`,
          },
        })
      );
    },
  };
}

const rateLimitKeyLocks = new Map<string, Promise<void>>();

async function withRateLimitKeyLock<T>(key: string, operation: () => Promise<T>): Promise<T> {
  const previousLock = rateLimitKeyLocks.get(key) ?? Promise.resolve();
  let releaseCurrentLock: () => void = () => {};
  const currentLock = new Promise<void>((resolve) => {
    releaseCurrentLock = resolve;
  });
  const nextLock = previousLock.catch(() => undefined).then(() => currentLock);
  rateLimitKeyLocks.set(key, nextLock);

  await previousLock.catch(() => undefined);

  try {
    return await operation();
  } finally {
    releaseCurrentLock();
    if (rateLimitKeyLocks.get(key) === nextLock) {
      rateLimitKeyLocks.delete(key);
    }
  }
}

function rateLimitCacheRequest(key: string): Request {
  return new Request(`https://suniye-rate-limit.invalid/issue-reports/${encodeURIComponent(key)}`);
}

async function makeRateLimitKey(request: Request): Promise<string> {
  const ip = request.headers.get("CF-Connecting-IP")
    ?? request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim()
    ?? "unknown";
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(ip)
  );
  const hash = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  return hash.slice(0, 32);
}

function parseRateLimitRecord(
  value: string | null,
  now: number,
  windowSeconds: number
): { count: number; resetAt: number } {
  if (!value) {
    return { count: 0, resetAt: now + windowSeconds };
  }

  try {
    const parsed = JSON.parse(value) as { count?: unknown; resetAt?: unknown };
    if (
      typeof parsed.count !== "number"
      || typeof parsed.resetAt !== "number"
      || parsed.resetAt <= now
    ) {
      return { count: 0, resetAt: now + windowSeconds };
    }
    return { count: parsed.count, resetAt: parsed.resetAt };
  } catch {
    return { count: 0, resetAt: now + windowSeconds };
  }
}

function validateAppMetadata(value: unknown, errors: string[]): void {
  if (!isObject(value)) {
    errors.push("App metadata is missing.");
    return;
  }
  if (!isReasonableText(value.version, 1, 100)) {
    errors.push("App version is required.");
  }
  if (value.build !== undefined && !isReasonableText(value.build, 1, 100)) {
    errors.push("App build is invalid.");
  }
  if (!isReasonableText(value.macOSVersion, 1, 100)) {
    errors.push("macOS version is required.");
  }
  if (!isReasonableText(value.architecture, 1, 100)) {
    errors.push("Architecture is required.");
  }
}

function validateStateMetadata(value: unknown, errors: string[]): void {
  if (!isObject(value)) {
    errors.push("State metadata is missing.");
    return;
  }
  if (!isReasonableText(value.phase, 1, 100)) {
    errors.push("App phase is required.");
  }
  if (value.lastError !== undefined && typeof value.lastError !== "string") {
    errors.push("Last error is invalid.");
  }
  if (value.updateStatus !== undefined && typeof value.updateStatus !== "string") {
    errors.push("Update status is invalid.");
  }
}

function validatePermissionMetadata(value: unknown, errors: string[]): void {
  if (!isObject(value)) {
    errors.push("Permission metadata is missing.");
    return;
  }
  if (typeof value.microphone !== "boolean") {
    errors.push("Microphone permission is invalid.");
  }
  if (typeof value.accessibility !== "boolean") {
    errors.push("Accessibility permission is invalid.");
  }
}

function validateModelMetadata(value: unknown, errors: string[]): void {
  if (!isObject(value)) {
    errors.push("Model metadata is missing.");
    return;
  }
  if (!isReasonableText(value.selectedModelId, 1, 200)) {
    errors.push("Selected model ID is required.");
  }
  if (!isReasonableText(value.selectedModelName, 1, 200)) {
    errors.push("Selected model name is required.");
  }
  if (typeof value.selectedModelInstalled !== "boolean") {
    errors.push("Selected model install state is invalid.");
  }
  if (!isStringArray(value.installedModelIds)) {
    errors.push("Installed model IDs are invalid.");
  }
}

function validateSettingsMetadata(value: unknown, errors: string[]): void {
  if (!isObject(value)) {
    errors.push("Settings metadata is missing.");
    return;
  }

  for (const key of [
    "autoSubmitEnabled",
    "echoCancellationEnabled",
    "soundFeedbackEnabled",
    "hideFloatingIndicatorWhenIdle",
    "llmEnabled",
    "llmHasAPIKey",
  ]) {
    if (typeof value[key] !== "boolean") {
      errors.push(`${key} setting is invalid.`);
    }
  }
}

function errorResponse(code: string, message: string): IssueReportFailure {
  return {
    success: false,
    error: { code, message },
  };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isReasonableText(value: unknown, minLength: number, maxLength: number): value is string {
  if (typeof value !== "string") {
    return false;
  }
  const trimmed = value.trim();
  return trimmed.length >= minLength && trimmed.length <= maxLength;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value)
    && value.length <= 100
    && value.every((item) => isReasonableText(item, 1, 200));
}

function trimForMarkdown(value: string, maxLength: number): string {
  const trimmed = value.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return `${trimmed.slice(0, maxLength - 1)}…`;
}
