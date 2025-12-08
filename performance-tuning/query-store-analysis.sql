/*
    Query Store Analysis Script
    Purpose: Analyze query performance using Query Store data
    Author: SQL Server Portfolio
    Compatible: SQL Server 2016+
*/

-- Enable Query Store (if not already enabled)
-- ALTER DATABASE [YourDatabase] SET QUERY_STORE = ON;

-- Top Resource Consuming Queries
SELECT TOP 25
    q.query_id,
    qt.query_sql_text,
    rs.count_executions,
    rs.avg_duration / 1000000.0 AS avg_duration_seconds,
    rs.avg_cpu_time / 1000000.0 AS avg_cpu_time_seconds,
    rs.avg_logical_io_reads,
    rs.avg_physical_io_reads,
    rs.avg_query_max_used_memory,
    rs.max_duration / 1000000.0 AS max_duration_seconds,
    qp.plan_id,
    TRY_CAST(qp.query_plan AS XML) AS query_plan_xml
FROM sys.query_store_query q
INNER JOIN sys.query_store_query_text qt
    ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan qp
    ON q.query_id = qp.query_id
INNER JOIN sys.query_store_runtime_stats rs
    ON qp.plan_id = rs.plan_id
INNER JOIN sys.query_store_runtime_stats_interval rsi
    ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY rs.avg_duration DESC;

-- Regressed Queries (Plan Regression)
SELECT 
    q.query_id,
    qt.query_sql_text,
    p.plan_id,
    rs.avg_duration / 1000000.0 AS avg_duration_seconds,
    rs.last_execution_time,
    rs.first_execution_time
FROM sys.query_store_query q
INNER JOIN sys.query_store_query_text qt
    ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan p
    ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats rs
    ON p.plan_id = rs.plan_id
WHERE p.is_forced_plan = 0
    AND rs.avg_duration > 
        (SELECT AVG(rs2.avg_duration) * 2
         FROM sys.query_store_plan p2
         INNER JOIN sys.query_store_runtime_stats rs2 ON p2.plan_id = rs2.plan_id
         WHERE p2.query_id = q.query_id)
ORDER BY rs.avg_duration DESC;

-- Queries with Multiple Plans (Plan Instability)
SELECT 
    q.query_id,
    qt.query_sql_text,
    COUNT(DISTINCT p.plan_id) AS number_of_plans,
    MIN(rs.avg_duration) / 1000000.0 AS min_avg_duration_seconds,
    MAX(rs.avg_duration) / 1000000.0 AS max_avg_duration_seconds,
    (MAX(rs.avg_duration) - MIN(rs.avg_duration)) / 1000000.0 AS duration_variance_seconds
FROM sys.query_store_query q
INNER JOIN sys.query_store_query_text qt
    ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan p
    ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats rs
    ON p.plan_id = rs.plan_id
GROUP BY q.query_id, qt.query_sql_text
HAVING COUNT(DISTINCT p.plan_id) > 1
ORDER BY number_of_plans DESC, duration_variance_seconds DESC;

-- Query Store Configuration Status
SELECT 
    actual_state_desc,
    desired_state_desc,
    readonly_reason,
    current_storage_size_mb,
    max_storage_size_mb,
    flush_interval_seconds,
    interval_length_minutes,
    stale_query_threshold_days,
    size_based_cleanup_mode_desc,
    query_capture_mode_desc,
    wait_stats_capture_mode_desc
FROM sys.database_query_store_options;
