/*
    Always On Availability Groups Health Check
    Purpose: Monitor and validate Always On AG configuration and health
    Author: SQL Server Portfolio
    Compatible: SQL Server 2012+
*/

-- Availability Group Overview
SELECT 
    ag.name AS AGName,
    ag.automated_backup_preference_desc AS BackupPreference,
    ag.failure_condition_level,
    ag.health_check_timeout,
    ags.primary_replica,
    ags.primary_recovery_health_desc,
    ags.secondary_recovery_health_desc,
    ags.synchronization_health_desc
FROM sys.availability_groups ag
INNER JOIN sys.dm_hadr_availability_group_states ags
    ON ag.group_id = ags.group_id;

-- Replica Status Details
SELECT 
    ag.name AS AGName,
    ar.replica_server_name,
    ar.availability_mode_desc,
    ar.failover_mode_desc,
    ar.session_timeout,
    ar.primary_role_allow_connections_desc,
    ar.secondary_role_allow_connections_desc,
    ar.backup_priority,
    ars.role_desc AS CurrentRole,
    ars.operational_state_desc,
    ars.connected_state_desc,
    ars.synchronization_health_desc,
    ars.recovery_health_desc,
    ars.last_connect_error_description,
    ars.last_connect_error_timestamp
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar
    ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_availability_replica_states ars
    ON ar.replica_id = ars.replica_id
ORDER BY ag.name, ar.replica_server_name;

-- Database Replica Status
SELECT 
    ag.name AS AGName,
    ar.replica_server_name,
    db.name AS DatabaseName,
    drs.is_local,
    drs.is_primary_replica,
    drs.synchronization_state_desc,
    drs.synchronization_health_desc,
    drs.database_state_desc,
    drs.is_suspended,
    drs.suspend_reason_desc,
    drs.log_send_queue_size,
    drs.log_send_rate,
    drs.redo_queue_size,
    drs.redo_rate,
    drs.last_sent_time,
    drs.last_received_time,
    drs.last_hardened_time,
    drs.last_redone_time,
    drs.last_commit_time,
    drs.secondary_lag_seconds
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar
    ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_database_replica_states drs
    ON ar.replica_id = drs.replica_id
INNER JOIN sys.databases db
    ON drs.database_id = db.database_id
ORDER BY ag.name, ar.replica_server_name, db.name;

-- Listener Configuration
SELECT 
    ag.name AS AGName,
    agl.dns_name AS ListenerName,
    agl.port AS ListenerPort,
    agl.is_conformant,
    aglip.ip_address,
    aglip.ip_subnet_mask,
    aglip.state_desc AS IPState,
    aglip.is_dhcp
FROM sys.availability_groups ag
INNER JOIN sys.availability_group_listeners agl
    ON ag.group_id = agl.group_id
INNER JOIN sys.availability_group_listener_ip_addresses aglip
    ON agl.listener_id = aglip.listener_id;

-- Synchronization Lag Alert (Secondary replicas behind more than 5 seconds)
SELECT 
    ag.name AS AGName,
    ar.replica_server_name,
    db.name AS DatabaseName,
    drs.secondary_lag_seconds,
    drs.log_send_queue_size AS LogSendQueueKB,
    drs.redo_queue_size AS RedoQueueKB,
    'WARNING: Secondary is lagging' AS AlertMessage
FROM sys.availability_groups ag
INNER JOIN sys.availability_replicas ar
    ON ag.group_id = ar.group_id
INNER JOIN sys.dm_hadr_database_replica_states drs
    ON ar.replica_id = drs.replica_id
INNER JOIN sys.databases db
    ON drs.database_id = db.database_id
WHERE drs.is_primary_replica = 0
    AND drs.secondary_lag_seconds > 5;

-- Cluster Health Summary
SELECT 
    member_name,
    member_type_desc,
    member_state_desc,
    number_of_quorum_votes
FROM sys.dm_hadr_cluster_members;

-- Cluster Network Information
SELECT 
    member_name,
    network_subnet_ip,
    network_subnet_ipv4_mask,
    network_subnet_prefix_length,
    is_public,
    is_ipv4
FROM sys.dm_hadr_cluster_networks;
