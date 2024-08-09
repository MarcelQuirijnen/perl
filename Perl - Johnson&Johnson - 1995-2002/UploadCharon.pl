#!/usr/local/bin/perl
#############################################################
#
# remarks for Tom : 
#       - this routine can be improved by using DBI instead of oraPerl
#       - High level documentation is currently being removed
#         and made available through the portal (EURO, Japan & US)
#         Sorry .. new project management policies
#         Scientists need/want to know about their perl-routines these days
#         without poking around in the code .. WHy not duplicating ? .. beats me
#
require 5.000;

use IO::Handle;
use Time::localtime;
use Env;
use Oraperl;
use Compress::Zlib;
use POSIX qw(strftime setsid getpid waitpid);
use lib "/usr/local/bin/scripts/automation";
use Modules::TMCDefs;
use Modules::TMCSubs;
use Modules::TMCOracle;

use sigtrap qw(die normal-signals error-signals);

($JRF, $MAIL_LIST, $DEBUG, $TEST, $NOMAIL, $TMPSDF) = (1, 'ttabruyn@janbe.jnj.com,tthielem@janbe.jnj.com,mengels@janbe.jnj.com,mquirij1@janbe.jnj.com', 0, 0, 0, '');
#($JRF, $MAIL_LIST, $DEBUG, $TEST, $NOMAIL, $TMPSDF) = (1, 'ttabruyn@janbe.jnj.com,mquirij1@janbe.jnj.com', 1, 1, 1, '');
(%by_comp_nr, %compound_by_comp_nr, %prop) = ((), (), ());
$tmp_file = '/usr/tmp/mol2smi_' . localtime->hour() . '_' . localtime->min() . '.tdt';
my $PID_FILE = '/tmp/propServer.pid';
my $tmp_molcon = "/tmp/molconupload.$$";

my $day = localtime->mday();
$day = ($day < 10) ? (0 . $day) : $day;
my $month = localtime->mon() + 1;
$month = ($month < 10) ? (0 . $month) : $month;
my $startdate = $day . '-' . $month . '-' . (localtime->year() +1900);


sub InitProperties
{
   LogMsg(*LOGFILE, "Initialising property structure...");
   $db = &ora_login($ORA_SID, $ORA_RW_USER, $ORA_RW_PWD);
   if ($? || $ora_errno) {
      LogMsg(*LOGFILE, "Unable to connect to $ORA_SID : $?\n");
      return 1;
   }
   $csr = &ora_open($db, "SELECT PROP_MEMO, PROP_ID from TMC.TB_PROPERTY");
   if ($? || $ora_errno) {
      LogMsg(*LOGFILE, "Couldn't open SQL statement : $! : $ora_errno\n$ora_errstr\n");
      &ora_logoff($db);
      return 1;
   }
   while (($name, $id) = &ora_fetch($csr)) {
      if ($? || $ora_errno) {
         LogMsg(*LOGFILE, "Couldn't fetch property names & values : $! : $ora_errno\n$ora_errstr\n");
         &ora_close($csr);
         &ora_logoff($db);
         return 1;
      }
      $prop{$name} = $id;
   }
   &ora_close($csr);
   &ora_logoff($db);
   LogMsg(*LOGFILE, "Property structure initialised OK...");
  
   if ($DEBUG) {
      $count=0;
      LogMsg(*LOGFILE, "Compound properties\n");
      foreach $key (sort(keys %prop)) {
         LogMsg(*LOGFILE, ' -> ' . "$key = $prop{$key}");
      }
   }
   return 0;
}

#########################################################################
# AMW
# Input : 
#    $SMI<CCOC(=O)C1CN(CC2COc3cccnc3O2)CCC1N4CCCNC4=O>
#    COMP_ID<273054>
#    |
#
# Output :
#    $SMI<CCOC(=O)C1CN(CC2COc3cccnc3O2)CCC1N4CCCNC4=O>
#    AMW<404.52>
#    COMP_ID<273054>
#    |
# Remarks : No error nor version info given back
#########################################################################
sub DoAMW
{
   LogMsg(*LOGFILE, "Calcualting AMW");

   @amw = ExecAmw($tmp_file);

   LogMsg(*LOGFILE, "AMW data available. Noof records : " . $#amw);

   foreach $chunk (@amw) {
      next if $chunk =~ /\$SMIG/;
      next if $chunk =~ /^$/;
      $key = &FindItem($chunk,'COMP_ID');
      next if ! $key;
      $amw = &FindItem($chunk,'AMW');
      $smi = &FindItem($chunk,'\$SMI');
      if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $key = $1;
      } else {
         $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
      }
      if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
         $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
         $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
         $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
      }
      $compound_by_comp_nr{$key}->{PROP_ID} = $prop{'AMW'};
      $compound_by_comp_nr{$key}->{VALUE} = $amw;
      $compound_by_comp_nr{$key}->{ERROR_CODE} = 0;
      $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
      $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
      $compound_by_comp_nr{$key}->{VERSION} = 0;
   }
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %compound_by_comp_nr)) {
         LogMsg(*LOGFILE, "ReadAMW : record " . ++$count . "\n" .
                ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
                ' 'x12 . "SMILES = $smi\n" .
                ' 'x12 . "AMW = $compound_by_comp_nr{$key}->{VALUE}\n" .
                ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{'AMW'};
      }
   }
   &Load_ORA_TB_COMPOUND_PROP($prop{'AMW'});

   LogMsg(*LOGFILE, "Calcualting AMWs done.");
   return 0;
}

