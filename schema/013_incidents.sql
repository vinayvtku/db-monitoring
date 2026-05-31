-- ============================================================
-- 013_incidents.sql
-- ============================================================

CREATE SCHEMA IF NOT EXISTS incidents;

CREATE TABLE incidents.incidents (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title       TEXT NOT NULL,
    summary     TEXT,
    severity    TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'open',
    asset_id    UUID REFERENCES core.assets(id),
    opened_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ,
    resolved_by TEXT,
    ai_summary  TEXT,
    ai_priority INT,
    embedding   vector(1536)
);
CREATE INDEX idx_incidents_asset     ON incidents.incidents(asset_id);
CREATE INDEX idx_incidents_open      ON incidents.incidents(status) WHERE status = 'open';
CREATE INDEX idx_incidents_embedding
    ON incidents.incidents USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

CREATE TABLE incidents.incident_alerts (
    incident_id UUID NOT NULL REFERENCES incidents.incidents(id),
    alert_id    UUID NOT NULL REFERENCES alerts.alert_instances(id),
    linked_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (incident_id, alert_id)
);

CREATE TABLE incidents.incident_timeline (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incident_id UUID NOT NULL REFERENCES incidents.incidents(id),
    time        TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_type  TEXT NOT NULL,
    detail      TEXT,
    author      TEXT
);
CREATE INDEX idx_timeline_incident ON incidents.incident_timeline(incident_id, time);
