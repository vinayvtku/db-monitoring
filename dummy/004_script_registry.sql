-- ============================================================
-- 004_script_registry.sql  (v2)
-- Script registry — every collection script the platform knows
-- Technology agnostic — T-SQL, PowerShell, Bash, Python, REST
-- Full version history
-- Target type defines what the script runs against
-- ============================================================

CREATE SCHEMA IF NOT EXISTS script_registry;

-- ------------------------------------------------------------
-- Scripts
-- The central registry of every script the platform can run
-- script_body stores the actual script — T-SQL, PowerShell,
-- Bash, Python, REST call definition — anything
-- ------------------------------------------------------------
CREATE TABLE script_registry.scripts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identity
    name                TEXT NOT NULL UNIQUE,
    display_name        TEXT NOT NULL,
    description         TEXT,
    category            TEXT NOT NULL,
    -- 'discovery'    — runs once on onboarding, populates inventory
    -- 'collection'   — runs on schedule, populates metrics
    -- 'security'     — security checks, feeds scoring
    -- 'maintenance'  — backup, job history, maintenance windows
    -- 'schema'       — schema intel collection
    -- 'operational'  — one-off operational scripts (onboarding etc)

    -- Target
    target_type_id      UUID NOT NULL REFERENCES core.target_types(id),
    -- which type of target this script runs against
    -- e.g. sql_server_instance, windows_server, linux_host

    -- Execution
    execution_type      TEXT NOT NULL,
    -- 'tsql'        — T-SQL against SQL Server / Azure SQL
    -- 'powershell'  — PowerShell script (Windows or PS Core)
    -- 'bash'        — Bash script (Linux)
    -- 'python'      — Python script
    -- 'rest'        — REST API call (script_body is JSON request spec)
    -- 'ssh'         — command run over SSH
    -- 'psql'        — psql / PostgreSQL query
    -- 'mysql'       — MySQL query
    -- 'db2'         — DB2 query

    credential_purpose  TEXT NOT NULL DEFAULT 'default',
    -- which credential purpose to use when executing
    -- e.g. 'sql', 'winrm', 'ssh', 'default'

    script_body         TEXT NOT NULL,
    -- the actual script content
    -- for 'rest': JSON defining method, url, headers, body
    -- for everything else: the script text

    -- Version
    version             TEXT NOT NULL DEFAULT '1.0.0',
    -- semver: major.minor.patch
    script_hash         TEXT NOT NULL,
    -- SHA256 of script_body — verified by agent before execution

    -- Schedule
    default_schedule    TEXT NOT NULL DEFAULT '*/1 * * * *',
    -- cron expression
    -- discovery scripts typically run once: '0 0 * * *' (daily)
    -- collection scripts: '*/1 * * * *' (every minute)
    -- schema intel: '0 * * * *' (hourly)
    -- security checks: '*/5 * * * *' (every 5 minutes)

    -- Output
    output_schema       JSONB NOT NULL DEFAULT '{}',
    -- documents what fields the script returns
    -- used by the ingestion worker to route results correctly
    -- e.g. {"sql_cpu_pct": "int", "idle_cpu_pct": "int"}
    output_destination  TEXT NOT NULL DEFAULT 'metrics',
    -- 'metrics'    — goes to metrics schema hypertables
    -- 'inventory'  — goes to inventory schema
    -- 'scoring'    — goes to scoring schema
    -- 'audit'      — goes to audit schema
    -- 'raw'        — stored as JSONB in work_results

    -- Timeout
    timeout_seconds     INT NOT NULL DEFAULT 30,
    max_retries         INT NOT NULL DEFAULT 3,

    -- Flags
    is_enabled          BOOLEAN NOT NULL DEFAULT true,
    is_system           BOOLEAN NOT NULL DEFAULT false,
    -- system = platform built-in, protected from user edits
    is_discovery        BOOLEAN NOT NULL DEFAULT false,
    -- discovery scripts run once on onboarding
    -- collection scripts run on schedule

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          TEXT NOT NULL DEFAULT 'system'
);

CREATE INDEX idx_scripts_target_type
    ON script_registry.scripts(target_type_id, is_enabled);
CREATE INDEX idx_scripts_category
    ON script_registry.scripts(category);