#########################################################################
#  PLOGD
#  Input :
#     $SMI<Cc1cc(C)cc(c1)C(=O)N2CCC(CC2Cc3ccccc3)N4CCNCC4>
#     COMP_ID<286674>
#     |
#     $SMI<Cc1cc2nc3n(C)c(C)c(CCN4CCC(CC4Cc5ccccc5)C6c7nc8ccccc8n7CCc9ccccc69)c(=O)n3c2cc1C>
#     COMP_ID<281874>
#     |
#     $SMI<Clc1ccc(cc1)C(=O)c2ccc3NC(=O)CSC(c4cccc(Cl)c4)c3c2>
#     COMP_ID<286670>
#     |
#  Output :
#     PrologD 2.01 Copyright (c) 1992, 1996 CompuDrug Chemistry Ltd.
#     Name                                      lD2 4 6 7 7.40 10
#     286674                                      0.02 0.02 0.02 0.020.02
#     281874                                      5.38 5.38 5.38 5.38 5.38
#     286670                                     -0.50 -0.50 -0.50 -0.50 -0.50
#  Remarks : version number is extracted from first line
#########################################################################
sub DoPLOGD
{
   my @plogd = ();
   my $version;
   my $val = '';
   my $err = 0;

   LogMsg(*LOGFILE, "Calcualting PLOGDs.");

   &SetupDaylightEnv;
   qx { $SMI2MOL -input_format TDT <$tmp_file >/tmp/smi2mol_plogd.sdf 2>/dev/null };
   @plogd = ExecPrologD('-ityp sdf -idfld COMP_ID -det /dev/null -pH 2 5 7 7.4 8 10', '/tmp/smi2mol_plogd.sdf');

   LogMsg(*LOGFILE, "PLOGD data available. Noof records : " . ($#plogd - 1));

   require DBI;
   my $dbh = DBI->connect($ORA_SID, $ORA_RW_USER, $ORA_RW_PWD, 'Oracle');
   croak("Unable to connect to $ORA_SID.\n$DBI::errstr\nTerminated.\n") if ($DBI::err);
   my $delete = $dbh->prepare( q{ DELETE FROM tmc.tb_compound_prop
                                  WHERE comp_nr = ? AND prop_id = ?
                                }
                              );
   foreach $comp (keys %by_comp_nr) {
      $delete->execute($comp, $prop{'PLOGD'});
   }
   $dbh->commit; 

   my $insert = $dbh->prepare( q{ INSERT into tmc.tb_compound_prop(comp_nr, comp_type, prop_id, value, error_code, dt_lu, attrib1_id, attrib1_val, version) values ( ?, 'R', ?, ?, ?, to_date(sysdate), ?, ?, ?)
                                }
                             );
   foreach (@plogd) {
      chomp;
      next if $_ =~ /^Name/;
      (undef, $version) = /^(PrologD)\s+([\d\-\.]+)/ if $_ =~ /^PrologD/;
      next if $_ !~ /^\d+/;
      if (/nan/) {
         ($key, undef) = split(/\s+/, $_, 2);
         $val2 = $val5 = $val7 = $val74 = $val8 = $val10 = '*';
      } else {
         ($key, $val2, $val5, $val7, $val74, $val8, $val10) = split /\s+/;
      }
      next if ! $key;
      if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $key = $1;
      } else {
         $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
      }
 
      $err2 = ($val2 eq '*') ? 99 : 0;
      $err5 = ($val5 eq '*') ? 99 : 0;
      $err7 = ($val7 eq '*') ? 99 : 0;
      $err74 = ($val74 eq '*') ? 99 : 0;
      $err8 = ($val8 eq '*') ? 99 : 0;
      $err10 = ($val10 eq '*') ? 99 : 0;
      $val2 = ($val2 eq '*') ? 0 : $val2;
      $val5 = ($val5 eq '*') ? 0 : $val5;
      $val7 = ($val7 eq '*') ? 0 : $val7;
      $val74 = ($val74 eq '*') ? 0 : $val74;
      $val8 = ($val8 eq '*') ? 0 : $val8;
      $val10 = ($val10 eq '*') ? 0 : $val10;
      foreach $ph (2,5,7,74,8,10) {
         LogMsg(*LOGFILE, "Insert ", $count++," : $key with ${'val'.$ph}, ${'err'.$ph}, $ph, $version\n") if $DEBUG;
         $insert->execute($key, $prop{'PLOGD'}, ${'val'.$ph}, ${'err'.$ph}, $ph, ${'val'.$ph}, $version) || die $dbh->errstr;
         $dbh->commit;
      }
   }
   $dbh->disconnect();
   LogMsg(*LOGFILE, "Calcualting PLOGDs done.");
   return 0;
}

#########################################################################
#  Fingerprints
#  Input :
#    sdf file
#  Output :
#    $FPG<na;fingerprint;4.71;/tmp/mq.tdt;2048,2048,0.30,0/7>
#    |
#    $SMIG<;/sw/daylight/v471/contrib/src/applics/convert/molfiles/mol2smi;4.51-11Dec1997;>
#    |
#    $SMI<Cc1cc(C)cc(c1)C(=O)N2CCC(CC2Cc3ccccc3)N4CCNCC4>
#    FP<...E2G.6..E5+22.V.E..+....U...U.W.cEM.E.....+I2.7.IU.....0....U.E.2.3.E.0c..266.E1UFE.UEU+.22..0...U..
#       U+00U+6E0......6.U.6..E6U....6.5...0.+.U2..+...E...E+U.UE.c7F0........+.8kU2.1.Y0+F0..E..W.2cc62..E..+.
#       U2...U......1+UU.6....E36U.0..6V7c62+7.C.+U..+0.2UB00.....6.E.M01.0E.6.W.+0.k0.M02.7...G..02E2.....U.
#       U..F..+.U...2..+U.006.2...+I0.2+..2...1;2048;218;2048;218;1>
#    COMP_ID<111301>
#    |
#  Remarks :
#########################################################################
sub DoFingerPrint
{
   my $version;
   my @fingerprint = ();
   
   LogMsg(*LOGFILE, "Calcualting Fingerprints");

   ($version, @fingerprint) = ExecFingerPrint("-b $CLUSTERSIZE -c $CLUSTERSIZE -z", $tmp_file);

   LogMsg(*LOGFILE, "FINGERPRINT data available. Noof records : " . ($#fingerprint - 1));

   foreach $chunk (@fingerprint) {
      $key = &FindItem($chunk,'COMP_ID');
      next if !defined($key) || ! length($key);
      if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $key = $1;
      } else {
         $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
      }
      $fp = &FindItem($chunk,'FP');
      $by_comp_nr{$key}->{FP} = ((defined($fp)) ? (length($fp) ? $fp : $ERR_FINGERPRINTNOTAVAIL) : $ERR_FINGERPRINTNOTAVAIL);
   }
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %by_comp_nr)) {
         LogMsg(*LOGFILE, "FINGERPRINT : record " . ++$count . "\n" .
                ' 'x12 . "COMP_NR = $by_comp_nr{$key}->{COMP_NR}\n" .
                ' 'x12 . "SMILES = $by_comp_nr{$key}->{SMILES}\n" .
                ' 'x12 . "FP = $by_comp_nr{$key}->{FP}" ) if $by_comp_nr{$key}->{COMP_NR};
      }
   }

   &Load_ORA_TB_SMILES;

   LogMsg(*LOGFILE, "Calcualting Fingerprints : done.");
   return 0;
}

sub Reaper
{
   local($pid);
   do {
      $pid = waitpid(-1, &POSIX::WNOHANG);
      @childpids = grep { $_ != $pid } @childpids;
   } while($pid > 0);
}

sub TermHandler
{
   if (@childpids) {
      #$len = @childpids;
      kill('TERM', @childpids);
   }
   LogMsg(*LOGFILE, "UploadCharon terminated by TERM signal.");
   close(LOGFILE);
   syslog(LOG_INFO, "UploadCharon terminated by TERM signal.");
   exit(1);
}

sub UpdatePropServer
{
   my (%propInfo, @res) = ((), ());
   my $key;
   my $progpid;

   open(PROPPIDFILE, "<$PID_FILE");
   if ($!) {
      LogMsg(*LOGFILE, "propServer data NOT updated .. server not running.");
      return 1;
   } elsif (! flock (PROPPIDFILE, LOCK_SH | LOCK_NB)) {
      LogMsg(*LOGFILE, "propServer data NOT updated .. server not ready.");
      close(PROPPIDFILE);
      return 1;
   }
   flock (PROPPIDFILE, LOCK_UN); 
   close(PROPPIDFILE);

   foreach $key (sort(keys %by_comp_nr)) {
      $propInfo{$key} = $by_comp_nr{$key}->{FP};
   }
   # we have to fork this task off, since it takes to much time to handle sequentially
   # should I wait somewhere ?

   $SIG{'CHLD'} = "Reaper";
   $SIG{'TERM'} = "TermHandler";

   LogMsg(*LOGFILE, "Forking off propServer update task...");
   if (!($progpid = fork())) {
      @res = ExecCRPS('UPDATE', \%propInfo);
      exit 0;
   }
   push(@childpids, $progpid);
   undef @res;
   undef %propInfo;
   return 0;
}

