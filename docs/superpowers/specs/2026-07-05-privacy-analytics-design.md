# Privacy-First Anonymous Usage Analytics — Design

- **Linear:** [KIS-164](https://linear.app/kishan/issue/KIS-164/privacy-first-anonymous-usage-analytics-self-hosted-cloudflare-worker)
- **Date:** 2026-07-05
- **Status:** Design — pending review

## 1. Goal

Add anonymous usage analytics to Suniye so we can understand real-world usage (how much people dictate, which models/features they use, where things break) and use that to improve the app — **without collecting any PII, audio, or transcript content, and without paying for a third-party service.**

### Non-goals
- No per-user tracking, user identification, or cross-app profiling.
- No crash reporting (out of scope; `IssueReportService` already handles user-initiated reports).
- No paid analytics vendor. No new servers beyond the existing Cloudflare Worker.
- **Not** a standalone/multi-tenant product yet. Built as a clean, self-contained module inside Suniye, designed so it *can* be extracted into its own repo later with no data migration (see §11).

## 2. Principles

1. **Anonymous by construction.** Random per-install UUID, no hardware identifiers, no IP stored. Data is anonymous under GDPR Recital 26 (no consent pop-up legally required), but we disclose anyway.
2. **Content never leaves the device.** We send counts, durations, categories, versions, and toggle states — never transcript text, audio, learned vocab, or raw target-app bundle IDs.
3. **Opt-out, disclosed.** On by default, clearly disclosed in onboarding, one-click disable in Settings. Debug/dev builds excluded.
4. **Fail silent, never block.** Analytics failures never affect dictation. Fire-and-forget, offline-queued, best-effort.
5. **Stable contracts forever.** Versioned event schema + stable anon-ID scheme + never-retired endpoint. These three are the day-one invariants that make future extraction and data continuity free (§11).

## 3. Architecture

```
┌─────────────────────┐   HTTPS POST /v1/events    ┌────────────────────────┐
│  Suniye (Swift)     │   JSON, batched, queued    │  Cloudflare Worker     │
│                     │───────────────────────────▶│  (existing website     │
│  Analytics module:  │                            │   Worker, new route)   │
│  - anon install ID  │◀───────────────────────────│  - validate + rate-limit│
│  - opt-out toggle   │      204 No Content         │  - strip PII, derive    │
│  - batch + disk Q   │                            │    country from cf, drop IP
│  - super-properties │                            │  - schema_version guard │
└─────────────────────┘                            └───────────┬────────────┘
                                                                │
                                      writeDataPoint            │  upsert
                                   ┌────────────────────────────┴──────────────┐
                                   ▼                                            ▼
                        ┌────────────────────┐                    ┌────────────────────────┐
                        │ Analytics Engine    │                    │ D1 (SQLite)            │
                        │ event stream        │                    │ install registry       │
                        │ ~90-day retention   │                    │ 1 row / install, perm. │
                        └─────────┬──────────┘                    └───────────┬────────────┘
                                  │                                            │
                                  └────────── /stats dashboard ───────────────┘
                                     Astro route, AE SQL API + D1, Chart.js,
                                     gated by Cloudflare Access + JWT check
```

**Storage split rationale:** Analytics Engine handles the high-volume event firehose (free, effectively unlimited writes, ~90-day retention). D1 holds one durable row per anonymous install so total-installs / active-devices stays exact and permanent even after AE data ages out.

## 4. Anonymous identity & consent

### Install ID
- `UUID().uuidString`, generated once on first launch, persisted in a new `AnalyticsSettingsStore` (UserDefaults, key `dev.suniye.analytics.settings`). No hardware serial, `IOPlatformUUID`, MAC, or username — ever.
- **This scheme is frozen forever.** Changing it silently resets all retention/DAU history (every install looks new). Documented as an invariant.
- Enables true DAU/retention (the advantage self-hosting gives us over Aptabase's IP-hash model), while mapping to no natural person.

### Consent model — opt-out with disclosure (locked)
- **Default: enabled.** Since data is fully anonymous, this is legally fine and standard for indie privacy apps.
- **Onboarding:** a short, honest disclosure line ("Suniye sends anonymous usage stats — word counts, OS version, feature usage. No audio, no text. Turn off anytime in Settings.") with a link to a public "what we collect" page.
- **Settings:** a prominent toggle. When off, no events are emitted and no queued events are sent.
- **Excluded automatically:** debug builds, simulator (`is_debug` true → drop client-side and flag server-side).

## 5. Event schema (v1)

Every payload carries `schema_version: 1`. All fields below are **[SAFE]** (non-identifying). The explicit **[NEVER]** list is enforced by convention + a redactor safety net.

### Super-properties (attached to every event)
| Property | Source |
|---|---|
| `install_id` | `AnalyticsSettingsStore` (random UUID) |
| `session_id` | new per app-session (new after ~5 min inactivity) |
| `app_version`, `build`, `channel` | `AppVersion.fromBundle()` (`AppVersion.swift:64`) |
| `os_version` (major.minor) | `ProcessInfo.suniyeOperatingSystemVersionString` (`IssueReportService.swift:490`) |
| `architecture` (arm64/x86_64) | `ProcessInfo.suniyeArchitecture` (`IssueReportService.swift:496`) |
| `mac_model` / `chip` | **new** `sysctlbyname("hw.model"/"machdep.cpu.brand_string")` helper (bucket rare values) |
| `locale`, `region` | `Locale.current` |
| `country` | **server-derived** from `request.cf.country`; IP discarded immediately |
| `is_debug` | build flag |

### Events
| Event | Properties | Hook point |
|---|---|---|
| `app_launch` | all super-props + settings snapshot (below) | `AppState.init` log (`AppState.swift:1485`) |
| `onboarding_step` | `step`, `granted` | `advanceOnboarding` (`AppState.swift:1563`), `completeCoreOnboarding` (`:1630`) |
| `permission_transition` | `kind` (mic/accessibility), `granted` | `refreshPermissions` (`AppState.swift:1643`) — emit on false→true only |
| `dictation_started` | `source` (hotkey/manual/indicator), `destination` | `startRecording` (`AppState.swift:2816`) |
| `dictation_start_blocked` | `reason` (wrong_phase/mic_denied/ax_denied) | guards `AppState.swift:2785,2793,2805` |
| `transcription_completed` | `word_count`, `char_count`, `duration_ms`, `wpm`, `asr_model`, `asr_family`, `language`, `was_llm_polished` | `transcribe` return (`AppState.swift:2921,2954`) |
| `transcription_empty` | — | `AppState.swift:2967` |
| `text_inserted` | `insertion_method` (direct_ax/clipboard), `target_category` (bucketed: email/editor/browser/terminal/chat/notes/other) | `insertText` (`AppState.swift:2942`; `TextInsertionService.swift:82`) |
| `magic_format_succeeded` | `provider`, `model`, `latency_ms` | `MagicFormatCoordinator.swift:164/194/230` |
| `magic_format_fell_back_to_raw` | `reason` (invalid_endpoint/missing_key/empty_output/timeout/network/unknown) | `MagicFormatCoordinator.swift` fallback logs |
| `audio_capture_failed` | `outcome` (`AudioCaptureOutcome`) | `handleAudioCaptureFailure` (`AppState.swift:3033`) |
| `audio_capture_interrupted` | `reason` (`AudioCaptureInterruption`) | `handleAudioCaptureInterruption` (`AppState.swift:3015`) |
| `audio_backend_used` | `backend`, `fallback_occurred`, `rung` | `session.route` at capture start (`AppState.swift:2853`) |
| `vocab_learned_from_edit` | `count` (integer only) | `handleLearnedVocabularyTerms` (`AppState.swift:1967`) |
| `model_changed` | `kind` (asr/cleanup), `model` | `AppState.swift:2294` (asr), LLM settings |
| `model_download` | `kind`, `model`, `outcome`, `duration_ms` | `AppState.swift:2206/2231/2256` (asr), `:2030–2085` (llm) |
| `feature_toggled` | `feature`, `enabled` | settings change sites |
| `update_action` | `kind` (manual_check/auto_toggle/channel_change), `channel` | `AppState.swift:2561/2569/2574` |
| `error` | `type`, `code` (no messages, no paths) | catch blocks `AppState.swift:2997,3009` |

### Settings snapshot (properties on `app_launch`)
From `GeneralSettings` (`SettingsModels.swift`) and `LLMSettings` (`LLMSettings.swift`): `asr_model_id` + `asr_family`, `auto_submit_enabled`, `echo_cancellation_enabled`, `sound_feedback_enabled`, `hotkey_kind` (kind only, never keyCode/modifiers), `update_channel`, `magic_format_enabled`, `magic_format_provider`, `llm_model_preset`, `llm_endpoint_is_default`, `local_model_keep_alive`, `learn_from_edits_enabled`, `vocab_keyword_count` (count only), `input_device_transport` (`AudioDeviceTransport` enum, **not** device name).

### [NEVER] collect
Transcript text, partial hypotheses, corrected text, audio/features, learned vocab terms, raw per-user bundle IDs, IP, serial/`IOPlatformUUID`/MAC, hostname, username, Apple ID, email, precise geo, free-text of any kind, keyboard shortcut keyCodes, input device names.

## 6. Swift client design

New self-contained module `SuniyeAnalytics` (own folder/target; no Suniye domain types leak in), so it can be extracted later (§11):

- **`Analytics` protocol** — `track(_ event: AnalyticsEvent)`, `setEnabled(_:)`. Suniye code depends only on this.
- **`AnalyticsClient`** — owns install ID, opt-out flag, super-property provider, batching (buffer, flush on threshold/background/timer), and an on-disk offline queue with a TTL cap. Gated on the opt-out flag: emit is a no-op when disabled.
- **`AnalyticsUploadService`** — modeled on `IssueReportUploadService` (`IssueReportService.swift:305`): injectable `URLSession`, endpoint from a new Info.plist key `SuniyeAnalyticsEndpointURL` (mirrors `SuniyeIssueReportEndpointURL`), versioned `Codable` payload, JSON POST (request-factory pattern per `ChatCompletionClient.swift:46`), background encode. Reuse `DiagnosticRedactor` (`IssueReportService.swift:149`) as a safety net.
- **`AnalyticsSettingsStore`** — copy `GeneralSettingsStore` verbatim (injectable UserDefaults + storage key + Codable load/save), key `dev.suniye.analytics.settings`. Holds `installID`, `enabled`, `firstLaunchAt`.
- **Wiring** — inject into `AppState.init` alongside existing services (`AppState.swift:1379`). Emit events imperatively at the §5 hook points (same call sites that already `AppLogger.shared.log(...)`). No event bus needed.

**Persistence note:** the repo's `KeychainService` is misnamed plain-file storage, not Keychain. Use UserDefaults (the established convention) for the anon ID — it's not a secret.

## 7. Backend design (Cloudflare Worker)

Extends the existing website Worker (`website/`), following its conventions (`env` from `import { env } from "cloudflare:workers"`, `prerender = false`, pure config helpers in `src/lib/`, `bun test`).

- **Endpoint:** `POST /api/events` (`src/pages/api/events.ts`, mirrors `api/issue-reports.ts`). Validates `schema_version`, shape, and size; rate-limits; rejects `is_debug`.
- **Enrichment:** read `request.cf.country`; **never read or store IP**.
- **Writes:**
  - Analytics Engine `writeDataPoint({ blobs, doubles, indexes })` — `blob1`=event type, then event/device strings; `double1`=word_count etc.; `index1`=`install_id` (sampling key, keeps per-install counts exact).
  - D1 upsert into `installs(install_id PK, first_seen, last_seen, app_version, os_version, mac_model, country)` — one row per install, updated `last_seen`.
- **Bindings** (`wrangler.jsonc`, source — adapter merges into `dist/server/wrangler.json`):
  ```jsonc
  "analytics_engine_datasets": [{ "binding": "EVENTS", "dataset": "suniye_events" }],
  "d1_databases": [{ "binding": "INSTALLS_DB", "database_name": "suniye-installs", "database_id": "<id>" }]
  ```
- **Secrets** (for the read path / dashboard): `CF_ACCOUNT_ID`, `AE_API_TOKEN` (Account Analytics → Read).

## 8. Dashboard design (`/stats`)

Custom route in the existing Astro/Workers site — no Grafana, no third party (keeps the AE API token in our own infra).

- **`src/lib/stats.ts`** (pure, testable): builds SQL, POSTs to the AE SQL API (`POST https://api.cloudflare.com/client/v4/accounts/<id>/analytics_engine/sql`, Bearer token), parses JSON, and merges with D1 results **in JS** (AE has no JOINs).
- **`src/pages/api/stats.ts`** (SSR JSON, `prerender=false`): validates Access JWT, calls `stats.ts`, returns JSON.
- **`src/pages/stats.astro`**: Access-gated page, Tailwind v4 cards + a Chart.js client island fetching `/api/stats`.
- **Charts:** **Chart.js** (line/bar/doughnut, framework-agnostic, no React — this repo has none). uPlot if it becomes time-series-heavy.
- **Auth:** **Cloudflare Access** (Zero Trust free tier, allow-list your email via Email OTP) **+ Worker-side JWT validation** of `Cf-Access-Jwt-Assertion` against `https://<team>.cloudflareaccess.com/cdn-cgi/access/certs` (the origin is publicly routable, so validate to prevent bypass).

**Sampling correctness (write queries this way from day one):** AE downsamples at volume; each row carries `_sample_interval`. Use `SUM(_sample_interval)` for counts, `SUM(doubleN * _sample_interval)` for metric sums, `COUNT(DISTINCT index1)` for exact install counts. Example — words/day:
```sql
SELECT toStartOfDay(timestamp) AS day, SUM(double1 * _sample_interval) AS words
FROM suniye_events
WHERE blob1 = 'transcription_completed' AND timestamp > NOW() - INTERVAL '30' DAY
GROUP BY day ORDER BY day
```

**Dashboard v1 panels:** words dictated/day, active installs/day, total installs, new installs/day, ASR-model distribution, macOS/chip breakdown, Magic Format adoption %, magic-format fallback reasons, audio-backend fallback frequency, onboarding funnel, error counts by type.

## 9. Privacy & compliance

- Anonymous under GDPR Recital 26 (no singling-out: no hardware ID, no IP stored, coarse country only). No consent pop-up legally required; we disclose + offer opt-out regardless.
- Bucket rare/fingerprintable combos (exotic Mac model + rare locale) before storing.
- Publish a plain-language "what we collect / what we never collect" page; link from onboarding and Settings.
- `THIRD_PARTY_NOTICES.md` / privacy policy on the website updated.

## 10. Testing

App-hosted unit + integration tests (repo convention):
- `AnalyticsSettingsStore`: install-ID generation/stability, opt-out persistence (injected UserDefaults).
- `AnalyticsClient`: no-op when disabled; batching flush triggers; offline queue persistence + TTL eviction; super-property assembly.
- `AnalyticsUploadService`: payload encoding, `schema_version`, endpoint from Info.plist, injected `URLSession` mock — assert **no [NEVER] fields** ever serialized (redactor test).
- Backend (`bun test`): `stats.ts` SQL builders, `events.ts` validation + PII stripping (config helpers kept pure).

## 11. Future extraction — day-one invariants

Building inside Suniye now does **not** trap code or data. Extraction later is a repackage, not a rewrite/migration, **if** we hold three contracts from v1:

1. **Versioned event schema** (`schema_version`) — future changes are additive/negotiated, never breaking.
2. **Frozen anon-ID scheme** — random per-install UUID, never changed (changing it resets retention history).
3. **Never-retired endpoint** — old app versions POST forever to their baked-in URL; keep it alive/proxied.

Given those:
- **Code:** the `SuniyeAnalytics` module moves to its own repo as a Swift package; Suniye swaps a local import for a package dependency — same API, same call sites.
- **Data:** it lives in our Cloudflare account, not "in the app." If productized as **self-host** (recommended), Suniye is simply our own deployment — nothing moves. If productized as **SaaS**, add an `app_id` (D1: `ALTER TABLE ... DEFAULT 'suniye'`; AE: start writing an `app_id` blob, old rows age out in 90 days) — additive, no gap.

## 12. Milestones

1. Swift `SuniyeAnalytics` module: settings store, client, uploader, opt-out — with tests. (No events wired yet.)
2. Backend: `/api/events` endpoint + AE/D1 bindings + install upsert — with tests.
3. Wire core events (`app_launch`, `dictation_started`, `transcription_completed`, `text_inserted`, errors) at the §5 hook points.
4. Onboarding disclosure + Settings toggle + public "what we collect" page.
5. `/stats` dashboard (endpoint + page + Chart.js + Access).
6. Wire remaining events; verify end-to-end from a real build.

## 13. Decisions locked
- Storage: Analytics Engine (events) + D1 (install registry).
- Consent: opt-out with disclosure; debug/simulator excluded.
- Identity: random per-install UUID, frozen scheme.
- Dashboard: Astro `/stats` + Chart.js + Cloudflare Access (no Grafana).
- Build inside Suniye now; keep clean seams for later extraction (self-host productization preferred).

### Open (resolve during implementation)
- Verify current D1 free-tier write limits vs. expected install/upsert volume (batch `last_seen` updates if needed).
- Final `target_category` bundle-ID→category mapping table.
- `mac_model`/`chip` bucketing thresholds for rare values.
