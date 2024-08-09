#!/usr/local/bin/perl
######################################################################################################################
# @(#)FILE      : CalcProps"                                                                                         #
# @(#)TYPE FILE : Executable perl5 script"                                                                           #
# @(#)ENVRONMENT: Daylight + Molconn-Z"                                                                              #
# @(#)EXECUTE   : usage:\t$0 -f inputfile [-k keyInfo] [-p all|prop_list] [-i IdFieldName]                           #
# @(#)PARAMS    :                                                                                                    #
#       -f inputfile   : input file is in SD format                                                                  #
#                        Either 1. lines of smiles strings (CCCCNCC) .. -k smiles                                    #
#                               2. lines of id and smiles strings (123 CCCCNCC) .. -k id                             #
#                               3. SD file .. -k sdf                                                                 #
#                               4. TDT file .. -k tdt                                                                #
#       -k keyInfo       : inputfile is in smiles|id|sdf|tdt format, '-k id' is default                              #
#       -i IdFieldName   : only used with SD or TDT filetypes to identify the compound id line, 'COMP_ID' is default #       
#       -p all|prop_list : calculate all know properties (-p all = default) or those specified                       #
#                           prop_list : comma separated list of properties, not case sensitive                       #
#                           CLOGP(cmr incl),PLOGP,AMW,PLOGD,PK,SLOGP(smr incl),HB,ROTBOND,FLEX,TPSA,ROFV             #
# @(#)AUTHOR    : M. Quirijnen                                     DATE: 05/01/01"                                   #
# @(#)USAGE     : Calculate chemical parameters using the Molconn-Z environment"                                     #
# @(#)Molconn-Z file format :                                                                                        #
#           CCOC(=O)N1CCc2c(C1)c(=O)[nH]c3ccccc23 R0027725                                                           #
#           CCOC(=O)N1CCc2c(C1)c(=O)c3ccccc23 R0027726                                                               #
# @(#)RETURN CODES :                                                                                                 #
#   0  = normal successfull completion                                                                               #
#   -1 = there was an error                                                                                          #
######################################################################################################################
require 5.000;

use IO::Handle;
use FileHandle;
use Time::localtime;
use Env;
use Carp;
use Getopt::Std;
use lib "/usr/local/bin/scripts/automation";
use Modules::TMCDefs;
use Modules::TMCSubs;

use sigtrap qw(die normal-signals error-signals);

my (%Id, %ClogP, %Cmr, %PlogP, %Amw, %PlogD, %Pka, %Pkb, %SlogP, %Smr, %Hbonda, %Hbondd) = ((),(),(),(),(),(),(),(),(),(),(),());
my (%ClogP_err, %Rotbond, %Flex, %Tpsa, %Rofv, %Indic) = ((),(),(),(),(),());
my $tmp_file = '/usr/tmp/calcprops_' . localtime->hour() . '_' . localtime->min() . $$ . '.tdt';

my %Properties  = ( 'CLOGP' => \&DoCLOGP_CMR,
                    'HB'    => \&DoHBond,
                    'PK'    => \&DoPkaPkb,
                    'AMW'   => \&DoAMW,
                    'ROF'   => \&DoRofv,
                    'RB'    => \&DoRotBond,
                    'FLEX'  => \&DoFlexibility,
                    'TPSA'  => \&DoTpsa,
                    'SLOGP' => \&DoSlogPSmr,
                    'PLOGP'  => \&DoPLOGP,
                    'PLOGD' => \&DoPLOGD,
                  );
my @propertyList = ();
my ($ID, $STATE, $FILE, $KEYINFO);

my $day = localtime->mday();
$day = ($day < 10) ? (0 . $day) : $day;
my $month = localtime->mon() + 1;
$month = ($month < 10) ? (0 . $month) : $month;
my $startdate = $day . '-' . $month . '-' . (localtime->year() +1900);


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
   my @amw = ();

   @amw = ExecAmw($tmp_file);

   foreach $chunk (@amw) {
      next if $chunk =~ /\$SMIG/;
      next if $chunk =~ /^$/;
      $key = &FindItem($chunk,'COMP_ID');
      $amw = &FindItem($chunk,'AMW');
      $Amw{$key} = $amw;
   }
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

   qx { $SMI2MOL -input_format TDT <$tmp_file >/tmp/calcprops_plogd.$$.sdf 2>/dev/null };
   @plogd = ExecPrologD('-ityp sdf -idfld COMP_ID -det /dev/null -pH 2 5 7 7.4 8 10', '/tmp/calcprops_plogd.$$.sdf');

   foreach (@plogd) {
      chomp;
      next if $_ =~ /^Name/;
      next if $_ !~ /^\d+/;
      if (/nan/) {
         ($key, undef) = split(/\s+/, $_, 2);
         $val = '* * * * * *';
      } else {
         ($key, $val) = split(/\s+/, $_, 2);
      }
      $val =~ s/\s+/,/g;
      $PlogD{$key} = $val;
   }
   unlink "/tmp/calcprops_plogd.$$.sdf";
   return 0;
}