#########################################################################
#  RuleOfFiveViolation ROFV
#########################################################################
sub DoRofv
{
   my ($rofv, $indicator) = (0,0);
   my ($prop_id, $value,$err_code);
   my ($clogp_val,$hba_val,$hbd_val,$amw_val);

   LogMsg(*LOGFILE, "Calcualting Rofv.");
   require DBI;
   my $dbh = DBI->connect($ORA_SID, $ORA_RW_USER, $ORA_RW_PWD, 'Oracle');
   croak("Unable to connect to $ORA_SID.\n$DBI::errstr\nTerminated.\n") if ($DBI::err);
   # prepare upfront..
   my $select = $dbh->prepare( q{  SELECT prop_id, value, error_code
                                   FROM tmc.tb_compound_prop
                                   WHERE comp_nr = ? AND
                                         prop_id = 1
                                   UNION
                                   SELECT prop_id, value, error_code
                                   FROM tmc.tb_compound_prop
                                   WHERE comp_nr = ? AND
                                         prop_id = 13
                                   UNION
                                   SELECT prop_id, value, error_code
                                   FROM tmc.tb_compound_prop
                                   WHERE comp_nr = ? AND
                                         prop_id = 10
                                   UNION
                                   SELECT prop_id, value, error_code
                                   FROM tmc.tb_compound_prop
                                   WHERE comp_nr = ? AND
                                         prop_id = 11
                                }
                             );
   foreach $key (sort(keys %by_comp_nr)) {
      $rofv = $indicator = 0;
      $select->execute($key, $key, $key, $key) || die $dbh->errstr;
      $clogp_val = $hba_val =  $hbd_val = $amw_val = -99;
      while (($prop_id, $value,$err_code) = $select->fetchrow_array) {
         RECORD : {
            if ($prop_id == 1) { if ($err_code =~ /-(\d+)[\w+\s+]/) {
                                    $err = $1;
                                    $clogp_val = $value if $err < 60;
                                 }
                                 last RECORD;
            }
            if ($prop_id == 10) { $hba_val = $value; last RECORD; }
            if ($prop_id == 11) { $hbd_val = $value; last RECORD; }
            if ($prop_id == 13) { $amw_val = $value; last RECORD; }
         }
      }
      $indicator = ($clogp_val != -99) ? (($amw_val != -99) ? (($hba_val != -99) ? (($hbd_val != -99) ? 0 : 1) : 1) : 1) : 1;
      $rofv += 1 if $clogp_val > 5.0;
      $rofv += 1 if $amw_val > 500.0;
      $rofv += 1 if $hba_val > 10.0;
      $rofv += 1 if $hbd_val > 5.0;

      if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
         $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
         $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
         $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
      }
      $compound_by_comp_nr{$key}->{PROP_ID} = $prop{'ROFV'};
      $compound_by_comp_nr{$key}->{VALUE} = $rofv;
      $compound_by_comp_nr{$key}->{ERROR_CODE} = $indicator;
      $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
      $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
      $compound_by_comp_nr{$key}->{VERSION} = 0;
   }
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %compound_by_comp_nr)) {
         LogMsg(*LOGFILE, "ROFV : record " . ++$count . "\n" .
                ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
                ' 'x12 . "SMILES = $smi\n" .
                ' 'x12 . "ROFV = $compound_by_comp_nr{$key}->{VALUE}\n" .
                ' 'x12 . "INDICATOR = $compound_by_comp_nr{$key}->{ERROR_CODE}\n" .
                ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{'ROFV'};
      }
   }
   $dbh->disconnect();
   &Load_ORA_TB_COMPOUND_PROP($prop{'ROFV'});

   LogMsg(*LOGFILE, "Calculating Rofv done."); 
   return 0;
}

#########################################################################
#  Tpsa
#########################################################################
sub DoTpsa
{
   my $err;
   @tpsa = ();

   LogMsg(*LOGFILE, "Calcualting Tpsa.");
   @tpsa = ExecTpsa('-q -tdt -id COMP_ID', $tmp_file);
   foreach $chunk (@tpsa) {
      chomp($chunk);
      $err = 0;
      (undef, $val, $key, undef, $version) = split(/\s+/, $chunk);
      if ($val eq 'NA') {
         #005164 NA      -99
         ($key, undef, $err) = split(/\s+/, $chunk);
         $val = $version = 0;
      }
      $version = $1 if $version =~ /v([0-9.]+)/;
      next if ! defined $key;
      if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $key = $1;
      } else {
         $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
      }
      if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
         $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
         $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
         $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
      }
      $compound_by_comp_nr{$key}->{PROP_ID} = $prop{'TPSA'};
      $compound_by_comp_nr{$key}->{VALUE} = $val;
      $compound_by_comp_nr{$key}->{ERROR_CODE} = $err;
      $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
      $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
      $compound_by_comp_nr{$key}->{VERSION} = $version;
   }
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %compound_by_comp_nr)) {
         LogMsg(*LOGFILE, "TPSA : record " . ++$count . "\n" .
                ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
                ' 'x12 . "SMILES = $smi\n" .
                ' 'x12 . "TPSA = $compound_by_comp_nr{$key}->{VALUE}\n" .
                ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{'TPSA'};
      }
   }
   &Load_ORA_TB_COMPOUND_PROP($prop{'TPSA'});

   LogMsg(*LOGFILE, "Calcualting Tpsa done.");
   return 0;
}

#########################################################################
#  Flexibility
#########################################################################
sub DoFlexibility
{
   my $err;
   @flex = ();

   LogMsg(*LOGFILE, "Calcualting Flexibility.");
   @flex = ExecFlexibility('-tdt -id COMP_ID', $tmp_file);
   foreach $chunk (@flex) {
      chomp($chunk);
      $err = 0;
      (undef, $val, $key, undef, $version) = split(/\s+/, $chunk);
      if ($val eq 'NA') {
         #005164 NA      -99
         ($key, undef, $err) = split(/\s+/, $chunk);
         $val = $version = 0;
      }
      $version = $1 if $version =~ /v([0-9.]+)/;
      next if ! defined $key;
      if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $key = $1;
      } else {
         $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
      }
      if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
         $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
         $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
         $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
      }
      $compound_by_comp_nr{$key}->{PROP_ID} = $prop{'FLEX'};
      $compound_by_comp_nr{$key}->{VALUE} = $val;
      $compound_by_comp_nr{$key}->{ERROR_CODE} = $err;
      $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
      $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
      $compound_by_comp_nr{$key}->{VERSION} = $version;
   }
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %compound_by_comp_nr)) {
         LogMsg(*LOGFILE, "FLEX : record " . ++$count . "\n" .
                ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
                ' 'x12 . "SMILES = $smi\n" .
                ' 'x12 . "FLEXIBILITY = $compound_by_comp_nr{$key}->{VALUE}\n" .
                ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{'FLEX'};
      }
   }
   &Load_ORA_TB_COMPOUND_PROP($prop{'FLEX'});

   LogMsg(*LOGFILE, "Calcualting Flexibility done.");
   return 0;
}

#########################################################################
#  RotBond
#########################################################################
sub DoRotBond
{
   my $err;
   @rotbond = ();

   LogMsg(*LOGFILE, "Calcualting RotBond.");
   @rotbond = ExecRotBond('-id COMP_ID', $tmp_file);
   foreach $chunk (@rotbond) {
      $err = 0;
      chomp($chunk);
      (undef, $val, $key, undef, $version) = split(/\s+/, $chunk);
      if ($val eq 'NA') {
         ($key, undef, $err) = split(/\s+/, $chunk);
         $val = $version = 0;
      }
      next if ! defined $key;
      if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $key = $1;
      } else {
         $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
      }
      $version = $1 if $version =~ /v([0-9.]+)/;
      if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
         $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
         $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
         $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
      }
      $compound_by_comp_nr{$key}->{PROP_ID} = $prop{'ROTBOND'};
      $compound_by_comp_nr{$key}->{VALUE} = $val;
      $compound_by_comp_nr{$key}->{ERROR_CODE} = $err;
      $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
      $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
      $compound_by_comp_nr{$key}->{VERSION} = $version;
   }
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %compound_by_comp_nr)) {
         LogMsg(*LOGFILE, "ReadRotbond : record " . ++$count . "\n" .
                ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
                ' 'x12 . "SMILES = $smi\n" .
                ' 'x12 . "ROTBOND = $compound_by_comp_nr{$key}->{VALUE}\n" .
                ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{'ROTBOND'};
      }
   }
   &Load_ORA_TB_COMPOUND_PROP($prop{'ROTBOND'});

   LogMsg(*LOGFILE, "Calcualting RotBond done.");
   return 0;
}

#########################################################################
#  PLOGP
#########################################################################
sub DoPLOGP
{
   my $err;
   @plogp = ();

   LogMsg(*LOGFILE, "Calcualting PLOGPs.");

   qx { $SMI2MOL -input_format TDT <$tmp_file >/tmp/smi2mol_plogp.sdf 2>/dev/null };
   @plogp = ExecLogP('PlogP', "-ityp sdf -idfld COMP_ID -det /dev/null", '/tmp/smi2mol_plogp.sdf');

   LogMsg(*LOGFILE, "PLOGP data available. Noof records : " . ($#plogp - 1));

   $_ = $plogp[0];
   $version = $1 if /^PrologP\s+([\d+\.]+)/;
   #$version = 0;
   #unshift(@plogp); unshift(@plogp);

   foreach (@plogp) {
      next if $_ !~ /^\d+/;
      ($key, $logp) = split (/\s+/);
      next if ! $key;
      if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $key = $1;
      } else {
         $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
      }
      $err = ($logp eq '*') ? 99 : 0;
      $logp = ($logp eq '*') ? 0 : $logp;
      if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
         $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
         $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
         $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
      }
      $compound_by_comp_nr{$key}->{PROP_ID} = $prop{'PLOGP'};
      $compound_by_comp_nr{$key}->{VALUE} = $logp;
      $compound_by_comp_nr{$key}->{ERROR_CODE} = $err;
      $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
      $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
      $compound_by_comp_nr{$key}->{VERSION} = $version;
   }
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %compound_by_comp_nr)) {
         LogMsg(*LOGFILE, "ReadPLOGP : record " . ++$count . "\n" .
                ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
                ' 'x12 . "PLOGP = $compound_by_comp_nr{$key}->{VALUE}\n" .
                ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{'PLOGP'};
      }
   }

   &Load_ORA_TB_COMPOUND_PROP($prop{'PLOGP'});

   LogMsg(*LOGFILE, "Calcualting PLOGPs done.");
   return 0;
}


