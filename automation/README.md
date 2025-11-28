# Automation PowerShell Scripts

SQL Server automation and maintenance scripts.

## Scripts

### Index-Maintenance.ps1
Intelligent index maintenance automation:
- Analyzes index fragmentation levels
- Performs REORGANIZE for 10-30% fragmentation
- Performs REBUILD for >30% fragmentation
- Supports online operations
- Detailed logging

**Usage:**
```powershell
.\Index-Maintenance.ps1 -ServerInstance "localhost" -DatabaseName "AdventureWorks"
.\Index-Maintenance.ps1 -ServerInstance "localhost" -DatabaseName "ALL" -FragmentationThreshold 15
```

### Backup-Database.ps1
Comprehensive backup automation:
- Full, differential, and log backups
- Backup compression support
- Checksum verification
- Automatic retention management
- Multi-database support

**Usage:**
```powershell
.\Backup-Database.ps1 -ServerInstance "localhost" -DatabaseName "ALL" -BackupType "Full" -BackupPath "D:\Backups"
.\Backup-Database.ps1 -ServerInstance "localhost" -DatabaseName "MyDB" -BackupType "Log" -BackupPath "D:\Backups" -RetentionDays 14
```

### Server-HealthCheck.ps1
SQL Server health monitoring:
- Connection validation
- Database status check
- Disk space monitoring
- SQL Agent job status
- Backup validation
- Memory usage analysis
- HTML/JSON/Console output

**Usage:**
```powershell
.\Server-HealthCheck.ps1 -ServerInstance "localhost"
.\Server-HealthCheck.ps1 -ServerInstance "localhost" -OutputFormat "HTML" -OutputPath ".\report.html"
```

## Requirements

- PowerShell 5.1 or later
- SqlServer PowerShell module (`Install-Module SqlServer`)
- Appropriate SQL Server permissions
