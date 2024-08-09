REM ##########################################################################
REM #
REM # change the controlfile for a DB, so the previous one can be backed-up
REM #
REM # note that the control file will be reset to its original value when
REM #	the instance is shutdown and restarted later on in the backup scripts,
REM # 	so we do not need anothe .sql file to set the controlfile back
REM #
REM ##########################################################################
REM # RCS ID: 
REM # 	$Id: backup_ora_ctrlfile.sql,v 1.1 2002/02/12 21:30:26 oracle Exp $
REM #
REM # RCS History:
REM #	$Log: backup_ora_ctrlfile.sql,v $
REM #	Revision 1.1  2002/02/12 21:30:26  oracle
REM #	Initial revision
REM #
REM ##########################################################################


alter database backup controlfile to '&1' reuse;
host sleep 60
alter database backup controlfile to trace noresetlogs;
exit SQL.SQLCODE
