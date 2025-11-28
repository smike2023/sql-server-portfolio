/*
    Log Shipping Health Check
    Purpose: Monitor log shipping status and identify issues
    Author: SQL Server Portfolio
    Compatible: SQL Server 2008+
*/

-- Log Shipping Primary Server Status
SELECT 
    primary_server,
    primary_database,
    backup_directory,
    backup_share,
    backup_retention_period,
    backup_threshold,
    threshold_alert_enabled,
    last_backup_file,
    last_backup_date,
    DATEDIFF(MINUTE, last_backup_date, GETDATE()) AS MinutesSinceLastBackup,
    CASE 
        WHEN DATEDIFF(MINUTE, last_backup_date, GETDATE()) > backup_threshold 
        THEN 'ALERT: Backup threshold exceeded'
        ELSE 'OK'
    END AS BackupStatus
FROM msdb.dbo.log_shipping_monitor_primary;

-- Log Shipping Secondary Server Status
SELECT 
    secondary_server,
    secondary_database,
    primary_server,
    primary_database,
    restore_threshold,
    threshold_alert_enabled,
    last_copied_file,
    last_copied_date,
    last_restored_file,
    last_restored_date,
    last_restored_latency,
    DATEDIFF(MINUTE, last_restored_date, GETDATE()) AS MinutesSinceLastRestore,
    CASE 
        WHEN DATEDIFF(MINUTE, last_restored_date, GETDATE()) > restore_threshold 
        THEN 'ALERT: Restore threshold exceeded'
        ELSE 'OK'
    END AS RestoreStatus
FROM msdb.dbo.log_shipping_monitor_secondary;

-- Log Shipping Job History (Recent)
SELECT TOP 50
    j.name AS JobName,
    jh.step_name,
    jh.run_date,
    jh.run_time,
    jh.run_duration,
    CASE jh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END AS RunStatus,
    jh.message
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobhistory jh
    ON j.job_id = jh.job_id
WHERE j.name LIKE '%LSBackup%' 
    OR j.name LIKE '%LSCopy%' 
    OR j.name LIKE '%LSRestore%'
ORDER BY jh.run_date DESC, jh.run_time DESC;

-- Log Shipping Configuration Validation
SELECT 
    lsp.primary_id,
    lsp.primary_database,
    lsp.backup_directory,
    lsp.backup_share,
    lsp.backup_compression,
    lsp.backup_job_id,
    lss.secondary_server,
    lss.secondary_database,
    lss.copy_job_id,
    lss.restore_job_id,
    lss.restore_mode,
    CASE lss.restore_mode
        WHEN 0 THEN 'NORECOVERY - Standby Mode Disabled'
        WHEN 1 THEN 'STANDBY - Read-Only Access'
    END AS RestoreModeDesc
FROM msdb.dbo.log_shipping_primary_databases lsp
INNER JOIN msdb.dbo.log_shipping_secondary lss
    ON lsp.primary_id = lss.primary_id
INNER JOIN msdb.dbo.log_shipping_secondary_databases lssd
    ON lss.secondary_id = lssd.secondary_id;

-- Alert: Databases with stale log shipping
SELECT 
    'CRITICAL ALERT' AS AlertLevel,
    secondary_database AS Database,
    primary_server AS PrimaryServer,
    secondary_server AS SecondaryServer,
    last_restored_date,
    DATEDIFF(HOUR, last_restored_date, GETDATE()) AS HoursBehind
FROM msdb.dbo.log_shipping_monitor_secondary
WHERE DATEDIFF(HOUR, last_restored_date, GETDATE()) > 1;
