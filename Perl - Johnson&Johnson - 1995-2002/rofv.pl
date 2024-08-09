#!/usr/local/bin/perl
#####################################################################################
# @(#)FILE      : rofv.pl"                                                          #
# @(#)TYPE FILE : Executable perl5 script"                                          #
# @(#)ENVRONMENT: Oracle                                                            #
# @(#)PARAMS    :                                                                   #
#       -sdf    : input file is in SD format                                        #
#       -tdt    : input file is in TDT format                                       #
#       -smi    : input file is in SMI format                                       #
#       -txt    : input file is a txt file comming from PC (Excel interface)        #
#       -rno    : input file is a Rno or compound no list                           #
#       -out    : output file                                                       #
#       -full   : extended record output                                            #
# @(#)AUTHOR    : M. Quirijnen                                     DATE: 05/06/01"  #
# @(#)USAGE     : Calculate Rule Of Five violations"                                #
# @(#)RETURN CODES :                                                                #
#   0  = normal successfull completion                                              #
#   -1 = there was an error                                                         #
#####################################################################################

require 5.000;

use Env;
use Carp;
use FileHandle;
use lib "/usr/local/bin/scripts/automation";
use Modules::TMCDefs;
use Modules::TMCSubs;

use sigtrap qw(die normal-signals error-signals);

my ($JNJ, $JRF, $FULL, $TABLE, $SDF_FILE, $TDT_FILE, $SMI_FILE, $COMPOUND_FILE, $OUT, $TXT_FILE) = (0,1,0,0,'','','','','','');
my ($cleantdt, $tmp_tdt) = (0, '/tmp/tmptdt.' . $$ . '.tdt');
my %compounds = ();
my (%clogp_val, %clogp_err, %amw_val, %hba_val, %hbd_val) = ((),(),(),(),());
my ($rofv, $indicator) = (0,0);
my $fh = *STDOUT;
# on behalf of txt file
my (@heading, @data) = ((),());
my ($ID_COL, $SMILES_COL) = ('ID', 'SMILES');
my ($compound_id, $ID) = ('','');

####
# Determin ROFV value and print it
####
sub RofV
{
   if ($TXT_FILE) {
      push @heading, 'INDICATOR', 'ROFV';
      push @heading, 'CLOGP', 'CLOGP_ERR', 'AMW', 'HBA', 'HBD' if $FULL;
      $first = 0;
      foreach $col (@heading) {
         if (!$first) {
            print $fh $col;
            $first++;
         } else {
            print $fh "\t", $col;
         }
      }
      print $fh "\n";
   }
   foreach $key (keys %compounds) {
      $indicator = defined($clogp_val{$key}) ? (defined($amw_val{$key}) ?
                   (defined($hba_val{$key}) ? (defined($hbd_val{$key}) ? 0 : 1) : 1) : 1) : 1;
      $rofv += 1 if defined($clogp_val{$key}) && $clogp_val{$key} > 5.0;
      $rofv += 1 if defined($amw_val{$key}) && $amw_val{$key} > 500.0;
      $rofv += 1 if defined($hba_val{$key}) && $hba_val{$key} > 10.0;
      $rofv += 1 if defined($hbd_val{$key}) && $hbd_val{$key} > 5.0;
      if ($TABLE) {
         print $fh "$key\t$compounds{$key}\t$indicator\t$rofv";
         if ($FULL) {
            print $fh "\t", defined($clogp_val{$key}) ? $clogp_val{$key} : '', 
                      "\t", defined($clogp_err{$key}) ? $clogp_err{$key} : '', 
                      "\t", defined($amw_val{$key}) ? $amw_val{$key} : '', 
                      "\t", defined($hba_val{$key}) ? $hba_val{$key} : '', 
                      "\t", defined($hbd_val{$key}) ? $hbd_val{$key} : '';
         }
         print $fh "\n";
      } else {
         print $fh '$SMI<', $compounds{$key}, ">\n";
         print $fh 'COMP_ID<', $key, ">\n";
         print $fh 'INDICATOR<', $indicator, ">\n";
         print $fh 'ROFV<', $rofv, ">\n";
         if ($FULL) {
            print $fh 'CLOGP<', defined($clogp_val{$key}) ? $clogp_val{$key} : '', ';', defined($clogp_err{$key}) ? $clogp_err{$key} : '', ">\n";
            print $fh 'AMW<', defined($amw_val{$key}) ? $amw_val{$key} : '', ">\n";
            print $fh 'HBA<', defined($hba_val{$key}) ? $hba_val{$key} : '', ">\n";
            print $fh 'HBD<', defined($hbd_val{$key}) ? $hbd_val{$key} : '', ">\n";
         }
         print $fh "|\n";
      }
      $rofv = $indicator = 0;
   }
}

