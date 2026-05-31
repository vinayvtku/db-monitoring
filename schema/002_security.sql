-- ============================================================
-- 002_security.sql
-- Credential profiles and Key Vault references
-- No passwords stored here — ever
-- Agents resolve credentials at runtime via Managed Identity
-- ============================================================

CREATE SCHEMA IF NOT EXISTS security;

-- Credential profiles — one profile covers many assets
CREATE TABLE security.credential_profiles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                TEXT NOT NULL UNIQUE,
    description         TEXT,
    auth_type           TEXT NOT NULL,  -- 'managed_identity','sql_login','windows'
    keyvault_secret_uri TEXT,           -- Key Vault URI only, never the secret value
    is_active           BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Asset to credential profile mapping
CREATE TABLE security.asset_credentials (
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    credential_id   UUID NOT NULL REFERENCES security.credential_profiles(id),
    is_primary      BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (asset_id, credential_id)
);

-- Credential fetch audit log
CREATE TABLE security.credential_fetch_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    time            TIMESTAMPTZ NOT NULL DEFAULT now(),
    credential_id   UUID NOT NULL REFERENCES security.credential_profiles(id),
    agent_id        TEXT NOT NULL,
    success         BOOLEAN NOT NULL,
    error           TEXT
);

SELECT create_hypertable('security.credential_fetch_log', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('security.credential_fetch_log',
    INTERVAL '30 days');
