-- How far has my update got?
-- Part of the SQL Server DBA Patrick Cecilio at  Cecilio
-- This script queries the transaction log and returns the number of rows that have been modified, inserted or deleted by the nominated SPID.
-- It’s worth noting that this script will return the count of all rows that have been affected by the running transaction and not the
-- statement. If your transaction contains a number of statements, the count will be the total number of rows affected so far by all
-- statements that have run and are running.
-- From

DECLARE @SPID INT = <SPID>;

SELECT COUNT(*)
FROM fn_dblog(NULL, NULL)
WHERE Operation IN ( 'LOP_MODIFY_ROW', 'LOP_INSERT_ROWS', 'LOP_DELETE_ROWS' )
      AND Context IN ( 'LCX_HEAP', 'LCX_CLUSTERED' )
      AND [Transaction ID] =
      (
          SELECT fn_dblog.[Transaction ID]
          FROM sys.dm_tran_session_transactions session_trans
              JOIN fn_dblog(NULL, NULL)
                  ON fn_dblog.[Xact ID] = session_trans.transaction_id
          WHERE session_id = @SPID
      );
