-- ============================================================
-- 017_audit.sql
-- Drift events — security, configuration, schema changes
-- Feeds scoring signals and AI context builder
-- ============================================================

CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE audit.drift_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    time            TIMESTAMPTZ NOT NULL DEFAULT now(),
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    drift_type      TEXT NOT NULL,      -- 'security','configuration','schema'
    category        TEXT NOT NULL,
    property        TEXT NOT NULL,
    previous_value  TEXT,
    current_value   TEXT,
    detail          TEXT,
    severity        TEXT NOT NULL DEFAULT 'info',
    is_acknowledged BOOLEAN NOT NULL DEFAULT false,
    acknowledged_at TIMESTAMPTZ,
    acknowledged_by TEXT
);
SELECT create_hypertable('audit.drift_events', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('audit.drift_events', INTERVAL '365 days');
CREATE INDEX idx_drift_asset_time
    ON audit.drift_events(asset_id, time DESC);
CREATE INDEX idx_drift_unacknowledged
    ON audit.drift_events(is_acknowledged) WHERE is_acknowledged = false;
