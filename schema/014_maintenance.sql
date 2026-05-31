-- ============================================================
-- 014_maintenance.sql
-- Maintenance windows, SQL Agent jobs, backup history
-- Correlates with alert suppression and incident context
-- ============================================================

CREATE SCHEMA IF NOT EXISTS maintenance;

CREATE TABLE maintenance.maintenance_windows (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id    UUID REFERENCES core.assets(id),
    name        TEXT NOT NULL,
    window_type TEXT NOT NULL,  -- 'backup','index_rebuild','patching','manual'
    starts_at   TIMESTAMPTZ NOT NULL,
    ends_at     TIMESTAMPTZ NOT NULL,
    recurrence  TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_by  TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE maintenance.sql_agent_jobs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id                UUID NOT NULL REFERENCES core.assets(id),
    job_id                  TEXT NOT NULL,
    job_name                TEXT NOT NULL,
    is_enabled              BOOLEAN NOT NULL,
    schedule                TEXT,
    last_run_at             TIMESTAMPTZ,
    last_run_status         TEXT,
    last_run_duration_seconds INT,
    collected_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (asset_id, job_id)
);

CREATE TABLE maintenance.sql_agent_job_history (
    time                TIMESTAMPTZ NOT NULL,
    asset_id            UUID NOT NULL REFERENCES core.assets(id),
    job_id              TEXT NOT NULL,
    step_id             INT,
    step_name           TEXT,
    status              TEXT NOT NULL,
    duration_seconds    INT,
    message             TEXT
);
SELECT create_hypertable('maintenance.sql_agent_job_history', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('maintenance.sql_agent_job_history', INTERVAL '90 days');

CREATE TABLE maintenance.backup_history (
    time                TIMESTAMPTZ NOT NULL,
    asset_id            UUID NOT NULL REFERENCES core.assets(id),
    database_name       TEXT NOT NULL,
    backup_type         TEXT NOT NULL,
    status              TEXT NOT NULL,
    backup_size_mb      BIGINT,
    compressed_size_mb  BIGINT,
    duration_seconds    INT,
    backup_location     TEXT,
    expiry_date         TIMESTAMPTZ
);
SELECT create_hypertable('maintenance.backup_history', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('maintenance.backup_history', INTERVAL '365 days');
CREATE INDEX idx_backup_asset_time ON maintenance.backup_history(asset_id, time DESC);
