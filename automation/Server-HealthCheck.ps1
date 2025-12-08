<#
.SYNOPSIS
    SQL Server health check and reporting script.

.DESCRIPTION
    Comprehensive health check that validates SQL Server instance health,
    database status, disk space, and critical performance metrics.

.PARAMETER ServerInstance
    The SQL Server instance name.

.PARAMETER OutputFormat
    Output format: Console, HTML, or JSON.

.PARAMETER OutputPath
    Path for HTML or JSON output file.

.PARAMETER EmailReport
    Send report via email (requires SMTP configuration).

.EXAMPLE
    .\Server-HealthCheck.ps1 -ServerInstance "localhost" -OutputFormat "HTML" -OutputPath ".\HealthReport.html"

.NOTES
    Author: SQL Server Portfolio
    Version: 1.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ServerInstance,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Console", "HTML", "JSON")]
    [string]$OutputFormat = "Console",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\HealthReport.html"
)

# Import SQL Server module
try {
    Import-Module SqlServer -ErrorAction Stop
}
catch {
    Write-Warning "SqlServer module not found. Install with: Install-Module SqlServer"
    Write-Warning "Attempting to continue without module..."
}

$healthReport = @{
    ServerName = $ServerInstance
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    OverallStatus = "Healthy"
    Checks = @()
}

function Add-CheckResult {
    param (
        [string]$Category,
        [string]$CheckName,
        [string]$Status,
        [string]$Details,
        [object]$Data = $null
    )

    $script:healthReport.Checks += @{
        Category = $Category
        CheckName = $CheckName
        Status = $Status
        Details = $Details
        Data = $Data
    }

    if ($Status -eq "Critical") {
        $script:healthReport.OverallStatus = "Critical"
    }
    elseif ($Status -eq "Warning" -and $script:healthReport.OverallStatus -ne "Critical") {
        $script:healthReport.OverallStatus = "Warning"
    }
}

function Test-SQLConnection {
    try {
        $query = "SELECT @@SERVERNAME AS ServerName, @@VERSION AS Version"
        $result = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query $query
        Add-CheckResult -Category "Connectivity" -CheckName "SQL Server Connection" -Status "Healthy" -Details "Connected to $($result.ServerName)" -Data $result
        return $true
    }
    catch {
        Add-CheckResult -Category "Connectivity" -CheckName "SQL Server Connection" -Status "Critical" -Details "Failed to connect: $_"
        return $false
    }
}

function Test-DatabaseStatus {
    $query = @"
SELECT 
    name AS DatabaseName,
    state_desc AS State,
    recovery_model_desc AS RecoveryModel,
    user_access_desc AS UserAccess,
    is_read_only AS IsReadOnly
FROM sys.databases
ORDER BY name
"@

    try {
        $databases = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query $query
        
        $offlineDbs = $databases | Where-Object { $_.State -ne "ONLINE" }
        
        if ($offlineDbs.Count -gt 0) {
            Add-CheckResult -Category "Databases" -CheckName "Database Status" -Status "Critical" -Details "$($offlineDbs.Count) database(s) not online" -Data $offlineDbs
        }
        else {
            Add-CheckResult -Category "Databases" -CheckName "Database Status" -Status "Healthy" -Details "All $($databases.Count) databases are online" -Data $databases
        }
    }
    catch {
        Add-CheckResult -Category "Databases" -CheckName "Database Status" -Status "Critical" -Details "Failed to check: $_"
    }
}

