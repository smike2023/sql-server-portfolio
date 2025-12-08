/*
    Customer Data ETL Pipeline
    Purpose: Extract, transform, and load customer data with SCD Type 2 handling
    Author: SQL Server Portfolio
    Compatible: SQL Server 2016+
*/

-- ============================================
-- Staging Table Structure
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'stg_Customer')
BEGIN
    CREATE TABLE dbo.stg_Customer (
        SourceCustomerID NVARCHAR(50) NOT NULL,
        FirstName NVARCHAR(100),
        LastName NVARCHAR(100),
        Email NVARCHAR(255),
        Phone NVARCHAR(50),
        AddressLine1 NVARCHAR(255),
        AddressLine2 NVARCHAR(255),
        City NVARCHAR(100),
        State NVARCHAR(50),
        PostalCode NVARCHAR(20),
        Country NVARCHAR(100),
        CustomerType NVARCHAR(50),
        SourceSystem NVARCHAR(50),
        ExtractDate DATETIME DEFAULT GETDATE(),
        BatchID INT
    );
END
GO

-- ============================================
-- Dimension Table Structure (SCD Type 2)
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'dim_Customer')
BEGIN
    CREATE TABLE dbo.dim_Customer (
        CustomerKey INT IDENTITY(1,1) PRIMARY KEY,
        SourceCustomerID NVARCHAR(50) NOT NULL,
        FirstName NVARCHAR(100),
        LastName NVARCHAR(100),
        FullName AS (FirstName + ' ' + LastName) PERSISTED,
        Email NVARCHAR(255),
        Phone NVARCHAR(50),
        AddressLine1 NVARCHAR(255),
        AddressLine2 NVARCHAR(255),
        City NVARCHAR(100),
        State NVARCHAR(50),
        PostalCode NVARCHAR(20),
        Country NVARCHAR(100),
        CustomerType NVARCHAR(50),
        SourceSystem NVARCHAR(50),
        EffectiveStartDate DATETIME NOT NULL,
        EffectiveEndDate DATETIME NULL,
        IsCurrent BIT NOT NULL DEFAULT 1,
        RowHash VARBINARY(32),
        CreateDate DATETIME DEFAULT GETDATE(),
        ModifyDate DATETIME DEFAULT GETDATE()
    );

    CREATE NONCLUSTERED INDEX IX_dim_Customer_SourceID 
        ON dbo.dim_Customer(SourceCustomerID, IsCurrent);
END
GO

-- ============================================
-- ETL Control Table
-- ============================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'etl_BatchControl')
BEGIN
    CREATE TABLE dbo.etl_BatchControl (
        BatchID INT IDENTITY(1,1) PRIMARY KEY,
        BatchName NVARCHAR(100),
        StartTime DATETIME,
        EndTime DATETIME,
        Status NVARCHAR(50),
        RowsExtracted INT,
        RowsInserted INT,
        RowsUpdated INT,
        RowsErrored INT,
        ErrorMessage NVARCHAR(MAX)
    );
END
GO