CREATE INDEX idx_scripts_execution_type
    ON script_registry.scripts(execution_type);

-- ------------------------------------------------------------
-- Script version history
-- Full history of every version of every script
-- Old versions kept forever for audit and rollback
-- ------------------------------------------------------------
CREATE TABLE script_registry.script_versions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    script_id       UUID NOT NULL REFERENCES script_registry.scripts(id),
    version         TEXT NOT NULL,
    script_body     TEXT NOT NULL,
    script_hash     TEXT NOT NULL,
    change_note     TEXT,
    changed_by      TEXT NOT NULL DEFAULT 'system',
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (script_id, version)
);

CREATE INDEX idx_script_versions_script
    ON script_registry.script_versions(script_id, changed_at DESC);

-- Trigger: automatically save a version snapshot when script_body changes
CREATE OR REPLACE FUNCTION script_registry.save_script_version()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.script_body IS DISTINCT FROM NEW.script_body THEN
        INSERT INTO script_registry.script_versions
            (script_id, version, script_body, script_hash, change_note, changed_by)
        VALUES
            (NEW.id, OLD.version, OLD.script_body, OLD.script_hash,
             'Auto-saved before update', NEW.updated_by);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add updated_by column for the trigger
ALTER TABLE script_registry.scripts
    ADD COLUMN IF NOT EXISTS updated_by TEXT DEFAULT 'system';

CREATE TRIGGER trg_script_version
    BEFORE UPDATE ON script_registry.scripts
    FOR EACH ROW EXECUTE FUNCTION script_registry.save_script_version();

-- ------------------------------------------------------------
-- Seed system scripts
-- Discovery and collection scripts for SQL Server (MVP)
-- PowerShell and Bash scripts added as stubs — replace
-- script_body with actual content as platform grows
-- ------------------------------------------------------------

-- SQL Server instance discovery (runs once on onboarding)
INSERT INTO script_registry.scripts
    (name, display_name, description, category,
     target_type_id, execution_type, credential_purpose,
     default_schedule, timeout_seconds, is_system, is_discovery,
     output_destination, script_hash,
     output_schema, script_body)
VALUES (
    'sql_server_discovery',
    'SQL Server Instance Discovery',
    'Collects instance metadata on onboarding. Runs once daily to detect config drift.',
    'discovery',
    (SELECT id FROM core.target_types WHERE name = 'sql_server_instance'),
    'tsql', 'sql',
    '0 0 * * *', 60, true, true,
    'inventory', 'sha256_sql_server_discovery',
    '{"server_name":"string","edition":"string","version":"string","collation":"string","max_dop":"int","max_server_memory_mb":"int"}',
    $SCRIPT$
SELECT
    SERVERPROPERTY('ServerName')            AS server_name,
    SERVERPROPERTY('Edition')               AS edition,
    SERVERPROPERTY('ProductVersion')        AS version,
    SERVERPROPERTY('ProductBuild')          AS version_build,
    SERVERPROPERTY('ProductUpdateLevel')    AS patch_level,
    SERVERPROPERTY('Collation')             AS collation,
    SERVERPROPERTY('IsClustered')           AS is_clustered,
    SERVERPROPERTY('IsHadrEnabled')         AS is_hadr_enabled,
    (SELECT value_in_use FROM sys.configurations
     WHERE name = 'max degree of parallelism')  AS max_dop,
    (SELECT value_in_use FROM sys.configurations
     WHERE name = 'max server memory (MB)')     AS max_server_memory_mb,
    (SELECT value_in_use FROM sys.configurations
     WHERE name = 'cost threshold for parallelism') AS cost_threshold_parallelism
$SCRIPT$
);

-- SQL Server database discovery (runs once on onboarding)
INSERT INTO script_registry.scripts
    (name, display_name, description, category,
     target_type_id, execution_type, credential_purpose,
     default_schedule, timeout_seconds, is_system, is_discovery,
     output_destination, script_hash,
     output_schema, script_body)
