#!/usr/local/bin/perl -w

######
# - dumps CHAROn properties in following format
# - input file is a list of Rnos, 1 Rno per line
# - Clogp values >= -60P or 'ClogpNotAvailable' are filtered out
######

require 5.000;

use Env;
use Carp;
use FileHandle;
use DBI;
use lib "/usr/local/bin/scripts/automation";
use Modules::TMCDefs;
use Modules::TMCSubs;
use Modules::TMCOracle;

use sigtrap qw(die normal-signals error-signals);

my %compounds = ();
my @molcontables = ('MZ1', 'MZ2_3', 'MZ4', 'MZ5', 'MZ6_7', 'MZ8', 'MZ9_14', 'MZ15_21', 'MZ22_28', 'MZ29_34', 'MZ35', 'MZ36', 'MZ37_39', 'MZ40', 'MZ41_43', 'MZ44_46');


######################################
# Start of script
######################################
my $dbh = DBI->connect($ORA_SID, $ORA_R_USER, $ORA_R_PWD, 'Oracle');
croak("Unable to connect to $ORA_SID.\n$DBI::errstr\nTerminated.\n") if ($DBI::err);
STDOUT->autoflush(1);
my $select;

if ($ARGV[0]) {
   open(RNO, "<$ARGV[0]") || die "could not open $ARGV[0] : $!\n";
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
   $select = $dbh->prepare( q{ SELECT smiles from tmc.tb_smiles where comp_nr = ? }) || die "Prepare :: DBI::err\n$DBI::errstr\n";
   foreach $key (keys %compounds) {
      $select->execute($key) || die "Execute :: DBI::err\n$DBI::errstr\n";
      while (($smi) = $select->fetchrow_array) {
         $compounds{$key} = $smi;
      }
   }
} else {
   $select = $dbh->prepare( q{ Select smiles, comp_nr from tmc.tb_smiles where smiles <> 'SmilesNotAvailable' order by comp_nr });
   $select->execute || die "Execute :: $DBI::err-$DBI::errstr\n";
   while (($smi, $key) = $select->fetchrow_array) {
      $compounds{$key} = $smi;
   }
}
# get Molcon data
foreach $table (@molcontables) {
   $cols = $dbh->prepare("select column_name from SYS.dba_tab_columns where table_name=?");
   $cols->execute(uc($table));
   while (@row = $cols->fetchrow_array) {
      next if $row[0] =~ /COMP_/;
      push @{'columns'.$table}, $row[0];
   }
}
foreach $table (sort { $a cmp $b } @molcontables) {
   $header="ID\tSMILES\t";
   foreach $col (@{'columns'.$table}) {
      $header .= ($col . "\t") if $col ne 'COMP_NR' && $col ne 'COMP_TYPE';
   }
   print $header, "\n";
   foreach $key (keys %compounds) {
      $select_str = 'SELECT * FROM TMC.' . $table . ' WHERE COMP_NR = ?';
      $molcon = $dbh->prepare($select_str) || die $dbh->errstr;
      $molcon->execute($key) || die $dbh->errstr;
      @{'row'.$table} = $molcon->fetchrow_array;
      print "$key\t$compounds{$key}\t";
      $line = '';
      shift@{'row'.$table};
      shift@{'row'.$table};
      foreach $row (@{'row'.$table}) {
         $line .= ($row . "\t");
      }
      print "$line\n";
   }
   print "\n";
}
$dbh->disconnect();
