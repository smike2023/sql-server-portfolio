/*
    Instance Health Dashboard Queries
    Purpose: SQL Server instance health monitoring
    Author: SQL Server Portfolio
    Compatible: SQL Server 2016+
*/

-- ============================================
-- Server Configuration Overview
-- ============================================
SELECT 
    @@SERVERNAME AS ServerName,
    @@VERSION AS SQLVersion,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductLevel') AS ServicePack,
    SERVERPROPERTY('ProductUpdateLevel') AS CumulativeUpdate,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('IsClustered') AS IsClustered,
    SERVERPROPERTY('IsHadrEnabled') AS IsAlwaysOnEnabled;

-- ============================================
-- Instance Uptime
-- ============================================
SELECT 
    sqlserver_start_time AS StartTime,
    DATEDIFF(DAY, sqlserver_start_time, GETDATE()) AS DaysRunning,
    DATEDIFF(HOUR, sqlserver_start_time, GETDATE()) AS HoursRunning
FROM sys.dm_os_sys_info;

-- ============================================
-- Key Configuration Settings
-- ============================================
SELECT 
    name AS ConfigOption,
    value AS ConfiguredValue,
    value_in_use AS RunningValue,
    minimum AS MinValue,
    maximum AS MaxValue,
    is_dynamic AS IsDynamic,
    is_advanced AS IsAdvanced
FROM sys.configurations
WHERE name IN (
    'max server memory (MB)',
    'min server memory (MB)',
    'max degree of parallelism',
    'cost threshold for parallelism',
    'optimize for ad hoc workloads',
    'backup compression default',
    'clr enabled',
    'cross db ownership chaining',
    'xp_cmdshell'
)
ORDER BY name;

-- ============================================
-- Database States Summary
-- ============================================
SELECT 
    state_desc AS DatabaseState,
    COUNT(*) AS DatabaseCount
FROM sys.databases
GROUP BY state_desc
ORDER BY DatabaseCount DESC;

SELECT 
    name AS DatabaseName,
    state_desc AS State,
    recovery_model_desc AS RecoveryModel,
    compatibility_level AS CompatibilityLevel,
    collation_name AS Collation,
    is_auto_shrink_on AS AutoShrink,
    is_auto_close_on AS AutoClose,
    page_verify_option_desc AS PageVerify
FROM sys.databases
ORDER BY name;

-- ============================================
-- SQL Server Error Log (Recent Errors)
-- ============================================
CREATE TABLE #ErrorLog (
    LogDate DATETIME,
    ProcessInfo NVARCHAR(50),
    Text NVARCHAR(MAX)
);

INSERT INTO #ErrorLog
EXEC xp_readerrorlog 0, 1, N'error';

SELECT TOP 50
    LogDate,
    ProcessInfo,
    Text AS ErrorMessage
FROM #ErrorLog
WHERE LogDate >= DATEADD(DAY, -7, GETDATE())
ORDER BY LogDate DESC;

DROP TABLE #ErrorLog;

-- ============================================
-- Disk Space Alert Status
-- ============================================
SELECT 
    DISTINCT vs.volume_mount_point AS Drive,
    vs.logical_volume_name AS VolumeName,
    CAST(vs.total_bytes / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS TotalGB,
    CAST(vs.available_bytes / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS FreeGB,
    CAST((vs.available_bytes * 100.0 / vs.total_bytes) AS DECIMAL(5,2)) AS FreePercent,
    CASE 
        WHEN (vs.available_bytes * 100.0 / vs.total_bytes) < 10 THEN 'CRITICAL'
        WHEN (vs.available_bytes * 100.0 / vs.total_bytes) < 20 THEN 'WARNING'
        ELSE 'OK'
    END AS Status
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
ORDER BY FreePercent;

-- ============================================
-- SQL Agent Job Status
-- ============================================
SELECT 
    j.name AS JobName,
    CASE j.enabled WHEN 1 THEN 'Enabled' ELSE 'Disabled' END AS JobStatus,
    CASE jh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
        ELSE 'Unknown'
    END AS LastRunStatus,
    msdb.dbo.agent_datetime(jh.run_date, jh.run_time) AS LastRunTime,
    jh.run_duration AS DurationSeconds,
    js.next_run_date,
    js.next_run_time
FROM msdb.dbo.sysjobs j
LEFT JOIN (
    SELECT job_id, run_status, run_date, run_time, run_duration,
           ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0
) jh ON j.job_id = jh.job_id AND jh.rn = 1
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
WHERE j.enabled = 1
ORDER BY jh.run_status, j.name;

-- ============================================
-- Backup Compliance Status
-- ============================================
SELECT 
    d.name AS DatabaseName,
    d.recovery_model_desc AS RecoveryModel,
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFullBackup,
    MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS LastDiffBackup,
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLogBackup,
    CASE 
        WHEN MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) IS NULL THEN 'CRITICAL: No backup'
        WHEN DATEDIFF(DAY, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) > 7 THEN 'WARNING: >7 days'
        ELSE 'OK'
    END AS BackupStatus
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON d.name = b.database_name
WHERE d.database_id > 4
    AND d.state_desc = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
ORDER BY 
    CASE 
        WHEN MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) IS NULL THEN 1
        ELSE 2
    END,
    d.name;

-- ============================================
-- Security Audit Summary
-- ============================================
SELECT 
    name AS LoginName,
    type_desc AS LoginType,
    create_date AS CreateDate,
    modify_date AS ModifyDate,
    is_disabled AS IsDisabled,
    LOGINPROPERTY(name, 'PasswordLastSetTime') AS PasswordLastSet,
    LOGINPROPERTY(name, 'DaysUntilExpiration') AS DaysUntilExpiry,
    LOGINPROPERTY(name, 'IsLocked') AS IsLocked
FROM sys.server_principals
WHERE type IN ('S', 'U', 'G')
    AND name NOT LIKE '##%'
    AND name NOT LIKE 'NT %'
ORDER BY create_date DESC;
