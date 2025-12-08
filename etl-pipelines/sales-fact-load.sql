/*
    Sales Fact ETL Pipeline
    Purpose: Incremental load of sales transaction data into fact table
    Author: SQL Server Portfolio
    Compatible: SQL Server 2016+
*/

-- ============================================
-- Staging Table for Sales Data
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'stg_Sales')
BEGIN
    CREATE TABLE dbo.stg_Sales (
        SourceTransactionID NVARCHAR(50) NOT NULL,
        TransactionDate DATETIME NOT NULL,
        CustomerID NVARCHAR(50),
        ProductID NVARCHAR(50),
        StoreID NVARCHAR(50),
        EmployeeID NVARCHAR(50),
        Quantity INT,
        UnitPrice DECIMAL(18,4),
        DiscountAmount DECIMAL(18,4),
        TaxAmount DECIMAL(18,4),
        TotalAmount DECIMAL(18,4),
        PaymentMethod NVARCHAR(50),
        SourceSystem NVARCHAR(50),
        ExtractDate DATETIME DEFAULT GETDATE(),
        BatchID INT,
        IsValid BIT DEFAULT 1,
        ValidationMessage NVARCHAR(500)
    );

    CREATE NONCLUSTERED INDEX IX_stg_Sales_BatchID ON dbo.stg_Sales(BatchID);
END
GO

-- ============================================
-- Fact Table Structure
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'fact_Sales')
BEGIN
    CREATE TABLE dbo.fact_Sales (
        SalesKey BIGINT IDENTITY(1,1) PRIMARY KEY,
        DateKey INT NOT NULL,
        CustomerKey INT,
        ProductKey INT,
        StoreKey INT,
        EmployeeKey INT,
        SourceTransactionID NVARCHAR(50) NOT NULL,
        Quantity INT,
        UnitPrice DECIMAL(18,4),
        ExtendedAmount DECIMAL(18,4),
        DiscountAmount DECIMAL(18,4),
        TaxAmount DECIMAL(18,4),
        TotalAmount DECIMAL(18,4),
        PaymentMethod NVARCHAR(50),
        SourceSystem NVARCHAR(50),
        BatchID INT,
        LoadDate DATETIME DEFAULT GETDATE()
    );

    CREATE NONCLUSTERED INDEX IX_fact_Sales_DateKey ON dbo.fact_Sales(DateKey);
    CREATE NONCLUSTERED INDEX IX_fact_Sales_CustomerKey ON dbo.fact_Sales(CustomerKey);
    CREATE NONCLUSTERED INDEX IX_fact_Sales_SourceTransactionID ON dbo.fact_Sales(SourceTransactionID);
END
GO

-- ============================================
-- Date Dimension Helper (if not exists)
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'dim_Date')
BEGIN
    CREATE TABLE dbo.dim_Date (
        DateKey INT PRIMARY KEY,
        FullDate DATE NOT NULL,
        DayOfWeek INT,
        DayName NVARCHAR(20),
        DayOfMonth INT,
        DayOfYear INT,
        WeekOfYear INT,
        MonthNumber INT,
        MonthName NVARCHAR(20),
        Quarter INT,
        Year INT,
        IsWeekend BIT,
        IsHoliday BIT DEFAULT 0
    );

    -- Populate date dimension (5 years)
    DECLARE @StartDate DATE = '2020-01-01';
    DECLARE @EndDate DATE = '2030-12-31';

    ;WITH DateCTE AS (
        SELECT @StartDate AS DateValue
        UNION ALL
        SELECT DATEADD(DAY, 1, DateValue)
        FROM DateCTE
        WHERE DateValue < @EndDate
    )
    INSERT INTO dbo.dim_Date (DateKey, FullDate, DayOfWeek, DayName, DayOfMonth, DayOfYear, 
                               WeekOfYear, MonthNumber, MonthName, Quarter, Year, IsWeekend)
    SELECT 
        CONVERT(INT, FORMAT(DateValue, 'yyyyMMdd')) AS DateKey,
        DateValue,
        DATEPART(WEEKDAY, DateValue),
        DATENAME(WEEKDAY, DateValue),
        DATEPART(DAY, DateValue),
        DATEPART(DAYOFYEAR, DateValue),
        DATEPART(WEEK, DateValue),
        DATEPART(MONTH, DateValue),
        DATENAME(MONTH, DateValue),
        DATEPART(QUARTER, DateValue),
        DATEPART(YEAR, DateValue),
        CASE WHEN DATEPART(WEEKDAY, DateValue) IN (1, 7) THEN 1 ELSE 0 END
    FROM DateCTE
    OPTION (MAXRECURSION 0);
END
GO

