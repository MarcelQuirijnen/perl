REM ##########################################################################
REM #
REM # Check wether database is in archivelog mode or not
REM #
REM ##########################################################################
REM # RCS ID: 
REM # 	$Id: check_ora_archivemode.sql,v 1.1 2002/02/12 21:28:27 oracle Exp $
REM #
REM # RCS History:
REM #	$Log: check_ora_archivemode.sql,v $
REM #	Revision 1.1  2002/02/12 21:28:27  oracle
REM #	Initial revision
REM #
REM ##########################################################################


set pagesize 0
set heading off
set feedback off
set echo off
select log_mode from v$database;
exit SQL.SQLCODE