######################################
# Start of script
######################################
my $rc = 0;
unless (scalar(@ARGV)) {
   die "Usage : $0 [-jnj|jrf] [-id <someID>] -sdf|tdt|rno|smi|txt infile [-out outfile] [-full] [-table] [-h]\n";
} else {
   while (@ARGV && ($_ = $ARGV[0])) {
      if (/^-(\w+)/) {
         CASE : {
              if ($1 =~ /jnj/) { $JNJ = 1; $JRF = 0; last CASE; }
              if ($1 =~ /jrf/) { $JNJ = 0; $JRF = 1; last CASE; }
              if ($1 =~ /^sdf/) { shift(@ARGV); $SDF_FILE = $ARGV[0]; $STATE = 0; last CASE; }
              if ($1 =~ /^tdt/) { shift(@ARGV); $TDT_FILE = $ARGV[0]; $STATE = 1; last CASE; }
              if ($1 =~ /^rno/) { shift(@ARGV); $TDT_FILE = $ARGV[0]; $STATE = 2; last CASE; }
              if ($1 =~ /^smi/) { shift(@ARGV); $SMI_FILE = $ARGV[0]; $STATE = 0; last CASE; }
              if ($1 =~ /^txt/) { shift(@ARGV); $TXT_FILE = $ARGV[0]; $STATE = 0; $TABLE=1; last CASE; }
              if ($1 =~ /^out/) { shift(@ARGV); $OUT = $ARGV[0]; last CASE; }
              if ($1 =~ /^id/)  { shift(@ARGV); $ID = $ARGV[0]; last CASE; }
              if ($1 =~ /^full/) { $FULL = 1; last CASE; }
              if ($1 =~ /^table/) { $TABLE = 1; last CASE; }
              if ($1 =~ /^h/) { die "Usage : $0 [-jrf|jnj] -sdf|tdt|rno|smi|txt infile [-out outfile] [-table] [-full] [-h]\n";
                                last CASE;
                              }
         }
      } else {
         print "Oops: Unknown option : $_\n";
         die "Usage : $0 [-jnj|jrf] [-id <someID>] -sdf|tdt|rno|smi|txt infile [-out outfile] [-table] [-full] [-h]\n";
      }
      shift(@ARGV);
   }
}
croak("InFile is mandatory. Terminated.\n") if ($SDF_FILE eq '' and $TDT_FILE eq '' and $SMI_FILE eq '' and $TXT_FILE eq '');
#croak("Compound type (Rno or JNJ) is mandatory.\n") if (! $JNJ and ! $JRF);
if ($OUT) {
   $fh = FileHandle->new(">$OUT");
}

