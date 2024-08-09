REM ##########################################################################
REM #
REM # report of general oracle information
REM #
REM ##########################################################################
REM # RCS ID: 
REM # 	$Id: list_ora_diag.sql,v 1.1 2002/02/12 21:23:45 oracle Exp $
REM #
REM # RCS History:
REM #	$Log: list_ora_diag.sql,v $
REM #	Revision 1.1  2002/02/12 21:23:45  oracle
REM #	Initial revision
REM #
REM ##########################################################################


set pagesize 9999
set linesize 132
set termout off
set echo off

spool &1
PROMPT    Dump current date and time list_ora_diag.sql was run

SELECT TO_CHAR
(sysdate, 'Day Month DD, YYYY  HH24:MM:SS')
FROM dual;

PROMPT    Dump database name and version

SELECT *
FROM v$database;

SELECT *
FROM v$version;

PROMPT    Dump system parameter information

SELECT *
FROM v$parameter;

PROMPT    Dump tablespace related information

SELECT tablespace_name, status
FROM sys.dba_tablespaces;

PROMPT    Dump data file related information

SELECT tablespace_name, file_name, status
FROM sys.dba_data_files;

SELECT *
FROM v$datafile;

SELECT *
FROM v$controlfile;

PROMPT    Dump current backup status of any data files

SELECT *
FROM v$backup;

PROMPT    Dump the contents of v$recover_file to check if there are any
PROMPT    entries in this view

SELECT *
FROM v$recover_file;

PROMPT    Dump information about log file(s)

SELECT group#, members, status, archived
FROM v$log;

SELECT *
FROM v$logfile;

SELECT *
FROM v$log_history;

SELECT *
FROM v$recovery_log;

PROMPT    Dump the contents of v$pwfile_users

SELECT *
FROM v$pwfile_users;

spool off;
exit SQL.SQLCODE
