-- ATENÇÃO: material de referência. Revise o banco, o escopo e os filtros antes de executar comandos destrutivos.

-- Find the last known good date when was DBCC CHECKDB was run on each database
-- Part of the SQL Server DBA Patrick Cecilio at  Cecilio
-- This script uses DBCC DBINFO to retrieve the dbi_dbccLastKnownGood value to determine the date on which DBCC CHECKDB was last successfully
-- run on each database.
-- From

CREATE TABLE #DBInfo
(
    Id INT IDENTITY(1, 1),
    ParentObject VARCHAR(255),
    [Object] VARCHAR(255),
    Field VARCHAR(255),
    [Value] VARCHAR(255)
);

CREATE TABLE #Value
(
    DatabaseName VARCHAR(255),
    LastDBCCCheckDBRunDate VARCHAR(255)
);

EXECUTE dbo.sp_ineachdb @command = 'INSERT INTO #DBInfo Execute (''DBCC DBINFO ( ''''?'''') WITH TABLERESULTS'');
INSERT INTO #Value (DatabaseName) SELECT [Value] FROM #DBInfo WHERE Field IN (''dbi_dbname'');
UPDATE #Value SET LastDBCCCheckDBRunDate = (SELECT TOP 1 [Value] FROM #DBInfo WHERE Field IN (''dbi_dbccLastKnownGood'')) where LastDBCCCheckDBRunDate is NULL;
TRUNCATE TABLE #DBInfo', @suppress_quotename = 1, @exclude_list = 'tempdb';

SELECT DatabaseName,
       LastDBCCCheckDBRunDate,
	   'DBCC CHECKDB(' + DatabaseName + ')' AS DBCCCOmmand
FROM #Value
ORDER BY LastDBCCCheckDBRunDate;

DROP TABLE #DBInfo;
DROP TABLE #Value;
