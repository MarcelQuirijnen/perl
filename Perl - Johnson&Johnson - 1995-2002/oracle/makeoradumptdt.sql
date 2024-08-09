REM ##########################################################################
REM #
REM # make oracle dump in TDT format, containing SMILES and comp_nr
REM #
REM ##########################################################################
REM # RCS ID: 
REM # 	$Id: makeOraDumpTdt.sql,v 1.1 2002/03/06 16:26:23 root Exp $
REM #
REM # RCS History:
REM #	$Log: makeOraDumpTdt.sql,v $
REM #	Revision 1.1  2002/03/06 16:26:23  root
REM #	Initial revision
REM #
REM ##########################################################################


set heading off
set lin 400
set feedback off
set termout off
set echo off
spool &1
select '$SMI<' || rtrim(SMILES,' ') || '>', 
       '$RNR<' || rtrim(COMP_TYPE, ' ') || rtrim(COMP_NR,' ' ) || '>',
       '|'
       from tmc.tb_smiles
       where SMILES <> 'SmilesNotAvailable' and SMILES is not null
       and fp <> 'FingerprintNotAvailable' and fp is not null;
spool off
exit SQL.SQLCODE
