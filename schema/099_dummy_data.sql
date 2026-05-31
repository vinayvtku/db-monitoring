-- ============================================================
-- 099_dummy_data.sql
-- Realistic demo dataset for MVP demo and VP presentation
--
-- The story this data tells:
--   3 assets: Tier 1 SQL Server instance + 2 databases
--   StackOverflowDB: troubled — health score 7/10
--     - sa account enabled (security drift)
--     - high recompile rate
--     - high growth rate
--   TempDB: healthy — health score 10/10
--   A 2am CPU anomaly became an incident
--   A plan regression on top query degraded 62%
--   A backup failed on the Tier 1 instance
--   PagerDuty fired for the Tier 1 server
--   Daily digest captured everything
-- ============================================================

-- -------------------------------------------------------
-- Environments
-- -------------------------------------------------------
INSERT INTO core.environments (id, name, description) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'production',  'Production environment'),
    ('a0000000-0000-0000-0000-000000000002', 'development', 'Development environment');

-- -------------------------------------------------------
-- Assets
-- -------------------------------------------------------
WITH
    instance_type  AS (SELECT id FROM core.asset_types WHERE name = 'sql_server_instance'),
    database_type  AS (SELECT id FROM core.asset_types WHERE name = 'sql_server_database'),
    prod_env       AS (SELECT id FROM core.environments WHERE name = 'production'),
    tier1          AS (SELECT id FROM core.asset_tiers WHERE name = 'tier1'),
    tier2          AS (SELECT id FROM core.asset_tiers WHERE name = 'tier2')
INSERT INTO core.assets (id, asset_type_id, environment_id, tier_id, name, fqdn, region,
    resource_group, tags)
VALUES
    ('b0000000-0000-0000-0000-000000000001',
     (SELECT id FROM instance_type), (SELECT id FROM prod_env), (SELECT id FROM tier1),
     'SQL-PROD-01', 'sql-prod-01.internal', 'eastus', 'rg-monitoring-demo',
     '{"app": "stackoverflow", "team": "platform"}'),

    ('b0000000-0000-0000-0000-000000000002',
     (SELECT id FROM database_type), (SELECT id FROM prod_env), (SELECT id FROM tier1),
     'StackOverflowDB', 'sql-prod-01.internal/StackOverflowDB', 'eastus', 'rg-monitoring-demo',
     '{"app": "stackoverflow", "criticality": "high"}'),

    ('b0000000-0000-0000-0000-000000000003',
     (SELECT id FROM database_type), (SELECT id FROM prod_env), (SELECT id FROM tier2),
     'TempDB', 'sql-prod-01.internal/tempdb', 'eastus', 'rg-monitoring-demo',
     '{"app": "system", "criticality": "low"}');

-- Set parent relationships
UPDATE core.assets SET parent_id = 'b0000000-0000-0000-0000-000000000001'
    WHERE id IN (
        'b0000000-0000-0000-0000-000000000002',
        'b0000000-0000-0000-0000-000000000003'
    );

-- -------------------------------------------------------
-- Security — credential profiles
-- -------------------------------------------------------
INSERT INTO security.credential_profiles (id, name, auth_type, keyvault_secret_uri) VALUES
    ('c0000000-0000-0000-0000-000000000001',
     'prod-sqlserver-monitoring',
     'sql_login',
     'https://kv-monitoring-demo.vault.azure.net/secrets/prod-sql-monitor-login');

INSERT INTO security.asset_credentials (asset_id, credential_id) VALUES
    ('b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001'),
    ('b0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001'),
    ('b0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001');

-- -------------------------------------------------------
-- Inventory
-- -------------------------------------------------------
INSERT INTO inventory.sql_instances
    (asset_id, host, port, edition, version, version_build, patch_level,
     collation, is_clustered, is_hadr_enabled, max_dop, max_server_memory_mb,
     cost_threshold_parallelism)
