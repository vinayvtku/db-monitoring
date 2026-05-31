-- ============================================================
-- 005_collector.sql
-- Plugin manifest, work envelopes, assignments, heartbeats
-- Agents are dumb executors — pick up, run, return status
-- ============================================================

CREATE SCHEMA IF NOT EXISTS collector;

-- Plugin manifest — describes what each collector produces
CREATE TABLE collector.plugin_manifest (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    TEXT NOT NULL UNIQUE,
    display_name            TEXT NOT NULL,
    version                 TEXT NOT NULL DEFAULT '1.0.0',
    category                TEXT NOT NULL,
    target_type             TEXT NOT NULL,
    execution_type          TEXT NOT NULL,  -- 'tsql','powershell','bash','rest'
    output_schema           JSONB NOT NULL DEFAULT '{}',
    min_sql_version         TEXT,
    max_sql_version         TEXT,
    default_interval_seconds INT NOT NULL DEFAULT 60,
    is_enabled              BOOLEAN NOT NULL DEFAULT true,
    script_hash             TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO collector.plugin_manifest
    (name, display_name, category, target_type, execution_type,
     default_interval_seconds, output_schema)
VALUES
    ('sql_cpu',         'SQL Server CPU',           'performance', 'sql_server_instance', 'tsql', 60,
     '{"sql_cpu_pct": "int", "other_cpu_pct": "int", "idle_cpu_pct": "int"}'),
    ('sql_wait_stats',  'SQL Server Wait Stats',    'performance', 'sql_server_instance', 'tsql', 60,
     '{"wait_type": "text", "wait_time_ms": "bigint", "waiting_tasks": "int"}'),
    ('sql_memory',      'SQL Server Memory',        'performance', 'sql_server_instance', 'tsql', 60,
     '{"total_server_memory_mb": "bigint", "target_server_memory_mb": "bigint"}'),
    ('sql_io',          'SQL Server IO',            'performance', 'sql_server_database', 'tsql', 60,
     '{"file_id": "int", "io_stall_read_ms": "bigint", "num_of_reads": "bigint"}'),
    ('sql_plan_cache',  'SQL Server Plan Cache',    'performance', 'sql_server_instance', 'tsql', 60,
     '{"sql_compilations_sec": "int", "sql_recompilations_sec": "int"}'),
    ('sql_db_size',     'SQL Server DB Size',       'capacity',    'sql_server_database', 'tsql', 300,
     '{"data_size_mb": "bigint", "log_size_mb": "bigint", "data_used_mb": "bigint"}'),
    ('sql_top_queries', 'SQL Server Top Queries',   'performance', 'sql_server_instance', 'tsql', 300,
     '{"query_hash": "text", "total_cpu_ms": "bigint", "execution_count": "bigint"}'),
    ('sql_schema_intel','SQL Server Schema Intel',  'schema',      'sql_server_database', 'tsql', 3600,
     '{"object_type": "text", "schema_name": "text", "object_name": "text", "definition": "text"}'),
    ('sql_principals',  'SQL Server Principals',    'security',    'sql_server_instance', 'tsql', 3600,
     '{"principal_name": "text", "is_sysadmin": "bool", "auth_type": "text"}'),
    ('sql_agent_jobs',  'SQL Agent Jobs',           'maintenance', 'sql_server_instance', 'tsql', 300,
     '{"job_name": "text", "last_run_status": "text", "last_run_duration_seconds": "int"}'),
    ('sql_backup_history', 'SQL Backup History',   'maintenance', 'sql_server_database', 'tsql', 3600,
     '{"backup_type": "text", "backup_size_mb": "bigint", "status": "text"}'),
    ('sql_app_connections', 'App Connection Map',  'inventory',   'sql_server_database', 'tsql', 300,
     '{"app_name": "text", "client_ip": "text", "login_name": "text", "connection_count": "int"}');

-- Collector assignments
CREATE TABLE collector.collector_assignments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plugin_id           UUID NOT NULL REFERENCES collector.plugin_manifest(id),
    asset_id            UUID NOT NULL REFERENCES core.assets(id),
    interval_seconds    INT NOT NULL,
    is_enabled          BOOLEAN NOT NULL DEFAULT true,
    config              JSONB NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plugin_id, asset_id)
);

-- Work envelopes — sealed tasks on Service Bus
-- Agents execute blind: no context, just run and return
CREATE TABLE collector.work_envelopes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id       UUID NOT NULL REFERENCES collector.collector_assignments(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    scheduled_for       TIMESTAMPTZ NOT NULL,
    status              TEXT NOT NULL DEFAULT 'pending',
    -- execution payload
    execution_type      TEXT NOT NULL,
    script_payload      TEXT NOT NULL,
    credential_ref      TEXT NOT NULL,      -- Key Vault URI only
    target_host         TEXT NOT NULL,
    target_port         INT,
    target_database     TEXT,
    timeout_seconds     INT NOT NULL DEFAULT 30,
    retry_count         INT NOT NULL DEFAULT 0,
    max_retries         INT NOT NULL DEFAULT 3,
    dead_letter_at      TIMESTAMPTZ,        -- set when max_retries exceeded
    -- result
    picked_up_at        TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    duration_ms         INT,
    result_status       TEXT,               -- 'success','failed','timeout','partial'
    result_payload      JSONB,
    error               TEXT,
    agent_id            TEXT
);

SELECT create_hypertable('collector.work_envelopes', 'created_at',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('collector.work_envelopes', INTERVAL '7 days');
SELECT add_compression_policy('collector.work_envelopes', INTERVAL '2 days');

CREATE INDEX idx_work_envelopes_pending
    ON collector.work_envelopes(status, scheduled_for)
    WHERE status = 'pending';
CREATE INDEX idx_work_envelopes_dead_letter
    ON collector.work_envelopes(dead_letter_at)
    WHERE dead_letter_at IS NOT NULL;

-- Collector heartbeats
CREATE TABLE collector.collector_heartbeats (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id       UUID NOT NULL REFERENCES collector.collector_assignments(id),
    agent_id            TEXT NOT NULL,
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_success_at     TIMESTAMPTZ,
    last_error          TEXT,
    consecutive_failures INT NOT NULL DEFAULT 0,
    status              TEXT NOT NULL DEFAULT 'ok'   -- ok, degraded, failed
);

CREATE INDEX idx_heartbeats_assignment
    ON collector.collector_heartbeats(assignment_id);
