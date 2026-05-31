-- ============================================================
-- 000_extensions.sql
-- Required PostgreSQL extensions
-- Run this first before any other schema file
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "timescaledb" CASCADE;
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
