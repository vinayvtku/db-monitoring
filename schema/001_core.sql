-- ============================================================
-- 001_core.sql
-- Foundation entities — assets, tiers, environments
-- Everything in the platform references this schema
-- ============================================================

CREATE SCHEMA IF NOT EXISTS core;

-- Environments
CREATE TABLE core.environments (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    description TEXT,
    tags        JSONB NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Asset tiers — drives alert routing and SLA
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
    ('tier2', 'Tier 2 — Standard',  300, false, 'Production non-critical. High severity only.'),
    ('tier3', 'Tier 3 — Non-Prod',  0,   false, 'Dev, staging, test. Digest only.');

-- Asset types
CREATE TABLE core.asset_types (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    category    TEXT NOT NULL,
    description TEXT
);

INSERT INTO core.asset_types (name, category, description) VALUES
    ('sql_server_instance', 'database', 'SQL Server instance'),
    ('sql_server_database', 'database', 'SQL Server database'),
    ('azure_vm',            'host',     'Azure Virtual Machine'),
    ('azure_container_app', 'service',  'Azure Container App');

-- Assets — everything is an asset
CREATE TABLE core.assets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_type_id   UUID NOT NULL REFERENCES core.asset_types(id),
    environment_id  UUID NOT NULL REFERENCES core.environments(id),
    tier_id         UUID NOT NULL REFERENCES core.asset_tiers(id),
    name            TEXT NOT NULL,
    fqdn            TEXT,
    region          TEXT,
    resource_group  TEXT,
    subscription_id TEXT,
    parent_id       UUID REFERENCES core.assets(id),
    tags            JSONB NOT NULL DEFAULT '{}',
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (asset_type_id, fqdn)
);

CREATE INDEX idx_assets_type        ON core.assets(asset_type_id);
CREATE INDEX idx_assets_environment ON core.assets(environment_id);
CREATE INDEX idx_assets_tier        ON core.assets(tier_id);
CREATE INDEX idx_assets_parent      ON core.assets(parent_id);
CREATE INDEX idx_assets_tags        ON core.assets USING gin(tags);