# we need to convert the inputfile depending on type given..act as if we're a finite state machine
STATE : {
   if ($STATE == 0) {
      $cleantdt = 1;
      if ($SMI_FILE) {
         open(SMI, "<$SMI_FILE") || die "Could not open $SMI_FILE : $!\n";
         open(TDT, "+>$tmp_tdt") || die "Cant open conversionfile $tmp_tdt : $!\n";
         while (<SMI>) {
            chomp;
            ($smi, $comp_nr, undef) = split(/\s+/, $_, 3);
            print TDT '$SMI<', $smi, ">\n";
            print TDT 'COMP_ID<', $comp_nr, ">\n|\n";
         }
         close(SMI);
         close(TDT);
      } elsif ($TXT_FILE) {
         my @tmp = ();
         my ($id_index, $smiles_index) = (-1,-1);
         open(TDT, "+>$tmp_tdt") || die "Cant open conversionfile $tmp_tdt : $!\n";
         open(TXT, "<$TXT_FILE") || die "Could not open $TXT_FILE : $!\n"; 
         while(<TXT>) {
            @tmp = split(/\s+/);
            if ($. == 1) {
               # read heading .. to determine order of fields
               @heading = @tmp;
               # need array index .. so foreach wont do
               for ($x=0; $x < scalar(@heading); $x++) {
                  $id_index = $x if $heading[$x] eq $ID_COL;
                  $smiles_index = $x if $heading[$x] eq $SMILES_COL;
               }
               # now we know at what position our required data is
            } else {
               print TDT '$SMI<', $tmp[$smiles_index], ">\n";
               print TDT 'COMP_ID<', $tmp[$id_index], ">\n|\n";
               # need orig. data for output..so put it away safe
               #push @data, $_;
            }
         }
         close(TXT);
         close (TDT);
      } else {
         # inputfile is SDF file .. convert to TDT (we need smiles field)
         # TDT file is intermediate file .. cleanup when finished with it
         # now do your stuff
         if (length($ID)) {
            $mol2smi_params = '-output_format TDT -write_2d FALSE -write_3d FALSE -id ' . $ID;
         } else {
            $mol2smi_params = '-output_format TDT -write_2d FALSE -write_3d FALSE -id COMP_ID';
         }
         if (ExecMol2Smi($mol2smi_params ,$SDF_FILE, $tmp_tdt, '/dev/null')) {
            unlink $tmp_tdt;
            croak("Could not convert SDF file to TDT file. Terminated");
         }
      }
      $TDT_FILE = $tmp_tdt;
      $STATE++;
      redo;
   }
   if ($STATE == 1) {
      # inputfile has correct format .. now do what you're supposed to do
      # read TDT chunks
      my @chunks_tdt = ();
      @chunks_tdt = ExecReadTDT($TDT_FILE);
      foreach $chunk (@chunks_tdt) {
         chomp($chunk);
         next if $chunk =~ /^\$SMIG/;
         $key = '';
         if (length($ID)) {
            $key = &FindItem($chunk, $ID);
            $compound_id = $ID;
         } else {
            LASTID : foreach $id ('COMP_ID', '\$NAM', '\$RNR') {
               $key = &FindItem($chunk, $id);
               $compound_id = $id;
               last LASTID if length($key);
            }
         }
         $smi = &FindItem($chunk,'\$SMI');
         #$ism = &FindItem($chunk,'ISM');
         $compounds{$key} = $smi;
      }
      # CLOGP
      my @clogp = ();
      @clogp = ExecLogP('ClogP', '-i', $TDT_FILE, 0); 
      foreach $chunk (@clogp) {
         next if $chunk =~ /\$SMIG/;
         next if $chunk =~ /^$/;
         $key = '';
         if (length($ID)) {
            $key = &FindItem($chunk, $ID);
            $compound_id = $ID;
         } else {
            LASTID : foreach $id ('COMP_ID', '\$NAM', '\$RNR') {
               $key = &FindItem($chunk, $id);
               last LASTID if length($key);
            }
         }
         next if ! $key;
         $cp = &FindItem($chunk,'CP');
         next if ! $cp;
         ($value, $err, undef) = split(/;/, $cp, 3);
         $err_lim = $1 if $err =~ /([0-9]{1,})/;
         next if $err_lim >= 60;
         $clogp_val{$key} = $value; $clogp_err{$key} = $err;
      }
      # AMW
      my @amw = ();
      @amw = ExecAmw($TDT_FILE);
      foreach $chunk (@amw) {
         next if $chunk =~ /\$SMIG/;
         next if $chunk =~ /^$/;
         if (length($ID)) {
            $key = &FindItem($chunk, $ID);
            $compound_id = $ID;
         } else {
            LASTID : foreach $id ("$ID", 'COMP_ID', '\$NAM', '\$RNR') {
               $key = &FindItem($chunk, $id);
               last LASTID if length($key);
            }
         }
         next if ! $key;
         $amw = &FindItem($chunk,'AMW');
         next if ! $amw;
         $amw_val{$key} = $amw;
      }
      # HBA & HBD
      my @hb = ();
      foreach $hb ('HBA', 'HBD') {
         @hb = ExecHBond($hb, "-id $compound_id", $TDT_FILE);
         foreach $chunk (@hb) {
            chomp($chunk);
            (undef, $value, $key) = split(/\s+/, $chunk);
            next if ! defined $key;
            next if ! defined $value;
            if ($hb eq 'HBA') {
               $hba_val{$key} = $value;
            } else {
               $hbd_val{$key} = $value;
            }
         }
      }
      &RofV;
      last STATE;
   }
   if ($STATE == 2) {
      # list of compound numbers .. get data from CHAROn
      open(RNOS, "<$TDT_FILE") || die "Could not open $TDT_FILE : $!\n";
      while(<RNOS>) {
         chomp;
         if ($JRF) {
            $key = $1 if /\w*?([0-9]{1,})/;   # get all numeric items
            # we now have numeric part .. if > 6, take only 6 right most chars
            #                             if < 6, padd with zeros (for now)
            if (length($key) > $RNUM_LEN) {
               $key = $1 if $key =~ /[0-9]*([0-9]{$RNUM_LEN})/;
            } else {
               $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
            }
            $compounds{$1} = '' if $key =~ /[0-9]*([0-9]{$RNUM_LEN})/;
         } else {
            $compounds{$1} = '' if /\w*?([0-9]{1,})/;
         }
      }
      close(RNOS);
      require DBI;
      require Modules::TMCOracle;
      my $dbh = DBI->connect($Modules::TMCOracle::ORA_SID, $Modules::TMCOracle::ORA_R_USER, $Modules::TMCOracle::ORA_R_PWD, 'Oracle');
      croak("Unable to connect to $Modules::TMCOracle::ORA_SID.\n$DBI::errstr\nTerminated.\n") if ($DBI::err);
      ########
      # get smiles for output
      ########
      my $sth = $dbh->prepare(q{ SELECT SMILES FROM TMC.TB_SMILES WHERE COMP_NR = ? });
      if ($dbh->err) {
         print "Error preparing CHARON data retrieval : $DBI::err\n$DBI::errstr\n";
         $rc = 1;
      }  else {
         foreach $key (keys %compounds) {
            $sth->execute($key);
            if ($dbh->err) {
               print "Error executing CHARON data retrieval : $DBI::err\n$DBI::errstr\n";
               $rc = 1;
            } else {
               LASTSMILES : while (($smi) = $sth->fetchrow_array) {
                  if ($dbh->err) {
                     print "Error fetching CHARON data : $DBI::err\n$DBI::errstr\n";
                     $rc = 1;
                     last LASTSMILES;
                  } else {
                     $compounds{$key} = $smi;
                  }
               }

            }
         }
      }
      $dbh->disconnect() if $rc;
      croak("Abandoned due to error.\n") if $rc;
      ########
      # now get properties
      ########
         #WHERE PROP_ID = 1 AND 
         #      COMP_NR = ? AND
         #      ERROR_CODE <> ? AND
         #      TRANSLATE(ERROR_CODE,'0123456789 -P', '0123456789') < 60
      $sth = $dbh->prepare(q{
         SELECT COMP_NR, COMP_TYPE, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 1 AND 
               COMP_NR = ? AND
               ERROR_CODE <> ?
         UNION
         SELECT COMP_NR, COMP_TYPE, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 13 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, COMP_TYPE, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 10 AND COMP_NR = ?
         UNION
         SELECT COMP_NR, COMP_TYPE, PROP_ID, VALUE, ERROR_CODE
         FROM TMC.TB_COMPOUND_PROP
         WHERE PROP_ID = 11 AND COMP_NR = ?
                               }
                             );
      if ($dbh->err) {
         print "Error preparing CHARON data retrieval : $DBI::err\n$DBI::errstr\n";
         $rc = 1;
      }  else {
         foreach $key (keys %compounds) {
            $sth->execute($key, $ERR_CLOGPNOTAVAIL, $key, $key, $key);
            #$sth->execute($key, $key, $key, $key);
            if ($dbh->err) {
               print "Error executing CHARON data retrieval : $DBI::err\n$DBI::errstr\n";
               $rc = 1;
            } else {
               # We dont use $comp_nr,$comp_type as yet .. :-)
               LASTROW : while ((undef,undef,$prop_id,$value,$err_code) = $sth->fetchrow_array) {
                  if ($dbh->err) {
                     print "Error fetching CHARON data : $DBI::err\n$DBI::errstr\n";
                     $rc = 1;
                     last LASTROW;
                  } else {
                     RECORD : {
                        if ($prop_id == 1) { if ($err_code =~ /-(\d+)[\w+\s+]/) {
                                                $err = $1; 
                                                if ($err < 60) {
                                                   $clogp_val{$key} = $value; $clogp_err{$key} = $err_code;
                                                }
                                             }
                                             last RECORD;
                                            }
                        if ($prop_id == 10) { $hba_val{$key} = $value; last RECORD; }
                        if ($prop_id == 11) { $hbd_val{$key} = $value; last RECORD; }
                        if ($prop_id == 13) { $amw_val{$key} = $value; last RECORD; }
                     } 
                  }
               }
            }
         }
      }
      $dbh->disconnect();
      croak("Abandoned due to error.\n") if $rc;
      &RofV;
      last STATE;
   }
}
unlink $TDT_FILE if $cleantdt;
exit $rc;
