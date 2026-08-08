-- View read-only routing configurations
-- Part of the SQL Server DBA Patrick Cecilio at  Cecilio
-- This script returns information on any read-only routing configurations that have been set up on this instance
-- From

SELECT replica_server_name,
       endpoint_url,
       secondary_role_allow_connections_desc,
       backup_priority,
       read_only_routing_url
FROM sys.availability_replicas;

SELECT replica_id,
       routing_priority,
       read_only_replica_id
FROM sys.availability_read_only_routing_lists;

SELECT dns_name,
       port,
       is_conformant,
       ip_configuration_string_from_cluster
FROM sys.availability_group_listeners;
