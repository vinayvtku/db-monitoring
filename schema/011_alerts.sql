-- ============================================================
-- 011_alerts.sql
-- Alert rules and instances
-- Rules seeded for MVP: server down, db down, disk full,
-- smart CPU, plan regression
-- ============================================================

CREATE SCHEMA IF NOT EXISTS alerts;

CREATE TABLE alerts.alert_rules (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    category        TEXT NOT NULL,
    target_type     TEXT NOT NULL,
    metric_source   TEXT NOT NULL,
    condition       JSONB NOT NULL,
    severity        TEXT NOT NULL,
    use_baseline    BOOLEAN NOT NULL DEFAULT false,
    is_enabled      BOOLEAN NOT NULL DEFAULT true,
    is_mvp          BOOLEAN NOT NULL DEFAULT false,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO alerts.alert_rules
    (name, display_name, category, target_type, metric_source,
     condition, severity, use_baseline, is_mvp)
VALUES
    ('server_down',
     'Server unavailable', 'availability', 'sql_server_instance',
     'collector.collector_heartbeats',
     '{"consecutive_failures": 3}',
     'critical', false, true),

    ('database_down',
     'Database unavailable', 'availability', 'sql_server_database',
     'collector.collector_heartbeats',
     '{"consecutive_failures": 3}',
     'critical', false, true),

    ('disk_full',
     'Disk space critical', 'capacity', 'sql_server_database',
     'metrics.db_size_1h',
     '{"metric": "data_used_pct", "operator": ">", "threshold": 90}',
     'critical', false, true),

    ('smart_cpu_high',
     'Smart CPU high', 'performance', 'sql_server_instance',
     'metrics.cpu_5m',
     '{"metric": "sql_cpu_pct_avg", "operator": ">", "threshold": 80,
       "sustained_minutes": 10}',
     'warning', true, true),

    ('plan_regression',
     'Query plan regression', 'performance', 'sql_server_instance',
     'query_intel.plan_regressions',
     '{"metric": "degradation_pct", "operator": ">", "threshold": 50}',
     'warning', false, true),

    ('backup_failed',
     'Backup job failed', 'availability', 'sql_server_database',
     'maintenance.backup_history',
     '{"status": "failed", "within_hours": 24}',
     'critical', false, false),

    ('security_drift',
     'Security configuration changed', 'security', 'sql_server_instance',
     'audit.drift_events',
     '{"drift_type": "security", "severity": "high"}',
     'critical', false, false);

CREATE TABLE alerts.alert_instances (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    time                TIMESTAMPTZ NOT NULL,
    rule_id             UUID NOT NULL REFERENCES alerts.alert_rules(id),
    asset_id            UUID NOT NULL REFERENCES core.assets(id),
    severity            TEXT NOT NULL,
    status              TEXT NOT NULL DEFAULT 'open',
    fired_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at         TIMESTAMPTZ,
    acknowledged_at     TIMESTAMPTZ,
    acknowledged_by     TEXT,
    metric_value        TEXT,
    detail              TEXT,
    suppression_reason  TEXT
);
SELECT create_hypertable('alerts.alert_instances', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('alerts.alert_instances', INTERVAL '365 days');
CREATE INDEX idx_alert_instances_asset
    ON alerts.alert_instances(asset_id, time DESC);
CREATE INDEX idx_alert_instances_open
    ON alerts.alert_instances(status) WHERE status = 'open';