#########################################################################
#  RuleOfFiveViolation ROFV
#########################################################################
sub DoRofv
{
   my ($rofv, $indicator) = (0,0);
   my $clogp_val;

   foreach $key (keys %Id) {
      $rofv = $indicator = 0;
      $clogp_val = -99;
      if (defined($ClogP{$key}) && defined($ClogP_err{$key})) {
         $err = $1 if $ClogP_err{$key} =~ /-(\d+)[\w+\s+]/;
         $clogp_val = $ClogP{$key} if $err < 60;
      }
      $amw_val = defined($Amw{$key}) ? $Amw{$key} : -99;
      $hba_val = defined($Hbonda{$key}) ? $Hbonda{$key} : -99;
      $hbd_val = defined($Hbondd{$key}) ? $Hbondd{$key} : -99;

      $indicator = ($clogp_val != -99) ? (($amw_val != -99) ? (($hba_val != -99) ? (($hbd_val != -99) ? 0 : 1) : 1) : 1) : 1;
      $rofv += 1 if $clogp_val > 5.0;
      $rofv += 1 if $amw_val > 500.0;
      $rofv += 1 if $hba_val > 10.0;
      $rofv += 1 if $hbd_val > 5.0;

      $Rofv{$key} = $rofv;
      $Indic{$key} = $indicator;
   }
   return 0;
}

#########################################################################
#  Tpsa
#########################################################################
sub DoTpsa
{
   my @tpsa = ();

   @tpsa = ExecTpsa('-q -tdt -id COMP_ID', $tmp_file);
   foreach $chunk (@tpsa) {
      chomp($chunk);
      (undef, $val, $key, undef) = split(/\s+/, $chunk, 4);
      if ($val eq 'NA') {
         #005164 NA      -99
         ($key, undef, $err) = split(/\s+/, $chunk);
         $val = 0;
      }
      next if ! defined $key;
      $Tpsa{$key} = $val;
   }
   return 0;
}

#########################################################################
#  Flexibility
#########################################################################
sub DoFlexibility
{
   my @flex = ();

   @flex = ExecFlexibility('-tdt -id COMP_ID', $tmp_file);
   foreach $chunk (@flex) {
      chomp($chunk);
      (undef, $val, $key, undef) = split(/\s+/, $chunk, 4);
      if ($val eq 'NA') {
         #005164 NA      -99
         ($key, undef, $err) = split(/\s+/, $chunk);
         $val = 0;
      }
      next if ! defined $key;
      $Flex{$key} = sprintf("%.3f", $val);
   }
   return 0;
}

#########################################################################
#  RotBond
#########################################################################
sub DoRotBond
{
   my @rotbond = ();

   @rotbond = ExecRotBond('-id COMP_ID', $tmp_file);
   foreach $chunk (@rotbond) {
      chomp($chunk);
      (undef, $val, $key, undef) = split(/\s+/, $chunk, 4);
      if ($val eq 'NA') {
         ($key, undef, $err) = split(/\s+/, $chunk);
         $val = 0;
      }
      next if ! defined $key;
      $Rotbond{$key} = $val;
   }
   return 0;
}

#########################################################################
#  PLOGP
#########################################################################
sub DoPLOGP
{
   my $err;
   @plogp = ();

   qx { $SMI2MOL -input_format TDT <$tmp_file >/tmp/calcprops_plogp.$$.sdf 2>/dev/null };
   @plogp = ExecLogP('PlogP', "-ityp sdf -idfld COMP_ID -det /dev/null", '/tmp/calcprops_plogp.$$.sdf');

   foreach (@plogp) {
      next if $_ !~ /^\d+/;
      ($key, $logp) = split (/\s+/);
      $PlogP{$key} = $logp;
   }
   unlink "/tmp/calcprops_plogp.$$.sdf";
   return 0;
}


