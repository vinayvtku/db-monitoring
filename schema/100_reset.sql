-- ============================================================
-- 100_reset.sql
-- Drops and recreates everything cleanly
-- USE WITH CAUTION — destroys all data
-- Safe to run repeatedly during development
-- ============================================================

-- Drop schemas in reverse dependency order
DROP SCHEMA IF EXISTS migrations    CASCADE;
DROP SCHEMA IF EXISTS audit         CASCADE;
DROP SCHEMA IF EXISTS forecasts     CASCADE;
DROP SCHEMA IF EXISTS ai            CASCADE;
DROP SCHEMA IF EXISTS maintenance   CASCADE;
DROP SCHEMA IF EXISTS incidents     CASCADE;
DROP SCHEMA IF EXISTS notifications CASCADE;
DROP SCHEMA IF EXISTS alerts        CASCADE;
DROP SCHEMA IF EXISTS query_intel   CASCADE;
DROP SCHEMA IF EXISTS scoring       CASCADE;
DROP SCHEMA IF EXISTS baselines     CASCADE;
DROP SCHEMA IF EXISTS schema_intel  CASCADE;
DROP SCHEMA IF EXISTS metrics       CASCADE;
DROP SCHEMA IF EXISTS collector     CASCADE;
DROP SCHEMA IF EXISTS inventory     CASCADE;
DROP SCHEMA IF EXISTS policy        CASCADE;
DROP SCHEMA IF EXISTS security      CASCADE;
DROP SCHEMA IF EXISTS core          CASCADE;

-- Extensions stay — they are database-level
-- Re-run 000_extensions.sql if needed

\echo 'Reset complete. Run run_all.sql to rebuild.'
