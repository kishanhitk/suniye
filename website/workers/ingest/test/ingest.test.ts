import { describe, expect, test } from "bun:test";
import { handleIngestRequest, ingestConfigFromEnv } from "../src/ingest";
import { buildDataPoint } from "../src/eventSchema";
import type { AnalyticsEngineDataset, IngestEnv, RateLimitStore, WireBatch, WireEvent } from "../src/types";
import type { DataPoint } from "../src/eventSchema";

function mockEvents(): { binding: AnalyticsEngineDataset; points: DataPoint[] } {
  const points: DataPoint[] = [];
  return {
    binding: { writeDataPoint: (p) => points.push(p as DataPoint) },
    points,
  };
}

function mockDB() {
  const calls: Array<{ query: string; binds: unknown[] }> = [];
  const db = {
    prepare(query: string) {
      const stmt = {
        binds: [] as unknown[],
        bind(...values: unknown[]) { this.binds = values; return this; },
        async run() { calls.push({ query, binds: this.binds }); return {}; },
      };
      return stmt;
    },
  };
  return { db, calls };
}

class MemoryStore implements RateLimitStore {
  m = new Map<string, string>();
  async get(k: string) { return this.m.get(k) ?? null; }
  async put(k: string, v: string) { this.m.set(k, v); }
}

function event(name: string, props: Record<string, string | number | boolean> = {}): WireEvent {
  return { event_id: "e-" + name, event_ts: 1_700_000_000_000, session_id: "s1", name, props };
}

function batch(events: WireEvent[], overrides: Partial<WireBatch> = {}): WireBatch {
  return {
    schema_version: 1, install_id: "install-1", app_version: "0.0.8",
    build: "8", channel: "stable", is_debug: false, sent_at: 1_700_000_000_000,
    events, ...overrides,
  };
}