#########################################################################
#  pKa
#  pKb
#########################################################################
sub DoPkaPkb
{
   my @results = ();
   my (@pka, @pkb) = ((),());
   
   qx { $SMI2MOL -input_format TDT <$tmp_file >/tmp/calcprops_pkab.$$.sdf 2>/dev/null };
   @results = ExecPkaPkb('-ityp sdf -idfld COMP_ID -lpKa 0 -hpKa 14 -det /dev/null -vert', '/tmp/calcprops_pkab.$$.sdf');
   foreach (@results) {
      next if $_ !~ /^\d+/;
      ($r, $v, $s, undef) = /^(\d+)\s+([\d\-\.]+)\s(Acid|Base)\s+(\d+)/;
      next if ! defined($r);
      $Pka{$r} = '' if ! defined($Pka{$r});
      $Pkb{$r} = '' if ! defined($Pkb{$r});
      if ($s eq 'Acid') {
         $Pka{$r} .= (sprintf("%.1f", $v) . ',');
      } else {
         $Pkb{$r} .= (sprintf("%.1f", $v) . ',');
      }
   }
   unlink "/tmp/calcprops_pkab.$$.sdf";
   return 0;
}

#########################################################################
#  CLOGP
#  CMR
#########################################################################
sub DoCLOGP_CMR
{
   @clogp = ();
   $cmr_too = 1;
   @clogp = ExecLogP('ClogP', '-i', $tmp_file, $cmr_too);

   # CLOGP

   foreach $chunk (@clogp) {
      next if $chunk =~ /\$SMIG/;
      next if $chunk =~ /^$/;
      $key = &FindItem($chunk,'COMP_ID');
      $cp = &FindItem($chunk,'CP');
      $ClogP{$key} = $cp;
   } 

   # CMR

   foreach $chunk (@clogp) {
      next if $chunk =~ /\$SMIG/;
      next if $chunk =~ /^$/;
      $key = &FindItem($chunk,'COMP_ID');
      $cp = &FindItem($chunk,'CR');
      $Cmr{$key} = $cp;
   } 
   return 0;
}

#########################################################################
#  SLOGP
#  SMR
#########################################################################
sub DoSlogPSmr
{
   my (@slogp, @smr) = ((),());

   @slogp = ExecLogP('SlogPv2', "-q -s -id 'COMP_ID'", $tmp_file);
   @smr = ExecSmr("-MR -q -s -id 'COMP_ID'", $tmp_file);

   # SLOGP

   foreach $chunk (@slogp) {
      chomp($chunk);
      ($key, $val) = split(/\s+/, $chunk, 2);
      $SlogP{$key} = $val;
   }

   # SMR

   foreach $chunk (@smr) {
      chomp($chunk);
      ($key, $val) = split(/\s+/, $chunk, 2);
      $Smr{$key} = $val;
   }
   return 0;
}

#########################################################################
#  HBONDs
#########################################################################
sub DoHBond
{
   my @hbs = ();

   foreach $hb ('HBA', 'HBD') {
      @hbs = ExecHBond($hb, "-id 'COMP_ID'", $tmp_file);
      foreach $chunk (@hbs) {
         chomp($chunk);
         (undef, $val, $key) = split(/\s+/, $chunk);
         if ($val eq 'NA') {
            ($key, undef, $err) = split(/\s+/, $chunk);
            $val = 0;
         }
         next if ! defined $key;
         if ($hb eq 'HBA') {
            $Hbonda{$key} = $val;
         } else {
            $Hbondd{$key} = $val;
         }
      }
   }
   return 0;
}

