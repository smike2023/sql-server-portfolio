# ETL Pipeline Templates

SQL Server ETL pipeline templates for data warehouse loading.

## Templates

### customer-dimension-load.sql
Customer dimension ETL with SCD Type 2:
- Staging table structure
- Dimension table with history tracking
- Hash-based change detection
- Batch control and logging
- Stored procedure for incremental loads

### sales-fact-load.sql
Sales fact table incremental loading:
- Staging table with validation flags
- Fact table structure
- Date dimension population
- Data validation procedures
- Dimension key lookups
- Error handling and logging

### data-quality-framework.sql
Comprehensive data quality framework:
- Configurable quality rules
- Multiple rule types (completeness, validity, uniqueness, consistency)
- Automated rule execution
- Results tracking and reporting
- Table profiling capabilities

## Architecture

```
Source Systems
     ↓
 [Extract]
     ↓
Staging Tables (stg_*)
     ↓
 [Transform & Validate]
     ↓
Dimension Tables (dim_*)
Fact Tables (fact_*)
     ↓
 [Quality Checks]
     ↓
Data Quality Reports
```

## Usage

1. Create the staging and dimension/fact tables
2. Configure ETL batch control
3. Load data into staging tables
4. Execute ETL stored procedures
5. Run data quality checks

```sql
-- Load customer dimension
EXEC dbo.usp_ETL_LoadCustomerDimension;

-- Load sales fact
EXEC dbo.usp_ETL_LoadSalesFact;

-- Run data quality checks
EXEC dbo.usp_DQ_ExecuteAllRules;
```

## Requirements

- SQL Server 2016 or later
- CREATE TABLE permissions
- EXECUTE permissions on stored procedures
