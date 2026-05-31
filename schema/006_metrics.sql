-- ============================================================
-- 006_metrics.sql
-- All time-series metric hypertables with rollup ladder
-- Raw 24h → 5min 7d → 15min 30d → 1hr 1yr
-- TimescaleDB open core only (Apache 2.0)
-- ============================================================

CREATE SCHEMA IF NOT EXISTS metrics;

-- -------------------------------------------------------
-- CPU (instance level)
-- -------------------------------------------------------
CREATE TABLE metrics.cpu (
    time            TIMESTAMPTZ NOT NULL,
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    sql_cpu_pct     SMALLINT,
    other_cpu_pct   SMALLINT,
    idle_cpu_pct    SMALLINT
);
SELECT create_hypertable('metrics.cpu', 'time', chunk_time_interval => INTERVAL '1 hour');
SELECT add_retention_policy('metrics.cpu', INTERVAL '24 hours');
SELECT add_compression_policy('metrics.cpu', INTERVAL '2 hours');

CREATE MATERIALIZED VIEW metrics.cpu_5m WITH (timescaledb.continuous) AS
SELECT time_bucket('5 minutes', time) AS bucket, asset_id,
    AVG(sql_cpu_pct)::SMALLINT  AS sql_cpu_pct_avg,
    MAX(sql_cpu_pct)::SMALLINT  AS sql_cpu_pct_max,
    AVG(idle_cpu_pct)::SMALLINT AS idle_cpu_pct_avg,
    COUNT(*) AS sample_count
FROM metrics.cpu GROUP BY bucket, asset_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.cpu_5m',
    start_offset => INTERVAL '10 minutes', end_offset => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 minute');
SELECT add_retention_policy('metrics.cpu_5m', INTERVAL '7 days');

CREATE MATERIALIZED VIEW metrics.cpu_15m WITH (timescaledb.continuous) AS
SELECT time_bucket('15 minutes', bucket) AS bucket, asset_id,
    AVG(sql_cpu_pct_avg)::SMALLINT AS sql_cpu_pct_avg,
    MAX(sql_cpu_pct_max)::SMALLINT AS sql_cpu_pct_max,
    SUM(sample_count) AS sample_count
FROM metrics.cpu_5m GROUP BY time_bucket('15 minutes', bucket), asset_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.cpu_15m',
    start_offset => INTERVAL '30 minutes', end_offset => INTERVAL '5 minutes',
    schedule_interval => INTERVAL '5 minutes');
SELECT add_retention_policy('metrics.cpu_15m', INTERVAL '30 days');

CREATE MATERIALIZED VIEW metrics.cpu_1h WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', bucket) AS bucket, asset_id,
    AVG(sql_cpu_pct_avg)::SMALLINT AS sql_cpu_pct_avg,
    MAX(sql_cpu_pct_max)::SMALLINT AS sql_cpu_pct_max,
    SUM(sample_count) AS sample_count
FROM metrics.cpu_15m GROUP BY time_bucket('1 hour', bucket), asset_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.cpu_1h',
    start_offset => INTERVAL '2 hours', end_offset => INTERVAL '15 minutes',
    schedule_interval => INTERVAL '15 minutes');
SELECT add_retention_policy('metrics.cpu_1h', INTERVAL '365 days');

-- -------------------------------------------------------
-- Wait stats (instance level)
-- -------------------------------------------------------
CREATE TABLE metrics.wait_stats (
    time                TIMESTAMPTZ NOT NULL,
    asset_id            UUID NOT NULL REFERENCES core.assets(id),
    wait_type           TEXT NOT NULL,
    wait_time_ms        BIGINT NOT NULL,
    signal_wait_time_ms BIGINT NOT NULL,
    waiting_tasks       INT NOT NULL
);
SELECT create_hypertable('metrics.wait_stats', 'time', chunk_time_interval => INTERVAL '1 hour');
SELECT add_retention_policy('metrics.wait_stats', INTERVAL '24 hours');
SELECT add_compression_policy('metrics.wait_stats', INTERVAL '2 hours');

CREATE MATERIALIZED VIEW metrics.wait_stats_5m WITH (timescaledb.continuous) AS
SELECT time_bucket('5 minutes', time) AS bucket, asset_id, wait_type,
    SUM(wait_time_ms) AS wait_time_ms_total,
    SUM(signal_wait_time_ms) AS signal_wait_time_ms_total,
    SUM(waiting_tasks) AS waiting_tasks_total,
    COUNT(*) AS sample_count
FROM metrics.wait_stats GROUP BY bucket, asset_id, wait_type WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.wait_stats_5m',
    start_offset => INTERVAL '10 minutes', end_offset => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 minute');
