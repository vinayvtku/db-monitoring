-- ============================================================
-- 012_notifications.sql
-- Channels, routing matrix, escalations, subscriptions,
-- suppression windows, notification log
-- Alert routing by asset tier + severity + category
-- ============================================================

CREATE SCHEMA IF NOT EXISTS notifications;

-- Channels — credentials stored in Key Vault only
CREATE TABLE notifications.channels (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,
    channel_type    TEXT NOT NULL,  -- 'pagerduty','teams','email','sms'
    config_ref      TEXT NOT NULL,  -- Key Vault URI for webhook/credentials
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO notifications.channels (name, channel_type, config_ref) VALUES
    ('PagerDuty On-Call',   'pagerduty', 'kv://monitoring/pagerduty-integration-key'),
    ('Teams Ops Channel',   'teams',     'kv://monitoring/teams-webhook-ops'),
    ('DBA Email Group',     'email',     'kv://monitoring/smtp-dba-group'),
    ('VP Daily Digest',     'email',     'kv://monitoring/smtp-vp-digest');

-- Routing matrix — asset tier + severity + category → channel
CREATE TABLE notifications.routing_rules (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tier_id         UUID REFERENCES core.asset_tiers(id),   -- NULL = all tiers
    severity        TEXT,                                    -- NULL = all severities
    alert_category  TEXT,                                    -- NULL = all categories
    channel_id      UUID NOT NULL REFERENCES notifications.channels(id),
    priority        INT NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT true
);

-- Seed routing matrix
-- Tier 1 critical (server down, disk full, backup fail, security) → PagerDuty
-- Tier 1 warning (CPU, plan regression) → Teams + Email
-- Tier 2 critical → Email only
-- Tier 2 warning → Email only
-- Tier 3 → nothing (digest only)
WITH
    t1 AS (SELECT id FROM core.asset_tiers WHERE name = 'tier1'),
    t2 AS (SELECT id FROM core.asset_tiers WHERE name = 'tier2'),
    pd AS (SELECT id FROM notifications.channels WHERE name = 'PagerDuty On-Call'),
    tm AS (SELECT id FROM notifications.channels WHERE name = 'Teams Ops Channel'),
    em AS (SELECT id FROM notifications.channels WHERE name = 'DBA Email Group')
INSERT INTO notifications.routing_rules (tier_id, severity, alert_category, channel_id, priority)
VALUES
    ((SELECT id FROM t1), 'critical', 'availability',   (SELECT id FROM pd), 100),
    ((SELECT id FROM t1), 'critical', 'capacity',       (SELECT id FROM pd), 100),
    ((SELECT id FROM t1), 'critical', 'security',       (SELECT id FROM pd), 100),
    ((SELECT id FROM t1), 'warning',  'performance',    (SELECT id FROM tm), 80),
    ((SELECT id FROM t1), 'warning',  'performance',    (SELECT id FROM em), 70),
    ((SELECT id FROM t1), 'warning',  'capacity',       (SELECT id FROM em), 70),
    ((SELECT id FROM t2), 'critical', NULL,             (SELECT id FROM em), 60),
    ((SELECT id FROM t2), 'warning',  NULL,             (SELECT id FROM em), 50);

-- Escalation rules
CREATE TABLE notifications.escalation_rules (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tier_id         UUID NOT NULL REFERENCES core.asset_tiers(id),
    severity        TEXT NOT NULL,
    escalation_step INT NOT NULL,
    delay_minutes   INT NOT NULL,
    channel_id      UUID NOT NULL REFERENCES notifications.channels(id),
    notify_user     TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT true
);

WITH
    t1 AS (SELECT id FROM core.asset_tiers WHERE name = 'tier1'),
    pd AS (SELECT id FROM notifications.channels WHERE name = 'PagerDuty On-Call'),
    em AS (SELECT id FROM notifications.channels WHERE name = 'DBA Email Group')
INSERT INTO notifications.escalation_rules
    (tier_id, severity, escalation_step, delay_minutes, channel_id, notify_user)
VALUES
    ((SELECT id FROM t1), 'critical', 1, 5,  (SELECT id FROM pd), 'dba-oncall'),
    ((SELECT id FROM t1), 'critical', 2, 15, (SELECT id FROM em), 'dba-manager'),
    ((SELECT id FROM t1), 'warning',  1, 30, (SELECT id FROM em), 'dba-oncall');

-- Subscriptions
CREATE TABLE notifications.subscriptions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         TEXT NOT NULL,
    scope_type      TEXT NOT NULL,
    scope_id        UUID,
    severity_filter TEXT[],
    category_filter TEXT[],
    channel_id      UUID NOT NULL REFERENCES notifications.channels(id),
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Suppression windows
CREATE TABLE notifications.suppression_windows (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id            UUID REFERENCES core.assets(id),
    name                TEXT NOT NULL,
    starts_at           TIMESTAMPTZ NOT NULL,
    ends_at             TIMESTAMPTZ NOT NULL,
    recurrence          TEXT,
    recurrence_day      SMALLINT,
    suppress_categories TEXT[],
    created_by          TEXT NOT NULL,
    is_active           BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX idx_suppression_active
    ON notifications.suppression_windows(starts_at, ends_at)
    WHERE is_active = true;

-- Notification log
CREATE TABLE notifications.notification_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    time        TIMESTAMPTZ NOT NULL DEFAULT now(),
    alert_id    UUID REFERENCES alerts.alert_instances(id),
    channel_id  UUID NOT NULL REFERENCES notifications.channels(id),
    sent_to     TEXT,
    status      TEXT NOT NULL,
    error       TEXT,
    duration_ms INT
);
SELECT create_hypertable('notifications.notification_log', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('notifications.notification_log', INTERVAL '90 days');
