/*
    Index Analysis Script
    Purpose: Identify missing indexes and analyze existing index usage
    Author: SQL Server Portfolio
    Compatible: SQL Server 2016+
*/

-- Missing Index Recommendations
SELECT TOP 20
    mig.index_handle,
    mid.database_id,
    DB_NAME(mid.database_id) AS DatabaseName,
    mid.[object_id],
    OBJECT_NAME(mid.[object_id], mid.database_id) AS TableName,
    migs.unique_compiles,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact,
    -- Calculate improvement measure
    (migs.user_seeks + migs.user_scans) * migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) AS ImprovementMeasure,
    -- Generate CREATE INDEX statement
    'CREATE NONCLUSTERED INDEX [IX_' + OBJECT_NAME(mid.[object_id], mid.database_id) + '_' 
        + REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns, ''), ', ', '_'), '[', ''), ']', '') 
        + '] ON ' + mid.[statement] 
        + ' (' + ISNULL(mid.equality_columns, '') 
        + CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ', ' ELSE '' END 
        + ISNULL(mid.inequality_columns, '') + ')' 
        + ISNULL(' INCLUDE (' + mid.included_columns + ')', '') AS CreateIndexStatement
FROM sys.dm_db_missing_index_groups mig
INNER JOIN sys.dm_db_missing_index_group_stats migs
    ON migs.group_handle = mig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details mid
    ON mig.index_handle = mid.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY ImprovementMeasure DESC;

-- Unused Indexes (candidates for removal)
SELECT 
    OBJECT_NAME(i.[object_id]) AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_updates,
    ius.last_user_seek,
    ius.last_user_scan,
    ius.last_user_lookup,
    ius.last_user_update
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats ius
    ON i.[object_id] = ius.[object_id] AND i.index_id = ius.index_id AND ius.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.[object_id], 'IsMSShipped') = 0
    AND i.is_disabled = 0
    AND i.is_hypothetical = 0
    AND i.type > 0 -- Exclude heaps
    AND (ius.user_seeks = 0 AND ius.user_scans = 0 AND ius.user_lookups = 0)
ORDER BY ius.user_updates DESC;

-- Index Fragmentation Analysis
SELECT 
    DB_NAME() AS DatabaseName,
    OBJECT_SCHEMA_NAME(ips.[object_id]) AS SchemaName,
    OBJECT_NAME(ips.[object_id]) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc AS IndexType,
    ips.avg_fragmentation_in_percent AS FragmentationPercent,
    ips.page_count AS PageCount,
    ips.record_count AS RecordCount,
    CASE 
        WHEN ips.avg_fragmentation_in_percent < 5 THEN 'No action needed'
        WHEN ips.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN 'REORGANIZE recommended'
        ELSE 'REBUILD recommended'
    END AS RecommendedAction
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i
    ON ips.[object_id] = i.[object_id] AND ips.index_id = i.index_id
WHERE ips.page_count > 1000 -- Only analyze indexes with significant pages
    AND ips.avg_fragmentation_in_percent > 5
ORDER BY ips.avg_fragmentation_in_percent DESC;
