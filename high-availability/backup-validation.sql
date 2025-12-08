/*
    Backup Validation Script
    Purpose: Validate backup health, history, and recovery readiness
    Author: SQL Server Portfolio
    Compatible: SQL Server 2008+
*/

-- Recent Backup Summary by Database
SELECT 
    d.name AS DatabaseName,
    d.recovery_model_desc AS RecoveryModel,
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFullBackup,
    MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS LastDiffBackup,
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLogBackup,
    DATEDIFF(DAY, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) AS DaysSinceFullBackup,
    DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), GETDATE()) AS HoursSinceLogBackup
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b
    ON d.name = b.database_name
WHERE d.database_id > 4 -- Exclude system databases
    AND d.state_desc = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
ORDER BY DaysSinceFullBackup DESC NULLS FIRST;

-- Backup Alerts: Missing Backups
SELECT 
    d.name AS DatabaseName,
    d.recovery_model_desc AS RecoveryModel,
    CASE 
        WHEN MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) IS NULL 
            THEN 'CRITICAL: No full backup exists'
        WHEN DATEDIFF(DAY, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) > 7 
            THEN 'WARNING: Full backup older than 7 days'
        ELSE 'OK'
    END AS FullBackupStatus,
    CASE 
        WHEN d.recovery_model_desc = 'FULL' 
            AND MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) IS NULL 
            THEN 'CRITICAL: No log backup for FULL recovery model'
        WHEN d.recovery_model_desc = 'FULL' 
            AND DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), GETDATE()) > 1 
            THEN 'WARNING: Log backup older than 1 hour'
        ELSE 'OK'
    END AS LogBackupStatus
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b
    ON d.name = b.database_name
WHERE d.database_id > 4
    AND d.state_desc = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
HAVING 
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) IS NULL
    OR DATEDIFF(DAY, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) > 7
    OR (d.recovery_model_desc = 'FULL' 
        AND DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), GETDATE()) > 1);

-- Backup Size and Duration Trends
SELECT TOP 100
    database_name,
    CASE type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
    END AS BackupType,
    backup_start_date,
    backup_finish_date,
    DATEDIFF(SECOND, backup_start_date, backup_finish_date) AS DurationSeconds,
    backup_size / 1024.0 / 1024.0 AS BackupSizeMB,
    compressed_backup_size / 1024.0 / 1024.0 AS CompressedSizeMB,
    CASE 
        WHEN backup_size > 0 
        THEN 100.0 - (compressed_backup_size * 100.0 / backup_size)
        ELSE 0 
    END AS CompressionRatio,
    physical_device_name
FROM msdb.dbo.backupset b
INNER JOIN msdb.dbo.backupmediafamily m
    ON b.media_set_id = m.media_set_id
WHERE backup_finish_date >= DATEADD(DAY, -30, GETDATE())
ORDER BY backup_finish_date DESC;

-- Verify Latest Backups are Readable
SELECT 
    database_name,
    backup_start_date,
    CASE type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
    END AS BackupType,
    has_backup_checksums,
    is_damaged,
    is_copy_only,
    recovery_model,
    expiration_date
FROM msdb.dbo.backupset
WHERE backup_finish_date >= DATEADD(DAY, -7, GETDATE())
ORDER BY database_name, backup_finish_date DESC;

-- Backup Job Status
SELECT 
    j.name AS JobName,
    j.enabled AS IsEnabled,
    js.last_run_date,
    js.last_run_time,
    CASE js.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 5 THEN 'Unknown'
    END AS LastRunOutcome,
    js.last_outcome_message
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobservers js
    ON j.job_id = js.job_id
WHERE j.name LIKE '%Backup%'
ORDER BY j.name;