VALUES (
    'sql_database_discovery',
    'SQL Server Database Discovery',
    'Discovers all user databases on a SQL Server instance.',
    'discovery',
    (SELECT id FROM core.target_types WHERE name = 'sql_server_instance'),
    'tsql', 'sql',
    '0 * * * *', 60, true, true,
    'inventory', 'sha256_sql_database_discovery',
    '{"name":"string","state":"string","recovery_model":"string","size_mb":"int","log_size_mb":"int"}',
    $SCRIPT$
SELECT
    d.name,
    d.state_desc                            AS state,
    d.recovery_model_desc                   AS recovery_model,
    d.compatibility_level,
    d.collation_name                        AS collation,
    d.is_read_only,
    d.is_auto_close_on                      AS is_auto_close,
    d.is_auto_shrink_on                     AS is_auto_shrink,
    SUSER_SNAME(d.owner_sid)                AS owner,
    d.create_date                           AS created_at_source,
    SUM(CASE WHEN mf.type = 0
        THEN mf.size * 8 / 1024 ELSE 0 END) AS data_size_mb,
    SUM(CASE WHEN mf.type = 1
        THEN mf.size * 8 / 1024 ELSE 0 END) AS log_size_mb
FROM sys.databases d
LEFT JOIN sys.master_files mf ON mf.database_id = d.database_id
WHERE d.state_desc = 'ONLINE'
  AND d.name NOT IN ('master','model','msdb','tempdb')
GROUP BY d.name, d.state_desc, d.recovery_model_desc,
    d.compatibility_level, d.collation_name,
    d.is_read_only, d.is_auto_close_on, d.is_auto_shrink_on,
    d.owner_sid, d.create_date
ORDER BY d.name
$SCRIPT$
);

-- SQL Server CPU collection
INSERT INTO script_registry.scripts
    (name, display_name, description, category,
     target_type_id, execution_type, credential_purpose,
     default_schedule, timeout_seconds, is_system,
     output_destination, script_hash,
     output_schema, script_body)
VALUES (
    'sql_cpu_collection',
    'SQL Server CPU Metrics',
    'Collects SQL Server CPU utilisation every minute.',
    'collection',
    (SELECT id FROM core.target_types WHERE name = 'sql_server_instance'),
    'tsql', 'sql',
    '*/1 * * * *', 30, true,
    'metrics', 'sha256_sql_cpu_collection',
    '{"sql_cpu_pct":"int","other_cpu_pct":"int","idle_cpu_pct":"int"}',
    $SCRIPT$
SELECT
    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')
        AS sql_cpu_pct,
    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
        AS idle_cpu_pct,
    100
    - record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')
    - record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
        AS other_cpu_pct
FROM (
    SELECT TOP 1
        CONVERT(XML, record) AS record
    FROM sys.dm_os_ring_buffers
    WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
      AND record LIKE '%<SystemHealth>%'
    ORDER BY timestamp DESC
) AS ring
$SCRIPT$
);

-- SQL Server wait stats collection
INSERT INTO script_registry.scripts
    (name, display_name, description, category,
     target_type_id, execution_type, credential_purpose,
     default_schedule, timeout_seconds, is_system,
     output_destination, script_hash,
     output_schema, script_body)
VALUES (
    'sql_wait_stats_collection',
    'SQL Server Wait Stats',
    'Collects SQL Server wait statistics every minute.',
    'collection',
    (SELECT id FROM core.target_types WHERE name = 'sql_server_instance'),
    'tsql', 'sql',
    '*/1 * * * *', 30, true,
    'metrics', 'sha256_sql_wait_stats',
    '{"wait_type":"string","wait_time_ms":"bigint","signal_wait_time_ms":"bigint","waiting_tasks":"int"}',
    $SCRIPT$
SELECT
    wait_type,
    wait_time_ms,
    signal_wait_time_ms,
    waiting_tasks_count AS waiting_tasks
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SLEEP_TASK','BROKER_TO_FLUSH','BROKER_TASK_STOP',
    'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE',
    'FT_IFTS_SCHEDULER_IDLE_WAIT','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
    'HADR_WORK_QUEUE','LAZYWRITER_SLEEP','LOGMGR_QUEUE',
    'ONDEMAND_TASK_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH',
    'RESOURCE_QUEUE','SERVER_IDLE_CHECK','SLEEP_DBSTARTUP',
    'SLEEP_DBTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','WAITFOR',
    'XE_DISPATCHER_WAIT','XE_TIMER_EVENT'
)
  AND wait_time_ms > 0
