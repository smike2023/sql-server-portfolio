/*
    Data Quality Framework
    Purpose: Comprehensive data quality validation and profiling
    Author: SQL Server Portfolio
    Compatible: SQL Server 2016+
*/

-- ============================================
-- Data Quality Rules Table
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'dq_Rules')
BEGIN
    CREATE TABLE dbo.dq_Rules (
        RuleID INT IDENTITY(1,1) PRIMARY KEY,
        RuleName NVARCHAR(100) NOT NULL,
        RuleDescription NVARCHAR(500),
        TargetSchema NVARCHAR(128) NOT NULL,
        TargetTable NVARCHAR(128) NOT NULL,
        TargetColumn NVARCHAR(128),
        RuleType NVARCHAR(50) NOT NULL, -- 'COMPLETENESS', 'VALIDITY', 'UNIQUENESS', 'CONSISTENCY', 'ACCURACY'
        RuleExpression NVARCHAR(MAX) NOT NULL,
        Threshold DECIMAL(5,2) DEFAULT 100.00, -- Expected pass rate percentage
        Severity NVARCHAR(20) DEFAULT 'Warning', -- 'Info', 'Warning', 'Critical'
        IsActive BIT DEFAULT 1,
        CreateDate DATETIME DEFAULT GETDATE()
    );
END
GO

-- ============================================
-- Data Quality Results Table
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'dq_Results')
BEGIN
    CREATE TABLE dbo.dq_Results (
        ResultID BIGINT IDENTITY(1,1) PRIMARY KEY,
        RuleID INT NOT NULL,
        BatchID INT,
        ExecutionTime DATETIME DEFAULT GETDATE(),
        TotalRows BIGINT,
        PassedRows BIGINT,
        FailedRows BIGINT,
        PassRate DECIMAL(5,2),
        Status NVARCHAR(20), -- 'PASSED', 'WARNING', 'FAILED'
        SampleFailures NVARCHAR(MAX), -- JSON sample of failed records
        CONSTRAINT FK_dq_Results_Rules FOREIGN KEY (RuleID) REFERENCES dbo.dq_Rules(RuleID)
    );

    CREATE NONCLUSTERED INDEX IX_dq_Results_RuleID ON dbo.dq_Results(RuleID, ExecutionTime);
END
GO

-- ============================================
-- Sample Data Quality Rules
-- ============================================
-- Insert sample rules if table is empty
IF NOT EXISTS (SELECT 1 FROM dbo.dq_Rules)
BEGIN
    INSERT INTO dbo.dq_Rules (RuleName, RuleDescription, TargetSchema, TargetTable, TargetColumn, RuleType, RuleExpression, Threshold, Severity)
    VALUES 
    -- Completeness rules
    ('Customer_Email_NotNull', 'Email address should not be null', 'dbo', 'dim_Customer', 'Email', 'COMPLETENESS', 'Email IS NOT NULL', 95.00, 'Warning'),
    ('Customer_Name_NotNull', 'Customer name should not be null', 'dbo', 'dim_Customer', 'FirstName', 'COMPLETENESS', 'FirstName IS NOT NULL AND LastName IS NOT NULL', 100.00, 'Critical'),
    
    -- Validity rules
    ('Customer_Email_Format', 'Email should be in valid format', 'dbo', 'dim_Customer', 'Email', 'VALIDITY', 'Email LIKE ''%@%.%''', 99.00, 'Warning'),
    ('Customer_PostalCode_Format', 'US postal code should be 5 or 9 digits', 'dbo', 'dim_Customer', 'PostalCode', 'VALIDITY', 'Country <> ''USA'' OR PostalCode LIKE ''[0-9][0-9][0-9][0-9][0-9]%''', 98.00, 'Info'),
    
    -- Uniqueness rules
    ('Customer_SourceID_Unique', 'Source customer ID should be unique among current records', 'dbo', 'dim_Customer', 'SourceCustomerID', 'UNIQUENESS', 'SourceCustomerID IS NOT NULL', 100.00, 'Critical'),
    
    -- Consistency rules
    ('Sales_Amount_Consistency', 'Total amount should equal quantity * unit price - discount + tax', 'dbo', 'fact_Sales', 'TotalAmount', 'CONSISTENCY', 'ABS(TotalAmount - (ExtendedAmount - DiscountAmount + TaxAmount)) < 0.01', 99.99, 'Critical');
