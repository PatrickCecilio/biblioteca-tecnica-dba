-- Check for Instant File Initialization
-- Part of the SQL Server DBA Patrick Cecilio at  Cecilio
-- This script checks the SQL Server database service for this instance to reveal the current status of Instance File Initialisation
-- From:

SELECT @@SERVERNAME AS [Server Name],
       RIGHT(@@version, LEN(@@version) - 3 - CHARINDEX(' ON ', @@VERSION)) AS [OS Info],
       LEFT(@@VERSION, CHARINDEX('-', @@VERSION) - 2) + ' ' + CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(300)) AS [SQL Server Version],
       service_account,
       instant_file_initialization_enabled
FROM sys.dm_server_services
WHERE servicename LIKE 'SQL Server (%';
