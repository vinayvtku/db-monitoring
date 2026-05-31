-- ============================================================
-- 007_schema_intel.sql
-- Full schema capture, object-level deltas, embeddings
-- ============================================================

CREATE SCHEMA IF NOT EXISTS schema_intel;

CREATE TABLE schema_intel.snapshots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    snapshot_type   TEXT NOT NULL DEFAULT 'full',
    captured_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    object_count    INT,
    index_count     INT,
    proc_count      INT,
    snapshot_hash   TEXT NOT NULL
);
CREATE INDEX idx_snapshots_asset ON schema_intel.snapshots(asset_id, captured_at DESC);

CREATE TABLE schema_intel.schema_objects (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_id         UUID NOT NULL REFERENCES schema_intel.snapshots(id),
    asset_id            UUID NOT NULL REFERENCES core.assets(id),
    object_type         TEXT NOT NULL,
    schema_name         TEXT NOT NULL,
    object_name         TEXT NOT NULL,
    definition          TEXT,
    object_hash         TEXT NOT NULL,
    row_count           BIGINT,
    size_mb             NUMERIC(12,2),
    created_at_source   TIMESTAMPTZ,
    modified_at_source  TIMESTAMPTZ,
    captured_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_current          BOOLEAN NOT NULL DEFAULT true,
    raw                 JSONB
);
CREATE INDEX idx_schema_objects_asset   ON schema_intel.schema_objects(asset_id, is_current);
CREATE INDEX idx_schema_objects_type    ON schema_intel.schema_objects(asset_id, object_type);

CREATE TABLE schema_intel.schema_columns (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    object_id       UUID NOT NULL REFERENCES schema_intel.schema_objects(id),
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    column_name     TEXT NOT NULL,
    column_order    INT NOT NULL,
    data_type       TEXT NOT NULL,
    max_length      INT,
    precision       INT,
    scale           INT,
    is_nullable     BOOLEAN,
    is_identity     BOOLEAN,
    is_computed     BOOLEAN,
    default_value   TEXT,
    captured_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_schema_columns_object ON schema_intel.schema_columns(object_id);

CREATE TABLE schema_intel.schema_indexes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    object_id           UUID NOT NULL REFERENCES schema_intel.schema_objects(id),
    asset_id            UUID NOT NULL REFERENCES core.assets(id),
    index_name          TEXT NOT NULL,
    index_type          TEXT NOT NULL,
    is_unique           BOOLEAN,
    is_primary_key      BOOLEAN,
    key_columns         TEXT[],
    included_columns    TEXT[],
    fill_factor         INT,
    is_disabled         BOOLEAN,
    captured_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- pgvector embeddings on schema objects for AI semantic search
-- Refresh triggered when object_hash changes on delta snapshot
CREATE TABLE schema_intel.schema_embeddings (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    object_id       UUID NOT NULL REFERENCES schema_intel.schema_objects(id),
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    embedding_text  TEXT NOT NULL,
    embedding       vector(1536) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_current      BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX idx_schema_embeddings_vector
    ON schema_intel.schema_embeddings USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);
CREATE INDEX idx_schema_embeddings_current
    ON schema_intel.schema_embeddings(asset_id, is_current);
