# Performance Tuning Scripts

SQL Server performance analysis and optimization scripts.

## Scripts

### index-analysis.sql
Comprehensive index analysis including:
- Missing index recommendations with CREATE INDEX statements
- Unused index identification for cleanup
- Index fragmentation analysis with recommendations

### query-store-analysis.sql
Query Store performance analysis:
- Top resource-consuming queries
- Regressed queries (plan regression detection)
- Plan instability analysis (queries with multiple plans)
- Query Store configuration status

### wait-statistics.sql
Wait statistics analysis for bottleneck identification:
- Current wait statistics summary with recommendations
- Real-time blocking analysis
- Per-session wait statistics

## Usage

Execute these scripts against your SQL Server database to identify performance bottlenecks and optimization opportunities.

```sql
-- Connect to your database
USE [YourDatabase];
GO

-- Run the analysis scripts
```

## Requirements

- SQL Server 2016 or later
- Query Store must be enabled for query-store-analysis.sql
- VIEW SERVER STATE permission required
