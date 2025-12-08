/*
    Alerting Thresholds Configuration
    Purpose: Define monitoring thresholds and alert conditions
    Author: SQL Server Portfolio
    Compatible: SQL Server 2016+
*/

-- ============================================
-- Alert Configuration Table
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'monitor_AlertConfig')
BEGIN
    CREATE TABLE dbo.monitor_AlertConfig (
        AlertID INT IDENTITY(1,1) PRIMARY KEY,
        AlertName NVARCHAR(100) NOT NULL,
        Category NVARCHAR(50) NOT NULL,
        MetricQuery NVARCHAR(MAX) NOT NULL,
        WarningThreshold DECIMAL(18,2),
        CriticalThreshold DECIMAL(18,2),
        ThresholdOperator NVARCHAR(10) DEFAULT '>', -- '>', '<', '>=', '<=', '='
        CheckIntervalMinutes INT DEFAULT 15,
        IsEnabled BIT DEFAULT 1,
        NotificationEmail NVARCHAR(255),
        CreateDate DATETIME DEFAULT GETDATE()
    );
END
GO

-- ============================================
-- Alert History Table
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'monitor_AlertHistory')
BEGIN
    CREATE TABLE dbo.monitor_AlertHistory (
        HistoryID BIGINT IDENTITY(1,1) PRIMARY KEY,
        AlertID INT NOT NULL,
        AlertTime DATETIME DEFAULT GETDATE(),
        Severity NVARCHAR(20), -- 'Warning', 'Critical'
        MetricValue DECIMAL(18,2),
        ThresholdValue DECIMAL(18,2),
        AlertMessage NVARCHAR(500),
        IsAcknowledged BIT DEFAULT 0,
        AcknowledgedBy NVARCHAR(100),
        AcknowledgedTime DATETIME
    );

    CREATE NONCLUSTERED INDEX IX_AlertHistory_Time 
        ON dbo.monitor_AlertHistory(AlertTime DESC);
END
GO

-- ============================================
-- Default Alert Configurations
-- ============================================
IF NOT EXISTS (SELECT 1 FROM dbo.monitor_AlertConfig)
BEGIN
    INSERT INTO dbo.monitor_AlertConfig 
        (AlertName, Category, MetricQuery, WarningThreshold, CriticalThreshold, ThresholdOperator)
    VALUES
    -- CPU Alerts
    ('High CPU Usage', 'Performance', 
     'SELECT AVG(SQLProcessUtilization) FROM (SELECT record.value(''(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]'', ''int'') AS SQLProcessUtilization FROM (SELECT CONVERT(XML, record) AS record FROM sys.dm_os_ring_buffers WHERE ring_buffer_type = N''RING_BUFFER_SCHEDULER_MONITOR'') x) y',
     80, 95, '>'),

    -- Memory Alerts
    ('Low Available Memory', 'Performance',
     'SELECT (committed_kb * 100.0 / committed_target_kb) FROM sys.dm_os_sys_info',
     90, 98, '>'),

    -- Disk Space Alerts
    ('Low Disk Space', 'Storage',
     'SELECT MIN(available_bytes * 100.0 / total_bytes) FROM sys.dm_os_volume_stats(NULL, NULL) vs INNER JOIN sys.master_files mf ON vs.database_id = mf.database_id AND vs.file_id = mf.file_id',
     20, 10, '<'),

    -- Blocking Alerts
    ('Long Blocking', 'Performance',
     'SELECT ISNULL(MAX(wait_time / 1000.0), 0) FROM sys.dm_exec_requests WHERE blocking_session_id > 0',
     30, 120, '>'),

    -- Backup Alerts
    ('Missing Backups', 'Backup',
     'SELECT COUNT(*) FROM sys.databases d LEFT JOIN msdb.dbo.backupset b ON d.name = b.database_name AND b.type = ''D'' WHERE d.database_id > 4 AND d.state_desc = ''ONLINE'' AND b.backup_finish_date IS NULL OR DATEDIFF(DAY, b.backup_finish_date, GETDATE()) > 7',
     1, 3, '>='),

    -- Connection Alerts
    ('High Connection Count', 'Connections',
     'SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1',
     500, 800, '>'),

    -- Error Log Alerts
    ('Recent Errors', 'Errors',
     'SELECT COUNT(*) FROM (SELECT TOP 100 * FROM sys.dm_exec_query_stats) x WHERE 1=0', -- Placeholder
     10, 50, '>'),

    -- Long Running Queries
    ('Long Running Query', 'Performance',
     'SELECT ISNULL(MAX(total_elapsed_time / 1000.0), 0) FROM sys.dm_exec_requests WHERE session_id > 50',
     300, 900, '>');
END
GO

