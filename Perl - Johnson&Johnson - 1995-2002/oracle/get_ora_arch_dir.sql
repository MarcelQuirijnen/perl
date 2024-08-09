REM ##########################################################################
REM #
REM # determine where oracle keeps its log archive for this instance
REM #
REM ##########################################################################
REM # RCS ID: 
REM # 	$Id: get_ora_arch_dir.sql,v 1.1 2002/02/12 21:25:58 oracle Exp $
REM #
REM # RCS History:
REM #	$Log: get_ora_arch_dir.sql,v $
REM #	Revision 1.1  2002/02/12 21:25:58  oracle
REM #	Initial revision
REM #
REM ##########################################################################


set heading off
set feedback off
set termout off
set echo off
spool &1
select value from v$parameter where name = 'log_archive_dest';
spool off
exit SQL.SQLCODE