END
GO

-- ============================================
-- Execute Data Quality Rule
-- ============================================
CREATE OR ALTER PROCEDURE dbo.usp_DQ_ExecuteRule
    @RuleID INT,
    @BatchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RuleName NVARCHAR(100);
    DECLARE @TargetSchema NVARCHAR(128);
    DECLARE @TargetTable NVARCHAR(128);
    DECLARE @RuleExpression NVARCHAR(MAX);
    DECLARE @Threshold DECIMAL(5,2);
    DECLARE @Severity NVARCHAR(20);
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @TotalRows BIGINT;
    DECLARE @PassedRows BIGINT;
    DECLARE @FailedRows BIGINT;
    DECLARE @PassRate DECIMAL(5,2);
    DECLARE @Status NVARCHAR(20);

    -- Get rule details
    SELECT 
        @RuleName = RuleName,
        @TargetSchema = TargetSchema,
        @TargetTable = TargetTable,
        @RuleExpression = RuleExpression,
        @Threshold = Threshold,
        @Severity = Severity
    FROM dbo.dq_Rules
    WHERE RuleID = @RuleID AND IsActive = 1;

    IF @RuleName IS NULL
    BEGIN
        RAISERROR('Rule not found or inactive', 16, 1);
        RETURN;
    END

    -- Build and execute validation query
    SET @SQL = N'
        SELECT 
            @TotalRows = COUNT(*),
            @PassedRows = SUM(CASE WHEN ' + @RuleExpression + N' THEN 1 ELSE 0 END)
        FROM ' + QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@TargetTable);

    EXEC sp_executesql @SQL, 
        N'@TotalRows BIGINT OUTPUT, @PassedRows BIGINT OUTPUT',
        @TotalRows OUTPUT, @PassedRows OUTPUT;

    SET @FailedRows = @TotalRows - @PassedRows;
    SET @PassRate = CASE WHEN @TotalRows > 0 THEN (CAST(@PassedRows AS DECIMAL(18,2)) / @TotalRows) * 100 ELSE 100 END;

    -- Determine status
    SET @Status = CASE 
        WHEN @PassRate >= @Threshold THEN 'PASSED'
        WHEN @PassRate >= @Threshold - 5 THEN 'WARNING'
        ELSE 'FAILED'
    END;

    -- Record results
    INSERT INTO dbo.dq_Results (RuleID, BatchID, TotalRows, PassedRows, FailedRows, PassRate, Status)
    VALUES (@RuleID, @BatchID, @TotalRows, @PassedRows, @FailedRows, @PassRate, @Status);

    -- Return results
    SELECT 
        @RuleID AS RuleID,
        @RuleName AS RuleName,
        @TotalRows AS TotalRows,
        @PassedRows AS PassedRows,
        @FailedRows AS FailedRows,
        @PassRate AS PassRate,
        @Threshold AS Threshold,
        @Status AS Status,
        @Severity AS Severity;
END
GO