function request(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://ingest.example/api/v1/events", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-IPCountry": "US", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const noRateLimit = { rateLimit: false as const };

describe("handleIngestRequest", () => {
  test("rejects non-POST", async () => {
    const res = await handleIngestRequest(new Request("https://x/api/v1/events"), {}, noRateLimit);
    expect(res.status).toBe(405);
  });

  test("rejects non-JSON content type", async () => {
    const res = await handleIngestRequest(request(batch([event("app_launch")]), { "Content-Type": "text/plain" }), {}, noRateLimit);
    expect(res.status).toBe(415);
  });

  test("rejects invalid JSON", async () => {
    const res = await handleIngestRequest(request("{not json"), {}, noRateLimit);
    expect(res.status).toBe(400);
  });

  test("rejects wrong schema version", async () => {
    const res = await handleIngestRequest(request(batch([event("x")], { schema_version: 2 })), {}, noRateLimit);
    expect(res.status).toBe(400);
  });

  test("rejects missing install_id", async () => {
    const res = await handleIngestRequest(request(batch([event("x")], { install_id: "" })), {}, noRateLimit);
    expect(res.status).toBe(400);
  });

  test("rejects non-scalar prop values", async () => {
    const bad = batch([{ ...event("x"), props: { nested: { a: 1 } as unknown as string } }]);
    const res = await handleIngestRequest(request(bad), {}, noRateLimit);
    expect(res.status).toBe(400);
  });

  test("rejects props objects with too many keys", async () => {
    const many: Record<string, number> = {};
    for (let i = 0; i < 41; i++) many["k" + i] = i;
    const res = await handleIngestRequest(request(batch([{ ...event("x"), props: many }])), {}, noRateLimit);
    expect(res.status).toBe(400);
  });

  test("rejects props whose JSON backstop would blow the AE blob budget", async () => {
    const big = { blob: "x".repeat(500), blob2: "y".repeat(500), blob3: "z".repeat(500), blob4: "w".repeat(500), blob5: "q".repeat(500), blob6: "r".repeat(500), blob7: "s".repeat(500) };
    const res = await handleIngestRequest(request(batch([{ ...event("x"), props: big }])), {}, noRateLimit);
    expect(res.status).toBe(400);
  });

  test("writes one data point per event", async () => {
    const events = mockEvents();
    const env: IngestEnv = { EVENTS: events.binding };
    const res = await handleIngestRequest(
      request(batch([event("dictation_completed", { word_count: 42 }), event("dictation_empty")])),
      env, noRateLimit
    );
    expect(res.status).toBe(200);
    expect(events.points.length).toBe(2);
    expect(events.points[0].indexes).toEqual(["install-1"]);
    expect(events.points[0].blobs[0]).toBe("dictation_completed");
    expect(events.points[0].blobs[18]).toBe("US"); // server-derived country
  });

  test("is_debug batch is accepted but dropped", async () => {
    const events = mockEvents();
    const res = await handleIngestRequest(request(batch([event("x")], { is_debug: true })), { EVENTS: events.binding }, noRateLimit);
    expect(res.status).toBe(200);
    expect(events.points.length).toBe(0);
  });

  test("app_launch upserts install with device fields", async () => {
    const events = mockEvents();
    const { db, calls } = mockDB();
    const env: IngestEnv = { EVENTS: events.binding, INSTALLS_DB: db };
    await handleIngestRequest(
      request(batch([event("app_launch", { os_version: "15.5", mac_model: "mac15-3", chip: "apple-m3-pro", ram_gb: 36, cpu_cores: 12 })])),
      env, noRateLimit
    );
    expect(calls.length).toBe(1);
    expect(calls[0].query).toContain("INSERT INTO installs");
    expect(calls[0].binds).toContain("install-1");
    expect(calls[0].binds).toContain("apple-m3-pro");
    expect(calls[0].binds).toContain(36);
  });

  test("non-app_launch does not upsert", async () => {
    const events = mockEvents();
    const { db, calls } = mockDB();
    await handleIngestRequest(request(batch([event("dictation_completed")])), { EVENTS: events.binding, INSTALLS_DB: db }, noRateLimit);
    expect(calls.length).toBe(0);
  });

  test("kill switch: disabled config drops and tells client to stop", async () => {
    const events = mockEvents();
    const res = await handleIngestRequest(request(batch([event("x")])), { EVENTS: events.binding }, { ...noRateLimit, disabled: true });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ disabled: true });
    expect(events.points.length).toBe(0);
  });

  test("returns sample_rate directive", async () => {
    const events = mockEvents();
    const res = await handleIngestRequest(request(batch([event("x")])), { EVENTS: events.binding }, { ...noRateLimit, sampleRate: 0.5 });
    expect(await res.json()).toMatchObject({ sample_rate: 0.5 });
  });

  test("503 when storage binding missing", async () => {
    const res = await handleIngestRequest(request(batch([event("x")])), {}, noRateLimit);
    expect(res.status).toBe(503);
  });

  test("rate limit enforced", async () => {
    const store = new MemoryStore();
    const cfg = { rateLimit: { store, maxRequests: 1, windowSeconds: 600 } };
    const env: IngestEnv = { EVENTS: mockEvents().binding };
    const first = await handleIngestRequest(request(batch([event("x")]), { "CF-Connecting-IP": "1.2.3.4" }), env, cfg);
    expect(first.status).toBe(200);
    const second = await handleIngestRequest(request(batch([event("x")]), { "CF-Connecting-IP": "1.2.3.4" }), env, cfg);
    expect(second.status).toBe(429);
  });
});

