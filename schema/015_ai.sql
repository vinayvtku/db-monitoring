-- ============================================================
-- 015_ai.sql
-- Usage policies, tracking, query log, digest log
-- Cost control built in from day one
-- Daily digest exempt from per-user limits
-- ============================================================

CREATE SCHEMA IF NOT EXISTS ai;

CREATE TABLE ai.usage_policies (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    TEXT NOT NULL UNIQUE,
    trigger_type            TEXT,
    scope_type              TEXT NOT NULL DEFAULT 'global',
    scope_id                UUID,
    monthly_token_budget    INT,
    daily_request_limit     INT,
    max_tokens_per_request  INT NOT NULL DEFAULT 1000,
    preferred_model         TEXT NOT NULL DEFAULT 'gpt-4o-mini',
    fallback_model          TEXT,
    on_limit_action         TEXT NOT NULL DEFAULT 'warn',
    exempt_from_user_limits BOOLEAN NOT NULL DEFAULT false,
    is_active               BOOLEAN NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO ai.usage_policies
    (name, trigger_type, monthly_token_budget, daily_request_limit,
     max_tokens_per_request, on_limit_action, exempt_from_user_limits)
VALUES
    ('Global Monthly Budget',  NULL,               1000000, NULL, 2000, 'warn',  false),
    ('User Query Limit',       'user_query',        100000,  50,   1000, 'warn',  false),
    ('Daily Digest',           'digest',            NULL,    1,    2000, 'block', true),
    ('Incident Summary',       'incident_summary',  NULL,    100,  1000, 'warn',  false);

CREATE TABLE ai.usage_tracking (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    time            TIMESTAMPTZ NOT NULL DEFAULT now(),
    policy_id       UUID NOT NULL REFERENCES ai.usage_policies(id),
    user_id         TEXT,
    period_start    TIMESTAMPTZ NOT NULL,
    period_type     TEXT NOT NULL,
    tokens_used     INT NOT NULL DEFAULT 0,
    requests_made   INT NOT NULL DEFAULT 0,
    last_updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SELECT create_hypertable('ai.usage_tracking', 'time',
    chunk_time_interval => INTERVAL '1 month');
SELECT add_retention_policy('ai.usage_tracking', INTERVAL '365 days');

CREATE TABLE ai.usage_alerts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fired_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    policy_id       UUID NOT NULL REFERENCES ai.usage_policies(id),
    alert_type      TEXT NOT NULL,
    tokens_used     INT,
    token_budget    INT,
    is_acknowledged BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE ai.context_snapshots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    trigger_type    TEXT NOT NULL,
    asset_ids       UUID[],
    token_count     INT,
    context_json    JSONB NOT NULL
);
SELECT create_hypertable('ai.context_snapshots', 'created_at',
    chunk_time_interval => INTERVAL '1 month');
SELECT add_retention_policy('ai.context_snapshots', INTERVAL '90 days');

CREATE TABLE ai.query_log (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    time                TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_id             TEXT,
    query_text          TEXT NOT NULL,
    response_text       TEXT NOT NULL,
    context_id          UUID REFERENCES ai.context_snapshots(id),
    model               TEXT,
    prompt_tokens       INT,
    completion_tokens   INT,
    total_tokens        INT,
    duration_ms         INT,
    embedding           vector(1536)
);
SELECT create_hypertable('ai.query_log', 'time',
    chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('ai.query_log', INTERVAL '90 days');
CREATE INDEX idx_query_log_embedding
    ON ai.query_log USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

CREATE TABLE ai.digest_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    time        TIMESTAMPTZ NOT NULL DEFAULT now(),
    digest_date DATE NOT NULL UNIQUE,
    subject     TEXT NOT NULL,
    body_html   TEXT NOT NULL,
    sent_to     TEXT[],
    sent_at     TIMESTAMPTZ,
    send_status TEXT NOT NULL DEFAULT 'pending',
    context_id  UUID REFERENCES ai.context_snapshots(id),
    total_tokens INT,
    error       TEXT
);
SELECT create_hypertable('ai.digest_log', 'time',
    chunk_time_interval => INTERVAL '1 month');
SELECT add_retention_policy('ai.digest_log', INTERVAL '365 days');
