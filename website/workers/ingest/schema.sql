-- D1 install registry: one durable row per anonymous install, so total-installs
-- and active-devices stay exact and permanent even after Analytics Engine's
-- ~90-day window ages out. Upserted once per session (on app_launch) to stay
-- well under D1's free-tier write budget. No fine-grained timestamps are stored
-- (day granularity only) to avoid a permanent pattern-of-life record.
--
-- Apply: wrangler d1 execute suniye-installs --file workers/ingest/schema.sql

CREATE TABLE IF NOT EXISTS installs (
  install_id   TEXT PRIMARY KEY,
  first_seen   TEXT NOT NULL,   -- YYYY-MM-DD
  last_seen    TEXT NOT NULL,   -- YYYY-MM-DD
  app_version  TEXT,
  channel      TEXT,
  os_version   TEXT,
  mac_model    TEXT,
  chip         TEXT,
  ram_gb       INTEGER,
  cpu_cores    INTEGER,
  country      TEXT
);

CREATE INDEX IF NOT EXISTS idx_installs_last_seen ON installs (last_seen);
CREATE INDEX IF NOT EXISTS idx_installs_first_seen ON installs (first_seen);
