-- ============================================================
-- 002_security.sql  (v2)
-- Credential types, profiles, target assignments
-- Supports any connection method — SQL, SSH, WinRM,
-- Managed Identity, API Key, Certificate, and more
-- No credentials stored here — ever
-- All secrets live in Azure Key Vault
-- Agents fetch at runtime using Managed Identity
-- ============================================================

CREATE SCHEMA IF NOT EXISTS security;

-- ------------------------------------------------------------
-- Credential types
-- Defines the shape of each authentication mechanism
-- secret_schema documents what the Key Vault secret contains
-- ------------------------------------------------------------
CREATE TABLE security.credential_types (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    auth_mechanism  TEXT NOT NULL,
    description     TEXT,
    secret_schema   JSONB NOT NULL DEFAULT '{}',
    -- Documents what fields the Key Vault secret JSON contains.
    -- Agents use this to know how to parse the secret.
    -- e.g. {"username": "string", "password": "string"}
    -- e.g. {"private_key_pem": "string", "username": "string"}
    -- e.g. {} for managed_identity (no secret needed)
    requires_keyvault BOOLEAN NOT NULL DEFAULT true,
    -- false for managed_identity — agent uses its own token
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO security.credential_types
    (name, display_name, auth_mechanism, description,
     secret_schema, requires_keyvault)
VALUES
    ('sql_login',
     'SQL Server Login',
     'sql_login',
     'SQL Server username and password authentication',
     '{"username": "string", "password": "string"}',
     true),

    ('windows_auth',
     'Windows Authentication',
     'windows_auth',
     'Windows domain credentials — used for WinRM and SQL Server Windows auth',
     '{"username": "string", "password": "string", "domain": "string"}',
     true),

    ('ssh_key',
     'SSH Private Key',
     'ssh_key',
     'SSH private key for Linux host access',
     '{"username": "string", "private_key_pem": "string", "passphrase": "string"}',
     true),

    ('ssh_password',
     'SSH Password',
     'ssh_password',
     'SSH username and password for Linux host access',
     '{"username": "string", "password": "string"}',
     true),

    ('managed_identity',
     'Azure Managed Identity',
     'managed_identity',
     'Azure Managed Identity — agent uses its own token, no secret needed',
     '{}',
     false),

    ('api_key',
     'API Key',
     'api_key',
     'REST API key passed as a request header',
     '{"api_key": "string", "header_name": "string"}',
     true),

    ('pg_login',
     'PostgreSQL Login',
     'pg_login',
     'PostgreSQL username and password',
     '{"username": "string", "password": "string", "ssl_mode": "string"}',
     true),

    ('mysql_login',
     'MySQL Login',
     'mysql_login',
     'MySQL username and password',
     '{"username": "string", "password": "string"}',
     true),

    ('db2_login',
     'DB2 Login',
     'db2_login',
     'IBM DB2 username and password',
     '{"username": "string", "password": "string"}',
     true),

    ('certificate',
     'X.509 Certificate',
     'certificate',
     'Certificate from Azure Key Vault certificates API',
     '{"certificate_name": "string"}',
     true),

    ('oauth_client',
     'OAuth 2.0 Client Credentials',
     'oauth_client',
     'OAuth 2.0 client credentials flow for REST APIs',
     '{"client_id": "string", "client_secret": "string", "token_url": "string", "scope": "string"}',
     true);

-- ------------------------------------------------------------
-- Credential profiles
-- Named profiles — one profile covers many targets
-- Actual secrets live in Key Vault, referenced by URI only
-- ------------------------------------------------------------
CREATE TABLE security.credential_profiles (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    TEXT NOT NULL UNIQUE,
    description             TEXT,
    credential_type_id      UUID NOT NULL
                            REFERENCES security.credential_types(id),
    keyvault_secret_uri     TEXT,
    -- NULL for managed_identity — no secret needed
    -- For certificates: Key Vault certificate URI
    -- For everything else: Key Vault secret URI pointing to JSON
    -- e.g. https://kv-monitor.vault.azure.net/secrets/prod-sql-monitor
    is_active               BOOLEAN NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed common profiles
-- (keyvault_secret_uri values are placeholders — update for your environment)
INSERT INTO security.credential_profiles
    (name, description, credential_type_id, keyvault_secret_uri)
VALUES
    ('prod-sql-monitor',
     'Production SQL Server monitoring login',
     (SELECT id FROM security.credential_types WHERE name = 'sql_login'),
     'https://kv-monitor.vault.azure.net/secrets/prod-sql-monitor'),

    ('prod-windows-monitor',
     'Production Windows Server WinRM credentials',
     (SELECT id FROM security.credential_types WHERE name = 'windows_auth'),
     'https://kv-monitor.vault.azure.net/secrets/prod-windows-monitor'),

    ('prod-linux-ssh-key',
     'Production Linux SSH private key',
     (SELECT id FROM security.credential_types WHERE name = 'ssh_key'),
     'https://kv-monitor.vault.azure.net/secrets/prod-linux-ssh-key'),

    ('azure-managed-identity',
     'Azure Managed Identity — no secret needed',
     (SELECT id FROM security.credential_types WHERE name = 'managed_identity'),
     NULL),

    ('prod-pg-monitor',
     'Production PostgreSQL monitoring login',
     (SELECT id FROM security.credential_types WHERE name = 'pg_login'),
     'https://kv-monitor.vault.azure.net/secrets/prod-pg-monitor'),

    ('dev-sql-monitor',
     'Development SQL Server monitoring login',
     (SELECT id FROM security.credential_types WHERE name = 'sql_login'),
     'https://kv-monitor.vault.azure.net/secrets/dev-sql-monitor');

-- ------------------------------------------------------------
-- Target credential assignments
-- One target can have multiple credentials for different purposes
-- e.g. a Windows host: one for WinRM, one for SQL Server on same box
-- ------------------------------------------------------------
CREATE TABLE security.target_credentials (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_id       UUID NOT NULL REFERENCES core.targets(id)
                    ON DELETE CASCADE,
    credential_id   UUID NOT NULL REFERENCES security.credential_profiles(id),
    purpose         TEXT NOT NULL DEFAULT 'default',
    -- 'default'  — general purpose
    -- 'sql'      — SQL Server connection on this host
    -- 'winrm'    — WinRM / PowerShell remoting
    -- 'ssh'      — SSH connection
    -- 'api'      — REST API calls
    -- 'readonly' — read-only access
    -- 'admin'    — administrative access (used sparingly)
    is_primary      BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (target_id, purpose)
    -- One credential per purpose per target
    -- Changing a credential: UPDATE, don't INSERT a duplicate
);

CREATE INDEX idx_target_credentials_target
    ON security.target_credentials(target_id);
CREATE INDEX idx_target_credentials_credential
    ON security.target_credentials(credential_id);

-- ------------------------------------------------------------
-- Credential fetch audit log
-- Every time an agent fetches a credential it is logged here
-- Retention: 30 days
-- ------------------------------------------------------------
CREATE TABLE security.credential_fetch_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    time            TIMESTAMPTZ NOT NULL DEFAULT now(),
    credential_id   UUID NOT NULL
                    REFERENCES security.credential_profiles(id),
    target_id       UUID REFERENCES core.targets(id),
    agent_id        TEXT NOT NULL,
    purpose         TEXT,
    success         BOOLEAN NOT NULL,
    error           TEXT
);

SELECT create_hypertable('security.credential_fetch_log', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('security.credential_fetch_log',
    INTERVAL '30 days');

CREATE INDEX idx_credential_fetch_log_credential
    ON security.credential_fetch_log(credential_id, time DESC);
