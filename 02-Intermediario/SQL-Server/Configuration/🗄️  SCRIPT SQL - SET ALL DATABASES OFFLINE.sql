-- Set all databases offline
-- Part of the SQL Server DBA Patrick Cecilio at  Cecilio
-- This script sets all user databases offline - useful if you are going to move all data files to another drive, for instance

EXEC dbo.sp_foreachdb @command = 'ALTER DATABASE ? SET OFFLINE',
                      @user_only = 1;