#########################################################################
#  pKa
#  pKb
#########################################################################
sub DoPkaPkb
{
   @results = ();
   my %pka_compounds = (); 
   my %keysfound = ();
   
   LogMsg(*LOGFILE, "Calcualting pKa/pKb");

   require DBI;
   my $dbh = DBI->connect($ORA_SID, $ORA_RW_USER, $ORA_RW_PWD, 'Oracle');
   croak("Unable to connect to $ORA_SID.\n$DBI::errstr\nTerminated.\n") if ($DBI::err);

   my $select = $dbh->prepare( q{ SELECT ATTRIB_ID from TMC.TB_ATTRIB1 where attrib_memo = 'Atom' });
   $select->execute();
   ($Atom_id) = $select->fetchrow_array; 

   my $delete = $dbh->prepare( q{ DELETE FROM tmc.tb_compound_prop
                                  WHERE comp_nr = ? AND (prop_id = 4 or prop_id = 5)
                                }
                              );
   $count = 0;
   foreach $comp (keys %by_comp_nr) {
      $delete->execute($comp);
      $count++;
   }
   $dbh->commit;
   LogMsg(*LOGFILE, "\t$count PKa/PKb records deleted for this batch .. calculating new values.\n") if $DEBUG;

   qx { $SMI2MOL -input_format TDT <$tmp_file >/tmp/smi2mol_pkab.sdf 2>/dev/null };
   @results = ExecPkaPkb('-ityp sdf -idfld COMP_ID -lpKa 0 -hpKa 14 -det /dev/null -vert', '/tmp/smi2mol_pkab.sdf');

   $_ = $results[0];
   $version = /^pKalc\s([0-9\.]+)\s/;
   #$version = 0;
   
   $count=0;
   foreach (@results) {
        next if $_ !~ /^\d+/;
        ($r, $v, $s, $atom) = /^(\d+)\s+([\d\-\.]+)\s(Acid|Base)\s+(\d+)/;
        if ($DEBUG) { 
           print $_, "\n" unless $r;
        }
        next if ! defined($r);

        if ($r =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
           $r = $1;
        } else {
           $r = ('0' x ($RNUM_LEN - length($r))) . $r unless length($r) == $RNUM_LEN;
        }
        
        if (defined($v) && defined($s)) {
           $pka_compounds{$count}->{COMP_NR} = $r;
           $pka_compounds{$count}->{VALUE} = $v;
           $pka_compounds{$count}->{ATTRIB1_ID} = $Atom_id;
           $pka_compounds{$count}->{ATTRIB1_VAL} = $atom;
           $pka_compounds{$count}->{PROP_ID} = 
                ($s eq "Acid") ? $prop{'PKA'} : (($s eq "Base") ? $prop{'PKB'} : $ERR_PKAPKBNOTAVAIL);
           $pka_compounds{$count}->{COMP_TYPE} = $by_comp_nr{$r}->{COMP_TYPE};
           $pka_compounds{$count}->{DT_LU} = $by_comp_nr{$r}->{DT_LU};
           $pka_compounds{$count}->{ERROR_CODE} = 0;
           $pka_compounds{$count}->{VERSION} = $version;

           $count++;
        }
   }

   $count=0;
   foreach $key (sort(keys %pka_compounds)) {
      if ($DEBUG) {
         LogMsg(*LOGFILE, "Read_pKa : record " . $count . "\n" .
                ' 'x12 . "COMP_NR = $pka_compounds{$key}->{COMP_NR}\n" .
                ' 'x12 . (($pka_compounds{$key}->{PROP_ID} == $prop{'PKA'}) ? "pKa = " : "pKb = ") . "$pka_compounds{$key}->{VALUE}\n" .
                ' 'x12 . "ID = $pka_compounds{$key}->{PROP_ID}" .
                ' 'x12 . "AttribID = $pka_compounds{$key}->{ATTRIB1_ID}" .
                ' 'x12 . "AttribVal = $pka_compounds{$key}->{ATTRIB1_VAL}");
      }
        
      # special case upload
      $count++;
      next if $TEST;

      # if this is the first time we encounter this RNR, delete all records that existed for it
      LogMsg(*LOGFILE, "record " . $count . " ...insert : $pka_compounds{$key}->{COMP_NR}") if $DEBUG;

      $insert = $dbh->prepare( q{ INSERT INTO TMC.TB_COMPOUND_PROP (COMP_NR, COMP_TYPE, PROP_ID, VALUE, ERROR_CODE, DT_LU, 
                                                                    ATTRIB1_ID, ATTRIB1_VAL, VERSION)
                                  VALUES ( ?,?,?,?,?, to_date(sysdate), ?,?,?)
                                }
                             );
      $insert->execute($pka_compounds{$key}->{COMP_NR}, $pka_compounds{$key}->{COMP_TYPE},
                       $pka_compounds{$key}->{PROP_ID}, $pka_compounds{$key}->{VALUE}, $pka_compounds{$key}->{ERROR_CODE},
                       $pka_compounds{$key}->{ATTRIB1_ID}, $pka_compounds{$key}->{ATTRIB1_VAL}, $pka_compounds{$key}->{VERSION}
                      ) || die $dbh->errstr;

   }
   $dbh->commit;
   $dbh->disconnect();

   LogMsg(*LOGFILE, "Calcualting pKa/pKb done.");
   return 0;
}

#########################################################################
#  CLOGP
#  CMR
#########################################################################
sub DoCLOGP_CMR
{
   @clogp = ();
   LogMsg(*LOGFILE, "Calcualting CLOGPs");

   $cmr_too = 1;
   @clogp = ExecLogP('ClogP', '-i', $tmp_file, $cmr_too);

   LogMsg(*LOGFILE, "CLOGP data available. Noof records : ", scalar(@clogp));

   # CLOGP

   foreach $chunk (@clogp) {
      next if $chunk =~ /\$SMIG/;
      next if $chunk =~ /^$/;
      $key = &FindItem($chunk,'COMP_ID');
      if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $key = $1;
      } else {
         $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
      }
      if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
         $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
         $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
         $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
      }
      $cp = &FindItem($chunk,'CP');
      ($item, $err, $version) = split(/;/, $cp, 3);
   if ($DEBUG) {
      LogMsg(*LOGFILE, "$key : $item\t$err\t$version");
   }
      $compound_by_comp_nr{$key}->{PROP_ID} = $prop{'CLOGP'};
      $compound_by_comp_nr{$key}->{VALUE} = $item;
      $compound_by_comp_nr{$key}->{VERSION} = $version;
      $compound_by_comp_nr{$key}->{ERROR_CODE} = $err;
      $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
      $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
   } 
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %compound_by_comp_nr)) {
         LogMsg(*LOGFILE, "ReadCLOGP : record " . ++$count . "\n" . 
                ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
                ' 'x12 . "CLOGP = $compound_by_comp_nr{$key}->{VALUE}\n" .
                ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{'CLOGP'};
      }
   }
   &Load_ORA_TB_COMPOUND_PROP($prop{'CLOGP'});

   # CMR

   foreach $chunk (@clogp) {
      next if $chunk =~ /\$SMIG/;
      next if $chunk =~ /^$/;
      $key = &FindItem($chunk,'COMP_ID');
      if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $key = $1;
      } else {
         $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
      }
      if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
         $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
         $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
         $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
      }
      $cp = &FindItem($chunk,'CR');
      ($item, $err, $version) = split(/;/, $cp, 3);
      $compound_by_comp_nr{$key}->{PROP_ID} = $prop{'CMR'};
      $compound_by_comp_nr{$key}->{VALUE} = $item;
      $compound_by_comp_nr{$key}->{VERSION} = $version;
      $compound_by_comp_nr{$key}->{ERROR_CODE} = $err;
      $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
      $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
   } 
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %compound_by_comp_nr)) {
         LogMsg(*LOGFILE, "ReadCMR : record " . ++$count . "\n" .
              ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
              ' 'x12 . "CMR = $compound_by_comp_nr{$key}->{VALUE}\n" .
              ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{'CMR'};
      }
   }
   &Load_ORA_TB_COMPOUND_PROP($prop{'CMR'});

   return 0;
}