-- ============================================
-- Execute All Active Rules
-- ============================================
CREATE OR ALTER PROCEDURE dbo.usp_DQ_ExecuteAllRules
    @BatchID INT = NULL,
    @TargetTable NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RuleID INT;
    DECLARE @Results TABLE (
        RuleID INT,
        RuleName NVARCHAR(100),
        TotalRows BIGINT,
        PassedRows BIGINT,
        FailedRows BIGINT,
        PassRate DECIMAL(5,2),
        Threshold DECIMAL(5,2),
        Status NVARCHAR(20),
        Severity NVARCHAR(20)
    );

    DECLARE rule_cursor CURSOR FOR
        SELECT RuleID 
        FROM dbo.dq_Rules 
        WHERE IsActive = 1
            AND (@TargetTable IS NULL OR TargetTable = @TargetTable);

    OPEN rule_cursor;
    FETCH NEXT FROM rule_cursor INTO @RuleID;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            INSERT INTO @Results
            EXEC dbo.usp_DQ_ExecuteRule @RuleID = @RuleID, @BatchID = @BatchID;
        END TRY
        BEGIN CATCH
            -- Log error but continue with other rules
            PRINT 'Error executing rule ' + CAST(@RuleID AS NVARCHAR(10)) + ': ' + ERROR_MESSAGE();
        END CATCH

        FETCH NEXT FROM rule_cursor INTO @RuleID;
    END

    CLOSE rule_cursor;
    DEALLOCATE rule_cursor;

    -- Return all results
    SELECT * FROM @Results
    ORDER BY 
        CASE Status WHEN 'FAILED' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,
        CASE Severity WHEN 'Critical' THEN 1 WHEN 'Warning' THEN 2 ELSE 3 END;

    -- Return summary
    SELECT 
        COUNT(*) AS TotalRules,
        SUM(CASE WHEN Status = 'PASSED' THEN 1 ELSE 0 END) AS PassedRules,
        SUM(CASE WHEN Status = 'WARNING' THEN 1 ELSE 0 END) AS WarningRules,
        SUM(CASE WHEN Status = 'FAILED' THEN 1 ELSE 0 END) AS FailedRules
    FROM @Results;
END
GO

-- ============================================
-- Data Profiling Procedure
-- ============================================
CREATE OR ALTER PROCEDURE dbo.usp_DQ_ProfileTable
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ColumnName NVARCHAR(128);
    DECLARE @DataType NVARCHAR(128);

    -- Get row count
    SET @SQL = N'SELECT COUNT(*) AS TotalRows FROM ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName);
    EXEC sp_executesql @SQL;

    -- Profile each column
    DECLARE column_cursor CURSOR FOR
        SELECT c.name, t.name
        FROM sys.columns c
        INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
        INNER JOIN sys.tables tab ON c.object_id = tab.object_id
        INNER JOIN sys.schemas s ON tab.schema_id = s.schema_id
        WHERE s.name = @SchemaName AND tab.name = @TableName;

    OPEN column_cursor;
    FETCH NEXT FROM column_cursor INTO @ColumnName, @DataType;

    CREATE TABLE #Profile (
        ColumnName NVARCHAR(128),
        DataType NVARCHAR(128),
        TotalValues BIGINT,
        NullCount BIGINT,
        NullPercent DECIMAL(5,2),
        DistinctCount BIGINT,
        MinValue NVARCHAR(500),
        MaxValue NVARCHAR(500)
    );

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = N'
            INSERT INTO #Profile
            SELECT 
                ''' + @ColumnName + N''' AS ColumnName,
                ''' + @DataType + N''' AS DataType,
                COUNT(*) AS TotalValues,
                SUM(CASE WHEN ' + QUOTENAME(@ColumnName) + N' IS NULL THEN 1 ELSE 0 END) AS NullCount,
                CAST(SUM(CASE WHEN ' + QUOTENAME(@ColumnName) + N' IS NULL THEN 1.0 ELSE 0.0 END) / COUNT(*) * 100 AS DECIMAL(5,2)) AS NullPercent,
                COUNT(DISTINCT ' + QUOTENAME(@ColumnName) + N') AS DistinctCount,
                CAST(MIN(' + QUOTENAME(@ColumnName) + N') AS NVARCHAR(500)) AS MinValue,
                CAST(MAX(' + QUOTENAME(@ColumnName) + N') AS NVARCHAR(500)) AS MaxValue
            FROM ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName);

        EXEC sp_executesql @SQL;

        FETCH NEXT FROM column_cursor INTO @ColumnName, @DataType;
    END

    CLOSE column_cursor;
    DEALLOCATE column_cursor;

    SELECT * FROM #Profile ORDER BY ColumnName;
    DROP TABLE #Profile;
END
GO
