-- When was my SQL Server Database Last Accessed
-- Part of the SQL Server DBA Patrick Cecilio at  Cecilio
-- This script give you the latest date that any index in a database was touched and so indicates when the database was last accessed.
-- Any NULL value for last_user_access indicates that the database hasn’t been accessed since the last SQL Server instance restart.
-- From

SELECT DB_NAME(d.database_id) AS DBName,
       (
           SELECT MAX(value.last_user_access)
           FROM
           (
               VALUES
                   (MAX(last_user_seek)),
                   (MAX(last_user_scan)),
                   (MAX(last_user_lookup))
           ) AS value (last_user_access)
       ) AS last_user_access
FROM sys.dm_db_index_usage_stats ddius
    RIGHT OUTER JOIN sys.databases d
        ON ddius.database_id = d.database_id
GROUP BY DB_NAME(d.database_id)
ORDER BY DBName;
