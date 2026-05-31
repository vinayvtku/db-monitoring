-- ============================================================
-- 009_scoring.sql
-- Health scorecard — 10/10 default, signals deduct points
-- Drill-down shows each deduction with inline metric value
-- ============================================================

CREATE SCHEMA IF NOT EXISTS scoring;

CREATE TABLE scoring.signal_definitions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    category        TEXT NOT NULL,
    deduction       SMALLINT NOT NULL DEFAULT 1,
    description     TEXT,
    remediation     TEXT,
    is_enabled      BOOLEAN NOT NULL DEFAULT true,
    is_mvp          BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO scoring.signal_definitions
    (name, display_name, category, deduction, is_mvp, description, remediation)
VALUES
    ('elevated_local_account',
     'Local account with elevated rights', 'security', 1, true,
     'SQL login with sysadmin or securityadmin rights detected.',
     'Disable elevated SQL logins. Use Windows/AD authentication with least privilege.'),
    ('high_plan_changes',
     'High plan recompile rate', 'performance', 1, true,
     'SQL recompilations/sec exceed baseline threshold indicating unstable plans.',
     'Review parameterization settings. Investigate top recompiling queries.'),
    ('high_growth_rate',
     'High database growth rate', 'growth', 1, true,
     'Database grew more than 20% in the last 7 days vs rolling baseline.',
     'Investigate data growth source. Review autogrowth settings. Consider archiving.'),
    ('backup_failure',
     'Backup failed', 'availability', 1, false,
     'Most recent backup job failed or has not run within expected window.',
     'Check SQL Agent job history. Verify backup destination has sufficient space.'),
    ('plan_regression_detected',
     'Query plan regression', 'performance', 1, false,
     'A query is executing with a worse execution plan than its baseline.',
     'Review plan regression details. Consider USE PLAN hint or UPDATE STATISTICS.'),
    ('schema_drift_detected',
     'Unexpected schema change', 'configuration', 1, false,
     'A schema object was created, modified, or dropped outside a deployment window.',
     'Review change with DBA team. Update deployment records if change was authorised.');

-- Health scores — hypertable for score history
CREATE TABLE scoring.health_scores (
    time        TIMESTAMPTZ NOT NULL,
    asset_id    UUID NOT NULL REFERENCES core.assets(id),
    score       SMALLINT NOT NULL DEFAULT 10,
    max_score   SMALLINT NOT NULL DEFAULT 10
);
SELECT create_hypertable('scoring.health_scores', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('scoring.health_scores', INTERVAL '365 days');
CREATE INDEX idx_health_scores_asset
    ON scoring.health_scores(asset_id, time DESC);

-- Score deductions — inline metric values for Grafana drill-down
CREATE TABLE scoring.score_deductions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    time        TIMESTAMPTZ NOT NULL,
    asset_id    UUID NOT NULL REFERENCES core.assets(id),
    signal_id   UUID NOT NULL REFERENCES scoring.signal_definitions(id),
    deduction   SMALLINT NOT NULL,
    detail      TEXT NOT NULL,
    metric_value TEXT,
    metric_unit  TEXT
);
SELECT create_hypertable('scoring.score_deductions', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('scoring.score_deductions', INTERVAL '365 days');
CREATE INDEX idx_deductions_asset_time
    ON scoring.score_deductions(asset_id, time DESC);
