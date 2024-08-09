#!/usr/local/bin/perl -w

##############################################################################
#
# - dumps CHAROn properties in following format
#   Rno Smiles Clogp ClogpErr Amw Hba Hbd Plogd Cmr min(pka) max(pkb) RotBond
# - input file is a list of Rnos, 1 Rno per line
# - Clogp values >= -60P or 'ClogpNotAvailable' are filtered out
# - Author : M. Quirijnen
#
# 0.2: tom@011220:
#	- changed MAX(PKA) to MIN(PKA) in CHAROn SELECT statement (see
#	  Christophe)
#
##############################################################################
# RCS ID: 
# 	$Id: propdump.pl,v 1.1 2002/03/04 17:00:41 root Exp $
#
# RCS History:
#	$Log: propdump.pl,v $
#	Revision 1.1  2002/03/04 17:00:41  root
#	Initial revision
#
##############################################################################


require 5.000;

use Env;
use Carp;
use FileHandle;
use lib "/usr/local/bin/scripts/automation";
use Modules::TMCDefs;
use Modules::TMCSubs;
use Modules::TMCOracle;

use sigtrap qw(die normal-signals error-signals);

my %compounds = ();
my (%$indic_val, %tpsa_val, %flex_val, %plogp_val, %smr_val, %slogp_val, %clogp_val, %clogp_err, %amw_val, %hba_val, %hbd_val, %plogd_val, %cmr_val, %cmr_err, %pka_val, %pkb_val, %rotbond_val, %rofv_val) = ((),(),(),(),(),(),(),(),(),(),(),(),(),(),(),(),(),());

######################################
# Start of script
######################################
require DBI;
my $dbh = DBI->connect($ORA_SID, $ORA_R_USER, $ORA_R_PWD, 'Oracle');
croak("Unable to connect to $ORA_SID.\n$DBI::errstr\nTerminated.\n") if ($DBI::err);
STDOUT->autoflush(1);
my $rc = 0;
my $RNO_FILE = $ARGV[0] if scalar(@ARGV);
my $select;
my $key;