VALUES
    ('b0000000-0000-0000-0000-000000000001',
     'sql-prod-01.internal', 1433,
     'Developer Edition', '16.0', '16.0.1000.6', 'CU12',
     'SQL_Latin1_General_CP1_CI_AS',
     false, false, 4, 32768, 50);

INSERT INTO inventory.sql_databases
    (asset_id, instance_id, name, state, recovery_model, compatibility_level,
     is_read_only, is_auto_close, is_auto_shrink, size_mb, log_size_mb, owner)
VALUES
    ('b0000000-0000-0000-0000-000000000002',
     (SELECT id FROM inventory.sql_instances
      WHERE asset_id = 'b0000000-0000-0000-0000-000000000001'),
     'StackOverflowDB', 'ONLINE', 'FULL', 160,
     false, false, false, 52480, 4096, 'sa'),

    ('b0000000-0000-0000-0000-000000000003',
     (SELECT id FROM inventory.sql_instances
      WHERE asset_id = 'b0000000-0000-0000-0000-000000000001'),
     'tempdb', 'ONLINE', 'SIMPLE', 160,
     false, false, false, 512, 64, 'sa');

-- Security principals — sa account enabled (this will trigger scoring deduction)
INSERT INTO inventory.sql_principals
    (asset_id, principal_name, principal_type, auth_type, is_disabled, is_sysadmin)
VALUES
    ('b0000000-0000-0000-0000-000000000001', 'sa',          'LOGIN', 'SQL',     false, true),
    ('b0000000-0000-0000-0000-000000000001', 'monitor_user','LOGIN', 'SQL',     false, false),
    ('b0000000-0000-0000-0000-000000000001', 'app_user',    'LOGIN', 'WINDOWS', false, false);

-- Application connections
INSERT INTO inventory.app_connections
    (database_asset_id, app_name, client_ip, login_name, connection_count)
VALUES
    ('b0000000-0000-0000-0000-000000000002', 'StackOverflow.Web',    '10.0.1.10', 'app_user',    48),
    ('b0000000-0000-0000-0000-000000000002', 'StackOverflow.Search', '10.0.1.11', 'app_user',    12),
    ('b0000000-0000-0000-0000-000000000002', 'SSMS',                 '10.0.1.50', 'monitor_user', 2);

-- -------------------------------------------------------
-- Metrics — 24 hours of CPU data telling the 2am story
-- -------------------------------------------------------
INSERT INTO metrics.cpu (time, asset_id, sql_cpu_pct, other_cpu_pct, idle_cpu_pct)
SELECT
    now() - (generate_series * INTERVAL '1 minute'),
    'b0000000-0000-0000-0000-000000000001',
    CASE
        -- 2am spike: 90-95% for 15 minutes
        WHEN generate_series BETWEEN 600 AND 615 THEN (90 + random() * 5)::SMALLINT
        -- normal daytime: 20-45%
        WHEN generate_series % 1440 BETWEEN 480 AND 1020 THEN (20 + random() * 25)::SMALLINT
        -- overnight: 5-15%
        ELSE (5 + random() * 10)::SMALLINT
    END,
    (2 + random() * 5)::SMALLINT,
    (100 - CASE
        WHEN generate_series BETWEEN 600 AND 615 THEN (90 + random() * 5)::SMALLINT
        WHEN generate_series % 1440 BETWEEN 480 AND 1020 THEN (20 + random() * 25)::SMALLINT
        ELSE (5 + random() * 10)::SMALLINT
    END - (2 + random() * 5)::SMALLINT)::SMALLINT
FROM generate_series(1, 1440);

-- DB size — showing growth over 24 hours
INSERT INTO metrics.db_size (time, asset_id, data_size_mb, log_size_mb, data_used_mb, log_used_mb)
SELECT
    now() - (generate_series * INTERVAL '5 minutes'),
    'b0000000-0000-0000-0000-000000000002',
    (52480 + generate_series * 0.8)::BIGINT,
    (4096  + generate_series * 0.1)::BIGINT,
    (49800 + generate_series * 0.8)::BIGINT,
    (2800  + generate_series * 0.1)::BIGINT
