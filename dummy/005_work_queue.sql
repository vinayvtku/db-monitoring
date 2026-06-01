-- ============================================================
-- 005_work_queue.sql  (v2)
-- target_scripts  — persistent scheduling table
--                   one row per target per script
--                   this is the work queue seed
--
-- work_envelopes  — transient execution records
--                   created by scheduler when a job is due
--                   picked up by agent, executed, completed
--                   aged out after 7 days
--
-- work_results    — raw output from agent execution
--                   used when output_destination = 'raw'
-- ============================================================

CREATE SCHEMA IF NOT EXISTS work_queue;

-- ------------------------------------------------------------
-- Target scripts
-- The assignment table — one row per target per script
-- Created automatically on onboarding for all matching scripts
-- This is what the scheduler reads to know what to run and when
-- ------------------------------------------------------------
CREATE TABLE work_queue.target_scripts (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- What runs where
    target_id               UUID NOT NULL REFERENCES core.targets(id)
                            ON DELETE CASCADE,
    script_id               UUID NOT NULL REFERENCES script_registry.scripts(id),

    -- Schedule
    schedule                TEXT,
    -- NULL means use script default_schedule
    -- Set this to override for a specific target
    -- e.g. run CPU collection every 30s on Tier 1 instead of 60s

    -- State
    is_enabled              BOOLEAN NOT NULL DEFAULT true,
    last_run_at             TIMESTAMPTZ,
    last_run_status         TEXT,
    -- 'success','failed','timeout','partial','skipped'
    last_run_duration_ms    INT,
    last_error              TEXT,
    next_run_at             TIMESTAMPTZ,
    consecutive_failures    INT NOT NULL DEFAULT 0,
    total_runs              BIGINT NOT NULL DEFAULT 0,
    total_failures          BIGINT NOT NULL DEFAULT 0,

    -- Metadata
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              TEXT NOT NULL DEFAULT 'system',

    UNIQUE (target_id, script_id)
);

CREATE INDEX idx_target_scripts_due
    ON work_queue.target_scripts(next_run_at, is_enabled)
    WHERE is_enabled = true;
-- This is the hot index — the scheduler queries this constantly

CREATE INDEX idx_target_scripts_target
    ON work_queue.target_scripts(target_id);
CREATE INDEX idx_target_scripts_script
    ON work_queue.target_scripts(script_id);
CREATE INDEX idx_target_scripts_failures
    ON work_queue.target_scripts(consecutive_failures)
    WHERE consecutive_failures > 0;

-- Convenience view — what the scheduler sees
CREATE VIEW work_queue.due_scripts AS
SELECT
    ts.id           AS target_script_id,
    ts.target_id,
    ts.script_id,
    ts.schedule,
    ts.next_run_at,
    ts.consecutive_failures,
    t.name          AS target_name,
    t.fqdn          AS target_fqdn,
    t.host          AS target_host,
    t.port          AS target_port,
    t.connection_info,
    tt.name         AS target_type,
    tt.platform     AS target_platform,
    s.name          AS script_name,
    s.execution_type,
    s.script_body,
    s.script_hash,
    s.timeout_seconds,
    s.max_retries,
    s.credential_purpose,
    s.output_destination,
    s.output_schema,
    -- Resolve credential
    tc.credential_id,
    cp.keyvault_secret_uri  AS credential_uri,
    ct.auth_mechanism       AS credential_type,
    ct.requires_keyvault
FROM work_queue.target_scripts ts
JOIN core.targets               t   ON t.id  = ts.target_id
JOIN core.target_types          tt  ON tt.id = t.target_type_id
JOIN script_registry.scripts    s   ON s.id  = ts.script_id
LEFT JOIN security.target_credentials tc
    ON tc.target_id = ts.target_id
    AND tc.purpose  = s.credential_purpose
LEFT JOIN security.credential_profiles cp
    ON cp.id = tc.credential_id
LEFT JOIN security.credential_types ct
    ON ct.id = cp.credential_type_id
