REM ##########################################################################
REM #
REM # sql to dump oracle as follows:
REM #	smiles,R999999
REM #
REM ##########################################################################
REM # RCS ID: 
REM # 	$Id: make1-100OraDump.sql,v 1.1 2002/03/06 16:24:37 root Exp $
REM #
REM # RCS History:
REM #	$Log: make1-100OraDump.sql,v $
REM #	Revision 1.1  2002/03/06 16:24:37  root
REM #	Initial revision
REM #
REM ##########################################################################


set heading off
#set lin 400
set feedback off
set termout off
set echo off
spool &1
select rtrim(SMILES,' ') || ',' || rtrim(COMP_TYPE, ' ') || rtrim(COMP_NR,' ' )
       from tmc.tb_smiles
       where SMILES is not null and fp is not null and COMP_NR > 0
       order by COMP_NR;
spool off
exit SQL.SQLCODE
