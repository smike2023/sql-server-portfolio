/*
    Wait Statistics Analysis Script
    Purpose: Identify and analyze SQL Server wait types for performance bottlenecks
    Author: SQL Server Portfolio
    Compatible: SQL Server 2016+
*/

-- Current Wait Statistics Summary
WITH WaitStats AS (
    SELECT 
        wait_type,
        wait_time_ms / 1000.0 AS wait_time_sec,
        signal_wait_time_ms / 1000.0 AS signal_wait_time_sec,
        (wait_time_ms - signal_wait_time_ms) / 1000.0 AS resource_wait_time_sec,
        waiting_tasks_count,
        100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS wait_percentage
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (
        -- Filter out benign wait types
        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP',
        N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',
        N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
        N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',
        N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
        N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT',
        N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
        N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE',
        N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE',
        N'PARALLEL_REDO_DRAIN_WORKER', N'PARALLEL_REDO_LOG_CACHE', N'PARALLEL_REDO_TRAN_LIST',
        N'PARALLEL_REDO_WORKER_SYNC', N'PARALLEL_REDO_WORKER_WAIT_WORK',
        N'PREEMPTIVE_OS_FLUSHFILEBUFFERS', N'PREEMPTIVE_XE_GETTARGETSTATE',
        N'PVS_PREALLOCATE', N'PWAIT_ALL_COMPONENTS_INITIALIZED', N'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
        N'QDS_ASYNC_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'QDS_SHUTDOWN_QUEUE', N'REDO_THREAD_PENDING_WORK',
        N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE', N'SERVER_IDLE_CHECK',
        N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP',
        N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY', N'SLEEP_MASTERUPGRADED',
        N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT', N'SOS_WORK_DISPATCHER',
        N'SP_SERVER_DIAGNOSTICS_SLEEP', N'SQLTRACE_BUFFER_FLUSH',
        N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES',
        N'UCS_SESSION_REGISTRATION', N'WAIT_FOR_RESULTS', N'WAITFOR',
        N'WAITFOR_TASKSHUTDOWN', N'WAIT_XTP_CKPT_CLOSE', N'WAIT_XTP_HOST_WAIT',
        N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'WAIT_XTP_RECOVERY', N'XE_BUFFERMGR_ALLPROCESSED_EVENT',
        N'XE_DISPATCHER_JOIN', N'XE_DISPATCHER_WAIT', N'XE_LIVE_TARGET_TVF',
        N'XE_TIMER_EVENT'
    )
    AND wait_time_ms > 0
)
SELECT TOP 20
    wait_type,
    wait_time_sec,
    signal_wait_time_sec,
    resource_wait_time_sec,
    waiting_tasks_count,
    ROUND(wait_percentage, 2) AS wait_percentage,
    CASE 
        WHEN wait_type LIKE 'LCK%' THEN 'Locking - Consider query optimization or isolation level changes'
        WHEN wait_type LIKE 'PAGEIO%' OR wait_type LIKE 'WRITELOG' THEN 'I/O - Consider disk performance or buffer pool size'
        WHEN wait_type LIKE 'ASYNC_NETWORK%' THEN 'Network - Client not consuming data fast enough'
        WHEN wait_type = 'CXPACKET' OR wait_type = 'CXCONSUMER' THEN 'Parallelism - Consider MAXDOP settings'
        WHEN wait_type = 'SOS_SCHEDULER_YIELD' THEN 'CPU - Query optimization or hardware upgrade'
        WHEN wait_type LIKE 'MEMORY%' THEN 'Memory - Consider increasing memory allocation'
        ELSE 'Review specific wait type documentation'
    END AS recommendation
FROM WaitStats
ORDER BY wait_time_sec DESC;

-- Real-time Blocking Analysis
SELECT 
    blocking.session_id AS blocking_session_id,
    blocked.session_id AS blocked_session_id,
    blocking.login_name AS blocking_login,
    blocked.login_name AS blocked_login,
    blocking.host_name AS blocking_host,
    blocked.host_name AS blocked_host,
    blocking_request.command AS blocking_command,
    blocked_request.command AS blocked_command,
    blocking_text.text AS blocking_sql_text,
    blocked_text.text AS blocked_sql_text,
    blocked_request.wait_type,
    blocked_request.wait_time / 1000.0 AS wait_time_seconds,
    blocked_request.blocking_session_id
FROM sys.dm_exec_sessions blocked
INNER JOIN sys.dm_exec_requests blocked_request
    ON blocked.session_id = blocked_request.session_id
INNER JOIN sys.dm_exec_sessions blocking
    ON blocked_request.blocking_session_id = blocking.session_id
LEFT JOIN sys.dm_exec_requests blocking_request
    ON blocking.session_id = blocking_request.session_id
CROSS APPLY sys.dm_exec_sql_text(blocked_request.sql_handle) AS blocked_text
OUTER APPLY sys.dm_exec_sql_text(blocking_request.sql_handle) AS blocking_text
WHERE blocked_request.blocking_session_id > 0
ORDER BY blocked_request.wait_time DESC;

-- Per-Session Wait Statistics
SELECT TOP 20
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    ws.wait_type,
    ws.waiting_tasks_count,
    ws.wait_time_ms / 1000.0 AS wait_time_sec
FROM sys.dm_exec_session_wait_stats ws
INNER JOIN sys.dm_exec_sessions s
    ON ws.session_id = s.session_id
WHERE s.is_user_process = 1
    AND ws.wait_time_ms > 0
ORDER BY ws.wait_time_ms DESC;
