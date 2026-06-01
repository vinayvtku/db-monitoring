-- ============================================================
-- 001_core.sql  (v2)
-- Foundation — environments, tiers, target types, targets
-- Technology agnostic. Works for SQL Server, Linux, Windows,
-- PostgreSQL, Azure VM, DB2, MySQL, REST APIs — anything.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS core;

-- ------------------------------------------------------------
-- Environments
-- ------------------------------------------------------------
CREATE TABLE core.environments (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    description TEXT,
    tags        JSONB NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO core.environments (name, description) VALUES
    ('production',  'Production environment'),
    ('staging',     'Staging environment'),
    ('development', 'Development environment');

-- ------------------------------------------------------------
-- Asset tiers — drives SLA, alert routing, PagerDuty
-- ------------------------------------------------------------
CREATE TABLE core.asset_tiers (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                        TEXT NOT NULL UNIQUE,
    display_name                TEXT NOT NULL,
    notification_sla_seconds    INT NOT NULL,
    pagerduty_enabled           BOOLEAN NOT NULL DEFAULT false,
    description                 TEXT
);

INSERT INTO core.asset_tiers
    (name, display_name, notification_sla_seconds, pagerduty_enabled, description)
VALUES
    ('tier1', 'Tier 1 — Critical',  60,  true,  'Production critical. Everything is priority.'),
    ('tier2', 'Tier 2 — Standard',  300, false, 'Production non-critical. High severity alerts only.'),
    ('tier3', 'Tier 3 — Non-Prod',  0,   false, 'Dev, staging, test. Digest only.');

-- ------------------------------------------------------------
-- Target types — every kind of thing the platform can monitor
-- Open ended — add new types without schema changes
-- ------------------------------------------------------------
CREATE TABLE core.target_types (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,
    category        TEXT NOT NULL,
    -- 'database'  — SQL Server, PostgreSQL, MySQL, DB2, Azure SQL
    -- 'host'      — Windows Server, Linux, Azure VM
    -- 'service'   — REST API, Azure Container App, Azure Function
    -- 'cloud'     — Azure subscription, resource group
    platform        TEXT NOT NULL,
    -- 'sqlserver','postgresql','mysql','db2','azuresql'
    -- 'windows','linux','azure','aws','gcp'
    -- 'rest','generic'
    description     TEXT,
    default_port    INT,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO core.target_types
    (name, category, platform, description, default_port)
VALUES
    -- Database targets
    ('sql_server_instance', 'database', 'sqlserver',  'SQL Server instance',              1433),
    ('sql_server_database', 'database', 'sqlserver',  'SQL Server database',              1433),
    ('postgresql_instance', 'database', 'postgresql', 'PostgreSQL instance',              5432),
    ('postgresql_database', 'database', 'postgresql', 'PostgreSQL database',              5432),
    ('mysql_instance',      'database', 'mysql',      'MySQL instance',                   3306),
    ('mysql_database',      'database', 'mysql',      'MySQL database',                   3306),
    ('db2_instance',        'database', 'db2',        'IBM DB2 instance',                 50000),
    ('db2_database',        'database', 'db2',        'IBM DB2 database',                 50000),
    ('azure_sql',           'database', 'azuresql',   'Azure SQL Database',               1433),
    ('azure_sql_mi',        'database', 'azuresql',   'Azure SQL Managed Instance',       1433),
    -- Host targets
    ('windows_server',      'host',     'windows',    'Windows Server host',              5985),
    ('linux_host',          'host',     'linux',      'Linux host',                       22),
    ('azure_vm',            'host',     'azure',      'Azure Virtual Machine',            NULL),
    -- Service targets
    ('azure_container_app', 'service',  'azure',      'Azure Container App',              443),
    ('rest_endpoint',       'service',  'rest',       'REST API endpoint',                443);

-- ------------------------------------------------------------
-- Targets — every monitored entity
-- Replaces + extends core.assets
-- connection_info stores target-specific connection details
-- as JSONB so any target type is supported without schema changes
-- ------------------------------------------------------------
CREATE TABLE core.targets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type_id  UUID NOT NULL REFERENCES core.target_types(id),
    environment_id  UUID NOT NULL REFERENCES core.environments(id),
    tier_id         UUID NOT NULL REFERENCES core.asset_tiers(id),

    -- Identity
    name            TEXT NOT NULL,
    fqdn            TEXT NOT NULL,          -- unique identifier for the target
    display_name    TEXT,                   -- friendly name shown in UI

    -- Connection
    host            TEXT,                   -- hostname or IP
    port            INT,                    -- overrides target_type default_port
    connection_info JSONB NOT NULL          -- target-type specific connection details
                    DEFAULT '{}',
    -- Examples:
    -- SQL Server:  {"instance_name": "MSSQLSERVER", "use_windows_auth": false}
    -- PostgreSQL:  {"ssl_mode": "require", "database": "postgres"}
    -- Linux:       {"use_sudo": true, "python_path": "/usr/bin/python3"}
    -- Windows:     {"use_ssl": true, "auth_mechanism": "kerberos"}
    -- REST:        {"base_url": "https://api.example.com", "timeout_seconds": 30}

    -- Hierarchy
    parent_id       UUID REFERENCES core.targets(id),
    -- e.g. sql_server_database → parent is sql_server_instance
    --      sql_server_instance → parent is windows_server

    -- Metadata
    tags            JSONB NOT NULL DEFAULT '{}',
    is_active       BOOLEAN NOT NULL DEFAULT true,
    is_monitored    BOOLEAN NOT NULL DEFAULT true,
    onboarded_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    onboarded_by    TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (target_type_id, fqdn)
);

CREATE INDEX idx_targets_type        ON core.targets(target_type_id);
CREATE INDEX idx_targets_environment ON core.targets(environment_id);
CREATE INDEX idx_targets_tier        ON core.targets(tier_id);
CREATE INDEX idx_targets_parent      ON core.targets(parent_id);
CREATE INDEX idx_targets_platform    ON core.targets(target_type_id);
CREATE INDEX idx_targets_tags        ON core.targets USING gin(tags);
CREATE INDEX idx_targets_active      ON core.targets(is_active, is_monitored);

-- ------------------------------------------------------------
-- Convenience view — targets with type and tier info joined
-- Used by the scheduler, onboarding scripts, and Grafana
-- ------------------------------------------------------------
CREATE VIEW core.targets_view AS
SELECT
    t.id,
    t.name,
    t.fqdn,
    t.display_name,
    t.host,
    t.port,
    t.connection_info,
    t.parent_id,
    t.tags,
    t.is_active,
    t.is_monitored,
    t.onboarded_at,
    t.onboarded_by,
    tt.name         AS target_type,
    tt.category     AS target_category,
    tt.platform     AS target_platform,
    tt.default_port AS default_port,
    e.name          AS environment,
    at.name         AS tier,
    at.notification_sla_seconds,
    at.pagerduty_enabled
FROM core.targets t
JOIN core.target_types  tt ON tt.id = t.target_type_id
JOIN core.environments  e  ON e.id  = t.environment_id
JOIN core.asset_tiers   at ON at.id = t.tier_id;