#########################################################################
#  Process TDT file
#########################################################################
sub ReadTDT 
{
   $tm = localtime;
   ($DAY, $MONTH, $YEAR) = ($tm->mday, ($tm->mon+1 <10) ? '0'. int($tm->mon+1) : $tm->mon+1, $tm->year+1900);
   local $/ = undef;

   LogMsg(*LOGFILE, "Reading TDTs");
   @chunks_tdt = ExecReadTDT($TDT_FILE);
   LogMsg(*LOGFILE, "I read ", scalar(@chunks_tdt)-1, " TDTs.");
   foreach $chunk (@chunks_tdt) {
      next if $chunk =~ /^\$SMIG/;
      next if $chunk =~ /^\$FPG/;
      $comp_nr = &FindItem($chunk,'\$RNR');
      next if ! length($comp_nr);
      if ($comp_nr =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
         $comp_nr = $1;
      } else {
         $comp_nr = ('0' x ($RNUM_LEN - length($comp_nr))) . $comp_nr unless length($comp_nr) == $RNUM_LEN;
      }
      $by_comp_nr{$comp_nr}->{COMP_NR} = $comp_nr;
      $by_comp_nr{$comp_nr}->{COMP_TYPE} = ($JRF) ? 'R' : 'OC';
      $by_comp_nr{$comp_nr}->{DESCR2} = &FindItem($chunk,'DESC');
      $by_comp_nr{$comp_nr}->{DT_LU} = $DAY . "-" . $MONTH . "-" . $YEAR;
      $by_comp_nr{$comp_nr}->{GN} = &FindItem($chunk,'GN');
      $by_comp_nr{$comp_nr}->{CSRP} = &FindItem($chunk,'CSRP');
      $by_comp_nr{$comp_nr}->{MW} = &FindItem($chunk,'MW');
      $by_comp_nr{$comp_nr}->{MF} = &FindItem($chunk,'MF');
      $by_comp_nr{$comp_nr}->{FP} = $by_comp_nr{$comp_nr}->{ISM} = $by_comp_nr{$comp_nr}->{SMILES} = '';
      $by_comp_nr{$comp_nr}->{SDF} = '';

      if ($DEBUG) {
         LogMsg(*LOGFILE, "Count " . ++$count . " ReadTDT : COMP_ID = ", $by_comp_nr{$comp_nr}->{COMP_NR},"\n",
                "ReadTDT : COMP_TYPE = ", $by_comp_nr{$comp_nr}->{COMP_TYPE}, "\n",
                "ReadTDT : DESCR2 = ", $by_comp_nr{$comp_nr}->{DESCR2}, "\n");
      }
   }
   return 0;
}

#########################################################################
#  Process SDF file
#########################################################################
sub ReadSDF {
   ($DAY, $MONTH, $YEAR) = ($tm->mday, ($tm->mon+1 <10) ? '0'. int($tm->mon+1) : $tm->mon+1, $tm->year+1900);

   LogMsg(*LOGFILE, "Reading SDFs");
   $mol2smi_params = '-output_format TDT -write_2d FALSE -write_3d FALSE';
   if (! ExecMol2Smi($mol2smi_params ,$SDF_FILE, $tmp_file, '/dev/null')) {
      local $/ = undef;
      @chunks_sdf = &ExecReadTDT($tmp_file);
      LogMsg(*LOGFILE, "I read ", scalar(@chunks_sdf) - 2, " converted TDTs (SDFs).");
      foreach $chunk (@chunks_sdf) {
         next if $chunk =~ /^\$SMIG/;
         $comp_id = &FindItem($chunk,'COMP_ID');
         if (!defined($comp_id)) {
            LogMsg(*LOGFILE, "Invalid tag ID. COMP_ID tag not found. Did you play with it?");
            return 1;
         }
         if ($comp_id =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
            $comp_id = $1;
         } else {
            $comp_id = ('0' x ($RNUM_LEN - length($comp_id))) . $comp_id unless length($comp_id) == $RNUM_LEN;
         }
         next if $comp_id == '0' x $RNUM_LEN;
         $smi = &FindItem($chunk,'\$SMI');
         $ism = &FindItem($chunk,'ISM');
         if ( ! defined $by_comp_nr{$comp_id}->{COMP_NR}) {
               LogMsg(*LOGFILE, "Rno $comp_id does not exist : $by_comp_nr{$comp_id}->{COMP_NR}\n") if $DEBUG;
               $by_comp_nr{$comp_id}->{COMP_NR} = $comp_id;
               $by_comp_nr{$comp_id}->{COMP_TYPE} = ($JRF) ? 'R' : 'OC';
               $by_comp_nr{$comp_id}->{GN} = $by_comp_nr{$comp_id}->{FP} = '';
               $by_comp_nr{$comp_id}->{CSRP} = $by_comp_nr{$comp_id}->{MF} = '';
               $by_comp_nr{$comp_id}->{MW} = 0.0;
               $by_comp_nr{$comp_id}->{DT_LU} = $DAY . "-" . $MONTH . "-" . $YEAR;
               $by_comp_nr{$comp_id}->{DESCR2} = '';
               $by_comp_nr{$comp_nr}->{SDF} = '';
         }
         $by_comp_nr{$comp_id}->{SMILES} = (defined($smi)) ? (length($smi) ? $smi : $ERR_SMILESNOTAVAIL) : $ERR_SMILESNOTAVAIL;
         $by_comp_nr{$comp_id}->{ISM} = $ism;
         if ($DEBUG) {
            LogMsg(*LOGFILE, "ReadSDF : COMP_NR = ", 
                   $by_comp_nr{$comp_id}->{COMP_NR}, " SMILES= ", $by_comp_nr{$comp_id}->{SMILES}, 
                   " ISM = ", $by_comp_nr{$comp_id}->{ISM},
                   " MW = ", $by_comp_nr{$comp_id}->{MW}, " MF = ", $by_comp_nr{$comp_id}->{MF},
                   " TYPE = ", $by_comp_nr{$comp_id}->{COMP_TYPE}, " DESCR2 = ", $by_comp_nr{$comp_id}->{DESCR2},
                   " GN = ", $by_comp_nr{$comp_id}->{GN}, " CSRP = ", $by_comp_nr{$comp_id}->{CSRP},
                   " FP = ", $by_comp_nr{$comp_id}->{FP}, " DT_LU = ", $by_comp_nr{$comp_id}->{DT_LU},
                   "\n");
         }
      }
   } else {
      LogMsg(*LOGFILE, "ConvertMol2Smi terminated NOK\n");
      return 1;
   }
   return 0;
}

