-- ============================================================
-- 018_migrations.sql
-- Schema version tracking
-- Run this last — records that the full schema was applied
-- ============================================================

CREATE SCHEMA IF NOT EXISTS migrations;

CREATE TABLE migrations.schema_migrations (
    id          SERIAL PRIMARY KEY,
    version     TEXT NOT NULL UNIQUE,
    name        TEXT NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    duration_ms INT,
    checksum    TEXT NOT NULL,
    applied_by  TEXT NOT NULL DEFAULT current_user
);

INSERT INTO migrations.schema_migrations (version, name, checksum)
VALUES
    ('000', 'extensions',     'sha256_000'),
    ('001', 'core',           'sha256_001'),
    ('002', 'security',       'sha256_002'),
    ('003', 'policy',         'sha256_003'),
    ('004', 'inventory',      'sha256_004'),
    ('005', 'collector',      'sha256_005'),
    ('006', 'metrics',        'sha256_006'),
    ('007', 'schema_intel',   'sha256_007'),
    ('008', 'baselines',      'sha256_008'),
    ('009', 'scoring',        'sha256_009'),
    ('010', 'query_intel',    'sha256_010'),
    ('011', 'alerts',         'sha256_011'),
    ('012', 'notifications',  'sha256_012'),
    ('013', 'incidents',      'sha256_013'),
    ('014', 'maintenance',    'sha256_014'),
    ('015', 'ai',             'sha256_015'),
    ('016', 'forecasts',      'sha256_016'),
    ('017', 'audit',          'sha256_017'),
    ('018', 'migrations',     'sha256_018');
