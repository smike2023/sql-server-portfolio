<#
.SYNOPSIS
    Automated database backup script with compression and verification.

.DESCRIPTION
    This script performs full, differential, or log backups with compression,
    checksum verification, and backup file management.

.PARAMETER ServerInstance
    The SQL Server instance name.

.PARAMETER DatabaseName
    The target database name. Use 'ALL' for all user databases.

.PARAMETER BackupType
    Type of backup: Full, Differential, or Log.

.PARAMETER BackupPath
    Directory path for backup files.

.PARAMETER RetentionDays
    Number of days to retain backup files (default: 7).

.PARAMETER Compress
    Enable backup compression (default: $true).

.EXAMPLE
    .\Backup-Database.ps1 -ServerInstance "localhost" -DatabaseName "ALL" -BackupType "Full" -BackupPath "D:\Backups"

.NOTES
    Author: SQL Server Portfolio
    Version: 1.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ServerInstance,

    [Parameter(Mandatory = $true)]
    [string]$DatabaseName,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Full", "Differential", "Log")]
    [string]$BackupType,

    [Parameter(Mandatory = $true)]
    [string]$BackupPath,

    [Parameter(Mandatory = $false)]
    [int]$RetentionDays = 7,

    [Parameter(Mandatory = $false)]
    [bool]$Compress = $true
)

# Import SQL Server module
try {
    Import-Module SqlServer -ErrorAction Stop
}
catch {
    Write-Warning "SqlServer module not found. Install with: Install-Module SqlServer"
    Write-Warning "Attempting to continue without module..."
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }
    
    $logFile = Join-Path $BackupPath "BackupLog_$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $logFile -Value $logMessage
}

function Get-BackupFileName {
    param (
        [string]$Database,
        [string]$Type
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $extension = switch ($Type) {
        "Full" { "bak" }
        "Differential" { "dif" }
        "Log" { "trn" }
    }
    
    return "${Database}_${Type}_${timestamp}.$extension"
}

function Invoke-DatabaseBackup {
    param (
        [string]$Server,
        [string]$Database,
        [string]$Type,
        [string]$Path,
        [bool]$UseCompression
    )

    $fileName = Get-BackupFileName -Database $Database -Type $Type
    $fullPath = Join-Path $Path $fileName

    $backupOptions = @()
    $backupOptions += "CHECKSUM"
    $backupOptions += "STATS = 10"
    
    if ($UseCompression) {
        $backupOptions += "COMPRESSION"
    }

    $withClause = "WITH " + ($backupOptions -join ", ")

    $query = switch ($Type) {
        "Full" { "BACKUP DATABASE [$Database] TO DISK = N'$fullPath' $withClause" }
        "Differential" { "BACKUP DATABASE [$Database] TO DISK = N'$fullPath' $withClause, DIFFERENTIAL" }
        "Log" { "BACKUP LOG [$Database] TO DISK = N'$fullPath' $withClause" }
    }

    try {
        Write-Log "Starting $Type backup of [$Database] to $fullPath"
        $startTime = Get-Date

        Invoke-Sqlcmd -ServerInstance $Server -Database "master" -Query $query -QueryTimeout 7200

        $endTime = Get-Date
        $duration = $endTime - $startTime
        $fileInfo = Get-Item $fullPath
        $sizeMB = [math]::Round($fileInfo.Length / 1MB, 2)

        Write-Log "Backup completed: $fileName (Size: ${sizeMB}MB, Duration: $($duration.ToString('hh\:mm\:ss')))" -Level "SUCCESS"
        
        return @{
            Success = $true
            FileName = $fileName
            SizeMB = $sizeMB
            Duration = $duration
        }
    }
    catch {
        Write-Log "Backup failed for [$Database]: $_" -Level "ERROR"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Remove-OldBackups {
    param (
        [string]$Path,
        [int]$RetentionDays
    )

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $extensions = @("*.bak", "*.dif", "*.trn")
    
    $oldFiles = @()
    foreach ($ext in $extensions) {
        $oldFiles += Get-ChildItem -Path $Path -Filter $ext -File | 
            Where-Object { $_.LastWriteTime -lt $cutoffDate }
    }

    if ($oldFiles.Count -gt 0) {
        Write-Log "Removing $($oldFiles.Count) backup files older than $RetentionDays days"
        
        foreach ($file in $oldFiles) {
            try {
                Remove-Item $file.FullName -Force
                Write-Log "Deleted: $($file.Name)"
            }
            catch {
                Write-Log "Failed to delete $($file.Name): $_" -Level "WARNING"
            }
        }
    }
    else {
        Write-Log "No old backup files to remove"
    }
}

# Main execution
Write-Log "=========================================="
Write-Log "Starting Database Backup Process"
Write-Log "Server: $ServerInstance"
Write-Log "Database: $DatabaseName"
Write-Log "Backup Type: $BackupType"
Write-Log "Backup Path: $BackupPath"
Write-Log "Compression: $Compress"
Write-Log "Retention: $RetentionDays days"
Write-Log "=========================================="

# Ensure backup path exists
if (-not (Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    Write-Log "Created backup directory: $BackupPath"
}

try {
    # Get list of databases to backup
    if ($DatabaseName -eq "ALL") {
        $dbQuery = @"
SELECT name FROM sys.databases 
WHERE database_id > 4 
    AND state_desc = 'ONLINE'
    AND is_read_only = 0
"@
        # For log backups, only include FULL recovery model databases
        if ($BackupType -eq "Log") {
            $dbQuery += " AND recovery_model_desc = 'FULL'"
        }
        
        $databases = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query $dbQuery
    }
    else {
        $databases = @([PSCustomObject]@{ name = $DatabaseName })
    }

    $results = @{
        Total = 0
        Success = 0
        Failed = 0
    }

    foreach ($db in $databases) {
        $results.Total++
        $backupResult = Invoke-DatabaseBackup -Server $ServerInstance -Database $db.name -Type $BackupType -Path $BackupPath -UseCompression $Compress
        
        if ($backupResult.Success) {
            $results.Success++
        }
        else {
            $results.Failed++
        }
    }

    # Cleanup old backups
    Remove-OldBackups -Path $BackupPath -RetentionDays $RetentionDays

    Write-Log "=========================================="
    Write-Log "Backup Process Complete"
    Write-Log "Total Databases: $($results.Total)"
    Write-Log "Successful: $($results.Success)"
    Write-Log "Failed: $($results.Failed)"
    Write-Log "=========================================="

    if ($results.Failed -gt 0) {
        exit 1
    }
}
catch {
    Write-Log "CRITICAL ERROR: $_" -Level "ERROR"
    throw
}
