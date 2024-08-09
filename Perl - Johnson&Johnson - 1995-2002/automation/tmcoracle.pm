##############################################################################
#
# MDC perl library for oracle functions
#
##############################################################################
# RCS ID: 
# 	$Id: TMCOracle.pm,v 1.1 2002/02/12 21:36:24 root Exp $
#
# RCS History:
#	$Log: TMCOracle.pm,v $
#	Revision 1.1  2002/02/12 21:36:24  root
#	Initial revision
#
##############################################################################


package Modules::TMCOracle;

=head1 NAME

Modules::TMCOracle - TMC stuff

=head1 SYNOPSIS

        use Modules::TMCOracle;
	or
	use TMCOracle;

=head1 DESCRIPTION

        follows later

=head1 AUTHOR

Unix Sysmannen (5889)
JRF-IT 2000

=cut

require 5.000;
require Exporter;
@ISA = qw(Exporter);

use Env;
#use DBI;
#use Modules::TMCDefs;
#use Oraperl;

@EXPORT = qw($ORA_SID $ORA_R_USER $ORA_R_PWD $ORA_RW_USER $ORA_RW_PWD $ORA_DBA $ORA_PWD
             $ORA_SCRIPTS SetupOracleEnv SetupOracleEnvJNJ $ORA_SID_JNJ $ORA_DBA_JNJ $ORA_PWD_JNJ
            );

$VERSION = '1.0';
# Oracle users
*ORA_DBA = \'tmc';
*ORA_PWD = \'tmc';
*ORA_DBA_JNJ = \'mdc';
*ORA_PWD_JNJ = \'mdc';
*ORA_R_USER = \'physico_r';
*ORA_R_PWD = \'chem';
*ORA_RW_USER = \'physico_u';
*ORA_RW_PWD = \'chem';

*ORA_SID = \'TMC_S2';
*ORA_SID_JNJ = \'CHAROn';
*ORA_TAB = \'/etc/oratab';
*ORA_TABLESPACE = \'tmc';
*ORA_TABLESPACE_JNJ = \'mdc';

*ORA_BASE = \'/sw/oracle/app/oracle';
$ORA_HOME = $ORA_BASE . '/product/8.1.7';
*ORA_SCRIPTS = \'/usr/local/bin/scripts/oracle';

sub SetupOracleEnvJNJ
{
   $ENV{'ORACLE_BASE'} = $ORA_BASE;
   $ENV{'ORACLE_HOME'} = $ORA_HOME;
   $ENV{'ORACLE_SID'} = $ORA_SID_JNJ;

   @libs = split(/:/, $ENV{'LD_LIBRARY_PATH'});
   $ora = $ENV{'ORACLE_HOME'} . '/lib';
   @ora_libs = grep(/$ora/, @libs);
   unless (scalar(@ora_libs)) {
      $ENV{'LD_LIBRARY_PATH'} = $ENV{'LD_LIBRARY_PATH'} . ':' . $ENV{'ORACLE_HOME'} . '/lib';
   }

   return 0;
}

sub SetupOracleEnv
{
   $ENV{'ORACLE_BASE'} = $ORA_BASE;
   $ENV{'ORACLE_HOME'} = $ORA_HOME;
   $ENV{'ORACLE_SID'} = $ORA_SID;

   @libs = split(/:/, $ENV{'LD_LIBRARY_PATH'});
   $ora = $ENV{'ORACLE_HOME'} . '/lib';
   @ora_libs = grep(/$ora/, @libs);
   unless (scalar(@ora_libs)) {
      $ENV{'LD_LIBRARY_PATH'} = $ENV{'LD_LIBRARY_PATH'} . ':' . $ENV{'ORACLE_HOME'} . '/lib';
   }

   return 0;
}

$| = 1;

1;

