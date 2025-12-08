# High Availability Health Checks

SQL Server high availability monitoring and health check scripts.

## Scripts

### alwayson-health-check.sql
Comprehensive Always On Availability Groups monitoring:
- Availability Group overview and configuration
- Replica status and synchronization health
- Database replica synchronization status
- Listener configuration validation
- Synchronization lag alerts
- Cluster health and network information

### log-shipping-monitor.sql
Log shipping status and monitoring:
- Primary server backup status
- Secondary server restore status
- Log shipping job history
- Configuration validation
- Stale log shipping alerts

### mirroring-status.sql
Database mirroring monitoring (deprecated feature):
- Mirroring session status overview
- Mirroring performance metrics
- Endpoint configuration
- Migration recommendations to Always On

### backup-validation.sql
Backup health and recovery readiness:
- Recent backup summary by database
- Missing backup alerts
- Backup size and duration trends
- Backup integrity verification
- Backup job status monitoring

## Usage

Run these scripts regularly to monitor high availability health:

```sql
-- Execute on primary replica
USE master;
GO
-- Run alwayson-health-check.sql
```

## Requirements

- SQL Server 2012+ for Always On scripts
- Appropriate HA features must be configured
- VIEW SERVER STATE permission required