ORDER BY wait_time_ms DESC
$SCRIPT$
);

-- SQL Server memory collection
INSERT INTO script_registry.scripts
    (name, display_name, description, category,
     target_type_id, execution_type, credential_purpose,
     default_schedule, timeout_seconds, is_system,
     output_destination, script_hash,
     output_schema, script_body)
VALUES (
    'sql_memory_collection',
    'SQL Server Memory Metrics',
    'Collects SQL Server memory utilisation every minute.',
    'collection',
    (SELECT id FROM core.target_types WHERE name = 'sql_server_instance'),
    'tsql', 'sql',
    '*/1 * * * *', 30, true,
    'metrics', 'sha256_sql_memory',
    '{"total_server_memory_mb":"bigint","target_server_memory_mb":"bigint","sql_cache_memory_mb":"bigint"}',
    $SCRIPT$
SELECT
    physical_memory_in_use_kb / 1024       AS total_server_memory_mb,
    locked_page_allocations_kb / 1024      AS locked_pages_mb,
    page_fault_count,
    memory_utilization_percentage
FROM sys.dm_os_process_memory
$SCRIPT$
);

-- SQL Server database size collection
INSERT INTO script_registry.scripts
    (name, display_name, description, category,
     target_type_id, execution_type, credential_purpose,
     default_schedule, timeout_seconds, is_system,
     output_destination, script_hash,
     output_schema, script_body)
VALUES (
    'sql_db_size_collection',
    'SQL Server Database Size',
    'Collects database size and growth every 5 minutes.',
    'collection',
    (SELECT id FROM core.target_types WHERE name = 'sql_server_database'),
    'tsql', 'sql',
    '*/5 * * * *', 30, true,
    'metrics', 'sha256_sql_db_size',
    '{"data_size_mb":"bigint","log_size_mb":"bigint","data_used_mb":"bigint","log_used_mb":"bigint"}',
    $SCRIPT$
SELECT
    SUM(CASE WHEN type = 0 THEN size * 8 / 1024 ELSE 0 END) AS data_size_mb,
    SUM(CASE WHEN type = 1 THEN size * 8 / 1024 ELSE 0 END) AS log_size_mb,
    SUM(CASE WHEN type = 0 THEN FILEPROPERTY(name, 'SpaceUsed') * 8 / 1024
             ELSE 0 END)                                     AS data_used_mb,
    SUM(CASE WHEN type = 1 THEN FILEPROPERTY(name, 'SpaceUsed') * 8 / 1024
             ELSE 0 END)                                     AS log_used_mb
FROM sys.database_files
$SCRIPT$
);

-- SQL Server plan cache collection
INSERT INTO script_registry.scripts
    (name, display_name, description, category,
     target_type_id, execution_type, credential_purpose,
     default_schedule, timeout_seconds, is_system,
     output_destination, script_hash,
     output_schema, script_body)
VALUES (
    'sql_plan_cache_collection',
    'SQL Server Plan Cache',
    'Collects plan cache and recompile metrics every minute.',
    'collection',
    (SELECT id FROM core.target_types WHERE name = 'sql_server_instance'),
    'tsql', 'sql',
    '*/1 * * * *', 30, true,
    'metrics', 'sha256_sql_plan_cache',
    '{"sql_compilations_sec":"int","sql_recompilations_sec":"int","plan_cache_hit_ratio":"numeric"}',
    $SCRIPT$
SELECT
    (SELECT cntr_value FROM sys.dm_os_performance_counters
     WHERE counter_name = 'SQL Compilations/sec'
       AND object_name LIKE '%SQL Statistics%')   AS sql_compilations_sec,
    (SELECT cntr_value FROM sys.dm_os_performance_counters
     WHERE counter_name = 'SQL Re-Compilations/sec'
       AND object_name LIKE '%SQL Statistics%')   AS sql_recompilations_sec,
    (SELECT cntr_value FROM sys.dm_os_performance_counters
     WHERE counter_name = 'Cache Hit Ratio'
       AND object_name LIKE '%Plan Cache%'
       AND instance_name = '_Total')              AS plan_cache_hit_ratio
$SCRIPT$
);