describe("buildDataPoint slot registry", () => {
  // A representative device block (as it rides the batch envelope).
  const device = { chip: "apple-m3-pro", mac_model: "mac15-3", os_version: "15.5", arch: "arm64", ram_gb: 36, cpu_cores: 12 };
  const b = (overrides: Partial<WireBatch> = {}) => batch([], overrides);

  test("maps core fields to fixed slots", () => {
    const ev = event("dictation_completed", {
      word_count: 42, char_count: 213, audio_duration_ms: 4200,
      asr_model: "parakeet-v3", language: "en", was_llm_polished: true,
      target_category: "editor", lat_end_to_end: 512,
    });
    const dp = buildDataPoint(ev, b(), "DE");
    expect(dp.indexes).toEqual(["install-1"]);
    expect(dp.blobs[0]).toBe("dictation_completed"); // blob1
    expect(dp.blobs[4]).toBe("parakeet-v3");          // blob5 asr_model
    expect(dp.blobs[10]).toBe("editor");              // blob11 target_category
    expect(dp.blobs[18]).toBe("DE");                  // blob19 country
    expect(dp.doubles[0]).toBe(1_700_000_000_000);    // double1 event_ts
    expect(dp.doubles[1]).toBe(42);                   // double2 word_count
    expect(dp.doubles[4]).toBe(512);                  // double5 lat_end_to_end
    expect(dp.doubles[15]).toBe(1);                   // double16 was_llm_polished
  });

  test("session_id/app_version/channel populate blob2/3/4 (dead-slot fix)", () => {
    const dp = buildDataPoint(event("dictation_empty"), b({ install_id: "i", app_version: "1.2.3", channel: "beta" }), "");
    expect(dp.blobs[1]).toBe("s1");    // blob2 = session_id (event top-level field)
    expect(dp.blobs[2]).toBe("1.2.3"); // blob3 = app_version (batch envelope)
    expect(dp.blobs[3]).toBe("beta");  // blob4 = channel (batch envelope)
    expect(dp.indexes).toEqual(["i"]);
  });

  test("device block fans out to slots on dictation_completed", () => {
    const dp = buildDataPoint(event("dictation_completed", { word_count: 5 }), b({ device }), "US");
    expect(dp.blobs[15]).toBe("apple-m3-pro"); // blob16 chip
    expect(dp.blobs[16]).toBe("mac15-3");      // blob17 mac_model
    expect(dp.blobs[17]).toBe("15.5");         // blob18 os_version
    expect(dp.blobs[13]).toBe("arm64");        // blob14 arch (dictation has no reason/type/etc.)
    expect(dp.doubles[17]).toBe(12);           // double18 cpu_cores
    expect(dp.doubles[18]).toBe(36);           // double19 ram_gb
    expect(JSON.parse(dp.blobs[19] as string).chip).toBe("apple-m3-pro"); // blob20 backstop
  });

  test("native per-event fields win their shared slots over device (precedence)", () => {
    // error uses blob14=type — arch must NOT clobber it; chip still lands (blob16 free)
    const err = buildDataPoint(event("error", { type: "transcription", code: "timeout" }), b({ device }), "");
    expect(err.blobs[13]).toBe("transcription");                       // blob14 = type (not arch)
    expect(err.blobs[14]).toBe("timeout");                            // blob15 = code
    expect(err.blobs[15]).toBe("apple-m3-pro");                       // blob16 = chip
    expect(JSON.parse(err.blobs[19] as string).arch).toBe("arm64");   // arch survives in blob20

    // audio_backend_used uses blob14=backend, double18=rung
    const audio = buildDataPoint(event("audio_backend_used", { backend: "core_audio", fallback_occurred: true, rung: 2 }), b({ device }), "");
    expect(audio.blobs[13]).toBe("core_audio"); // blob14 = backend (not arch)
    expect(audio.doubles[17]).toBe(2);          // double18 = rung (not cpu_cores)
    expect(audio.blobs[15]).toBe("apple-m3-pro"); // blob16 = chip
    expect(audio.blobs[17]).toBe("15.5");       // blob18 = os_version

    // model_load uses blob17=model — mac_model must NOT clobber it
    const ml = buildDataPoint(event("model_load", { model: "gemma-3-4b", load_ms: 800 }), b({ device }), "");
    expect(ml.blobs[16]).toBe("gemma-3-4b");    // blob17 = model (not mac_model)
    expect(ml.blobs[15]).toBe("apple-m3-pro");  // blob16 = chip
  });

  test("event props win over device on any key collision (blob7 stays spoken language)", () => {
    const dp = buildDataPoint(event("dictation_completed", { language: "fr" }), b({ device: { ...device, language: "de" } }), "");
    expect(dp.blobs[6]).toBe("fr"); // blob7 = the dictation's own language, not the device's
  });

  test("props JSON backstop is present", () => {
    const dp = buildDataPoint(event("error", { type: "transcription", code: "timeout" }), b({ install_id: "i" }), "");
    const backstop = JSON.parse(dp.blobs[19] as string);
    expect(backstop.code).toBe("timeout");
    expect(dp.blobs[13]).toBe("transcription"); // type -> blob14
    expect(dp.blobs[14]).toBe("timeout");       // code -> blob15
  });

  test("event_ts falls back to event timestamp when not in props", () => {
    const dp = buildDataPoint(event("dictation_empty"), b({ install_id: "i" }), "");
    expect(dp.doubles[0]).toBe(1_700_000_000_000);
  });

  test("edit_rate_bucket maps to double20", () => {
    const dp = buildDataPoint(event("dictation_edited", { edit_rate_bucket: 30 }), b({ install_id: "i" }), "");
    expect(dp.doubles).toHaveLength(20);
    expect(dp.doubles[19]).toBe(30);
  });

  test("audio-quality fields survive in the props JSON backstop (blob20)", () => {
    const dp = buildDataPoint(event("dictation_completed", { audio_backend: "core_audio", input_sample_rate: 48000 }), b({ install_id: "i" }), "");
    const backstop = JSON.parse(dp.blobs[19] as string);
    expect(backstop.audio_backend).toBe("core_audio");
    expect(backstop.input_sample_rate).toBe(48000);
  });

  test("onboarding redesign events map to appended aliases", () => {
    // permission_request: kind → blob16, outcome → blob15; surface rides blob20 only.
    const pr = buildDataPoint(event("permission_request", { kind: "microphone", surface: "onboarding", outcome: "denied" }), b({ device }), "");
    expect(pr.blobs[15]).toBe("microphone"); // blob16 = kind (wins over device chip)
    expect(pr.blobs[14]).toBe("denied");     // blob15 = outcome
    expect(JSON.parse(pr.blobs[19] as string).surface).toBe("onboarding");

    // onboarding_practice_result: attempt → double15, outcome → blob15.
    const practice = buildDataPoint(event("onboarding_practice_result", { outcome: "empty_audio", attempt: 3 }), b({ device }), "");
    expect(practice.blobs[14]).toBe("empty_audio"); // blob15 = outcome
    expect(practice.doubles[14]).toBe(3);           // double15 = attempt

    // onboarding_step resumed → double17 (no granted on the same event).
    const step = buildDataPoint(event("onboarding_step", { step: "speak", resumed: true }), b({ device }), "");
    expect(step.blobs[13]).toBe("speak"); // blob14 = step (not device arch)
    expect(step.doubles[16]).toBe(1);     // double17 = resumed

    // onboarding_outcome: practiced → double17, duration_ms → double14; booleans in blob20.
    const outcome = buildDataPoint(
      event("onboarding_outcome", { duration_ms: 61_000, practiced: true, mic_granted: true, ax_granted: false, model_ready: true }),
      b({ device }),
      ""
    );
    expect(outcome.doubles[13]).toBe(61_000); // double14 = duration_ms
    expect(outcome.doubles[16]).toBe(1);      // double17 = practiced
    expect(JSON.parse(outcome.blobs[19] as string).ax_granted).toBe(false);
  });
});

describe("ingestConfigFromEnv", () => {
  test("reads kill switch and sample rate from env", () => {
    expect(ingestConfigFromEnv({ ANALYTICS_DISABLED: "1" }).disabled).toBe(true);
    expect(ingestConfigFromEnv({ ANALYTICS_SAMPLE_RATE: "0.25" }).sampleRate).toBe(0.25);
    expect(ingestConfigFromEnv({}).disabled).toBe(false);
  });
});