sub GetCommandLine {
   local @args = @_;
   local ($_, $params);

   $params = '';
   while (@args && ($_ = $args[0])) {
      $params .= ' ' . $_; 
      if (/^-(\w+)/) {
         CASE : {
           if ($1 =~ /^log/) { shift(@args); $params .= ' ' . $args[0]; $LOG = $args[0]; last CASE; }
           if ($1 =~ /^debug/) { $DEBUG = 1; last CASE; }
           if ($1 =~ /^tmpsdf/) { shift(@args); $params .= ' ' . $args[0]; $TMPSDF = $args[0]; last CASE; }
           if ($1 =~ /^test/) { $TEST = 1; last CASE; }
           if ($1 =~ /^jrf/) { $JRF = 1; last CASE; }
           if ($1 =~ /^nomail/) { $NOMAIL = 1; last CASE; }
           if ($1 =~ /^sdf/) { shift(@args); $params .= ' ' . $args[0]; $SDF_FILE = $args[0]; last CASE; }
           if ($1 =~ /^tdt/) { shift(@args); $params .= ' ' . $args[0]; $TDT_FILE = $args[0]; last CASE; }
           if ($1 =~ /^file/) { shift(@args); $params .= ' ' . $args[0]; $TDT_SDF_FILE = $args[0]; last CASE; }
           if ($1 =~ /^dir/) { shift(@args); $params .= ' ' . $args[0]; $CLOGP_DIR = $args[0]; last CASE; }
         }
      } else {
         print "Oops: Unknown option : $_\n";
      }
      shift(@args);
   }
   return $params;
}


sub Load_ORA_TB_SMILES
{
   return 0 if $TEST;
   LogMsg(*LOGFILE, "Load_ORA_TB_SMILES started");
   $db = &ora_login($ORA_SID, $ORA_RW_USER, $ORA_RW_PWD);
   if ($? || $ora_errno) {
      LogMsg(*LOGFILE, "LOGIN ERROR Load_ORA_TB_SMILES : $?\n");
      return 1;
   }
   $select = &ora_open($db, "SELECT COMP_NR from TMC.TB_SMILES WHERE COMP_NR = :1 AND COMP_TYPE = :2");
   if ($? || $ora_errno) {
      LogMsg(*LOGFILE, "SELECT OPEN Error Load_ORA_TB_SMILES : $! : $ora_errno\n$ora_errstr\n");
      &ora_logoff($db);
      return 1;
   }
   $count=0;
   foreach $key (sort(keys %by_comp_nr)) {
      next if (! $key || $key == '0' x $RNUM_LEN);
      next if (! exists $by_comp_nr{$key});
      next if (! defined $by_comp_nr{$key}->{COMP_NR} || $by_comp_nr{$key}->{COMP_NR} == '0' x $RNUM_LEN);
      &ora_bind($select, $key, $by_comp_nr{$key}->{COMP_TYPE});
      if ($? || $ora_errno) {
         LogMsg(*LOGFILE, "SELECT BIND Error Load_ORA_TB_SMILES : $! : $ora_errno\n$ora_errstr\n");
         &ora_close($select);
         &ora_logoff($db);
         return 1;
      }
      @compound_fields = &ora_fetch($select);
      if ($? || $ora_errno) {
         LogMsg(*LOGFILE, "SELECT FETCH Error Load_ORA_TB_SMILES : $! : $ora_errno\n$ora_errstr\n");
         &ora_close($select);
         &ora_logoff($db);
         return 1;
      }
      &ora_close($select);
      if ($#compound_fields == -1) {
         # nothing selected, so this info isn't in db
         LogMsg(*LOGFILE, "Count=" . ++$count . " ...insert : $key") if $DEBUG;
         $insert = &ora_open($db, "INSERT INTO TMC.TB_SMILES (COMP_NR, COMP_TYPE, SMILES, ISM, DESCR2, CSRP, GN, FP, DT_LU, MW, MF, SDF) VALUES (:1, :2, :3, :4, :5, :6, :7, :8, to_date(:9, 'DD-MM-YYYY'), :10, :11, empty_clob())");
         if ($? || $ora_errno) {
            LogMsg(*LOGFILE, "INSERT OPEN Error Load_ORA_TB_SMILES : $! : $ora_errno\n$ora_errstr\n");
            &ora_close($select);
            &ora_logoff($db);
            return 1;
         }
         &ora_bind($insert,  $key, 
                             $by_comp_nr{$key}->{COMP_TYPE}, 
                             length($by_comp_nr{$key}->{SMILES}) ? $by_comp_nr{$key}->{SMILES} : $ERR_SMILESNOTAVAIL, 
                             $by_comp_nr{$key}->{ISM}, 
                             $by_comp_nr{$key}->{DESCR2}, 
                             $by_comp_nr{$key}->{CSRP}, 
                             $by_comp_nr{$key}->{GN}, 
                             length($by_comp_nr{$key}->{FP}) ? $by_comp_nr{$key}->{FP} : $ERR_FINGERPRINTNOTAVAIL, 
                             $DAY . "-" . $MONTH . "-" . $YEAR,
                             $by_comp_nr{$key}->{MW},
                             $by_comp_nr{$key}->{MF});
                             #$by_comp_nr{$key}->{SDF});
         if ($? || $ora_errno) {
            LogMsg(*LOGFILE, "INSERT BIND Error Load_ORA_TB_SMILES : $! : $ora_errno\n$ora_errstr\nRno=$key\n");
            next;
            #&ora_close($insert);
            #&ora_close($select);
            #&ora_logoff($db);
            #return 1;
         }
         &ora_fetch($insert);
         if ($? || $ora_errno) {
            LogMsg(*LOGFILE, "INSERT FETCH Error Load_ORA_TB_SMILES : $! : $ora_errno\n$ora_errstr\n");
            &ora_close($insert);
            &ora_close($select);
            &ora_logoff($db);
            return 1;
         }
         &ora_close($insert);
      } else {
         # querry returned something
         LogMsg(*LOGFILE, "Count=" . ++$count . " ...update : $key") if $DEBUG;
         $update = &ora_open($db, "UPDATE TMC.TB_SMILES set SMILES = :1, ISM = :2, DESCR2 = :3, CSRP = :4, GN = :5, FP = :6, DT_LU = to_date(:7, 'DD-MM-YYYY'), MW = :8, MF = :9, SDF = empty_clob() where COMP_NR = :10 AND COMP_TYPE = :11");
         if ($? || $ora_errno) {
            LogMsg(*LOGFILE, "INSERT OPEN Error Load_ORA_TB_SMILES : $! : $ora_errno\n$ora_errstr\n");
            &ora_close($select);
            &ora_logoff($db);
            return 1;
         }
         &ora_bind($update, length($by_comp_nr{$key}->{SMILES}) ? $by_comp_nr{$key}->{SMILES} : $ERR_SMILESNOTAVAIL, 
                             $by_comp_nr{$key}->{ISM}, 
                            $by_comp_nr{$key}->{DESCR2}, 
                            $by_comp_nr{$key}->{CSRP}, 
                            $by_comp_nr{$key}->{GN}, 
                            length($by_comp_nr{$key}->{FP}) ? $by_comp_nr{$key}->{FP} : $ERR_FINGERPRINTNOTAVAIL, 
                            $DAY . "-" . $MONTH . "-" . $YEAR,
                            $by_comp_nr{$key}->{MW},
                            $by_comp_nr{$key}->{MF},
                            $key, 
                            $by_comp_nr{$key}->{COMP_TYPE});
                            #$by_comp_nr{$key}->{SDF});
         if ($? || $ora_errno) {
            LogMsg(*LOGFILE, "UPDATE BIND Error Load_ORA_TB_SMILES : $! : $ora_errno\n$ora_errstr\nRno=$key\n");
            next;
            #&ora_close($update);
            #&ora_close($select);
            #&ora_logoff($db);
            #return 1;
         }
         &ora_fetch($update);
         if ($? || $ora_errno) {
            LogMsg(*LOGFILE, "UPDATE FETCH Error Load_ORA_TB_SMILES : $! : $ora_errno\n$ora_errstr\n");
            &ora_close($update);
            &ora_close($select);
            &ora_logoff($db);
            return 1;
         }
         &ora_close($update);
      }
   }
   &ora_close($select);
   &ora_logoff($db);
   LogMsg(*LOGFILE, "Load_ORA_TB_SMILES ended");
   return 0;
}

