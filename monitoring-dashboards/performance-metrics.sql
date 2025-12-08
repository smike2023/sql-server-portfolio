/*
    Performance Dashboard Queries
    Purpose: SQL Server performance monitoring for dashboards
    Author: SQL Server Portfolio
    Compatible: SQL Server 2016+
*/

-- ============================================
-- CPU Utilization Over Time
-- ============================================
SELECT TOP 60
    record_id,
    DATEADD(ms, -1 * (sys.ms_ticks - [timestamp]), GETDATE()) AS EventTime,
    SQLProcessUtilization AS SQL_CPU_Percent,
    100 - SystemIdle - SQLProcessUtilization AS Other_CPU_Percent,
    SystemIdle AS Idle_CPU_Percent
FROM (
    SELECT 
        record.value('(./Record/@id)[1]', 'int') AS record_id,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
        [timestamp]
    FROM (
        SELECT [timestamp], CONVERT(XML, record) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
            AND record LIKE '%<SystemHealth>%'
    ) AS x
) AS y
CROSS JOIN sys.dm_os_sys_info sys
ORDER BY record_id DESC;

-- ============================================
-- Memory Usage Summary
-- ============================================
SELECT 
    'Buffer Pool' AS MemoryType,
    COUNT(*) * 8 / 1024.0 AS MemoryMB
FROM sys.dm_os_buffer_descriptors
UNION ALL
SELECT 
    'Plan Cache' AS MemoryType,
    SUM(size_in_bytes) / 1024.0 / 1024.0 AS MemoryMB
FROM sys.dm_exec_cached_plans
UNION ALL
SELECT 
    'Procedure Cache - ' + objtype AS MemoryType,
    SUM(size_in_bytes) / 1024.0 / 1024.0 AS MemoryMB
FROM sys.dm_exec_cached_plans
GROUP BY objtype;

-- ============================================
-- Active Sessions and Requests
-- ============================================
SELECT 
    r.session_id,
    s.login_name,
    s.host_name,
    DB_NAME(r.database_id) AS DatabaseName,
    r.status,
    r.command,
    r.cpu_time,
    r.total_elapsed_time / 1000.0 AS elapsed_seconds,
    r.reads,
    r.writes,
    r.logical_reads,
    r.wait_type,
    r.wait_time / 1000.0 AS wait_seconds,
    r.blocking_session_id,
    t.text AS QueryText,
    qp.query_plan AS QueryPlan
FROM sys.dm_exec_requests r
INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) qp
WHERE s.is_user_process = 1
    AND r.session_id <> @@SPID
ORDER BY r.cpu_time DESC;

-- ============================================
-- Database I/O Statistics
-- ============================================
SELECT 
    DB_NAME(vfs.database_id) AS DatabaseName,
    mf.name AS FileName,
    mf.physical_name,
    mf.type_desc AS FileType,
    vfs.num_of_reads AS Reads,
    vfs.num_of_bytes_read / 1024.0 / 1024.0 AS ReadMB,
    vfs.io_stall_read_ms AS ReadStallMs,
    CASE WHEN vfs.num_of_reads > 0 
        THEN vfs.io_stall_read_ms / vfs.num_of_reads 
        ELSE 0 
    END AS AvgReadLatencyMs,
    vfs.num_of_writes AS Writes,
    vfs.num_of_bytes_written / 1024.0 / 1024.0 AS WriteMB,
    vfs.io_stall_write_ms AS WriteStallMs,
    CASE WHEN vfs.num_of_writes > 0 
        THEN vfs.io_stall_write_ms / vfs.num_of_writes 
        ELSE 0 
    END AS AvgWriteLatencyMs
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
INNER JOIN sys.master_files mf
    ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
ORDER BY vfs.io_stall DESC;

-- ============================================
-- Top Wait Types
-- ============================================
WITH WaitStats AS (
    SELECT 
        wait_type,
        wait_time_ms,
        waiting_tasks_count,
        100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS WaitPercent,
        ROW_NUMBER() OVER (ORDER BY wait_time_ms DESC) AS RowNum
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT LIKE '%SLEEP%'
        AND wait_type NOT LIKE '%IDLE%'
        AND wait_type NOT LIKE '%QUEUE%'
        AND wait_time_ms > 0
)
SELECT 
    wait_type,
    wait_time_ms / 1000.0 AS WaitSeconds,
    waiting_tasks_count,
    ROUND(WaitPercent, 2) AS WaitPercent
FROM WaitStats
WHERE RowNum <= 15
ORDER BY wait_time_ms DESC;

-- ============================================
-- Database Size and Growth
-- ============================================
SELECT 
    DB_NAME(database_id) AS DatabaseName,
    type_desc AS FileType,
    name AS FileName,
    size * 8.0 / 1024.0 AS SizeMB,
    CASE max_size
        WHEN -1 THEN 'Unlimited'
        WHEN 0 THEN 'No Growth'
        ELSE CAST(max_size * 8.0 / 1024.0 AS VARCHAR(20))
    END AS MaxSizeMB,
    CASE is_percent_growth
        WHEN 1 THEN CAST(growth AS VARCHAR(10)) + '%'
        ELSE CAST(growth * 8.0 / 1024.0 AS VARCHAR(20)) + ' MB'
    END AS GrowthSetting
FROM sys.master_files
WHERE database_id > 4
ORDER BY DB_NAME(database_id), type_desc;

-- ============================================
-- Connection Summary
-- ============================================
SELECT 
    DB_NAME(database_id) AS DatabaseName,
    login_name,
    host_name,
    program_name,
    COUNT(*) AS ConnectionCount,
    SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) AS ActiveConnections,
    SUM(CASE WHEN status = 'sleeping' THEN 1 ELSE 0 END) AS SleepingConnections
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY database_id, login_name, host_name, program_name
ORDER BY ConnectionCount DESC;
