-- ============================================================
-- 003_policy.sql
-- Policy engine — Global → Environment → Asset Type → Asset
-- Most specific wins. Everything is policy driven.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS policy;

CREATE TABLE policy.policies (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    description TEXT,
    scope_type  TEXT NOT NULL,  -- 'global','environment','asset_type','asset'
    scope_id    UUID,           -- NULL for global
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE policy.policy_rules (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id   UUID NOT NULL REFERENCES policy.policies(id),
    category    TEXT NOT NULL,  -- 'collection','alerting','retention','scoring','ai'
    rule_key    TEXT NOT NULL,
    rule_value  TEXT NOT NULL,
    description TEXT,
    UNIQUE (policy_id, category, rule_key)
);

-- Resolved policy view — most specific wins
CREATE VIEW policy.resolved_policies AS
WITH ranked AS (
    SELECT
        p.id,
        p.scope_type,
        p.scope_id,
        pr.category,
        pr.rule_key,
        pr.rule_value,
        CASE p.scope_type
            WHEN 'global'      THEN 1
            WHEN 'environment' THEN 2
            WHEN 'asset_type'  THEN 3
            WHEN 'asset'       THEN 4
        END AS priority
    FROM policy.policies p
    JOIN policy.policy_rules pr ON pr.policy_id = p.id
    WHERE p.is_active = true
)
SELECT DISTINCT ON (scope_id, category, rule_key)
    *
FROM ranked
ORDER BY scope_id, category, rule_key, priority DESC;

-- Seed global defaults
INSERT INTO policy.policies (name, scope_type, description)
VALUES ('Global Defaults', 'global', 'Platform-wide defaults for all assets')
RETURNING id;

-- Seed default policy rules
WITH global_policy AS (
    SELECT id FROM policy.policies WHERE scope_type = 'global' LIMIT 1
)
INSERT INTO policy.policy_rules (policy_id, category, rule_key, rule_value, description)
SELECT
    global_policy.id,
    v.category,
    v.rule_key,
    v.rule_value,
    v.description
FROM global_policy,
(VALUES
    ('collection', 'cpu_interval_seconds',           '60',   'CPU collection interval'),
    ('collection', 'wait_stats_interval_seconds',    '60',   'Wait stats collection interval'),
    ('collection', 'memory_interval_seconds',        '60',   'Memory collection interval'),
    ('collection', 'io_interval_seconds',            '60',   'IO collection interval'),
    ('collection', 'plan_cache_interval_seconds',    '60',   'Plan cache collection interval'),
    ('collection', 'db_size_interval_seconds',       '300',  'DB size collection interval'),
    ('collection', 'top_queries_interval_seconds',   '300',  'Top queries collection interval'),
    ('collection', 'schema_intel_interval_seconds',  '3600', 'Schema intel collection interval'),
    ('alerting',   'cpu_warning_threshold_pct',      '80',   'CPU warning threshold'),
    ('alerting',   'cpu_sustained_minutes',          '10',   'Minutes CPU must be sustained high'),
    ('alerting',   'disk_critical_threshold_pct',    '90',   'Disk critical threshold'),
    ('alerting',   'plan_regression_threshold_pct',  '50',   'Plan regression degradation threshold'),
    ('scoring',    'high_recompile_threshold',       '100',  'Recompiles/sec threshold for scoring'),
    ('scoring',    'high_growth_threshold_pct',      '20',   'Weekly growth % threshold for scoring'),
    ('ai',         'max_tokens_per_request',         '1000', 'Max tokens per AI request'),
    ('ai',         'preferred_model',                'gpt-4o-mini', 'Default AI model'),
    ('retention',  'raw_hours',                      '24',   'Raw data retention hours'),
    ('retention',  'rollup_5m_days',                 '7',    '5-minute rollup retention days'),
    ('retention',  'rollup_15m_days',                '30',   '15-minute rollup retention days'),
    ('retention',  'rollup_1h_days',                 '365',  '1-hour rollup retention days')
) AS v(category, rule_key, rule_value, description);
