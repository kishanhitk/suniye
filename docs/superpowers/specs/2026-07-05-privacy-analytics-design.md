# Privacy-First Anonymous Usage Analytics — Design

- **Linear:** [KIS-164](https://linear.app/kishan/issue/KIS-164/privacy-first-anonymous-usage-analytics-self-hosted-cloudflare-worker)
- **Date:** 2026-07-05
- **Status:** Design — revised after independent review

## 1. Goal

Add pseudonymous, opt-out usage analytics to Suniye so we can understand real-world usage (how much people dictate, which models/features they use, which hardware they run, where things break) and use that to improve the app — **without collecting any PII, audio, or transcript content, and without paying for a third-party service.**

### Non-goals
- No user identification, real names, or cross-app profiling.
- No crash reporting (out of scope; `IssueReportService` already handles user-initiated reports). A launch-without-clean-exit *proxy* is in scope (§5), a symbolicated crash reporter is not.
- No paid analytics vendor. No new *cost* beyond existing Cloudflare usage (new Workers are free).
- **Not** a standalone/multi-tenant product yet. Built as a clean, self-contained module inside Suniye, designed so it *can* be extracted into its own repo later with no data migration (see §11).

## 2. Principles

1. **Pseudonymous, not "anonymous."** A persistent per-install UUID enables retention/DAU — which by definition lets us *single out a device over time*, so this is pseudonymous personal data under GDPR, not anonymous. Our legal posture is **legitimate interest + opt-out + clear disclosure** for strictly non-content telemetry — a defensible basis, not "no consent required as a matter of law." (Have whoever owns legal sign off on the disclosure copy.)
2. **Content never leaves the device.** We send counts, durations, categories, versions, enum labels, and toggle states — never transcript text, audio, learned vocab, or raw target-app bundle IDs.
3. **[NEVER] fields are structurally impossible, not scrubbed.** Payloads are a closed, typed schema (enums + numbers + known keys); free-form strings are not representable. A regex redactor is a backstop, not the guarantee.
4. **Opt-out, disclosed — and no build emits before the toggle exists.** On by default, disclosed in onboarding, one-click disable in Settings. Event emission is feature-flagged off until the toggle + disclosure ship (§12).
5. **Fail silent, never block.** Analytics failures never affect dictation. Fire-and-forget, offline-queued, best-effort, at-least-once.
6. **Stable contracts forever.** Versioned schema + committed field→slot registry + frozen anon-ID scheme + never-retired versioned endpoint. These are the day-one invariants that make future extraction and data continuity free (§11).

## 3. Architecture

```
┌─────────────────────┐  HTTPS POST /api/v1/events  ┌────────────────────────┐
│  Suniye (Swift)     │  JSON batch, client event_ts │  Ingest Worker         │
│  SuniyeAnalytics:   │─────────────────────────────▶│  (public, NO secrets)  │
│  - anon install_id  │                              │  - validate + size-cap │
│  - typed events     │◀─────────────────────────────│  - rate-limit          │
│  - atomic disk queue│   204 {disabled?, sample?}   │  - country from cf,    │
│  - flush on quit/... │   (kill-switch directive)    │    IP not stored       │
└─────────────────────┘                              └───────────┬────────────┘
                                        writeDataPoint (event_ts) │ upsert (per session)
                                   ┌────────────────────────────┬─┴──────────────┐
                                   ▼                            ▼                 ▼
                        ┌────────────────────┐      ┌────────────────────────┐
                        │ Analytics Engine    │      │ D1 (SQLite)            │
                        │ event stream        │      │ install registry        │
                        │ ~90d, positional    │      │ 1 row/install, perm.    │
                        │ 20 blob/20 dbl/1 idx│      │ (no fine timestamps)    │
                        └─────────┬──────────┘      └───────────┬────────────┘
                                  │                             │
                                  └──── Dashboard Worker ───────┘
                             /stats · Access-gated · holds AE read token
                             Astro route · AE SQL API + D1 · Chart.js
```

**Two Workers, both free, both separate from the marketing site (§7 A-rationale):** an **ingest** Worker (public, holds *no* secrets — only AE-write + D1 bindings) and a **dashboard** Worker (Access-gated, holds the AE read token). This bounds blast radius and means the ingest Worker *is already* the standalone service for a future extraction.

**Storage split rationale:** Analytics Engine handles the high-volume event firehose (free, effectively unlimited writes, ~90-day retention). D1 holds one durable row per install so total-installs / active-devices stays exact and permanent after AE ages out. **D1 stores no fine-grained timestamps** (only `first_seen`/`last_seen` at day granularity) to avoid a permanent pattern-of-life record.

## 4. Identity & consent

### Install ID
- `UUID().uuidString`, generated once on first launch, persisted in a new `AnalyticsSettingsStore` (UserDefaults, key `dev.suniye.analytics.settings`). No hardware serial, `IOPlatformUUID`, MAC, or username — ever.
- **Scheme frozen forever.** Changing it silently resets all retention/DAU history. Invariant.
- The Settings opt-out / "reset analytics" action **rotates (clears + regenerates) the ID**. Reinstall may or may not clear the plist depending on uninstall path — documented as acceptable (may inflate retention slightly), not relied upon.

### Consent model — opt-out with disclosure (locked)
- **Default: enabled** (pseudonymous, non-content, legitimate-interest basis).
- **Onboarding:** a short honest disclosure ("Suniye sends anonymous usage stats — word counts, OS version, hardware, feature usage. No audio, no text, ever. Turn off anytime in Settings.") linking a public "what we collect" page.
- **Settings:** a prominent toggle. When off: no emission, and the queue is dropped (not sent).
- **Debug/simulator: dropped client-side only.** They never reach the server (removed the earlier "flag server-side" contradiction).

## 5. Event schema (v1)

Every payload carries `schema_version: 1`, a per-event `event_id` (UUID, for at-least-once idempotency accounting), and a client `event_ts` (epoch ms, see G1 below). Fields are typed enums/numbers/known-keys — **free strings are not representable**. Time-series are bucketed on `event_ts`, **never** on AE ingestion `timestamp`.

### Super-properties on EVERY event (kept minimal — AE has only 20 blob slots)
`install_id` (→ AE `index1`), `session_id`, `event_id`, `event_ts`, `schema_version`, `app_version`, `channel`, `is_debug`.

### Device/env — sent on `app_launch` ONLY, joined by `install_id` in the dashboard
| Property | Source / notes |
|---|---|
| `build` | `AppVersion.fromBundle()` (`AppVersion.swift:64`) |
| `os_version` | `ProcessInfo.suniyeOperatingSystemVersionString` returns major.minor.patch — **truncate to major.minor** |
| `arch` (arm64/x86_64) | `ProcessInfo.suniyeArchitecture` (static, `IssueReportService.swift:496`) |
| `mac_model` | new `sysctlbyname("hw.model")` → `Mac15,3` — **bucket rare values before store** |
| `chip` | new `sysctlbyname("machdep.cpu.brand_string")` → `Apple M3 Pro` / `Intel Core i7` |
| `ram_gb` | new `sysctlbyname("hw.memsize")` → **bucketed** (8/16/24/32/36/48/64/96/128) |
| `cpu_cores` | `hw.physicalcpu` + P/E split via `hw.perflevel0/1.physicalcpu`; **`perflevel*` absent on Intel → fall back to `hw.physicalcpu` only** |
| `language` | language code only (e.g. `en`) — **not** full `Locale` identifier; `region` dropped (duplicates `country`, adds fingerprinting) |
| `country` | server-derived from `request.cf.country`; IP not stored |

> Rare-config combos (`mac_model`+`chip`+`ram_gb`+`os`+`country`) are fingerprintable; bucketing is a **v1 requirement**, applied before write in both AE and D1 — not a TODO.

### Events
| Event | Properties (typed) | Hook point |
|---|---|---|
| `app_launch` | device/env block + settings snapshot (below) | `AppState.init` log (`AppState.swift:1485`) |
| `onboarding_step` | `step`, `granted` | `advanceOnboarding` (`:1563`), `completeCoreOnboarding` (`:1630`) |
| `permission_transition` | `kind`(mic/accessibility), `granted` — on false→true only | `refreshPermissions` (`:1643`) |
| `dictation_started` | `source`(hotkey/manual/indicator), `destination` | `startRecording` (`:2816`) |
| `dictation_start_blocked` | `reason`(enum) | guards `:2785,2793,2805` |
| `dictation_cancelled` | `stage`(enum) | cancel/abort paths |
| `transcription_completed` | `word_count`, `char_count`, `duration_ms` (audio), **`asr_processing_ms`** (wall-clock), `asr_model`, `asr_family`, `language`, `was_llm_polished` | `transcribe` return (`:2921,2954`) |
| `transcription_empty` | — | `:2967` |
| `text_inserted` | `insertion_method`(direct_ax/clipboard), `target_category`(email/editor/browser/terminal/chat/notes/other) | **new read of `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` in `AppState` before insertion**, bucketed locally (see 5-note) — *not* `TextInsertionService`, which never sees the app |
| `magic_format_succeeded` | `provider`, `model`, `latency_ms`, `tokens_in`, `tokens_out` (counts only) | `MagicFormatCoordinator.swift:164/194/230` |
| `magic_format_fell_back_to_raw` | `reason`(enum) | `MagicFormatCoordinator` fallback logs |
| `audio_capture_failed` | `outcome`(`AudioCaptureOutcome`) | `handleAudioCaptureFailure` (`:3033`) |
| `audio_capture_interrupted` | `reason`(`AudioCaptureInterruption`) | `handleAudioCaptureInterruption` (`:3015`) |
| `audio_backend_used` | `backend`, `fallback_occurred`, `rung` | `session.route` (`:2852`) |
| `vocab_learned_from_edit` | `count` (int only) | `handleLearnedVocabularyTerms` (`:1967`) |
| `model_changed` | `kind`(asr/cleanup), `model` | `:2294`, LLM settings |
| `model_download` | `kind`, `model`, `outcome`, `duration_ms` | `:2206/2231/2256`, `:2030–2085` |
| `model_load` | `model`, `load_ms`, `evicted_by_keepalive`(bool) | local Gemma load / keep-alive eviction |
| `feature_toggled` | `feature`(enum), `enabled` | settings change sites |
| `update_action` | `kind`(manual_check/auto_toggle/channel_change), `channel` | `:2561/2569/2574` |
| `update_completed` | `from_version`, `to_version` | Sparkle post-update / version-delta on launch |
| `session_end` | `session_duration_ms`, `events_in_session`; a launch with no matching end ≈ **crash/force-quit proxy** | `applicationWillTerminate` + sleep/power-off (§6) |
| `error` | `type`(enum), `code`(enum — never message/path) | catch blocks `:2997,3009` |
| `analytics_health` | `queue_depth`, `upload_failures`, `evicted_by_ttl` (pipeline self-observability) | client, low frequency |

**Dropped from prior draft:** `wpm` (derivable from `word_count`/`duration_ms`, and it wastes a scarce AE double).

### Latency breakdown (per dictation — the headline perf signal)

Measure every stage of the pipeline with a **monotonic clock** (`DispatchTime`/`ContinuousClock`, not wall-clock) and attach the breakdown to `transcription_completed` (each is a separate AE `double`; the field→slot registry budgets them). Each metric is bracketed by two existing hook points, so no new call sites beyond stamping timestamps:

| Metric (ms) | From → To | Hooks |
|---|---|---|
| `lat_trigger_to_capture` | hotkey/trigger fired → mic actually capturing (warm-up) | `startRecording` (`:2816`) → capture started (`:2853`) |
| `lat_record_ms` | capture start → user stops (recording duration; not latency but needed to derive RTF) | `:2853` → `stopRecordingAndTranscribe` (`:2868`) |
| `lat_stop_to_asr_start` | stop → transcription begins | `:2868` → `transcribe` start (`:2898`) |
| `lat_asr_first_token` | ASR start → first partial/hypothesis (if streaming ASR exposes it) | inside `transcribe` |
| `lat_asr_processing` | ASR start → final text (== `asr_processing_ms`) | `:2898` → `:2921` |
| `lat_asr_to_llm` | ASR done → Magic Format starts | `:2907` (`postProcessTextIfEnabled` `:2586`) |
| `lat_llm_first_token` | LLM start → first token (local Gemma/streaming) | `MagicFormatCoordinator` |
| `lat_llm_total` | LLM start → cleaned text (== existing `latency_ms`) | `MagicFormatCoordinator:164/194/230` |
| `lat_insert` | insertion start → done; also `insertion_method` (direct_ax is fast, clipboard slower) | `insertText` (`:2942`) → `RecentResult` inserted (`:2944`) |
| `lat_end_to_end` | **stop → text visible in target app** — the number the user actually *feels*; the headline UX metric | `:2868` → `:2944` |

Dashboard slices each stage (esp. `lat_asr_processing`, `lat_llm_total`, `lat_end_to_end`) by `chip` / `ram_gb` / `asr_model` / `cleanup_model` to pinpoint which stage dominates on which hardware and which model tier is worth defaulting. Report percentiles (`quantileWeighted` with `_sample_interval`), not just means — tail latency is what users notice. `model_load` / `model_download` already carry their own `load_ms` / `duration_ms`.

### Settings snapshot (on `app_launch`)
From `GeneralSettings` (`SettingsModels.swift`) + `LLMSettings` (`LLMSettings.swift`): `asr_model_id`+`asr_family`, `auto_submit_enabled`, `echo_cancellation_enabled`, `sound_feedback_enabled`, `hotkey_kind` (kind only, never keyCode/modifiers), `update_channel`, `magic_format_enabled`, `magic_format_provider`, `llm_model_preset`, `llm_endpoint_is_default`, `local_model_keep_alive`, `learn_from_edits_enabled`, `vocab_keyword_count` (count only), `input_device_transport` (`AudioDeviceTransport` enum, **not** device name).

### [NEVER] collect
Transcript text, partial hypotheses, corrected text, audio/features, learned vocab terms, raw per-user bundle IDs, IP, serial/`IOPlatformUUID`/MAC, hostname, username, Apple ID, email, precise geo, full `Locale` identifier, free text of any kind, keyboard keyCodes, input device names, `NSError`/`URLError` messages or userInfo.

## 6. Swift client design

New self-contained module `SuniyeAnalytics` (own target; no Suniye domain types leak in). **Note the queue/retry/batching is net-new — `IssueReportUploadService` has injectable `URLSession` + Info.plist endpoint to copy, but no queue, no retry, and is multipart, so those parts have no prior art and must be built + tested from scratch.**

- **`Analytics` protocol** — `track(_ event: AnalyticsEvent)`, `setEnabled(_:)`. Suniye depends only on this. `AnalyticsEvent` is a closed enum with typed associated values → [NEVER] fields structurally impossible.
- **`AnalyticsClient`** — install ID, opt-out flag, super-property provider, batching, and an **on-disk queue written atomically on every enqueue** (so nothing depends on a clean shutdown). Emit is a no-op when disabled.
- **Flush triggers (macOS-correct — this is a resident menu-bar app with no `scenePhase` background):** threshold, timer, `applicationWillTerminate`, `NSWorkspace.willSleepNotification`, `willPowerOffNotification`. None fire on force-quit/crash — hence atomic-on-enqueue is the real durability guarantee; the crash proxy (`session_end` absence) is the intended signal for those.
- **`AnalyticsUploadService`** — injectable `URLSession`, endpoint from Info.plist key `SuniyeAnalyticsEndpointURL`, typed `Codable` payload, JSON POST (request-factory per `ChatCompletionClient.swift:46`), background encode. **Retry only on connection errors, never on ambiguous/timeout responses** (avoids over-counting; at-least-once accepted, deduped-by-`event_id` if ever needed). Honors the `204` **kill-switch directive** (`{disabled, sample_rate}`) by caching + obeying it.
- **`AnalyticsSettingsStore`** — copy `GeneralSettingsStore` verbatim (injectable UserDefaults + key + Codable). Holds `installID`, `enabled`, `firstLaunchAt`, cached kill-switch directive.
- **Wiring** — inject into `AppState.init` (`:1379`) alongside existing services; emit at §5 hook points (same sites that already `AppLogger.shared.log(...)`). No event bus.

## 7. Backend design (two Workers)

Follows website conventions (`import { env } from "cloudflare:workers"`, `prerender = false`, pure helpers in `src/lib/`, `bun test`). **Split from the marketing Worker** because: a bad analytics deploy shouldn't take the site down; the AE read token shouldn't share blast radius with the public site; and an ingest flood shouldn't burn the site's request quota.

### Ingest Worker (public, no secrets)
- **Endpoint:** `POST /api/v1/events` (versioned path so v2 can diverge while v1 lives forever). Validates `schema_version`, typed shape, and a **concrete body size cap** (≤4 KB, under AE's ~5 KB blob budget); rejects `is_debug`.
- **Rate-limit:** reuse the `checkRateLimit` pattern (`issueReports.ts:520`, Cache-API + SHA-256 of `CF-Connecting-IP`, fail-closed) with an **analytics-sized budget** (batches, not human bug reports). → We *read* `CF-Connecting-IP` transiently for hashing + country; we **never store** IP. (Corrected the earlier "never read IP" overstatement.)
- **Writes:**
  - AE `writeDataPoint({ blobs, doubles, indexes })` — `index1`=`install_id`; `blob1`=event type; remaining slots per the **field→slot registry** (below). Client `event_ts` written as a `double`.
  - D1 upsert into `installs(install_id PK, first_seen, last_seen, app_version, os_version, mac_model_bucketed, chip, ram_gb, country)` — **once per session (driven off `app_launch` only)**, not per event, to stay well under D1's ~100k writes/day free tier.
- **`204` response** carries the kill-switch directive `{disabled?, sample_rate?}`.
- **Bindings** (`wrangler.jsonc` → merged into `dist/server/wrangler.json`; don't collide with the adapter's `SESSION` KV):
  ```jsonc
  "analytics_engine_datasets": [{ "binding": "EVENTS", "dataset": "suniye_events" }],
  "d1_databases": [{ "binding": "INSTALLS_DB", "database_name": "suniye-installs", "database_id": "<id>" }]
  ```

### Field → slot registry (the real migration mechanism)
AE columns are **positional and unnamed** (`blob1..20`, `double1..20`, one `index`). A `schema_version` int is not enough. Commit `src/lib/eventSchema.ts` (shared conceptually with the Swift encoder) mapping each field to a fixed slot. **Rule: append to the next free slot; never move or repurpose one.** Budget accordingly — with device detail only on `app_launch`, per-event events keep ≥12 free blob slots.

### Dashboard Worker (Access-gated) — see §8. Holds `CF_ACCOUNT_ID` + `AE_API_TOKEN` (Account Analytics → Read).

## 8. Dashboard design (`/stats`)

Custom route on the Access-gated dashboard Worker — no Grafana, no third party (AE read token stays in our infra).

- **`src/lib/stats.ts`** (pure, testable): builds SQL, POSTs to the AE SQL API (`.../analytics_engine/sql`, Bearer token), parses JSON, merges with D1 **in JS** (AE has no JOINs).
- **`src/pages/api/stats.ts`** (SSR JSON, `prerender=false`): validates Access JWT, calls `stats.ts`.
- **`src/pages/stats.astro`**: Access-gated page, Tailwind v4 cards + a Chart.js client island fetching `/api/stats`.
- **Charts:** **Chart.js** (framework-agnostic; this repo has no React). uPlot if it turns heavily time-series.
- **Auth:** **Cloudflare Access** (Zero Trust free tier, email allow-list) **+ Worker-side JWT validation** of `Cf-Access-Jwt-Assertion` against the team certs (origin is publicly routable → validate to prevent bypass).

**Sampling + time correctness (queries this way from day one):** each AE row carries `_sample_interval`. Counts `SUM(_sample_interval)`; metric sums `SUM(doubleN * _sample_interval)`; exact installs `COUNT(DISTINCT index1)`. **Bucket time on the client `event_ts` double, not the ingestion `timestamp`** (offline-queued events ingest late). Example — words/day (`doubleN` = event_ts, `doubleM` = word_count):
```sql
SELECT toStartOfDay(toDateTime(intDiv(double_ts, 1000))) AS day,
       SUM(double_words * _sample_interval) AS words
FROM suniye_events
WHERE blob1 = 'transcription_completed' AND double_ts > (toUnixTimestamp(NOW()) - 30*86400)*1000
GROUP BY day ORDER BY day
```

**v1 panels:** words/day, active installs/day, total + new installs/day, ASR-model distribution, macOS/chip/**RAM** breakdown, real-time-factor (`asr_processing_ms` vs `duration_ms`) by chip tier, Magic Format adoption %, fallback reasons, audio-backend fallback frequency, onboarding funnel, crash-proxy rate, error counts by type.

## 9. Privacy & compliance

- **Pseudonymous** (persistent per-install UUID) + non-content telemetry, on a **legitimate-interest** basis with opt-out + disclosure. Do **not** claim "anonymous / no consent required" as settled law; get the disclosure copy reviewed.
- **Bucketing before store is a v1 requirement** (mac_model/chip/ram/os combos are fingerprintable). Applied in both AE and D1.
- No fine-grained timestamps in the permanent D1 row; rely on AE ~90-day retention to bound any pattern-of-life reconstruction.
- Publish a plain-language "what we collect / what we never collect" page; link from onboarding + Settings.
- Update the website privacy policy / `THIRD_PARTY_NOTICES.md`.

## 10. Testing

App-hosted unit + integration (repo convention):
- `AnalyticsSettingsStore`: install-ID generation/stability + rotation on reset; opt-out persistence (injected UserDefaults).
- `AnalyticsClient`: no-op when disabled; **atomic queue persists across simulated abrupt termination**; flush-trigger coverage; TTL eviction; super-property assembly; kill-switch obeyed.
- **Upload path (net-new, critical):** drive enqueue → offline → flush → retry against a mock `URLSession`; assert retry only on connection errors; assert **the typed schema cannot serialize any [NEVER] field** (the real guarantee, plus a redactor backstop test).
- Backend (`bun test`, injected `fetcher` + `MemoryRateLimitStore` per `tests/issueReports.test.ts`): `events.ts` validation + size-cap + PII rejection + slot mapping; `stats.ts` SQL builders (assert bucketing on `event_ts`); D1 once-per-session upsert.
- **Gap acknowledged:** no `wrangler dev`/real-HTTP end-to-end harness exists; M6 covers it with a manual signed-build check against production.

## 11. Future extraction — day-one invariants

Extraction later is a repackage, not a migration, **if** we hold from v1: (1) versioned schema + **committed field→slot registry** (append-only), (2) frozen anon-ID scheme, (3) never-retired versioned endpoint path.

- **Code:** `SuniyeAnalytics` moves to its own repo as a Swift package; Suniye swaps a local import for a package dep — same API, same call sites. The **ingest Worker is already the standalone service.**
- **Data:** it lives in our Cloudflare account. Self-host productization → Suniye is just our own deployment, nothing moves. SaaS → add an `app_id` (D1 `ALTER TABLE ... DEFAULT 'suniye'`; AE start writing an `app_id` blob at the next free slot, old rows age out in 90 days) — additive, no gap.

## 12. Milestones

1. **Swift `SuniyeAnalytics` module** — typed events, settings store, atomic queue, upload/retry, kill-switch, opt-out. Fully tested. **No events emitted.**
2. **Backend** — ingest Worker (`/api/v1/events`) + AE/D1 bindings + **field→slot registry** + `event_ts` contract + once-per-session upsert + size-cap/rate-limit. Tested. (Registry + `event_ts` are near-impossible to change later, so they land here before any event is wired.)
3. **Disclosure & control FIRST** — onboarding disclosure + Settings toggle + public "what we collect" page + emission feature-flag. *Must precede or ship in the same build as any event emission* (fixes the consent-sequencing bug).
4. **Wire core events** — `app_launch`, `dictation_started`, `transcription_completed`, `text_inserted`, `session_end`, errors — behind the flag from M3.
5. **`/stats` dashboard** — dashboard Worker + endpoint + Chart.js + Access.
6. **Fill in remaining events; verify end-to-end** from a real signed build hitting production.

## 13. Decisions locked
- Storage: Analytics Engine (events, bucket time on `event_ts`) + D1 (install registry, once-per-session upsert, no fine timestamps).
- Consent: opt-out + disclosure on a legitimate-interest basis (framed pseudonymous, not "anonymous"); debug/simulator client-dropped; emission gated behind M3.
- Identity: random per-install UUID, frozen scheme, rotated on reset.
- [NEVER] enforced by a closed typed schema; redactor is a backstop only.
- Backend: **two free Workers** (public ingest with no secrets + Access-gated dashboard), both split from the marketing site. Versioned endpoint path.
- Field→slot registry is the schema-migration mechanism (append-only).
- **Framework: stay on Astro** (islands + first-class Cloudflare adapter fit a content site + a few chart islands; Next.js/OpenNext adds cost for no gain; add React as an Astro island if ever needed; revisit only if a standalone product materializes).
- Dashboard: Astro `/stats` + Chart.js + Cloudflare Access (no Grafana).
- Build inside Suniye now; keep clean seams for later extraction (self-host productization preferred).

### Open (resolve during implementation)
- Concrete AE field→slot table (write it in M2).
- Final `target_category` bundle-ID→category mapping.
- Exact bucket thresholds for `mac_model`/`chip`/`ram_gb`; analytics rate-limit budget numbers.

**Why hardware details matter here:** Suniye runs local ASR + local Gemma. `chip`, `ram_gb`, `cpu_cores` + `asr_processing_ms`/`model_load_ms` tell us which model tiers run acceptably on which hardware — directly informing default-model choice, minimum-RAM guidance, and the sub-2B/QAT-requant tradeoffs. Captured as coarse hardware classes (RAM bucketed, combos bucketed before store), these carry no content and no natural-person identity.