-- ============================================
-- Validation Stored Procedure
-- ============================================
CREATE OR ALTER PROCEDURE dbo.usp_ETL_ValidateSalesStaging
    @BatchID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Mark invalid records: Missing required fields
    UPDATE dbo.stg_Sales
    SET IsValid = 0,
        ValidationMessage = 'Missing required field: TransactionID or TransactionDate'
    WHERE BatchID = @BatchID
        AND (SourceTransactionID IS NULL OR TransactionDate IS NULL);

    -- Mark invalid records: Invalid amounts
    UPDATE dbo.stg_Sales
    SET IsValid = 0,
        ValidationMessage = 'Invalid amount: Quantity <= 0 or UnitPrice < 0'
    WHERE BatchID = @BatchID
        AND IsValid = 1
        AND (Quantity <= 0 OR UnitPrice < 0);

    -- Mark invalid records: Future dates
    UPDATE dbo.stg_Sales
    SET IsValid = 0,
        ValidationMessage = 'Transaction date is in the future'
    WHERE BatchID = @BatchID
        AND IsValid = 1
        AND TransactionDate > GETDATE();

    -- Mark invalid records: Duplicate transactions
    ;WITH Duplicates AS (
        SELECT SourceTransactionID, 
               ROW_NUMBER() OVER (PARTITION BY SourceTransactionID ORDER BY ExtractDate) AS RowNum
        FROM dbo.stg_Sales
        WHERE BatchID = @BatchID AND IsValid = 1
    )
    UPDATE s
    SET IsValid = 0,
        ValidationMessage = 'Duplicate transaction ID in batch'
    FROM dbo.stg_Sales s
    INNER JOIN Duplicates d ON s.SourceTransactionID = d.SourceTransactionID AND d.RowNum > 1
    WHERE s.BatchID = @BatchID;

    -- Check for existing records (for incremental load)
    UPDATE stg
    SET IsValid = 0,
        ValidationMessage = 'Transaction already exists in fact table'
    FROM dbo.stg_Sales stg
    INNER JOIN dbo.fact_Sales fact ON stg.SourceTransactionID = fact.SourceTransactionID
    WHERE stg.BatchID = @BatchID AND stg.IsValid = 1;

    -- Return validation summary
    SELECT 
        COUNT(*) AS TotalRecords,
        SUM(CASE WHEN IsValid = 1 THEN 1 ELSE 0 END) AS ValidRecords,
        SUM(CASE WHEN IsValid = 0 THEN 1 ELSE 0 END) AS InvalidRecords
    FROM dbo.stg_Sales
    WHERE BatchID = @BatchID;
END
GO

-- ============================================
-- Main ETL Load Procedure
-- ============================================
CREATE OR ALTER PROCEDURE dbo.usp_ETL_LoadSalesFact
    @BatchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartTime DATETIME = GETDATE();
    DECLARE @RowsExtracted INT;
    DECLARE @RowsInserted INT;
    DECLARE @RowsErrored INT;
    DECLARE @ErrorMessage NVARCHAR(MAX);

    -- Create batch if not provided
    IF @BatchID IS NULL
    BEGIN
        INSERT INTO dbo.etl_BatchControl (BatchName, StartTime, Status)
        VALUES ('LoadSalesFact', @StartTime, 'Running');
        SET @BatchID = SCOPE_IDENTITY();

        UPDATE dbo.stg_Sales 
        SET BatchID = @BatchID 
        WHERE BatchID IS NULL;
    END

    SELECT @RowsExtracted = COUNT(*) FROM dbo.stg_Sales WHERE BatchID = @BatchID;

    BEGIN TRY
        -- Run validation
        EXEC dbo.usp_ETL_ValidateSalesStaging @BatchID = @BatchID;

        SELECT @RowsErrored = COUNT(*) FROM dbo.stg_Sales WHERE BatchID = @BatchID AND IsValid = 0;

        BEGIN TRANSACTION;

        -- Load valid records to fact table
        INSERT INTO dbo.fact_Sales (
            DateKey, CustomerKey, ProductKey, StoreKey, EmployeeKey,
            SourceTransactionID, Quantity, UnitPrice, ExtendedAmount,
            DiscountAmount, TaxAmount, TotalAmount, PaymentMethod,
            SourceSystem, BatchID
        )
        SELECT 
            CONVERT(INT, FORMAT(stg.TransactionDate, 'yyyyMMdd')) AS DateKey,
            dc.CustomerKey,
            NULL AS ProductKey, -- Lookup from dim_Product
            NULL AS StoreKey,   -- Lookup from dim_Store
            NULL AS EmployeeKey, -- Lookup from dim_Employee
            stg.SourceTransactionID,
            stg.Quantity,
            stg.UnitPrice,
            stg.Quantity * stg.UnitPrice AS ExtendedAmount,
            ISNULL(stg.DiscountAmount, 0),
            ISNULL(stg.TaxAmount, 0),
            stg.TotalAmount,
            stg.PaymentMethod,
            stg.SourceSystem,
            @BatchID
        FROM dbo.stg_Sales stg
        LEFT JOIN dbo.dim_Customer dc 
            ON stg.CustomerID = dc.SourceCustomerID AND dc.IsCurrent = 1
        WHERE stg.BatchID = @BatchID
            AND stg.IsValid = 1;

        SET @RowsInserted = @@ROWCOUNT;

        -- Archive invalid records (optional - move to error table)
        -- DELETE FROM dbo.stg_Sales WHERE BatchID = @BatchID AND IsValid = 0;

        -- Clear processed staging data
        DELETE FROM dbo.stg_Sales WHERE BatchID = @BatchID AND IsValid = 1;

        COMMIT TRANSACTION;

        -- Update batch control
        UPDATE dbo.etl_BatchControl
        SET 
            EndTime = GETDATE(),
            Status = 'Success',
            RowsExtracted = @RowsExtracted,
            RowsInserted = @RowsInserted,
            RowsErrored = @RowsErrored
        WHERE BatchID = @BatchID;

        -- Return summary
        SELECT 
            @BatchID AS BatchID,
            @RowsExtracted AS RowsExtracted,
            @RowsInserted AS RowsInserted,
            @RowsErrored AS RowsErrored,
            'Success' AS Status;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        
        SET @ErrorMessage = ERROR_MESSAGE();
        
        UPDATE dbo.etl_BatchControl
        SET 
            EndTime = GETDATE(),
            Status = 'Failed',
            RowsExtracted = @RowsExtracted,
            RowsErrored = @RowsErrored,
            ErrorMessage = @ErrorMessage
        WHERE BatchID = @BatchID;

        THROW;
    END CATCH
END
GO
