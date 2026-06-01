-- ============================================================
-- 003_inventory.sql  (v2)
-- Flexible inventory — works for any target type
-- target_metadata stores discovered properties as JSONB
-- Technology-specific detail tables for SQL Server (and future)
-- app_connections tracks application-to-database mapping
-- ============================================================

CREATE SCHEMA IF NOT EXISTS inventory;

-- ------------------------------------------------------------
-- Target metadata
-- Stores discovered properties for any target type
-- One row per target per collection run
-- is_current = true means this is the latest snapshot
--
-- Examples of what metadata contains per target type:
--
-- sql_server_instance:
--   {"edition": "Developer", "version": "16.0.1000",
--    "collation": "SQL_Latin1_General_CP1_CI_AS",
--    "max_dop": 4, "max_server_memory_mb": 32768,
--    "is_clustered": false, "is_hadr_enabled": false}
--
-- windows_server:
--   {"os_version": "Windows Server 2022",
--    "os_build": "20348.2340", "cpu_count": 8,
--    "ram_mb": 65536, "domain": "corp.internal",
--    "last_boot_time": "2024-01-15T02:00:00Z"}
--
-- linux_host:
--   {"distro": "Ubuntu", "distro_version": "22.04",
--    "kernel": "5.15.0-91-generic",
--    "cpu_count": 8, "ram_mb": 32768,
--    "hostname": "prod-db-01"}
--
-- postgresql_instance:
--   {"version": "16.1", "max_connections": 200,
--    "shared_buffers_mb": 4096,
--    "extensions": ["pgvector", "timescaledb"]}
--
-- azure_vm:
--   {"vm_size": "Standard_D8s_v3", "region": "eastus",
--    "resource_group": "rg-prod",
--    "os_disk_size_gb": 128, "availability_zone": "1"}
-- ------------------------------------------------------------
CREATE TABLE inventory.target_metadata (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_id       UUID NOT NULL REFERENCES core.targets(id)
                    ON DELETE CASCADE,
    collected_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    collector       TEXT NOT NULL,
    -- name of the script that collected this
    -- e.g. 'sql_server_discovery', 'windows_host_discovery'
    metadata        JSONB NOT NULL DEFAULT '{}',
    metadata_hash   TEXT NOT NULL,
    -- SHA256 of metadata — used to detect changes
    is_current      BOOLEAN NOT NULL DEFAULT true,
    -- only one current snapshot per target
    collection_duration_ms INT
);

CREATE INDEX idx_target_metadata_target
    ON inventory.target_metadata(target_id, is_current);
CREATE INDEX idx_target_metadata_collected
    ON inventory.target_metadata(target_id, collected_at DESC);
CREATE INDEX idx_target_metadata_json
    ON inventory.target_metadata USING gin(metadata);

-- Trigger: when a new metadata row is inserted for a target,
-- mark the previous one as not current
CREATE OR REPLACE FUNCTION inventory.set_metadata_current()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE inventory.target_metadata
    SET is_current = false
    WHERE target_id = NEW.target_id
      AND id != NEW.id
      AND is_current = true;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_target_metadata_current
    AFTER INSERT ON inventory.target_metadata
    FOR EACH ROW EXECUTE FUNCTION inventory.set_metadata_current();

-- ------------------------------------------------------------
-- SQL Server instance detail
-- Structured detail table for SQL Server — supplements
-- target_metadata with typed columns for query performance
-- Add equivalent tables for PostgreSQL, MySQL etc as needed
-- ------------------------------------------------------------
CREATE TABLE inventory.sql_instances (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_id                   UUID NOT NULL UNIQUE
                                REFERENCES core.targets(id) ON DELETE CASCADE,
    host                        TEXT NOT NULL,
    port                        INT NOT NULL DEFAULT 1433,
    instance_name               TEXT,
    edition                     TEXT,
    version                     TEXT,
    version_build               TEXT,
    patch_level                 TEXT,
    collation                   TEXT,
    is_clustered                BOOLEAN,
    is_hadr_enabled             BOOLEAN,
    max_dop                     INT,
    max_server_memory_mb        BIGINT,
    cost_threshold_parallelism  INT,
    collected_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- SQL Server database detail
-- ------------------------------------------------------------
CREATE TABLE inventory.sql_databases (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_id           UUID NOT NULL UNIQUE
                        REFERENCES core.targets(id) ON DELETE CASCADE,
    instance_id         UUID NOT NULL
                        REFERENCES inventory.sql_instances(id),
    name                TEXT NOT NULL,
    state               TEXT,
    recovery_model      TEXT,
    compatibility_level INT,
    collation           TEXT,
    is_read_only        BOOLEAN,
    is_auto_close       BOOLEAN,
    is_auto_shrink      BOOLEAN,
    size_mb             BIGINT,
    log_size_mb         BIGINT,
    owner               TEXT,
    created_at_source   TIMESTAMPTZ,
    collected_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- SQL Server database files
-- ------------------------------------------------------------
CREATE TABLE inventory.sql_database_files (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    database_id     UUID NOT NULL
                    REFERENCES inventory.sql_databases(id) ON DELETE CASCADE,
    file_id         INT NOT NULL,
    type            TEXT NOT NULL,
    logical_name    TEXT NOT NULL,
    physical_path   TEXT NOT NULL,
    size_mb         BIGINT,
    max_size_mb     BIGINT,
    growth          TEXT,
    is_autogrowth   BOOLEAN,
    collected_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- SQL Server security principals
-- ------------------------------------------------------------
CREATE TABLE inventory.sql_principals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_id       UUID NOT NULL REFERENCES core.targets(id)
                    ON DELETE CASCADE,
    principal_name  TEXT NOT NULL,
    principal_type  TEXT NOT NULL,
    auth_type       TEXT,
    is_disabled     BOOLEAN,
    is_sysadmin     BOOLEAN,
    default_db      TEXT,
    collected_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sql_principals_target
    ON inventory.sql_principals(target_id);

-- ------------------------------------------------------------
-- Application to database connection mapping
-- Collected from sys.dm_exec_sessions + sys.dm_exec_connections
-- Works for SQL Server today — extend for PostgreSQL pg_stat_activity
-- ------------------------------------------------------------
CREATE TABLE inventory.app_connections (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_id           UUID NOT NULL REFERENCES core.targets(id)
                        ON DELETE CASCADE,
    -- target is the database being connected to
    app_name            TEXT NOT NULL,
    client_ip           TEXT,
    login_name          TEXT,
    host_name           TEXT,
    connection_count    INT,
    first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_active           BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (target_id, app_name, client_ip, login_name)
);

CREATE INDEX idx_app_connections_target
    ON inventory.app_connections(target_id);