-- ============================================
-- ETL Stored Procedure: Load Customer Dimension
-- ============================================
CREATE OR ALTER PROCEDURE dbo.usp_ETL_LoadCustomerDimension
    @BatchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartTime DATETIME = GETDATE();
    DECLARE @RowsInserted INT = 0;
    DECLARE @RowsUpdated INT = 0;
    DECLARE @ErrorMessage NVARCHAR(MAX);

    -- Create batch record if not provided
    IF @BatchID IS NULL
    BEGIN
        INSERT INTO dbo.etl_BatchControl (BatchName, StartTime, Status)
        VALUES ('LoadCustomerDimension', @StartTime, 'Running');
        SET @BatchID = SCOPE_IDENTITY();
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Calculate hash for change detection
        UPDATE stg
        SET stg.BatchID = @BatchID
        FROM dbo.stg_Customer stg
        WHERE stg.BatchID IS NULL;

        -- Add computed hash to staging data (for comparison)
        ;WITH StagingWithHash AS (
            SELECT 
                SourceCustomerID,
                HASHBYTES('SHA2_256', 
                    CONCAT(
                        ISNULL(FirstName, ''), '|',
                        ISNULL(LastName, ''), '|',
                        ISNULL(Email, ''), '|',
                        ISNULL(Phone, ''), '|',
                        ISNULL(AddressLine1, ''), '|',
                        ISNULL(City, ''), '|',
                        ISNULL(State, ''), '|',
                        ISNULL(PostalCode, ''), '|',
                        ISNULL(Country, ''), '|',
                        ISNULL(CustomerType, '')
                    )
                ) AS RowHash
            FROM dbo.stg_Customer
            WHERE BatchID = @BatchID
        )

        -- SCD Type 2: Expire changed records
        UPDATE dim
        SET 
            dim.IsCurrent = 0,
            dim.EffectiveEndDate = @StartTime,
            dim.ModifyDate = @StartTime
        FROM dbo.dim_Customer dim
        INNER JOIN StagingWithHash stg
            ON dim.SourceCustomerID = stg.SourceCustomerID
            AND dim.IsCurrent = 1
            AND dim.RowHash <> stg.RowHash;

        SET @RowsUpdated = @@ROWCOUNT;

        -- Insert new and changed records
        INSERT INTO dbo.dim_Customer (
            SourceCustomerID, FirstName, LastName, Email, Phone,
            AddressLine1, AddressLine2, City, State, PostalCode,
            Country, CustomerType, SourceSystem,
            EffectiveStartDate, IsCurrent, RowHash
        )
        SELECT 
            stg.SourceCustomerID,
            stg.FirstName,
            stg.LastName,
            stg.Email,
            stg.Phone,
            stg.AddressLine1,
            stg.AddressLine2,
            stg.City,
            stg.State,
            stg.PostalCode,
            stg.Country,
            stg.CustomerType,
            stg.SourceSystem,
            @StartTime,
            1,
            HASHBYTES('SHA2_256', 
                CONCAT(
                    ISNULL(stg.FirstName, ''), '|',
                    ISNULL(stg.LastName, ''), '|',
                    ISNULL(stg.Email, ''), '|',
                    ISNULL(stg.Phone, ''), '|',
                    ISNULL(stg.AddressLine1, ''), '|',
                    ISNULL(stg.City, ''), '|',
                    ISNULL(stg.State, ''), '|',
                    ISNULL(stg.PostalCode, ''), '|',
                    ISNULL(stg.Country, ''), '|',
                    ISNULL(stg.CustomerType, '')
                )
            )
        FROM dbo.stg_Customer stg
        LEFT JOIN dbo.dim_Customer dim
            ON stg.SourceCustomerID = dim.SourceCustomerID
            AND dim.IsCurrent = 1
        WHERE dim.CustomerKey IS NULL -- New records
           OR dim.RowHash <> HASHBYTES('SHA2_256', 
                CONCAT(
                    ISNULL(stg.FirstName, ''), '|',
                    ISNULL(stg.LastName, ''), '|',
                    ISNULL(stg.Email, ''), '|',
                    ISNULL(stg.Phone, ''), '|',
                    ISNULL(stg.AddressLine1, ''), '|',
                    ISNULL(stg.City, ''), '|',
                    ISNULL(stg.State, ''), '|',
                    ISNULL(stg.PostalCode, ''), '|',
                    ISNULL(stg.Country, ''), '|',
                    ISNULL(stg.CustomerType, '')
                )
            ); -- Changed records

        SET @RowsInserted = @@ROWCOUNT;

        -- Clear processed staging data
        DELETE FROM dbo.stg_Customer WHERE BatchID = @BatchID;

        COMMIT TRANSACTION;

        -- Update batch control
        UPDATE dbo.etl_BatchControl
        SET 
            EndTime = GETDATE(),
            Status = 'Success',
            RowsInserted = @RowsInserted,
            RowsUpdated = @RowsUpdated
        WHERE BatchID = @BatchID;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        
        SET @ErrorMessage = ERROR_MESSAGE();
        
        UPDATE dbo.etl_BatchControl
        SET 
            EndTime = GETDATE(),
            Status = 'Failed',
            ErrorMessage = @ErrorMessage
        WHERE BatchID = @BatchID;

        THROW;
    END CATCH
END
GO