sub Load_ORA_TB_COMPOUND_PROP
{
   local $type = shift;

   return 0 if $TEST;
   return 1 if ! $type;
   LogMsg(*LOGFILE, "Load_ORA_TB_COMPOUND_PROP started for $type");
   $db = &ora_login($ORA_SID, $ORA_RW_USER, $ORA_RW_PWD);
   if ($? || $ora_errno) {
      LogMsg(*LOGFILE, "LOGIN ERROR Load_ORA_TB_COMPOUND_PROP : $?\n");
      return 1;
   }
   $select = &ora_open($db, "SELECT COMP_NR from TMC.TB_COMPOUND_PROP WHERE COMP_NR = :1 AND PROP_ID = :2 and ATTRIB1_VAL = :3 AND ATTRIB1_ID = :4");
   if ($? || $ora_errno) {
      LogMsg(*LOGFILE, "INSERT OPEN Error Load_ORA_TB_COMPOUND_PROP : $! : $ora_errno\n$ora_errstr\n");
      &ora_logoff($db);
      return 1;
   }
   $count=0;
   foreach $key (sort(keys %compound_by_comp_nr)) {
      next if $type != $compound_by_comp_nr{$key}->{PROP_ID};
      next if (! $key || $key == '0' x $RNUM_LEN);
      next if (! exists $compound_by_comp_nr{$key});
      next if (! defined $compound_by_comp_nr{$key}->{COMP_NR} || $compound_by_comp_nr{$key}->{COMP_NR} == '0' x $RNUM_LEN);

      &ora_bind($select, $key, $compound_by_comp_nr{$key}->{PROP_ID}, $compound_by_comp_nr{$key}->{ATTRIB1_VAL}, $compound_by_comp_nr{$key}->{ATTRIB1_ID});
      if ($? || $ora_errno) {
         LogMsg(*LOGFILE, "SELECT BIND Error Load_ORA_TB_COMPOUND_PROP : $! : $ora_errno\n$ora_errstr\n");
         &ora_close($select);
         &ora_logoff($db);
         return 1;
      }
      @compound_fields = &ora_fetch($select);
      if ($? || $ora_errno) {
         LogMsg(*LOGFILE, "SELECT FETCH Error Load_ORA_TB_COMPOUND_PROP : $! : $ora_errno\n$ora_errstr\n");
         &ora_close($select);
         &ora_logoff($db);
         return 1;
      }
      &ora_close($select);
      if ($#compound_fields == -1) {
         # nothing selected, so this info isn't in db
         LogMsg(*LOGFILE, "record " . ++$count . " ...insert : $key") if $DEBUG;
         $insert = &ora_open($db, "INSERT INTO TMC.TB_COMPOUND_PROP (COMP_NR, COMP_TYPE, PROP_ID, VALUE, ERROR_CODE, DT_LU, ATTRIB1_ID, ATTRIB1_VAL, VERSION) VALUES (:1, :2, :3, :4, :5, to_date(:6, 'DD-MM-YYYY'), :7, :8, :9)");
         if ($? || $ora_errno) {
            LogMsg(*LOGFILE, "INSERT OPEN Error Load_ORA_TB_COMPOUND_PROP : $! : $ora_errno\n$ora_errstr\n");
            &ora_logoff($db);
            return 1;
         }
         &ora_bind($insert,  $key, $compound_by_comp_nr{$key}->{COMP_TYPE}, $compound_by_comp_nr{$key}->{PROP_ID}, $compound_by_comp_nr{$key}->{VALUE}, $compound_by_comp_nr{$key}->{ERROR_CODE}, $DAY . "-" . $MONTH . "-" . $YEAR, $compound_by_comp_nr{$key}->{ATTRIB1_ID}, $compound_by_comp_nr{$key}->{ATTRIB1_VAL}, $compound_by_comp_nr{$key}->{VERSION});
         if ($? || $ora_errno) {
            LogMsg(*LOGFILE, "INSERT BIND Error Load_ORA_TB_COMPOUND_PROP : $! : $ora_errno\n$ora_errstr\nRno=$key\n");
            next;
            #&ora_close($insert);
            #&ora_logoff($db);
            #return 1;
         }
         &ora_fetch($insert);
         if ($? || $ora_errno) {
            LogMsg(*LOGFILE, "INSERT FETCH Error Load_ORA_TB_COMPOUND_PROP : $! : $ora_errno\n$ora_errstr\n");
            &ora_close($insert);
            &ora_logoff($db);
            return 1;
         }
         &ora_close($insert);
      } else {
         # querry returned something
            LogMsg(*LOGFILE, "record " . ++$count . " ...update : $key") if $DEBUG;
            $update = &ora_open($db, "UPDATE TMC.TB_COMPOUND_PROP set VALUE = :1, ERROR_CODE = :2, VERSION = :7, DT_LU = to_date(:3, 'DD-MM-YYYY') where COMP_NR = :4 AND PROP_ID = :5 AND ATTRIB1_VAL = :6");
            if ($? || $ora_errno) {
               LogMsg(*LOGFILE, "INSERT OPEN Error Load_ORA_TB_COMPOUND_PROP : $! : $ora_errno\n$ora_errstr\n");
               &ora_logoff($db);
               return 1;
            }
            &ora_bind($update, $compound_by_comp_nr{$key}->{VALUE}, $compound_by_comp_nr{$key}->{ERROR_CODE}, $DAY . "-" . $MONTH . "-" . $YEAR, $key, $compound_by_comp_nr{$key}->{PROP_ID}, $compound_by_comp_nr{$key}->{ATTRIB1_VAL}, $compound_by_comp_nr{$key}->{VERSION});
            if ($? || $ora_errno) {
               LogMsg(*LOGFILE, "UPDATE BIND Error Load_ORA_TB_COMPOUND_PROP : $! : $ora_errno\n$ora_errstr\nRno=$key");
               next;
               #&ora_close($update);
               #&ora_logoff($db);
               #return 1;
            }
            &ora_fetch($update);
            if ($? || $ora_errno) {
               LogMsg(*LOGFILE, "UPDATE FETCH Error Load_ORA_TB_COMPOUND_PROP : $! : $ora_errno\n$ora_errstr\n");
               &ora_close($update);
               &ora_logoff($db);
               return 1;
            }
            &ora_close($update);
      }
   }
   &ora_logoff($db);
   LogMsg(*LOGFILE, "Load_ORA_TB_COMPOUND_PROP ended");
   return 0;
}

sub GetSDFInfo
{
   my @sdffiles = ();
   LogMsg(*LOGFILE, "Retrieving SDF data");
   # if TMPSDF is not set -> SD files aren't split yet .. damn, gotta do it myself
   if (defined($TMPSDF) && length($TMPSDF) > 0) {
      @sdffiles = qx { ls $TMPSDF };
   } else {
      $remove = 1;
      $TMPSDF = '';
      mkdir "/tmp/clogp$$", 0777;
      mkdir "/tmp/clogp$$/sdf", 0777;
      @sdffiles = SplitSDF($SDF_FILE, "/tmp/clogp$$/sdf");
   }
   foreach $tmp_sdffile (@sdffiles) {
      LogMsg(*LOGFILE, "SD file = $tmp_sdffile") if $DEBUG;
      unless(open(TMPSDF, "<$TMPSDF/$tmp_sdffile")) {
         LogMsg(*LOGFILE, "Can't open individual sdf file $tmp_sdffile : $!");
         next;
      }
      @file = ();
      while (<TMPSDF>) {
         push @file, compress($_);
         chomp;
         if (/^[0-9]+/) {
            $rno = $_;
            $rno = ('0' x ($RNUM_LEN - length($rno))) . $_ unless length($rno) == $RNUM_LEN;
         }
      }
      #foreach $line (@file) {
      #   push @sdfile, uncompress($line);
      #}
      #print @sdfile;
      $by_comp_nr{$rno}->{SDF} = join('', @file);
      close(TMPSDF);
      undef @file;
   }
   LogMsg(*LOGFILE, "Noof compressed SD files : ", scalar(@sdffiles));
   qx { rm -r "/tmp/clogp$$" } if $remove;
   LogMsg(*LOGFILE, "Retrieving SDF ended");
   return 0;
}

sub DoTDT_SDF
{
   local $rc = 0;

   $rc = &ReadTDT;
   $rc = &ReadSDF unless $rc;
   $rc = &GetSDFInfo unless $rc;
   return $rc;
}

