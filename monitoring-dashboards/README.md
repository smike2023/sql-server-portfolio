# Monitoring Dashboards

SQL Server monitoring queries and alerting configuration.

## Components

### performance-metrics.sql
Real-time performance monitoring:
- CPU utilization over time
- Memory usage breakdown
- Active sessions and requests
- Database I/O statistics
- Top wait types
- Database size and growth
- Connection summary

### instance-health.sql
Server instance health monitoring:
- Server configuration overview
- Instance uptime
- Key configuration settings
- Database states summary
- Error log analysis
- Disk space alerts
- SQL Agent job status
- Backup compliance
- Security audit summary

### alerting-thresholds.sql
Configurable alerting system:
- Alert configuration table
- Alert history tracking
- Default alert thresholds for:
  - CPU usage
  - Memory usage
  - Disk space
  - Blocking
  - Backup compliance
  - Connection count
  - Long-running queries
- Automated alert checking procedure
- Alert summary view

## Dashboard Integration

These queries can be integrated with:
- **Grafana** - Use SQL Server data source
- **Power BI** - Direct query or import mode
- **SSRS** - SQL Server Reporting Services
- **Custom dashboards** - REST API integration

## Usage

### Manual Monitoring
```sql
-- Run performance metrics
:r "performance-metrics.sql"

-- Check instance health
:r "instance-health.sql"

-- Check alerts
EXEC dbo.usp_Monitor_CheckAlerts;
```

### Scheduled Monitoring
Create a SQL Agent job to run `usp_Monitor_CheckAlerts` every 15 minutes.

## Requirements

- SQL Server 2016 or later
- VIEW SERVER STATE permission
- CREATE TABLE permission (for alerting tables)
