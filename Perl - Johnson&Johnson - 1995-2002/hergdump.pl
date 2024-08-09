#!/usr/local/bin/perl -w

######
# - dumps CHAROn properties in following format
#   Rno Smiles Clogp ClogpErr Amw Hba Hbd Plogd Cmr max(pka) max(pkb) RotBond
# - input file is a list of Rnos, 1 Rno per line
# - Clogp values >= -60P or 'ClogpNotAvailable' are filtered out
######

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
my (%clogp_val, %cmr_val, %pkb_val) = ((),(),());

######################################
# Start of script
######################################
require DBI;
my $dbh = DBI->connect($ORA_SID, $ORA_R_USER, $ORA_R_PWD, 'Oracle');
croak("Unable to connect to $ORA_SID.\n$DBI::errstr\nTerminated.\n") if ($DBI::err);
STDOUT->autoflush(1);
my ($select, $sth);
my ($key, $smi);
my $RNO_FILE = $ARGV[0] if scalar(@ARGV);		#cmd line arg is a RNO file

if (defined($RNO_FILE)) {
   print "Using Rno file..\n";
   open(RNO, "<$RNO_FILE") || die "could not open $RNO_FILE : $!\n";
   while (<RNO>) {
      chomp;
      $_ = ('0' x ($RNUM_LEN - length($_))) . $_ unless length($_) == $RNUM_LEN;
      $compounds{$_} = 0;				# fill the hash with the required RNOs
   }
   close(RNO);
   $select = $dbh->prepare( q{ SELECT smiles, comp_nr	
                                  from tmc.tb_smiles
                                  where comp_nr = ?
                                }
                             ) || die "Prepare :: DBI::err\n$DBI::errstr\n";
   foreach $key (sort keys %compounds) {		# execute SQL statement for each RNO found
      $select->execute($key) || die "Execute :: $DBI::err\n$DBI::errstr\n";	
      while (($smi, $key) = $select->fetchrow_array) {
      	$compounds{$key} = $smi;
      }
   }			     
} else {			     		     
   print "Using CHAROn DB..\n";
   $select = $dbh->prepare( q{ Select comp_nr, smiles
                               from tmc.tb_smiles
                               where smiles <> 'SmilesNotAvailable'
                               and comp_nr = 10020
                               order by comp_nr
                             }
                          ) || die "Prepare :: DBI::err\n$DBI::errstr\n";
   $select->execute || die "Execute :: $DBI::err\n$DBI::errstr\n";
   while (($key, $smiles) = $select->fetchrow_array) {
      $compounds{$key} = $smiles;
   }
}
   
      ########
      # now get properties
      ########
      $sth = $dbh->prepare( q{
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 1 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 2 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, PROP_ID, MAX(VALUE) VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 5 AND COMP_NR = ?
         GROUP BY COMP_NR, PROP_ID, ERROR_CODE
                               }
                             );
      if ($dbh->err) {
         croak "Error preparing CHARON data retrieval : $DBI::err\n$DBI::errstr\n";
      }  else {
         print "COMP_ID\tSMILES\tCLOGP\tCMR\tMAX(PKB)\tHERG\n";
         foreach $key (sort keys %compounds) {
            $sth->execute($key, $key, $key);
            if ($dbh->err) {
               croak "Error executing CHARON data retrieval : $DBI::err\n$DBI::errstr\n";
            } else {
               # We dont use $comp_nr,$comp_type as yet .. :-)
               LASTROW : while ((undef,$prop_id,$value, $err_code) = $sth->fetchrow_array) {
                  if ($dbh->err) {
                     croak "Error fetching CHARON data : $DBI::err\n$DBI::errstr\n";
                     last LASTROW;
                  } else {
                     RECORD : {
                        if ($prop_id == 1) { $err_code = $1 if $err_code =~ /\-([0-9]{1,}).*/;
                                             $clogp_val{$key} = $value if $err_code < 60; 
                                             last RECORD; 
                                           }
                        if ($prop_id == 2) { $err_code = $1 if $err_code =~ /\-([0-9]{1,}).*/; 
                                             $cmr_val{$key}   = 10*$value if $err_code < 60; 
                                             last RECORD; 
                                           }
                        if ($prop_id == 5) { $pkb_val{$key}   = $value; last RECORD; }
                     } 
                  }
               }
               $herg = 'N';
               $herg = '-' if (!defined($clogp_val{$key}) || !defined($cmr_val{$key}) || !defined($pkb_val{$key}));
               if ($compounds{$key} eq $ERR_SMILESNOTAVAIL) {
                  print "$key\t$compounds{$key}\tNCtNCtNCtNC\n";
               } else {
                  if (defined($clogp_val{$key}) && defined($cmr_val{$key}) && defined($pkb_val{$key})) {
                     $herg = 'Y' if ($cmr_val{$key} < 179.0 &&
                                     $cmr_val{$key} >= 102.55 &&
                                     $clogp_val{$key} >= 3.665 &&
                                     $pkb_val{$key} >= 7.295);
                  }
                  print "$key\t$compounds{$key}";
                  print "\t", defined($clogp_val{$key}) ? $clogp_val{$key} : '-',
                         "\t", defined($cmr_val{$key}) ? $cmr_val{$key} : '-',
                         "\t", defined($pkb_val{$key}) ? $pkb_val{$key} : '-',
                         "\t", $herg;
                  print "\n";
               }
            }
         }
      }
      $dbh->disconnect();
exit 0;
