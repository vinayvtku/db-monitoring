-- ============================================================
-- 010_query_intel.sql
-- Top queries, execution plans, plan regressions, fingerprints
-- This is the DPA replacement story
-- ============================================================

CREATE SCHEMA IF NOT EXISTS query_intel;

-- Query fingerprints — normalized query text
CREATE TABLE query_intel.query_fingerprints (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id            UUID NOT NULL REFERENCES core.assets(id),
    fingerprint_hash    TEXT NOT NULL,
    normalized_text     TEXT NOT NULL,
    example_text        TEXT,
    first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (asset_id, fingerprint_hash)
);
CREATE INDEX idx_fingerprints_asset ON query_intel.query_fingerprints(asset_id);

-- Top query snapshots — hypertable
CREATE TABLE query_intel.top_queries (
    time                    TIMESTAMPTZ NOT NULL,
    asset_id                UUID NOT NULL REFERENCES core.assets(id),
    fingerprint_id          UUID NOT NULL REFERENCES query_intel.query_fingerprints(id),
    database_name           TEXT,
    execution_count         BIGINT NOT NULL,
    total_cpu_ms            BIGINT NOT NULL,
    total_duration_ms       BIGINT NOT NULL,
    total_logical_reads     BIGINT NOT NULL,
    total_logical_writes    BIGINT NOT NULL,
    total_physical_reads    BIGINT NOT NULL,
    avg_cpu_ms              NUMERIC(12,2),
    avg_duration_ms         NUMERIC(12,2),
    avg_logical_reads       NUMERIC(12,2),
    plan_count              INT
);
SELECT create_hypertable('query_intel.top_queries', 'time',
    chunk_time_interval => INTERVAL '1 hour');
SELECT add_retention_policy('query_intel.top_queries', INTERVAL '7 days');
SELECT add_compression_policy('query_intel.top_queries', INTERVAL '2 hours');

CREATE MATERIALIZED VIEW query_intel.top_queries_1h
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', time) AS bucket, asset_id, fingerprint_id,
    SUM(execution_count)        AS execution_count,
    MAX(total_cpu_ms)           AS total_cpu_ms,
    AVG(avg_cpu_ms)             AS avg_cpu_ms,
    AVG(avg_duration_ms)        AS avg_duration_ms,
    AVG(avg_logical_reads)      AS avg_logical_reads,
    MAX(plan_count)             AS plan_count_max
FROM query_intel.top_queries
GROUP BY bucket, asset_id, fingerprint_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('query_intel.top_queries_1h',
    start_offset => INTERVAL '2 hours', end_offset => INTERVAL '15 minutes',
    schedule_interval => INTERVAL '15 minutes');
SELECT add_retention_policy('query_intel.top_queries_1h', INTERVAL '365 days');

-- Execution plans — compressed XML
CREATE TABLE query_intel.execution_plans (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fingerprint_id  UUID NOT NULL REFERENCES query_intel.query_fingerprints(id),
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    plan_handle     TEXT NOT NULL,
    plan_hash       TEXT NOT NULL,
    plan_xml        TEXT,
    captured_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_current      BOOLEAN NOT NULL DEFAULT true,
    estimated_cost  NUMERIC(12,4),
    plan_warnings   TEXT[],
    UNIQUE (asset_id, plan_hash)
);
CREATE INDEX idx_plans_fingerprint
    ON query_intel.execution_plans(fingerprint_id, is_current);

-- Plan regressions — same query, worse plan
CREATE TABLE query_intel.plan_regressions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    detected_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    fingerprint_id          UUID NOT NULL REFERENCES query_intel.query_fingerprints(id),
    asset_id                UUID NOT NULL REFERENCES core.assets(id),
    previous_plan_id        UUID NOT NULL REFERENCES query_intel.execution_plans(id),
    current_plan_id         UUID NOT NULL REFERENCES query_intel.execution_plans(id),
    previous_avg_cpu_ms     NUMERIC(12,2),
    current_avg_cpu_ms      NUMERIC(12,2),
    degradation_pct         NUMERIC(6,2),
    status                  TEXT NOT NULL DEFAULT 'open',
    acknowledged_by         TEXT,
    resolved_at             TIMESTAMPTZ
);
CREATE INDEX idx_regressions_asset
    ON query_intel.plan_regressions(asset_id, detected_at DESC);
CREATE INDEX idx_regressions_open
    ON query_intel.plan_regressions(status) WHERE status = 'open';
