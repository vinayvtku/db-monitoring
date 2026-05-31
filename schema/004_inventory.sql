-- ============================================================
-- 004_inventory.sql
-- SQL Server instances, databases, files, principals,
-- and application-to-database connection mapping
-- ============================================================

CREATE SCHEMA IF NOT EXISTS inventory;

CREATE TABLE inventory.sql_instances (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id                    UUID NOT NULL UNIQUE REFERENCES core.assets(id),
    host                        TEXT NOT NULL,
    port                        INT NOT NULL DEFAULT 1433,
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
    collected_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    raw                         JSONB
);

CREATE TABLE inventory.sql_databases (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id            UUID NOT NULL UNIQUE REFERENCES core.assets(id),
    instance_id         UUID NOT NULL REFERENCES inventory.sql_instances(id),
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
    collected_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    raw                 JSONB
);

CREATE TABLE inventory.sql_database_files (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    database_id     UUID NOT NULL REFERENCES inventory.sql_databases(id),
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

CREATE TABLE inventory.sql_principals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    principal_name  TEXT NOT NULL,
    principal_type  TEXT NOT NULL,
    auth_type       TEXT,
    is_disabled     BOOLEAN,
    is_sysadmin     BOOLEAN,
    default_db      TEXT,
    collected_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    raw             JSONB
);

CREATE INDEX idx_principals_asset ON inventory.sql_principals(asset_id);

-- Application to database connection mapping
-- Sourced from sys.dm_exec_sessions + sys.dm_exec_connections
CREATE TABLE inventory.app_connections (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    database_asset_id   UUID NOT NULL REFERENCES core.assets(id),
    app_name            TEXT NOT NULL,
    client_ip           TEXT,
    login_name          TEXT,
    host_name           TEXT,
    connection_count    INT,
    first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_active           BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (database_asset_id, app_name, client_ip, login_name)
);

CREATE INDEX idx_app_connections_db ON inventory.app_connections(database_asset_id);
