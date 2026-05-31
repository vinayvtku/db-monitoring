-- ============================================================
-- run_all.sql
-- Master script — runs all schema files in correct order
-- Usage: psql -U postgres -d your_database -f run_all.sql
-- ============================================================

\echo '=== DB Monitoring Platform — Schema Setup ==='
\echo ''

\echo '[000] Installing extensions...'
\i 000_extensions.sql

\echo '[001] Creating core schema...'
\i 001_core.sql

\echo '[002] Creating security schema...'
\i 002_security.sql

\echo '[003] Creating policy schema...'
\i 003_policy.sql

\echo '[004] Creating inventory schema...'
\i 004_inventory.sql

\echo '[005] Creating collector schema...'
\i 005_collector.sql

\echo '[006] Creating metrics schema...'
\i 006_metrics.sql

\echo '[007] Creating schema_intel schema...'
\i 007_schema_intel.sql

\echo '[008] Creating baselines schema...'
\i 008_baselines.sql

\echo '[009] Creating scoring schema...'
\i 009_scoring.sql

\echo '[010] Creating query_intel schema...'
\i 010_query_intel.sql

\echo '[011] Creating alerts schema...'
\i 011_alerts.sql

\echo '[012] Creating notifications schema...'
\i 012_notifications.sql

\echo '[013] Creating incidents schema...'
\i 013_incidents.sql

\echo '[014] Creating maintenance schema...'
\i 014_maintenance.sql

\echo '[015] Creating ai schema...'
\i 015_ai.sql

\echo '[016] Creating forecasts schema...'
\i 016_forecasts.sql

\echo '[017] Creating audit schema...'
\i 017_audit.sql

\echo '[018] Creating migrations schema...'
\i 018_migrations.sql

\echo ''
\echo '=== Schema setup complete ==='
\echo ''
\echo 'To load demo data run:'
\echo '  psql -U postgres -d your_database -f 099_dummy_data.sql'
\echo ''
\echo 'To reset everything run:'
\echo '  psql -U postgres -d your_database -f 100_reset.sql'