function Test-DiskSpace {
    $query = @"
SELECT DISTINCT
    vs.volume_mount_point AS Drive,
    vs.logical_volume_name AS VolumeName,
    CAST(vs.total_bytes / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS TotalGB,
    CAST(vs.available_bytes / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS FreeGB,
    CAST((vs.available_bytes * 100.0 / vs.total_bytes) AS DECIMAL(5,2)) AS FreePercent
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
"@

    try {
        $diskInfo = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query $query
        
        $lowSpaceDisks = $diskInfo | Where-Object { $_.FreePercent -lt 10 }
        $warningDisks = $diskInfo | Where-Object { $_.FreePercent -ge 10 -and $_.FreePercent -lt 20 }
        
        if ($lowSpaceDisks.Count -gt 0) {
            Add-CheckResult -Category "Storage" -CheckName "Disk Space" -Status "Critical" -Details "$($lowSpaceDisks.Count) drive(s) with less than 10% free space" -Data $diskInfo
        }
        elseif ($warningDisks.Count -gt 0) {
            Add-CheckResult -Category "Storage" -CheckName "Disk Space" -Status "Warning" -Details "$($warningDisks.Count) drive(s) with less than 20% free space" -Data $diskInfo
        }
        else {
            Add-CheckResult -Category "Storage" -CheckName "Disk Space" -Status "Healthy" -Details "All drives have adequate free space" -Data $diskInfo
        }
    }
    catch {
        Add-CheckResult -Category "Storage" -CheckName "Disk Space" -Status "Warning" -Details "Failed to check: $_"
    }
}

function Test-SQLAgentJobs {
    $query = @"
SELECT 
    j.name AS JobName,
    j.enabled AS IsEnabled,
    CASE jh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END AS LastRunStatus,
    msdb.dbo.agent_datetime(jh.run_date, jh.run_time) AS LastRunTime,
    jh.message AS LastMessage
FROM msdb.dbo.sysjobs j
LEFT JOIN (
    SELECT job_id, run_status, run_date, run_time, message,
           ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0
) jh ON j.job_id = jh.job_id AND jh.rn = 1
WHERE j.enabled = 1
ORDER BY j.name
"@

    try {
        $jobs = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "msdb" -Query $query
        
        $failedJobs = $jobs | Where-Object { $_.LastRunStatus -eq "Failed" }
        
        if ($failedJobs.Count -gt 0) {
            Add-CheckResult -Category "SQL Agent" -CheckName "Job Status" -Status "Warning" -Details "$($failedJobs.Count) job(s) failed in last run" -Data $failedJobs
        }
        else {
            Add-CheckResult -Category "SQL Agent" -CheckName "Job Status" -Status "Healthy" -Details "All enabled jobs completed successfully" -Data $jobs
        }
    }
    catch {
        Add-CheckResult -Category "SQL Agent" -CheckName "Job Status" -Status "Warning" -Details "Failed to check: $_"
    }
}

function Test-BackupStatus {
    $query = @"
SELECT 
    d.name AS DatabaseName,
    d.recovery_model_desc AS RecoveryModel,
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFullBackup,
    DATEDIFF(DAY, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) AS DaysSinceFull,
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLogBackup,
    DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END), GETDATE()) AS HoursSinceLog
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON d.name = b.database_name
WHERE d.database_id > 4 AND d.state_desc = 'ONLINE'
GROUP BY d.name, d.recovery_model_desc
"@

    try {
        $backups = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query $query
        
        $criticalBackups = $backups | Where-Object { $_.DaysSinceFull -gt 7 -or $null -eq $_.LastFullBackup }
        
        if ($criticalBackups.Count -gt 0) {
            Add-CheckResult -Category "Backups" -CheckName "Backup Status" -Status "Critical" -Details "$($criticalBackups.Count) database(s) with outdated or missing backups" -Data $criticalBackups
        }
        else {
            Add-CheckResult -Category "Backups" -CheckName "Backup Status" -Status "Healthy" -Details "All databases have recent backups" -Data $backups
        }
    }
    catch {
        Add-CheckResult -Category "Backups" -CheckName "Backup Status" -Status "Warning" -Details "Failed to check: $_"
    }
}