FROM generate_series(1, 288);

-- Plan cache — high recompiles during the 2am window
INSERT INTO metrics.plan_cache (time, asset_id, sql_compilations_sec, sql_recompilations_sec, plan_cache_hit_ratio)
SELECT
    now() - (generate_series * INTERVAL '1 minute'),
    'b0000000-0000-0000-0000-000000000001',
    CASE WHEN generate_series BETWEEN 600 AND 615 THEN (250 + random() * 100)::INT
         ELSE (20 + random() * 30)::INT END,
    CASE WHEN generate_series BETWEEN 600 AND 615 THEN (180 + random() * 80)::INT
         ELSE (5 + random() * 15)::INT END,
    CASE WHEN generate_series BETWEEN 600 AND 615 THEN (55 + random() * 10)::NUMERIC(5,2)
         ELSE (88 + random() * 8)::NUMERIC(5,2) END
FROM generate_series(1, 1440);

-- -------------------------------------------------------
-- Health scores
-- -------------------------------------------------------

-- StackOverflowDB: 7/10 — 3 signals fired
INSERT INTO scoring.health_scores (time, asset_id, score, max_score) VALUES
    (now(), 'b0000000-0000-0000-0000-000000000002', 7, 10);

-- TempDB: healthy 10/10
INSERT INTO scoring.health_scores (time, asset_id, score, max_score) VALUES
    (now(), 'b0000000-0000-0000-0000-000000000003', 10, 10);

-- Score deductions for StackOverflowDB
INSERT INTO scoring.score_deductions
    (time, asset_id, signal_id, deduction, detail, metric_value, metric_unit)
VALUES
    (now(), 'b0000000-0000-0000-0000-000000000002',
     (SELECT id FROM scoring.signal_definitions WHERE name = 'elevated_local_account'),
     1, 'sa account is enabled and has sysadmin rights', 'sa', 'account name'),

    (now(), 'b0000000-0000-0000-0000-000000000002',
     (SELECT id FROM scoring.signal_definitions WHERE name = 'high_plan_changes'),
     1, '847 recompiles in last 24h — 3.2x above baseline', '847', 'recompiles/24h'),

    (now(), 'b0000000-0000-0000-0000-000000000002',
     (SELECT id FROM scoring.signal_definitions WHERE name = 'high_growth_rate'),
     1, 'Database grew 42 GB in last 7 days — 28% above baseline', '42', 'GB/7d');

-- -------------------------------------------------------
-- Audit — security drift: sa was enabled
-- -------------------------------------------------------
INSERT INTO audit.drift_events
    (time, asset_id, drift_type, category, property,
     previous_value, current_value, detail, severity)
VALUES
    (now() - INTERVAL '6 hours',
     'b0000000-0000-0000-0000-000000000001',
     'security', 'login', 'is_disabled',
     'true', 'false',
     'sa login was re-enabled. This is a sysadmin account with full server rights.',
     'high');

-- -------------------------------------------------------
-- Query intelligence — top query + plan regression
-- -------------------------------------------------------

-- Query fingerprint for the top slow query
INSERT INTO query_intel.query_fingerprints
    (id, asset_id, fingerprint_hash, normalized_text, example_text)
VALUES
    ('d0000000-0000-0000-0000-000000000001',
     'b0000000-0000-0000-0000-000000000001',
     'sha256_abc123',
     'SELECT p.*, a.* FROM Posts p JOIN Answers a ON p.Id = a.ParentId WHERE p.Score > ?',
     'SELECT p.*, a.* FROM Posts p JOIN Answers a ON p.Id = a.ParentId WHERE p.Score > 50');

-- Previous good plan
INSERT INTO query_intel.execution_plans
    (id, fingerprint_id, asset_id, plan_handle, plan_hash, is_current, estimated_cost, plan_warnings)
