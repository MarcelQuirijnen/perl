REM ##########################################################################
REM #
REM # Select all files from database for offline backup
REM #
REM ##########################################################################
REM # RCS ID: 
REM # 	$Id: sel_ora_off.sql,v 1.1 2002/02/12 21:21:38 oracle Exp $
REM #
REM # RCS History:
REM #	$Log: sel_ora_off.sql,v $
REM #	Revision 1.1  2002/02/12 21:21:38  oracle
REM #	Initial revision
REM #
REM ##########################################################################


set pagesize 0
set head off
set feed off
set term off
set echo off
spool &1
select name from v$datafile;
select member from v$logfile;
select name from v$controlfile;
spool off
exit
