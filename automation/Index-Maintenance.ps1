<#
.SYNOPSIS
    Automated index maintenance script for SQL Server databases.

.DESCRIPTION
    This script performs intelligent index maintenance by analyzing fragmentation
    levels and executing appropriate reorganize or rebuild operations.

.PARAMETER ServerInstance
    The SQL Server instance name.

.PARAMETER DatabaseName
    The target database name. Use 'ALL' for all user databases.

.PARAMETER FragmentationThreshold
    Minimum fragmentation percentage to trigger maintenance (default: 10).

.PARAMETER RebuildThreshold
    Fragmentation percentage threshold for rebuild vs reorganize (default: 30).

.PARAMETER LogPath
    Path for log file output.

.EXAMPLE
    .\Index-Maintenance.ps1 -ServerInstance "localhost" -DatabaseName "AdventureWorks"

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

    [Parameter(Mandatory = $false)]
    [int]$FragmentationThreshold = 10,

    [Parameter(Mandatory = $false)]
    [int]$RebuildThreshold = 30,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\IndexMaintenance.log"
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
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Write-Host $logMessage
    Add-Content -Path $LogPath -Value $logMessage
}

function Get-FragmentedIndexes {
    param (
        [string]$Server,
        [string]$Database
    )

    $query = @"
SELECT 
    OBJECT_SCHEMA_NAME(ips.[object_id]) AS SchemaName,
    OBJECT_NAME(ips.[object_id]) AS TableName,
    i.name AS IndexName,
    ips.index_id,
    ips.avg_fragmentation_in_percent AS FragmentationPercent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i
    ON ips.[object_id] = i.[object_id] AND ips.index_id = i.index_id
WHERE ips.page_count > 1000
    AND ips.avg_fragmentation_in_percent > $FragmentationThreshold
    AND i.name IS NOT NULL
ORDER BY ips.avg_fragmentation_in_percent DESC
"@

    return Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query $query
}

function Invoke-IndexMaintenance {
    param (
        [string]$Server,
        [string]$Database,
        [object]$Index
    )

    $schemaName = $Index.SchemaName
    $tableName = $Index.TableName
    $indexName = $Index.IndexName
    $fragmentation = $Index.FragmentationPercent

    try {
        if ($fragmentation -ge $RebuildThreshold) {
            $action = "REBUILD"
            $command = "ALTER INDEX [$indexName] ON [$schemaName].[$tableName] REBUILD WITH (ONLINE = ON, SORT_IN_TEMPDB = ON)"
        }
        else {
            $action = "REORGANIZE"
            $command = "ALTER INDEX [$indexName] ON [$schemaName].[$tableName] REORGANIZE"
        }

        Write-Log "Performing $action on [$schemaName].[$tableName].[$indexName] (Fragmentation: $([math]::Round($fragmentation, 2))%)"
        
        Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query $command -QueryTimeout 3600
        
        Write-Log "Successfully completed $action on [$schemaName].[$tableName].[$indexName]"
        return $true
    }
    catch {
        Write-Log "ERROR: Failed to maintain index [$indexName] - $_"
        return $false
    }
}

# Main execution
Write-Log "=========================================="
Write-Log "Starting Index Maintenance"
Write-Log "Server: $ServerInstance"
Write-Log "Database: $DatabaseName"
Write-Log "Fragmentation Threshold: $FragmentationThreshold%"
Write-Log "Rebuild Threshold: $RebuildThreshold%"
Write-Log "=========================================="

try {
    # Get list of databases to process
    if ($DatabaseName -eq "ALL") {
        $dbQuery = "SELECT name FROM sys.databases WHERE database_id > 4 AND state_desc = 'ONLINE'"
        $databases = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database "master" -Query $dbQuery
    }
    else {
        $databases = @([PSCustomObject]@{ name = $DatabaseName })
    }

    $totalIndexes = 0
    $successCount = 0
    $failCount = 0

    foreach ($db in $databases) {
        $currentDb = $db.name
        Write-Log "Processing database: $currentDb"

        $fragmentedIndexes = Get-FragmentedIndexes -Server $ServerInstance -Database $currentDb

        if ($fragmentedIndexes.Count -eq 0) {
            Write-Log "No fragmented indexes found in $currentDb"
            continue
        }

        Write-Log "Found $($fragmentedIndexes.Count) fragmented indexes in $currentDb"

        foreach ($index in $fragmentedIndexes) {
            $totalIndexes++
            $result = Invoke-IndexMaintenance -Server $ServerInstance -Database $currentDb -Index $index
            if ($result) { $successCount++ } else { $failCount++ }
        }
    }

    Write-Log "=========================================="
    Write-Log "Index Maintenance Complete"
    Write-Log "Total Indexes Processed: $totalIndexes"
    Write-Log "Successful: $successCount"
    Write-Log "Failed: $failCount"
    Write-Log "=========================================="
}
catch {
    Write-Log "CRITICAL ERROR: $_"
    throw
}