VALUES
    ('e0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000001',
     'b0000000-0000-0000-0000-000000000001',
     'prev_plan_handle_abc', 'prev_plan_hash_001',
     false, 42.5, NULL),

    ('e0000000-0000-0000-0000-000000000002',
     'd0000000-0000-0000-0000-000000000001',
     'b0000000-0000-0000-0000-000000000001',
     'curr_plan_handle_xyz', 'curr_plan_hash_002',
     true, 187.3, ARRAY['Missing Index on dbo.Posts (Score)', 'Implicit Conversion on PostTypeId']);

-- Plan regression
INSERT INTO query_intel.plan_regressions
    (detected_at, fingerprint_id, asset_id,
     previous_plan_id, current_plan_id,
     previous_avg_cpu_ms, current_avg_cpu_ms, degradation_pct, status)
VALUES
    (now() - INTERVAL '3 hours',
     'd0000000-0000-0000-0000-000000000001',
     'b0000000-0000-0000-0000-000000000001',
     'e0000000-0000-0000-0000-000000000001',
     'e0000000-0000-0000-0000-000000000002',
     245.0, 1842.0, 62.0, 'open');

-- Top query snapshot
INSERT INTO query_intel.top_queries
    (time, asset_id, fingerprint_id, database_name,
     execution_count, total_cpu_ms, total_duration_ms,
     total_logical_reads, total_logical_writes, total_physical_reads,
     avg_cpu_ms, avg_duration_ms, avg_logical_reads, plan_count)
VALUES
    (now() - INTERVAL '5 minutes',
     'b0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000001',
     'StackOverflowDB',
     4820, 8887240, 12450000, 94820000, 0, 28400,
     1842.0, 2582.0, 19672.0, 2);

-- -------------------------------------------------------
-- Alerts
-- -------------------------------------------------------

-- CPU alert fired during 2am spike
INSERT INTO alerts.alert_instances
    (id, time, rule_id, asset_id, severity, status,
     fired_at, resolved_at, metric_value, detail)
VALUES
    ('f0000000-0000-0000-0000-000000000001',
     now() - INTERVAL '10 hours',
     (SELECT id FROM alerts.alert_rules WHERE name = 'smart_cpu_high'),
     'b0000000-0000-0000-0000-000000000001',
     'warning', 'resolved',
     now() - INTERVAL '10 hours',
     now() - INTERVAL '9 hours 45 minutes',
     '92%',
     'SQL Server CPU sustained above 80% for 15 minutes. Peak: 92%. Resolved after 15 minutes.');

-- Plan regression alert
INSERT INTO alerts.alert_instances
    (id, time, rule_id, asset_id, severity, status, fired_at, metric_value, detail)
VALUES
    ('f0000000-0000-0000-0000-000000000002',
     now() - INTERVAL '3 hours',
     (SELECT id FROM alerts.alert_rules WHERE name = 'plan_regression'),
     'b0000000-0000-0000-0000-000000000001',
     'warning', 'open',
     now() - INTERVAL '3 hours',
     '62%',
     'Query plan regression detected. Posts/Answers join query degraded 62%. Missing index on Posts.Score.');

-- Backup failure alert
INSERT INTO alerts.alert_instances
    (id, time, rule_id, asset_id, severity, status, fired_at, metric_value, detail)
VALUES
    ('f0000000-0000-0000-0000-000000000003',
     now() - INTERVAL '2 hours',
     (SELECT id FROM alerts.alert_rules WHERE name = 'backup_failed'),
     'b0000000-0000-0000-0000-000000000002',
     'critical', 'open',
     now() - INTERVAL '2 hours',
     'FAILED',
     'Full backup job failed. Last successful backup was 49 hours ago. Backup destination may be full.');

-- -------------------------------------------------------
-- Maintenance — backup history showing the failure
-- -------------------------------------------------------
INSERT INTO maintenance.backup_history
    (time, asset_id, database_name, backup_type, status,
     backup_size_mb, compressed_size_mb, duration_seconds, backup_location)