sub ParseCommandLineOpts {
   my %options = ();
   getopts("f:k:p:i:", \%options);
   if (! defined ($options{f}) ) {
      print "\nusage:\t$0 -f inputfile [-k keyInfo] [-p all|prop_list] [-i IdFieldName]\n";
      print "with:\t-f inputfile : the actual data file\n";
      print "\t-k keyInfo : inputfile is in smiles|id|sdf|tdt format, '-k id' is default\n";
      print "\t-i IdFieldName : only used with SD or TDT filetypes to identify the compound id line, 'COMP_ID' is default\n";
      print "\t\tinputfile format :\n";
      print "\t\t\tEither 1. lines of smiles strings (CCCCNCC) .. -k smiles\n";
      print "\t\t\t       2. lines of id and smiles strings (123 CCCCNCC) .. -k id\n";
      print "\t\t\t       3. SD file .. -k sdf\n";
      print "\t\t\t       4. TDT file .. -k tdt\n";
      print "\t-p all|prop_list : calculate all know properties (-p all = default) or those specified\n";
      print "\t\tprop_list : comma separated list of properties, not case sensitive\n";
      print "\t\t            CLOGP(cmr incl),PLOGP,AMW,PLOGD,PK,SLOGP(smr incl),HB,ROTBOND,FLEX,TPSA,ROFV\n";
      exit 1;
   } else {
      $FILE =  $options{f};
      $KEYINFO = (defined($options{k})) ? uc($options{k}) : 'ID';
      $ID = (defined($options{i})) ? $options{i} : 'COMP_ID';
      $STATE = ($KEYINFO eq 'SDF') ? 0 : (($KEYINFO eq 'TDT') ? 1 : 2);
      $prop = (defined($options{p})) ? uc($options{p}) : 'ALL';
      if (uc($prop) eq 'ALL') {
         foreach (keys %Properties) {
            push(@propertyList, uc($_));
         }
      } else {
         @props = split (/,/, $prop);
         foreach (@props) {
            push(@propertyList, uc($_)); 
         }
      }
   }
}

######################################
# Start of script
######################################
my $rc = 0;

&ParseCommandLineOpts();

# SD files and TDT files need to be converted
# wanted to use finite state machine principle to accomplish this :-)
STATE : {
   if ($STATE == 0) {
       $mol2smi_params = '-output_format TDT -write_2d FALSE -write_3d FALSE -id ' . $ID;
       if (ExecMol2Smi($mol2smi_params ,$FILE, "$FILE.tdt", '/dev/null')) {
          unlink $FILE.tdt;
          croak("Could not convert SDF file to TDT file. Terminated");
       }
       $FILE = "$FILE.tdt";
       $STATE++;
       redo;
   }
   if ($STATE == 1) {
      my @chunks_tdt = ();
      @chunks_tdt = ExecReadTDT($FILE);
      foreach $chunk (@chunks_tdt) {
         #chomp($chunk);
         next if $chunk =~ /^\$SMIG/;
         $comp_nr = '';
         $comp_nr = &FindItem($chunk, $ID);
         $smiles = &FindItem($chunk,'\$SMI');
         $Id{$comp_nr} = $smiles;
      }
      $STATE++;
      $STATE++;  #make sure the next step is skipped .. cheating :-)
      redo;
   }
   if ($STATE == 2) {
      open(INPUT, "$FILE") || die "Could not open input file $FILE\n";
      $count=1;
      while (<INPUT>) {
         chomp;
         if ($KEYINFO eq 'ID') {
            ($comp_nr, $smiles) = split(/\s+/, $_, 2);
         } else {
            $noofFields = split /\s+/;
            croak "Not correct input format (#fields > 1 : $noofFields)\n" if $noofFields != 1;
            $comp_nr = $count++;
            $smiles = $_;
         }
         $Id{$comp_nr} = $smiles;
      }
      close(INPUT);
      $STATE++;
      redo;
   }
   last STATE;
}

&SetupDaylightEnv;

foreach $key (keys %Id) {
   # create temp tdt file
   open(TMP, "+>$tmp_file") || die "Can not create temp data file\n";
   print TMP "\$SMI<$Id{$key}>\n";
   print TMP "COMP_ID<$key>\n";
   print TMP "|\n";
   close(TMP);

   foreach $property (@propertyList) {
     if (exists $Properties{$property}) {
        &{$Properties{$property}}();
     }
   }
}
# printout calculated values, starting with header
my $header = '';
if ($KEYINFO eq 'ID' || $ID ne 'COMP_ID') {
   $header .= "ID\t";
}
$header .= 'SMILES';

