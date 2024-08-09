REM ##########################################################################
REM #
REM # determine directory where oracle keeps its udump for this instance
REM #
REM ##########################################################################
REM # RCS ID: 
REM # 	$Id: get_ora_dump_dest.sql,v 1.1 2002/02/12 21:25:01 oracle Exp $
REM #
REM # RCS History:
REM #	$Log: get_ora_dump_dest.sql,v $
REM #	Revision 1.1  2002/02/12 21:25:01  oracle
REM #	Initial revision
REM #
REM ##########################################################################


set pagesize 0
set heading off
set feedback off
set termout off
set echo off
spool &1
select value from v$parameter where name = 'user_dump_dest';
spool off
exit SQL.SQLCODE
