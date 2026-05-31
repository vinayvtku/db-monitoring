-- ============================================================
-- 016_forecasts.sql
-- Growth projections, capacity breach predictions
-- "This database will run out of space in 23 days"
-- ============================================================

CREATE SCHEMA IF NOT EXISTS forecasts;

CREATE TABLE forecasts.metric_forecasts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id            UUID NOT NULL REFERENCES core.assets(id),
    metric_name         TEXT NOT NULL,
    forecast_horizon    TEXT NOT NULL,      -- '7d','30d','90d'
    generated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    training_from       TIMESTAMPTZ NOT NULL,
    training_to         TIMESTAMPTZ NOT NULL,
    model_type          TEXT NOT NULL DEFAULT 'linear',  -- 'linear','exponential','seasonal'
    projected_value     NUMERIC(16,4) NOT NULL,
    confidence_low      NUMERIC(16,4),
    confidence_high     NUMERIC(16,4),
    growth_rate_pct     NUMERIC(8,4),
    breach_threshold    NUMERIC(16,4),
    breach_date         TIMESTAMPTZ,
    breach_days_out     INT,
    is_current          BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX idx_forecasts_asset
    ON forecasts.metric_forecasts(asset_id, metric_name, is_current);
CREATE INDEX idx_forecasts_breach
    ON forecasts.metric_forecasts(breach_days_out)
    WHERE breach_days_out IS NOT NULL AND is_current = true;