foreach $property (@propertyList) {
   if ($property eq 'CLOGP') {
      $header .= "\tCLOGP\tCLOGP_ERR\tCMR\tCMR_ERR";
   } elsif ($property eq 'HB') {
      $header .= "\tHBA\tHBD";
   } elsif ($property eq 'PK') {
      $header .= "\tPKA\tPKB";
   } elsif ($property eq 'AMW') {
      $header .= "\tAMW"
   } elsif ($property eq 'ROF') {
      $header .= "\tROFV\tINDICATOR";
   } elsif ($property eq 'RB') {
      $header .= "\tROTBOND";
   } elsif ($property eq 'FLEX') {
      $header .= "\tFLEX";
   } elsif ($property eq 'TPSA') {
      $header .= "\tTPSA";
   } elsif ($property eq 'SLOGP') {
      $header .= "\tSLOGP\tSLOGP_ERR\tSMR\tSMR_ERR";
   } elsif ($property eq 'PLOGP') {
      $header .= "\tLOGP\tLOGP_ERR";
   } elsif ($property eq 'PLOGD') {
      $header .= "\tPLOGD(ph 2 5 7 7.4 8 10)";
   }
}
print "$header\n";

my ($clogp, $clogp_err, $cmr, $cmr_err,$logp_err,$logp);
my ($slogp, $slogp_err, $smr, $smr_err);

foreach $key (sort { $a <=> $b } keys %Id) {
   if ($KEYINFO eq 'ID' || $ID ne 'COMP_ID') {
      print "$key\t";
   }
   print "$Id{$key}";
   foreach $property (@propertyList) {
      if ($property eq 'CLOGP') {
         if (! defined($ClogP{$key})) {
            $clogp = $clogp_err = $ClogP_err{$key} = '-';
            $cmr = $cmr_err = '-';
         } else {
            ($clogp, $clogp_err, undef) = split(/;/, $ClogP{$key}, 3);
            $ClogP_err{$key} = $clogp_err;
            $cmr = $cmr_err = '-' if ! defined($Cmr{$key});
            ($cmr, $cmr_err, undef) = split(/;/, $Cmr{$key}, 3);
         }
         print "\t$clogp\t$clogp_err\t$cmr\t$cmr_err";
      } elsif ($property eq 'HB') {
         $Hbonda{$key} = '-' if ! defined($Hbonda{$key});
         $Hbondd{$key} = '-' if ! defined($Hbondd{$key});
         print "\t$Hbonda{$key}\t$Hbondd{$key}"; 
      } elsif ($property eq 'PK') {
         $Pka{$key} = '-' if ! defined($Pka{$key}) || $Pka{$key} eq '';
         $Pkb{$key} = '-' if ! defined($Pkb{$key}) || $Pkb{$key} eq '';
         $Pka{$key} = $1 if $Pka{$key} =~ /(.*),/;
         $Pkb{$key} = $1 if $Pkb{$key} =~ /(.*),/;
         print "\t$Pka{$key}\t$Pkb{$key}";
      } elsif ($property eq 'AMW') {
         $Amw{$key} = '-' if ! defined($Amw{$key});
         print "\t$Amw{$key}";
      } elsif ($property eq 'ROF') {
         print "\t$Rofv{$key}\t$Indic{$key}";
      } elsif ($property eq 'RB') {
         $Rotbond{$key} = '-' if ! defined($Rotbond{$key});
         print "\t$Rotbond{$key}";
      } elsif ($property eq 'FLEX') {
         $Flex{$key} = '-' if ! defined($Flex{$key});
         print "\t$Flex{$key}";
      } elsif ($property eq 'TPSA') {
         $Tpsa{$key} = '-' if ! defined($Tpsa{$key});
         print "\t$Tpsa{$key}";
      } elsif ($property eq 'SLOGP') {
         if (! defined($SlogP{$key})) {
            $slogp = $slogp_err = '-';
            $smr = $smr_err = '-';
         } else {
            ($slogp, $slogp_err) = split(/\s+/, $SlogP{$key}, 2);
            ($smr, $smr_err) = split(/\s+/, $Smr{$key}, 2);
         }
         print "\t$slogp\t$slogp_err\t$smr\t$smr_err";
      } elsif ($property eq 'PLOGP') {
         if (! defined($PlogP{$key})) {
            $logp_err = $logp = '-';
         } else {
            $logp_err = ($PlogP{$key} eq '*') ? 99 : 0;
            $logp = ($PlogP{$key} eq '*') ? 0 : $PlogP{$key};
         }
         print "\t$logp\t$logp_err";
      } elsif ($property eq 'PLOGD') {
         $PlogD{$key} = '- - - - - -' if ! defined($PlogD{$key});
         print "\t$PlogD{$key}";
      }
   }
   print "\n";
}

qx{ rm -f $tmp_file* };
exit 0;