WHERE ts.is_enabled = true
  AND t.is_active   = true
  AND t.is_monitored = true
  AND s.is_enabled  = true
  AND (ts.next_run_at IS NULL OR ts.next_run_at <= now());

-- ------------------------------------------------------------
-- Work envelopes
-- Sealed execution records — agents execute blind
-- Agent knows: what to run, where to run it, how to auth
-- Agent does NOT know: why, which platform, business context
-- Transient — aged out after 7 days
-- ------------------------------------------------------------
CREATE TABLE work_queue.work_envelopes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_script_id    UUID NOT NULL
                        REFERENCES work_queue.target_scripts(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    scheduled_for       TIMESTAMPTZ NOT NULL,

    -- Sealed execution payload
    -- Agent reads these fields only — no business context
    execution_type      TEXT NOT NULL,
    script_body         TEXT NOT NULL,
    script_hash         TEXT NOT NULL,
    credential_uri      TEXT,
    -- NULL for managed_identity
    credential_type     TEXT NOT NULL,
    target_host         TEXT NOT NULL,
    target_port         INT,
    target_database     TEXT,
    -- relevant for SQL, PostgreSQL, MySQL, DB2
    connection_info     JSONB NOT NULL DEFAULT '{}',
    -- any extra connection params the agent needs
    timeout_seconds     INT NOT NULL DEFAULT 30,

    -- Retry state
    attempt             INT NOT NULL DEFAULT 1,
    max_attempts        INT NOT NULL DEFAULT 3,

    -- Execution state
    status              TEXT NOT NULL DEFAULT 'pending',
    -- 'pending','picked_up','running','success',
    -- 'failed','timeout','dead_letter'
    agent_id            TEXT,
    picked_up_at        TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    duration_ms         INT,

    -- Result
    result_status       TEXT,
    result_payload      JSONB,
    -- raw result from agent
    -- ingestion worker reads this and routes to correct schema
    error               TEXT,
    dead_letter_at      TIMESTAMPTZ
    -- set when max_attempts exceeded
);

SELECT create_hypertable('work_queue.work_envelopes', 'created_at',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('work_queue.work_envelopes',
    INTERVAL '7 days');
SELECT add_compression_policy('work_queue.work_envelopes',
    INTERVAL '2 days');

CREATE INDEX idx_envelopes_pending
    ON work_queue.work_envelopes(status, scheduled_for)
    WHERE status = 'pending';
CREATE INDEX idx_envelopes_dead_letter
    ON work_queue.work_envelopes(dead_letter_at)
    WHERE dead_letter_at IS NOT NULL;
CREATE INDEX idx_envelopes_target_script
    ON work_queue.work_envelopes(target_script_id, created_at DESC);

-- ------------------------------------------------------------
-- Work results
-- Raw output for scripts with output_destination = 'raw'
-- Also used for debugging any script output
-- ------------------------------------------------------------
CREATE TABLE work_queue.work_results (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    envelope_id     UUID NOT NULL
                    REFERENCES work_queue.work_envelopes(id),
    target_id       UUID NOT NULL REFERENCES core.targets(id),
    script_id       UUID NOT NULL REFERENCES script_registry.scripts(id),
    collected_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    result          JSONB NOT NULL,
    row_count       INT
);

SELECT create_hypertable('work_queue.work_results', 'collected_at',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('work_queue.work_results',
    INTERVAL '7 days');

CREATE INDEX idx_work_results_target
    ON work_queue.work_results(target_id, collected_at DESC);

-- ------------------------------------------------------------
-- Agent heartbeats
-- One row per agent — tracks that agents are alive
-- ------------------------------------------------------------
CREATE TABLE work_queue.agent_heartbeats (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id            TEXT NOT NULL UNIQUE,
    agent_version       TEXT,
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_envelope_id    UUID,
    envelopes_processed BIGINT NOT NULL DEFAULT 0,
    envelopes_failed    BIGINT NOT NULL DEFAULT 0,
    status              TEXT NOT NULL DEFAULT 'active',
    -- 'active','idle','degraded','offline'
    registered_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
