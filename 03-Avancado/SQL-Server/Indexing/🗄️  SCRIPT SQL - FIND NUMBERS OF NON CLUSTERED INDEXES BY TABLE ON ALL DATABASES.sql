-- ATENÇÃO: material de referência. Revise o banco, o escopo e os filtros antes de executar comandos destrutivos.

-- Find numbers of non-clustered indexes by table on all databases
-- Part of the SQL Server DBA Patrick Cecilio at  Cecilio
-- This script gives you a per-table count of non-clustered indexes for all databases on an instance, sorted descending by the highest number of indexes.
-- This is helpful when looking for excessive indexing on an instance, after which you can try to identify indexes that are no longer in use, by using:
--		dm_db_index_usage_stats ( Cecilio/blob/main/Indexing/Find%20unused%20indexes%20from%20sys.dm_db_index_usage_stats.sql) and
--		Query Store ( Cecilio/blob/main/Indexing/Find%20unused%20non-clustered%20indexes%20by%20checking%20Query%20Store.sql)
-- Modified from

CREATE TABLE #IndexCounts
(
    NonClusteredIndexCount TINYINT NOT NULL,
    DatabaseName sysname NOT NULL,
    SchemaName sysname NOT NULL,
    TableName sysname NOT NULL
);

INSERT INTO #IndexCounts
EXEC sp_ineachdb 'SELECT COUNT(i.TYPE) IndexCount, DB_NAME(), s.name, o.name
	FROM sys.indexes i
	INNER JOIN sys.objects o ON i.[object_id] = o.[object_id] INNER JOIN sys.schemas s ON o.[schema_id] = s.[schema_id] WHERE o.TYPE IN (''U'')
	AND i.TYPE = 2
	GROUP BY s.name, o.name',
@user_only = 1;

SELECT *
FROM #IndexCounts
ORDER BY NonClusteredIndexCount DESC,
		 DatabaseName,
         SchemaName,
         TableName;

DROP TABLE #IndexCounts;