-- SQL Server security principals (security check)
INSERT INTO script_registry.scripts
    (name, display_name, description, category,
     target_type_id, execution_type, credential_purpose,
     default_schedule, timeout_seconds, is_system,
     output_destination, script_hash,
     output_schema, script_body)
VALUES (
    'sql_security_principals',
    'SQL Server Security Principals',
    'Collects logins and permissions. Feeds security drift detection.',
    'security',
    (SELECT id FROM core.target_types WHERE name = 'sql_server_instance'),
    'tsql', 'sql',
    '*/5 * * * *', 30, true,
    'inventory', 'sha256_sql_principals',
    '{"principal_name":"string","principal_type":"string","auth_type":"string","is_sysadmin":"bool","is_disabled":"bool"}',
    $SCRIPT$
SELECT
    sp.name                                 AS principal_name,
    sp.type_desc                            AS principal_type,
    sp.authentication_type_desc            AS auth_type,
    CASE WHEN srm.role_principal_id IS NOT NULL
         THEN 1 ELSE 0 END                 AS is_sysadmin,
    sp.is_disabled
FROM sys.server_principals sp
LEFT JOIN sys.server_role_members srm
    ON srm.member_principal_id = sp.principal_id
    AND srm.role_principal_id = SUSER_ID('sysadmin')
WHERE sp.type IN ('S','U','G')
ORDER BY sp.name
$SCRIPT$
);

-- Windows Server discovery (PowerShell stub)
INSERT INTO script_registry.scripts
    (name, display_name, description, category,
     target_type_id, execution_type, credential_purpose,
     default_schedule, timeout_seconds, is_system, is_discovery,
     output_destination, script_hash,
     output_schema, script_body)
VALUES (
    'windows_server_discovery',
    'Windows Server Discovery',
    'Collects Windows host metadata via PowerShell / WinRM.',
    'discovery',
    (SELECT id FROM core.target_types WHERE name = 'windows_server'),
    'powershell', 'winrm',
    '0 0 * * *', 60, true, true,
    'inventory', 'sha256_windows_discovery',
    '{"os_version":"string","os_build":"string","cpu_count":"int","ram_mb":"bigint","domain":"string"}',
    $SCRIPT$
$info = Get-ComputerInfo
$os   = Get-WmiObject Win32_OperatingSystem
[PSCustomObject]@{
    os_version    = $info.OsName
    os_build      = $info.OsBuildNumber
    cpu_count     = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors
    ram_mb        = [math]::Round($info.CsTotalPhysicalMemory / 1MB)
    domain        = $info.CsDomain
    last_boot_time = $os.ConvertToDateTime($os.LastBootUpTime).ToUniversalTime().ToString('o')
} | ConvertTo-Json
$SCRIPT$
);

-- Linux host discovery (Bash stub)
INSERT INTO script_registry.scripts
    (name, display_name, description, category,
     target_type_id, execution_type, credential_purpose,
     default_schedule, timeout_seconds, is_system, is_discovery,
     output_destination, script_hash,
     output_schema, script_body)
VALUES (
    'linux_host_discovery',
    'Linux Host Discovery',
    'Collects Linux host metadata via SSH / Bash.',
    'discovery',
    (SELECT id FROM core.target_types WHERE name = 'linux_host'),
    'bash', 'ssh',
    '0 0 * * *', 60, true, true,
    'inventory', 'sha256_linux_discovery',
    '{"distro":"string","distro_version":"string","kernel":"string","cpu_count":"int","ram_mb":"bigint"}',
    $SCRIPT$
echo "{
  \"distro\": \"$(. /etc/os-release && echo $NAME)\",
  \"distro_version\": \"$(. /etc/os-release && echo $VERSION_ID)\",
  \"kernel\": \"$(uname -r)\",
  \"cpu_count\": $(nproc),
  \"ram_mb\": $(free -m | awk '/^Mem:/{print $2}'),
  \"hostname\": \"$(hostname -f)\",
  \"uptime_seconds\": $(cat /proc/uptime | awk '{print int($1)}')
}"
$SCRIPT$
);
