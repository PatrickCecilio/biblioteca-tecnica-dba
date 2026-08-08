-- ATENÇÃO: material de referência. Revise o banco, o escopo e os filtros antes de executar comandos destrutivos.

-- Find databases with LEGACY_CARDINALITY_ESTIMATION turned on
-- Part of the SQL Server DBA Patrick Cecilio at  Cecilio
-- This script lists databases that have the LEGACY_CARDINALITY_ESTIMATION property enabled

CREATE TABLE #dbs
(
    [dbname] sysname NOT NULL,
    value SQL_VARIANT NOT NULL
);

INSERT INTO #dbs
EXEC sp_ineachdb 'SELECT DB_NAME(DB_ID()), value FROM sys.database_scoped_configurations WHERE name = ''LEGACY_CARDINALITY_ESTIMATION'' AND value = 1';

SELECT dbname AS DatabaseName, 'USE ' + dbname + '; ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF' AS CommandToTurnOff
FROM #dbs;

DROP TABLE #dbs;
