/*
    Database Mirroring Health Check
    Purpose: Monitor database mirroring status and performance
    Author: SQL Server Portfolio
    Compatible: SQL Server 2005-2016 (Deprecated feature)
    Note: Consider migrating to Always On Availability Groups
*/

-- Database Mirroring Status Overview
SELECT 
    DB_NAME(database_id) AS DatabaseName,
    mirroring_role_desc AS Role,
    mirroring_state_desc AS State,
    mirroring_safety_level_desc AS SafetyLevel,
    mirroring_partner_name AS PartnerServer,
    mirroring_partner_instance AS PartnerInstance,
    mirroring_witness_name AS WitnessServer,
    mirroring_witness_state_desc AS WitnessState,
    mirroring_failover_lsn,
    mirroring_connection_timeout,
    mirroring_redo_queue,
    mirroring_redo_queue_type
FROM sys.database_mirroring
WHERE mirroring_guid IS NOT NULL;

-- Mirroring Session Details from DMVs
SELECT 
    dm.database_id,
    DB_NAME(dm.database_id) AS DatabaseName,
    dms.mirroring_state_desc,
    dms.mirroring_role_desc,
    dms.mirroring_role_sequence,
    dm.mirroring_safety_level_desc,
    dm.mirroring_partner_instance,
    dm.mirroring_witness_name
FROM sys.database_mirroring dm
INNER JOIN sys.dm_db_mirroring_connections dmc
    ON dm.database_id = dmc.database_id
CROSS APPLY (
    SELECT TOP 1 
        mirroring_state_desc, 
        mirroring_role_desc,
        mirroring_role_sequence
    FROM sys.database_mirroring 
    WHERE database_id = dm.database_id
) dms
WHERE dm.mirroring_guid IS NOT NULL;

-- Mirroring Performance Monitor
SELECT 
    instance_name AS DatabaseName,
    counter_name,
    cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%Database Mirroring%'
    AND cntr_value > 0
ORDER BY instance_name, counter_name;

-- Mirroring Endpoint Configuration
SELECT 
    name AS EndpointName,
    protocol_desc,
    type_desc,
    state_desc AS EndpointState,
    port,
    is_encryption_enabled,
    encryption_algorithm_desc,
    connection_auth_desc
FROM sys.database_mirroring_endpoints;

-- Migration Recommendation: Always On AG
SELECT 
    'RECOMMENDATION' AS Status,
    DB_NAME(database_id) AS DatabaseName,
    'Database Mirroring is deprecated. Consider migrating to Always On Availability Groups.' AS Recommendation,
    mirroring_role_desc AS CurrentRole,
    mirroring_state_desc AS CurrentState
FROM sys.database_mirroring
WHERE mirroring_guid IS NOT NULL;