sub DoSlogPSmr
{
   LogMsg(*LOGFILE, "Calcualting SLOGP/SMR");

   @slogp = ExecLogP('SlogPv2', "-q -s -id 'COMP_ID'", $tmp_file);
   @smr = ExecSmr("-MR -q -s -id 'COMP_ID'", $tmp_file);

   foreach $chunk (@slogp) {
         #chomp($chunk);
         ($key, $val, $err) = split(/\s+/, $chunk);
         if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
            $key = $1;
         } else {
            $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
         }
         if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
            $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
            $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
            $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
         }
         $compound_by_comp_nr{$key}->{PROP_ID} = $prop{'SLOGP'};
         $compound_by_comp_nr{$key}->{VALUE} = $val;
         $compound_by_comp_nr{$key}->{ERROR_CODE} = $err;
         $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
         $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
         $compound_by_comp_nr{$key}->{VERSION} = 0;
   }
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %compound_by_comp_nr)) {
         LogMsg(*LOGFILE, "ReadSLOGP : record " . ++$count . "\n" .
                ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
                ' 'x12 . "SLOGP = $compound_by_comp_nr{$key}->{VALUE}\n" .
                ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{'SLOGP'};
      }
   }
   &Load_ORA_TB_COMPOUND_PROP($prop{'SLOGP'});

   # SMR

   foreach $chunk (@smr) {
         #chomp($chunk);
         ($key, $val, $err) = split(/\s+/, $chunk);
         if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
            $key = $1;
         } else {
            $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
         }
         if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
            $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
            $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
            $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
         }
         $compound_by_comp_nr{$key}->{PROP_ID} = $prop{'SMR'};
         $compound_by_comp_nr{$key}->{VALUE} = $val;
         $compound_by_comp_nr{$key}->{ERROR_CODE} = $err;
         $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
         $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
         $compound_by_comp_nr{$key}->{VERSION} = 0;
   }
   if ($DEBUG) {
      $count=0;
      foreach $key (sort(keys %compound_by_comp_nr)) {
         LogMsg(*LOGFILE, "ReadSMR : record " . ++$count . "\n" .
                ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
                ' 'x12 . "SMR = $compound_by_comp_nr{$key}->{VALUE}\n" .
                ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{'SMR'};
      }
   }
   &Load_ORA_TB_COMPOUND_PROP($prop{'SMR'});

   return 0;
}

sub DoHBond
{
   my $err = 0;
   LogMsg(*LOGFILE, "Calcualting HBa/HBd");

   $version = 0;
   foreach $hb ('HBA', 'HBD') {
      @hb = ExecHBond($hb, "-id 'COMP_ID'", $tmp_file);
      foreach $chunk (@hb) {
         $err = 0;
         chomp($chunk);
         (undef, $val, $key) = split(/\s+/, $chunk);
         if ($val eq 'NA') {
            ($key, undef, $err) = split(/\s+/, $chunk);
            $val = 0;
         }
         next if ! defined $key;
         if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
            $key = $1;
         } else {
            $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
         }
         if ( ! defined $compound_by_comp_nr{$key}->{COMP_NR}) {
            $compound_by_comp_nr{$key}->{COMP_NR} = $by_comp_nr{$key}->{COMP_NR};
            $compound_by_comp_nr{$key}->{COMP_TYPE} = $by_comp_nr{$key}->{COMP_TYPE};
            $compound_by_comp_nr{$key}->{DT_LU} = $by_comp_nr{$key}->{DT_LU};
         }
         $compound_by_comp_nr{$key}->{PROP_ID} = $prop{$hb};
         $compound_by_comp_nr{$key}->{VALUE} = $val;
         $compound_by_comp_nr{$key}->{ERROR_CODE} = 0;
         $compound_by_comp_nr{$key}->{ATTRIB1_ID} = 0;
         $compound_by_comp_nr{$key}->{ATTRIB1_VAL} = 0;
         $compound_by_comp_nr{$key}->{VERSION} = $version;
      }
      if ($DEBUG) {
         $count=0;
         foreach $key (sort(keys %compound_by_comp_nr)) {
            LogMsg(*LOGFILE, 'Read' . $hb . ' : record ' . ++$count . "\n" .
                   ' 'x12 . "COMP_NR = $compound_by_comp_nr{$key}->{COMP_NR}\n" .
                   ' 'x12 . $hb . " = $compound_by_comp_nr{$key}->{VALUE}\n" .
                   ' 'x12 . "ID = $compound_by_comp_nr{$key}->{PROP_ID}") if $compound_by_comp_nr{$key}->{PROP_ID} == $prop{$hb};
         }
      }
      &Load_ORA_TB_COMPOUND_PROP($prop{$hb});
   }
   return 0;
}

sub DoMolconZ
{
  LogMsg(*LOGFILE, "Calcualting Molconn-Z params");
  my $conv = ($JRF) ? '-jrf' : '-jnj';
  LogMsg(*LOGFILE, "/usr/local/bin/scripts/molconZ $conv -sdf $SDF_FILE -Zout $tmp_molcon.S -err $tmp_molcon.err -mail");
  qx { /usr/local/bin/scripts/molconZ $conv -sdf $SDF_FILE -Zout $tmp_molcon.S -err $tmp_molcon.err -mail };
  LogMsg(*LOGFILE, "Uploading Molconn-Z params\n");
  $homedir = (getpwuid($<))[7];
  LogMsg(*LOGFILE, "$homedir/molconUpload.pl $conv -infile $tmp_molcon.S");
  qx { $homedir/molconUpload.pl $conv -infile $tmp_molcon.S };
  unlink "$tmp_molcon" . '*';
  return 0;
}

######################################
# Start of script
######################################
$params = &GetCommandLine(@ARGV);
my $rc = 0;
my @childpids = ();
qx{ umask 1 };

$LOG = '/usr/tmp/ora_upload_' . localtime->hour() . '_' . localtime->min() . '.log' unless defined $LOG;
open(LOGFILE, "+>$LOG") || die "Can't open log file $LOG : $!";
LOGFILE->autoflush(1);

LogMsg(*LOGFILE, "UploadCharon.pl called with params \n $params\n");
LogMsg(*LOGFILE, ($JRF) ? "JRF data types" : "NON-JRF types");

$SDF_FILE = defined($SDF_FILE) ? $SDF_FILE : $CLOGP_DIR . '/' . $TDT_SDF_FILE . '.sdf';
$TDT_FILE = defined($TDT_FILE) ? $TDT_FILE : $CLOGP_DIR . '/' . $TDT_SDF_FILE . '.tdt';

$rc = &InitProperties unless $rc;
$rc = &DoTDT_SDF unless $rc;
$rc = &DoFingerPrint unless $rc;
&UpdatePropServer unless $rc;
#      prop_id = 1
$rc = &DoCLOGP_CMR unless $rc;
#      prop_id = 3
$rc = &DoPLOGP unless $rc;
#      prop_id = 13
$rc = &DoAMW unless $rc;
#      prop_id = 12
$rc = &DoPLOGD unless $rc;
#      prop_id = 4 and 5
$rc = &DoPkaPkb unless $rc;
#      prop_id = 6 and 7
$rc = &DoSlogPSmr unless $rc;
#      prop_id = 10 and 11
$rc = &DoHBond unless $rc;
#      RotBond, prop_id = 15
$rc = &DoRotBond unless $rc;
#      Flexibility, prop_id = 8
$rc = &DoFlexibility unless $rc;
#      Tpsa, prop_id = 9
$rc = &DoTpsa unless $rc;
#      RuleOfFiveViolation, prop_id = 15
$rc = &DoRofv unless $rc;
#      Molconn-Z calculated props
$rc = &DoMolconZ unless $rc;

LogMsg(*LOGFILE, ($rc) ? "Shutdown due to error" : "Normal shutdown");
close(LOGFILE) || die "Close log file $LOG failed : $!"; 

if (! $TEST) {
   qx { /usr/local/bin/scripts/MailMengels.sh $startdate };
}
qx{ /usr/sbin/Mail -s 'UploadCharon.pl logfile' $MAIL_LIST < $LOG } unless $NOMAIL;

END 
{
   qx{ rm -f $tmp_file* $LOG };
   # always exit with zero, so batch calls can be used
   exit 0;
}
