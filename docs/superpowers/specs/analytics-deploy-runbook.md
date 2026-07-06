# Analytics — Deployment Runbook (KIS-164)

Steps that require your Cloudflare account (I can't run these). Do them once; then
the app → ingest → storage → dashboard path is live. All free-tier.

## 1. Create the D1 install registry

```bash
cd website/workers/ingest
wrangler d1 create suniye-installs          # copy the printed database_id
```

Paste the `database_id` into **both**:
- `website/workers/ingest/wrangler.jsonc`  (`d1_databases[0].database_id`)
- `website/workers/dashboard/wrangler.jsonc` (`d1_databases[0].database_id`)

Apply the schema:

```bash
wrangler d1 execute suniye-installs --remote --file schema.sql
```

## 2. Deploy the ingest Worker (public, no secrets)

The `suniye_events` Analytics Engine dataset is created implicitly on first
`writeDataPoint` — no separate step. Just deploy:

```bash
cd website/workers/ingest
wrangler deploy --config wrangler.jsonc
```

Point the app's endpoint host at it. The app posts to
`https://ingest.suniye.kishans.in/api/v1/events` (baked into `project.yml`
`SuniyeAnalyticsEndpointURL`). Either:
- add a route/custom domain `ingest.suniye.kishans.in` to `suniye-ingest`, or
- change `SuniyeAnalyticsEndpointURL` to the `*.workers.dev` URL and rebuild.

**Never retire this endpoint** — old app builds POST to it forever.

## 3. Create the AE read token + deploy the dashboard

```bash
# API token: My Profile → API Tokens → Create → permission "Account Analytics: Read"
cd website/workers/dashboard
bun install
wrangler secret put CF_ACCOUNT_ID     --config wrangler.jsonc   # your account id
wrangler secret put AE_API_TOKEN       --config wrangler.jsonc   # the token above
```

Fill the non-secret Access vars in `wrangler.jsonc` (`CF_ACCESS_TEAM_DOMAIN`,
`CF_ACCESS_AUD`) after step 4, then:

```bash
bun run build            # vite → dist/
wrangler deploy --config wrangler.jsonc
```

## 4. Gate the dashboard with Cloudflare Access (free Zero Trust)

- Zero Trust → Access → Applications → Add → Self-hosted.
- Domain: the dashboard Worker's hostname (e.g. `stats.suniye.kishans.in`).
- Policy: Allow, rule = your email (Email OTP — no IdP needed).
- Copy the application **Audience (AUD) tag** → `CF_ACCESS_AUD`.
- `CF_ACCESS_TEAM_DOMAIN` = `<your-team>.cloudflareaccess.com`.
- Redeploy the dashboard so the Worker validates the JWT (defense in depth).

For local dev only: set `DASHBOARD_ALLOW_INSECURE=1` in `.dev.vars` to bypass Access.

## 5. Verify end-to-end

1. Run a signed/release build of Suniye (analytics is disabled in DEBUG).
2. Do a few dictations; toggle Magic Format; quit the app.
3. AE: `wrangler d1 ...` for installs, and query events:
   ```bash
   curl -s "https://api.cloudflare.com/client/v4/accounts/$ACCT/analytics_engine/sql" \
     -H "Authorization: Bearer $AE_API_TOKEN" \
     --data "SELECT blob1, COUNT() FROM suniye_events GROUP BY blob1"
   ```
   Expect `app_launch`, `dictation_completed`, `session_end`.
4. Open the dashboard URL → Access prompt → panels populate.
5. Toggle analytics **off** in Settings → confirm emission stops (queue dropped).

## Free-tier ceilings (target: 100 users × 500/day)
- Workers 100k req/day — batching keeps ingest to a few k/day. ✅
- D1 100k writes/day — once-per-session upsert → hundreds/day. ✅
- Analytics Engine — unbilled today; ~6M/mo fits the $5 Paid tier if billing starts. ✅

## Rollback / kill switch
- Set `ANALYTICS_DISABLED=1` (var) on the ingest Worker → clients receive
  `{disabled:true}` and stop emitting (cached). No app update needed.