-- ============================================
-- Check Alerts Procedure
-- ============================================
CREATE OR ALTER PROCEDURE dbo.usp_Monitor_CheckAlerts
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AlertID INT;
    DECLARE @AlertName NVARCHAR(100);
    DECLARE @MetricQuery NVARCHAR(MAX);
    DECLARE @WarningThreshold DECIMAL(18,2);
    DECLARE @CriticalThreshold DECIMAL(18,2);
    DECLARE @ThresholdOperator NVARCHAR(10);
    DECLARE @MetricValue DECIMAL(18,2);
    DECLARE @Severity NVARCHAR(20);
    DECLARE @SQL NVARCHAR(MAX);

    DECLARE alert_cursor CURSOR FOR
        SELECT AlertID, AlertName, MetricQuery, WarningThreshold, CriticalThreshold, ThresholdOperator
        FROM dbo.monitor_AlertConfig
        WHERE IsEnabled = 1;

    OPEN alert_cursor;
    FETCH NEXT FROM alert_cursor INTO @AlertID, @AlertName, @MetricQuery, @WarningThreshold, @CriticalThreshold, @ThresholdOperator;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Execute metric query
            SET @SQL = N'SELECT @Value = (' + @MetricQuery + N')';
            EXEC sp_executesql @SQL, N'@Value DECIMAL(18,2) OUTPUT', @MetricValue OUTPUT;

            -- Determine severity
            SET @Severity = NULL;

            IF @ThresholdOperator = '>'
            BEGIN
                IF @MetricValue > @CriticalThreshold SET @Severity = 'Critical';
                ELSE IF @MetricValue > @WarningThreshold SET @Severity = 'Warning';
            END
            ELSE IF @ThresholdOperator = '<'
            BEGIN
                IF @MetricValue < @CriticalThreshold SET @Severity = 'Critical';
                ELSE IF @MetricValue < @WarningThreshold SET @Severity = 'Warning';
            END
            ELSE IF @ThresholdOperator = '>='
            BEGIN
                IF @MetricValue >= @CriticalThreshold SET @Severity = 'Critical';
                ELSE IF @MetricValue >= @WarningThreshold SET @Severity = 'Warning';
            END
            ELSE IF @ThresholdOperator = '<='
            BEGIN
                IF @MetricValue <= @CriticalThreshold SET @Severity = 'Critical';
                ELSE IF @MetricValue <= @WarningThreshold SET @Severity = 'Warning';
            END

            -- Log alert if threshold exceeded
            IF @Severity IS NOT NULL
            BEGIN
                INSERT INTO dbo.monitor_AlertHistory 
                    (AlertID, Severity, MetricValue, ThresholdValue, AlertMessage)
                VALUES 
                    (@AlertID, @Severity, @MetricValue, 
                     CASE @Severity WHEN 'Critical' THEN @CriticalThreshold ELSE @WarningThreshold END,
                     @AlertName + ': ' + @Severity + ' - Value: ' + CAST(@MetricValue AS NVARCHAR(20)));
            END
        END TRY
        BEGIN CATCH
            -- Log error but continue
            PRINT 'Error checking alert ' + @AlertName + ': ' + ERROR_MESSAGE();
        END CATCH

        FETCH NEXT FROM alert_cursor INTO @AlertID, @AlertName, @MetricQuery, @WarningThreshold, @CriticalThreshold, @ThresholdOperator;
    END

    CLOSE alert_cursor;
    DEALLOCATE alert_cursor;

    -- Return recent alerts
    SELECT 
        ah.AlertTime,
        ac.AlertName,
        ac.Category,
        ah.Severity,
        ah.MetricValue,
        ah.ThresholdValue,
        ah.AlertMessage,
        ah.IsAcknowledged
    FROM dbo.monitor_AlertHistory ah
    INNER JOIN dbo.monitor_AlertConfig ac ON ah.AlertID = ac.AlertID
    WHERE ah.AlertTime >= DATEADD(HOUR, -24, GETDATE())
    ORDER BY ah.AlertTime DESC;
END
GO

-- ============================================
-- Alert Summary View
-- ============================================
CREATE OR ALTER VIEW dbo.vw_AlertSummary
AS
SELECT 
    ac.Category,
    ac.AlertName,
    COUNT(ah.HistoryID) AS AlertCount24Hours,
    MAX(ah.AlertTime) AS LastAlertTime,
    MAX(ah.Severity) AS HighestSeverity,
    SUM(CASE WHEN ah.IsAcknowledged = 0 THEN 1 ELSE 0 END) AS UnacknowledgedCount
FROM dbo.monitor_AlertConfig ac
LEFT JOIN dbo.monitor_AlertHistory ah 
    ON ac.AlertID = ah.AlertID 
    AND ah.AlertTime >= DATEADD(HOUR, -24, GETDATE())
WHERE ac.IsEnabled = 1
GROUP BY ac.Category, ac.AlertName;
GO