VALUES
    (now() - INTERVAL '2 hours',
     'b0000000-0000-0000-0000-000000000002',
     'StackOverflowDB', 'full', 'failed',
     NULL, NULL, 48,
     '\\backup-server\sql-prod-01\StackOverflowDB\'),

    (now() - INTERVAL '26 hours',
     'b0000000-0000-0000-0000-000000000002',
     'StackOverflowDB', 'full', 'succeeded',
     48200, 18400, 3420,
     '\\backup-server\sql-prod-01\StackOverflowDB\');

-- -------------------------------------------------------
-- Incidents — 2am CPU spike became an incident
-- -------------------------------------------------------
INSERT INTO incidents.incidents
    (id, title, summary, severity, status, asset_id,
     opened_at, resolved_at, ai_summary, ai_priority)
VALUES
    ('g0000000-0000-0000-0000-000000000001',
     'SQL-PROD-01 — CPU spike at 2am correlated with plan regression',
     'Sustained CPU spike triggered during overnight batch window.',
     'high', 'resolved',
     'b0000000-0000-0000-0000-000000000001',
     now() - INTERVAL '10 hours',
     now() - INTERVAL '9 hours 45 minutes',
     'A CPU spike sustained at 92% for 15 minutes on SQL-PROD-01 coincided with a query plan '
     'regression on the Posts/Answers join query. The regression introduced a table scan on '
     'dbo.Posts due to a missing index on Score. The plan was stabilised when the query fell '
     'out of the plan cache. Recommend creating the missing index during next maintenance window.',
     1);

-- Link alert to incident
INSERT INTO incidents.incident_alerts (incident_id, alert_id) VALUES
    ('g0000000-0000-0000-0000-000000000001',
     'f0000000-0000-0000-0000-000000000001');

-- Incident timeline
INSERT INTO incidents.incident_timeline
    (incident_id, time, event_type, detail, author)
VALUES
    ('g0000000-0000-0000-0000-000000000001',
     now() - INTERVAL '10 hours', 'opened',
     'CPU alert fired: SQL Server CPU at 92% for 15 minutes', 'system'),

    ('g0000000-0000-0000-0000-000000000001',
     now() - INTERVAL '9 hours 55 minutes', 'alert_linked',
     'Plan regression alert correlated into this incident', 'system'),

    ('g0000000-0000-0000-0000-000000000001',
     now() - INTERVAL '9 hours 50 minutes', 'ai_summary',
     'AI investigation complete. Root cause: missing index on dbo.Posts (Score). '
     'Recommend: CREATE INDEX IX_Posts_Score ON dbo.Posts(Score) INCLUDE (Id, Body, Tags)',
     'system'),

    ('g0000000-0000-0000-0000-000000000001',
     now() - INTERVAL '9 hours 45 minutes', 'resolved',
     'CPU returned to baseline. Plan cache cleared. Incident resolved pending index creation.',
     'dba-oncall');

-- -------------------------------------------------------
-- Notification log — PagerDuty fired for Tier 1
-- -------------------------------------------------------
INSERT INTO notifications.notification_log
    (time, alert_id, channel_id, sent_to, status, duration_ms)
VALUES
    (now() - INTERVAL '10 hours',
     'f0000000-0000-0000-0000-000000000001',
     (SELECT id FROM notifications.channels WHERE name = 'PagerDuty On-Call'),
     'dba-oncall', 'sent', 312),

    (now() - INTERVAL '10 hours',
     'f0000000-0000-0000-0000-000000000001',
     (SELECT id FROM notifications.channels WHERE name = 'Teams Ops Channel'),
     '#ops-alerts', 'sent', 188),

    (now() - INTERVAL '3 hours',
     'f0000000-0000-0000-0000-000000000002',
     (SELECT id FROM notifications.channels WHERE name = 'Teams Ops Channel'),
     '#ops-alerts', 'sent', 201),

    (now() - INTERVAL '2 hours',
     'f0000000-0000-0000-0000-000000000003',
     (SELECT id FROM notifications.channels WHERE name = 'PagerDuty On-Call'),
     'dba-oncall', 'sent', 298);

-- -------------------------------------------------------
-- AI — daily digest
-- -------------------------------------------------------
INSERT INTO ai.digest_log
    (digest_date, subject, body_html, sent_to, sent_at, send_status, total_tokens)
VALUES
    (CURRENT_DATE,
     'DB Platform Daily Digest — ' || TO_CHAR(CURRENT_DATE, 'Mon DD YYYY')
     || ' — 1 open incident, 2 open alerts, StackOverflowDB health 7/10',
     '<h2>Good morning</h2>
      <p>Here is your database estate summary for ' || TO_CHAR(CURRENT_DATE, 'DD Mon YYYY') || '.</p>
      <h3>Health Scores</h3>
      <ul>
        <li><strong>StackOverflowDB</strong>: 7/10 — sa account enabled, high recompiles, high growth</li>
        <li><strong>TempDB</strong>: 10/10</li>
      </ul>
      <h3>Open Alerts</h3>
      <ul>
        <li><strong>CRITICAL</strong>: StackOverflowDB backup failed 2 hours ago. Last success 49h ago.</li>
        <li><strong>WARNING</strong>: Plan regression on Posts/Answers join — 62% degradation. Missing index.</li>
      </ul>
      <h3>Overnight Activity</h3>
      <ul>
        <li>CPU spike at 2am — resolved after 15 minutes. Root cause: plan regression.</li>
        <li>Security drift: sa login was re-enabled 6 hours ago.</li>
      </ul>
      <h3>My Priority Recommendation</h3>
      <ol>
        <li>Resolve backup failure immediately — StackOverflowDB has no recent backup.</li>
        <li>Create missing index on dbo.Posts(Score) to resolve plan regression and prevent recurrence.</li>
        <li>Disable sa login — this is a critical security risk on a Tier 1 server.</li>
      </ol>',
     ARRAY['dba-team@company.com', 'vp-engineering@company.com'],
     now() - INTERVAL '1 hour',
     'sent',
     1847);

-- -------------------------------------------------------
-- Baselines — example baselines for CPU (Monday 2am)
-- Shows why the 2am spike was flagged as anomalous
-- -------------------------------------------------------
INSERT INTO baselines.metric_baselines
    (asset_id, metric_name, hour_of_day, day_of_week,
     sample_count, mean, stddev, p50, p95, p99,
     anomaly_low, anomaly_high,
     training_from, training_to)
VALUES
    ('b0000000-0000-0000-0000-000000000001',
     'cpu_pct', 2, 1,  -- 2am Monday
     168, 8.4, 3.2, 7.0, 14.2, 18.6,
     -1.2, 18.0,  -- anomaly_high = mean + 3*stddev = 8.4 + 9.6 = 18
     now() - INTERVAL '28 days', now() - INTERVAL '1 day');

-- Anomaly event for the 2am spike
INSERT INTO baselines.anomaly_events
    (time, asset_id, metric_name, observed_value, baseline_mean, baseline_stddev,
     deviation_score, direction)
VALUES
    (now() - INTERVAL '10 hours',
     'b0000000-0000-0000-0000-000000000001',
     'cpu_pct', 92.0, 8.4, 3.2, 26.1, 'high');

-- -------------------------------------------------------
-- Forecasts — StackOverflowDB will breach disk in 23 days
-- -------------------------------------------------------
INSERT INTO forecasts.metric_forecasts
    (asset_id, metric_name, forecast_horizon, model_type,
     projected_value, confidence_low, confidence_high,
     growth_rate_pct, breach_threshold, breach_date, breach_days_out,
     training_from, training_to)
VALUES
    ('b0000000-0000-0000-0000-000000000002',
     'data_size_mb', '30d', 'linear',
     65536.0, 63488.0, 67584.0,
     1.84, 65536.0,
     now() + INTERVAL '23 days', 23,
     now() - INTERVAL '28 days', now());
