// Post-deploy smoke test for the deployed issue-report endpoint. Sends the
// exact request shape the macOS app sends: multipart/form-data, NO Origin
// header. Creates a real Linear issue; auto-archives it when LINEAR_API_KEY
// is set in the environment, otherwise prints the issue URL for manual cleanup.
//
// Usage: bun scripts/smoke.ts [endpoint]
//   endpoint defaults to https://suniye.app/api/issue-reports

const endpoint = process.argv[2] ?? "https://suniye.app/api/issue-reports";

const payload = {
  schemaVersion: 1,
  reportId: `smoke-${Date.now()}`,
  issueType: "other",
  title: "[API test] smoke — safe to close",
  description:
    "Automated post-deploy smoke test of the issue-report endpoint. Safe to close or archive.",
  includeDiagnostics: false,
  app: { version: "0.0.0-smoke", macOSVersion: "smoke", architecture: "arm64" },
  state: { phase: "idle" },
  permissions: { microphone: true, accessibility: true },
  model: {
    selectedModelId: "smoke",
    selectedModelName: "Smoke Test",
    selectedModelInstalled: true,
    installedModelIds: ["smoke"],
  },
  settings: {
    autoSubmitEnabled: false,
    echoCancellationEnabled: false,
    soundFeedbackEnabled: false,
    hideFloatingIndicatorWhenIdle: false,
    llmEnabled: false,
    llmHasAPIKey: false,
  },
};

const form = new FormData();
form.append("payload", JSON.stringify(payload));

const response = await fetch(endpoint, { method: "POST", body: form });
const bodyText = await response.text();

if (!response.ok) {
  console.error(`FAIL: HTTP ${response.status} from ${endpoint}`);
  console.error(bodyText);
  process.exit(1);
}

const body = JSON.parse(bodyText) as {
  success: boolean;
  issueId?: string;
  issueIdentifier?: string;
  issueUrl?: string;
};

if (!body.success || !body.issueId) {
  console.error(`FAIL: unexpected response body from ${endpoint}`);
  console.error(bodyText);
  process.exit(1);
}

console.log(`OK: HTTP ${response.status}, created ${body.issueIdentifier} (${body.issueUrl})`);

const apiKey = process.env.LINEAR_API_KEY;
if (!apiKey) {
  console.log("LINEAR_API_KEY not set — archive the smoke issue manually.");
  process.exit(0);
}

const archive = await fetch("https://api.linear.app/graphql", {
  method: "POST",
  headers: {
    Authorization: apiKey,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    query: "mutation IssueArchive($id: String!) { issueArchive(id: $id) { success } }",
    variables: { id: body.issueId },
  }),
});
const archiveBody = (await archive.json()) as {
  data?: { issueArchive?: { success?: boolean } };
  errors?: Array<{ message?: string }>;
};

if (!archive.ok || !archiveBody.data?.issueArchive?.success) {
  console.error(`WARN: could not archive ${body.issueIdentifier} — archive it manually.`);
  console.error(JSON.stringify(archiveBody.errors ?? archiveBody));
} else {
  console.log(`Archived ${body.issueIdentifier}.`);
}
