-- ============================================================
-- 008_baselines.sql
-- 4-week rolling statistical baselines with seasonality
-- hour_of_day + day_of_week captures full weekly patterns
-- Anomaly events fired when metrics deviate beyond thresholds
-- ============================================================

CREATE SCHEMA IF NOT EXISTS baselines;

CREATE TABLE baselines.metric_baselines (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    metric_name     TEXT NOT NULL,
    hour_of_day     SMALLINT NOT NULL CHECK (hour_of_day BETWEEN 0 AND 23),
    day_of_week     SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    sample_count    INT NOT NULL,
    mean            NUMERIC(12,4) NOT NULL,
    stddev          NUMERIC(12,4) NOT NULL,
    p50             NUMERIC(12,4),
    p95             NUMERIC(12,4),
    p99             NUMERIC(12,4),
    min_val         NUMERIC(12,4),
    max_val         NUMERIC(12,4),
    anomaly_low     NUMERIC(12,4),  -- mean - (3 * stddev)
    anomaly_high    NUMERIC(12,4),  -- mean + (3 * stddev)
    training_from   TIMESTAMPTZ NOT NULL,
    training_to     TIMESTAMPTZ NOT NULL,
    calculated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_current      BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (asset_id, metric_name, hour_of_day, day_of_week)
);

CREATE INDEX idx_baselines_asset_metric
    ON baselines.metric_baselines(asset_id, metric_name, is_current);

CREATE TABLE baselines.anomaly_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    time            TIMESTAMPTZ NOT NULL,
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    metric_name     TEXT NOT NULL,
    observed_value  NUMERIC(12,4) NOT NULL,
    baseline_mean   NUMERIC(12,4) NOT NULL,
    baseline_stddev NUMERIC(12,4) NOT NULL,
    deviation_score NUMERIC(6,2) NOT NULL,  -- stddevs from mean
    direction       TEXT NOT NULL,          -- 'high' or 'low'
    is_suppressed   BOOLEAN NOT NULL DEFAULT false,
    suppression_reason TEXT
);

SELECT create_hypertable('baselines.anomaly_events', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('baselines.anomaly_events', INTERVAL '90 days');
CREATE INDEX idx_anomaly_asset_time
    ON baselines.anomaly_events(asset_id, time DESC);