if (defined($RNO_FILE)) {
   open(RNO, "<$RNO_FILE") || die "could not open $RNO_FILE : $!\n";
   while (<RNO>) {
      chomp;
      $key = $_;
      if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $key = $1;
      } else {
         $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
      }
      $compounds{$key} = 0;
   }
   close(RNO);
   $select = $dbh->prepare( q{ SELECT smiles
                                  from tmc.tb_smiles
                                  where comp_nr = ?
                                }
                             ) || die "Prepare :: DBI::err\n$DBI::errstr\n";
   foreach $key (keys %compounds) {
      $select->execute($key) || die "Execute :: DBI::err\n$DBI::errstr\n";
      while (($smi) = $select->fetchrow_array) {
         $compounds{$key} = $smi;
      }
   }
} else {
   $select = $dbh->prepare( q{ Select smiles, comp_nr
                               from tmc.tb_smiles
                               where smiles <> 'SmilesNotAvailable'
                               order by comp_nr
                             }
                          ) || die "Prepare :: DBI::err\n$DBI::errstr\n";
   $select->execute || die "Execute :: $DBI::err\n$DBI::errstr\n";
   while (($smi, $key) = $select->fetchrow_array) {
      $compounds{$key} = $smi;
   }
}
      ########
      # now get properties
      ########
      $sth = $dbh->prepare(q{
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 1 AND 
               COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 2 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 3 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, MIN(VALUE) VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 4 AND COMP_NR = ?
         GROUP BY COMP_NR, PROP_ID, ERROR_CODE
         UNION
         SELECT COMP_NR, PROP_ID, MAX(VALUE) VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 5 AND COMP_NR = ?
         GROUP BY COMP_NR, PROP_ID, ERROR_CODE
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 6 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 7 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 8 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 9 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 10 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 11 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 12 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 13 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 14 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 15 AND COMP_NR = ?
                               }
                             );
      if ($dbh->err) {
         print "Error preparing CHARON data retrieval : $DBI::err\n$DBI::errstr\n";
         $rc = 1;
      }  else {
         print "COMP_ID\tSMILES\tCLOGP\tCLOGP_ERR\tAMW\tPLOGP\tSLOGP\tSMR\tHBA\tHBD\tPROLOGD\tCMR\tCMR_ERR\tMIN(PKA)\tMAX(PKB)\tROTBOND\tTPSA\tFLEX\tROFV\tINDICATOR\n";
         foreach $key (keys %compounds) {
            $sth->execute($key, $key, $key, $key, $key, $key, $key, $key, $key, $key, $key, $key, $key, $key, $key);
            if ($dbh->err) {
               print "Error executing CHARON data retrieval : $DBI::err\n$DBI::errstr\n";
               $rc = 1;
            } else {
               # We dont use $comp_nr,$comp_type as yet .. :-)
               LASTROW : while ((undef,$prop_id,$value,$err_code) = $sth->fetchrow_array) {
                  if ($dbh->err) {
                     print "Error fetching CHARON data : $DBI::err\n$DBI::errstr\n";
                     $rc = 1;
                     last LASTROW;
                  } else {
                     RECORD : {
                        if ($prop_id == 1) { $clogp_val{$key} = $value; $clogp_err{$key} = $err_code;
                                             last RECORD;
                                            }
                        if ($prop_id == 2) { $cmr_val{$key} = $value; $cmr_err{$key} = $err_code; last RECORD; }
                        if ($prop_id == 3) { $plogp_val{$key} = $value; last RECORD; }
                        if ($prop_id == 4) { $pka_val{$key} = $value; last RECORD; }
                        if ($prop_id == 5) { $pkb_val{$key} = $value; last RECORD; }
                        if ($prop_id == 6) { $slogp_val{$key} = $value; last RECORD; }
                        if ($prop_id == 7) { $smr_val{$key} = $value; last RECORD; }
                        if ($prop_id == 8) { $flex_val{$key} = $value; last RECORD; }
                        if ($prop_id == 9) { $tpsa_val{$key} = $value; last RECORD; }
                        if ($prop_id == 10) { $hba_val{$key} = $value; last RECORD; }
                        if ($prop_id == 11) { $hbd_val{$key} = $value; last RECORD; }
                        if ($prop_id == 12) { $plogd_val{$key} = $value; last RECORD; }
                        if ($prop_id == 13) { $amw_val{$key} = $value; last RECORD; }
                        if ($prop_id == 14) { $rotbond_val{$key} = $value; last RECORD; }
                        if ($prop_id == 15) { $rofv_val{$key} = $value; $indic_val{$key} = $err_code; last RECORD; }
                     } 
                  }
               }
               print "$key\t$compounds{$key}";
               print "\t", defined($clogp_val{$key}) ? $clogp_val{$key} : '',
                      "\t", defined($clogp_err{$key}) ? $clogp_err{$key} : '',
                      "\t", defined($amw_val{$key}) ? $amw_val{$key} : '',
                      "\t", defined($plogp_val{$key}) ? $plogp_val{$key} : '',
                      "\t", defined($slogp_val{$key}) ? $slogp_val{$key} : '',
                      "\t", defined($smr_val{$key}) ? $smr_val{$key} : '',
                      "\t", defined($hba_val{$key}) ? $hba_val{$key} : '',
                      "\t", defined($hbd_val{$key}) ? $hbd_val{$key} : '',
                      "\t", defined($plogd_val{$key}) ? $plogd_val{$key} : '',
                      "\t", defined($cmr_val{$key}) ? $cmr_val{$key} : '',
                      "\t", defined($cmr_err{$key}) ? $cmr_err{$key} : '',
                      "\t", defined($pka_val{$key}) ? $pka_val{$key} : '',
                      "\t", defined($pkb_val{$key}) ? $pkb_val{$key} : '',
                      "\t", defined($rotbond_val{$key}) ? $rotbond_val{$key} : '',
                      "\t", defined($tpsa_val{$key}) ? $tpsa_val{$key} : '',
                      "\t", defined($flex_val{$key}) ? $flex_val{$key} : '',
                      "\t", defined($rofv_val{$key}) ? $rofv_val{$key} : '',
                     "\t", defined($indic_val{$key}) ? $indic_val{$key} : '';
               print "\n";
            }
         }
      }
      $dbh->disconnect();
exit $rc;