SELECT add_retention_policy('metrics.wait_stats_5m', INTERVAL '7 days');

CREATE MATERIALIZED VIEW metrics.wait_stats_1h WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', bucket) AS bucket, asset_id, wait_type,
    SUM(wait_time_ms_total) AS wait_time_ms_total,
    SUM(waiting_tasks_total) AS waiting_tasks_total
FROM metrics.wait_stats_5m
GROUP BY time_bucket('1 hour', bucket), asset_id, wait_type WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.wait_stats_1h',
    start_offset => INTERVAL '2 hours', end_offset => INTERVAL '15 minutes',
    schedule_interval => INTERVAL '15 minutes');
SELECT add_retention_policy('metrics.wait_stats_1h', INTERVAL '365 days');

-- -------------------------------------------------------
-- Memory (instance level)
-- -------------------------------------------------------
CREATE TABLE metrics.memory (
    time                    TIMESTAMPTZ NOT NULL,
    asset_id                UUID NOT NULL REFERENCES core.assets(id),
    total_server_memory_mb  BIGINT,
    target_server_memory_mb BIGINT,
    sql_cache_memory_mb     BIGINT,
    stolen_server_memory_mb BIGINT,
    page_fault_count        BIGINT
);
SELECT create_hypertable('metrics.memory', 'time', chunk_time_interval => INTERVAL '1 hour');
SELECT add_retention_policy('metrics.memory', INTERVAL '24 hours');
SELECT add_compression_policy('metrics.memory', INTERVAL '2 hours');

CREATE MATERIALIZED VIEW metrics.memory_5m WITH (timescaledb.continuous) AS
SELECT time_bucket('5 minutes', time) AS bucket, asset_id,
    AVG(total_server_memory_mb)::BIGINT  AS total_server_memory_mb_avg,
    AVG(target_server_memory_mb)::BIGINT AS target_server_memory_mb_avg,
    MAX(stolen_server_memory_mb)::BIGINT AS stolen_server_memory_mb_max,
    COUNT(*) AS sample_count
FROM metrics.memory GROUP BY bucket, asset_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.memory_5m',
    start_offset => INTERVAL '10 minutes', end_offset => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 minute');
SELECT add_retention_policy('metrics.memory_5m', INTERVAL '7 days');

CREATE MATERIALIZED VIEW metrics.memory_1h WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', bucket) AS bucket, asset_id,
    AVG(total_server_memory_mb_avg)::BIGINT  AS total_server_memory_mb_avg,
    MAX(stolen_server_memory_mb_max)::BIGINT AS stolen_server_memory_mb_max,
    SUM(sample_count) AS sample_count
FROM metrics.memory_5m GROUP BY time_bucket('1 hour', bucket), asset_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.memory_1h',
    start_offset => INTERVAL '2 hours', end_offset => INTERVAL '15 minutes',
    schedule_interval => INTERVAL '15 minutes');
SELECT add_retention_policy('metrics.memory_1h', INTERVAL '365 days');

-- -------------------------------------------------------
-- I/O (database level)
-- -------------------------------------------------------
CREATE TABLE metrics.io (
    time                    TIMESTAMPTZ NOT NULL,
    asset_id                UUID NOT NULL REFERENCES core.assets(id),
    file_id                 INT NOT NULL,
    io_stall_read_ms        BIGINT,
    io_stall_write_ms       BIGINT,
    num_of_reads            BIGINT,
    num_of_writes           BIGINT,
    num_of_bytes_read       BIGINT,
    num_of_bytes_written    BIGINT
);
SELECT create_hypertable('metrics.io', 'time', chunk_time_interval => INTERVAL '1 hour');
SELECT add_retention_policy('metrics.io', INTERVAL '24 hours');
SELECT add_compression_policy('metrics.io', INTERVAL '2 hours');

CREATE MATERIALIZED VIEW metrics.io_5m WITH (timescaledb.continuous) AS
SELECT time_bucket('5 minutes', time) AS bucket, asset_id, file_id,
    SUM(io_stall_read_ms)       AS io_stall_read_ms_total,
    SUM(io_stall_write_ms)      AS io_stall_write_ms_total,
    SUM(num_of_reads)           AS reads_total,
    SUM(num_of_writes)          AS writes_total,
    SUM(num_of_bytes_read)      AS bytes_read_total,
    SUM(num_of_bytes_written)   AS bytes_written_total,
    COUNT(*) AS sample_count
FROM metrics.io GROUP BY bucket, asset_id, file_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.io_5m',
    start_offset => INTERVAL '10 minutes', end_offset => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 minute');