function Test-MemoryStatus {
    $query = @"
SELECT 
    physical_memory_kb / 1024 AS PhysicalMemoryMB,
    committed_kb / 1024 AS CommittedMemoryMB,
    committed_target_kb / 1024 AS TargetMemoryMB,
    visible_target_kb / 1024 AS VisibleTargetMB
FROM sys.dm_os_sys_info
"@

    try {
        $memory = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query $query
        
        $memoryUsage = ($memory.CommittedMemoryMB / $memory.TargetMemoryMB) * 100
        
        if ($memoryUsage -gt 95) {
            Add-CheckResult -Category "Performance" -CheckName "Memory Usage" -Status "Warning" -Details "Memory usage at $([math]::Round($memoryUsage, 1))%" -Data $memory
        }
        else {
            Add-CheckResult -Category "Performance" -CheckName "Memory Usage" -Status "Healthy" -Details "Memory usage at $([math]::Round($memoryUsage, 1))%" -Data $memory
        }
    }
    catch {
        Add-CheckResult -Category "Performance" -CheckName "Memory Usage" -Status "Warning" -Details "Failed to check: $_"
    }
}

# Run health checks
Write-Host "Starting SQL Server Health Check for $ServerInstance" -ForegroundColor Cyan
Write-Host "=========================================="

if (Test-SQLConnection) {
    Test-DatabaseStatus
    Test-DiskSpace
    Test-SQLAgentJobs
    Test-BackupStatus
    Test-MemoryStatus
}

# Output results based on format
switch ($OutputFormat) {
    "Console" {
        Write-Host ""
        Write-Host "Health Check Results" -ForegroundColor Cyan
        Write-Host "Overall Status: " -NoNewline
        switch ($healthReport.OverallStatus) {
            "Healthy" { Write-Host $healthReport.OverallStatus -ForegroundColor Green }
            "Warning" { Write-Host $healthReport.OverallStatus -ForegroundColor Yellow }
            "Critical" { Write-Host $healthReport.OverallStatus -ForegroundColor Red }
        }
        Write-Host ""
        
        foreach ($check in $healthReport.Checks) {
            $statusColor = switch ($check.Status) {
                "Healthy" { "Green" }
                "Warning" { "Yellow" }
                "Critical" { "Red" }
            }
            Write-Host "[$($check.Category)] $($check.CheckName): " -NoNewline
            Write-Host $check.Status -ForegroundColor $statusColor
            Write-Host "  $($check.Details)"
            Write-Host ""
        }
    }
    "JSON" {
        $healthReport | ConvertTo-Json -Depth 10 | Out-File $OutputPath
        Write-Host "JSON report saved to: $OutputPath"
    }
    "HTML" {
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>SQL Server Health Report - $ServerInstance</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .healthy { color: green; }
        .warning { color: orange; }
        .critical { color: red; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>SQL Server Health Report</h1>
    <p><strong>Server:</strong> $ServerInstance</p>
    <p><strong>Timestamp:</strong> $($healthReport.Timestamp)</p>
    <p><strong>Overall Status:</strong> <span class="$($healthReport.OverallStatus.ToLower())">$($healthReport.OverallStatus)</span></p>
    
    <table>
        <tr>
            <th>Category</th>
            <th>Check</th>
            <th>Status</th>
            <th>Details</th>
        </tr>
"@
        foreach ($check in $healthReport.Checks) {
            $html += @"
        <tr>
            <td>$($check.Category)</td>
            <td>$($check.CheckName)</td>
            <td class="$($check.Status.ToLower())">$($check.Status)</td>
            <td>$($check.Details)</td>
        </tr>
"@
        }
        
        $html += @"
    </table>
</body>
</html>
"@
        $html | Out-File $OutputPath -Encoding UTF8
        Write-Host "HTML report saved to: $OutputPath"
    }
}

# Return exit code based on status
switch ($healthReport.OverallStatus) {
    "Critical" { exit 2 }
    "Warning" { exit 1 }
    default { exit 0 }
}