SELECT add_retention_policy('metrics.io_5m', INTERVAL '7 days');

CREATE MATERIALIZED VIEW metrics.io_1h WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', bucket) AS bucket, asset_id, file_id,
    SUM(io_stall_read_ms_total)     AS io_stall_read_ms_total,
    SUM(io_stall_write_ms_total)    AS io_stall_write_ms_total,
    SUM(reads_total)                AS reads_total,
    SUM(writes_total)               AS writes_total
FROM metrics.io_5m GROUP BY time_bucket('1 hour', bucket), asset_id, file_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.io_1h',
    start_offset => INTERVAL '2 hours', end_offset => INTERVAL '15 minutes',
    schedule_interval => INTERVAL '15 minutes');
SELECT add_retention_policy('metrics.io_1h', INTERVAL '365 days');

-- -------------------------------------------------------
-- Plan cache / recompile (instance level)
-- -------------------------------------------------------
CREATE TABLE metrics.plan_cache (
    time                    TIMESTAMPTZ NOT NULL,
    asset_id                UUID NOT NULL REFERENCES core.assets(id),
    sql_compilations_sec    INT,
    sql_recompilations_sec  INT,
    plan_cache_hit_ratio    NUMERIC(5,2)
);
SELECT create_hypertable('metrics.plan_cache', 'time', chunk_time_interval => INTERVAL '1 hour');
SELECT add_retention_policy('metrics.plan_cache', INTERVAL '24 hours');
SELECT add_compression_policy('metrics.plan_cache', INTERVAL '2 hours');

CREATE MATERIALIZED VIEW metrics.plan_cache_5m WITH (timescaledb.continuous) AS
SELECT time_bucket('5 minutes', time) AS bucket, asset_id,
    AVG(sql_compilations_sec)::INT      AS compilations_avg,
    MAX(sql_recompilations_sec)::INT    AS recompilations_max,
    AVG(plan_cache_hit_ratio)           AS cache_hit_ratio_avg,
    COUNT(*) AS sample_count
FROM metrics.plan_cache GROUP BY bucket, asset_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.plan_cache_5m',
    start_offset => INTERVAL '10 minutes', end_offset => INTERVAL '1 minute',
    schedule_interval => INTERVAL '1 minute');
SELECT add_retention_policy('metrics.plan_cache_5m', INTERVAL '7 days');

CREATE MATERIALIZED VIEW metrics.plan_cache_1h WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', bucket) AS bucket, asset_id,
    MAX(recompilations_max)::INT AS recompilations_max,
    AVG(cache_hit_ratio_avg)     AS cache_hit_ratio_avg,
    SUM(sample_count)            AS sample_count
FROM metrics.plan_cache_5m GROUP BY time_bucket('1 hour', bucket), asset_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.plan_cache_1h',
    start_offset => INTERVAL '2 hours', end_offset => INTERVAL '15 minutes',
    schedule_interval => INTERVAL '15 minutes');
SELECT add_retention_policy('metrics.plan_cache_1h', INTERVAL '365 days');

-- -------------------------------------------------------
-- Database size / growth (database level)
-- -------------------------------------------------------
CREATE TABLE metrics.db_size (
    time            TIMESTAMPTZ NOT NULL,
    asset_id        UUID NOT NULL REFERENCES core.assets(id),
    data_size_mb    BIGINT NOT NULL,
    log_size_mb     BIGINT NOT NULL,
    data_used_mb    BIGINT,
    log_used_mb     BIGINT
);
SELECT create_hypertable('metrics.db_size', 'time', chunk_time_interval => INTERVAL '6 hours');
SELECT add_retention_policy('metrics.db_size', INTERVAL '24 hours');
SELECT add_compression_policy('metrics.db_size', INTERVAL '6 hours');

CREATE MATERIALIZED VIEW metrics.db_size_1h WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', time) AS bucket, asset_id,
    AVG(data_size_mb)::BIGINT AS data_size_mb_avg,
    MAX(data_size_mb)::BIGINT AS data_size_mb_max,
    AVG(log_size_mb)::BIGINT  AS log_size_mb_avg,
    COUNT(*) AS sample_count
FROM metrics.db_size GROUP BY bucket, asset_id WITH NO DATA;
SELECT add_continuous_aggregate_policy('metrics.db_size_1h',
    start_offset => INTERVAL '2 hours', end_offset => INTERVAL '15 minutes',
    schedule_interval => INTERVAL '15 minutes');
SELECT add_retention_policy('metrics.db_size_1h', INTERVAL '365 days');
