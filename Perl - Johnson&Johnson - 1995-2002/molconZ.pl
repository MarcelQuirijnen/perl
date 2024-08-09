#!/usr/local/bin/perl -w
#####################################################################################
# @(#)FILE      : molconZ"                                                          #
# @(#)TYPE FILE : Executable perl5 script"                                          #
# @(#)ENVRONMENT: Daylight + Molconn-Z                                              #
# @(#)PARAMS    :                                                                   #
#       -sdf    : input file is in SD format                                        #
#       -smi    : input file is in SMILES format                                    #
#       -tdt    : input file is in TDT format                                       #
#       -molcon : input format is already ok for molcon-Z                           #
#       -Zout   : Molcon-Z output file                                              #
#       -err    : error output file                                                 #
# @(#)AUTHOR    : M. Quirijnen                                     DATE: 05/04/01"  #
# @(#)USAGE     : Calculate chemical parameters using the Molconn-Z environment"    #
# @(#)Molconn-Z file format :                                                       #
#           CCOC(=O)N1CCc2c(C1)c(=O)[nH]c3ccccc23 R0027725                          #
#           CCOC(=O)N1CCc2c(C1)c(=O)c3ccccc23 R0027726                              #
# @(#)RETURN CODES :                                                                #
#   0  = normal successfull completion                                              #
#   -1 = there was an error                                                         #
#####################################################################################

require 5.000;

use Env;
use Carp;
use lib "/usr/local/bin/scripts/automation";
use Modules::TMCDefs;
use Modules::TMCSubs;

use sigtrap qw(die normal-signals error-signals);

my ($JRF, $JNJ, $DEBUG, $STATE, $MAIL, $SMI_FILE, $SDF_FILE, $TDT_FILE, $MOLCON_FILE, $MOLCON_PARAMS, $MOLCON_OUT, $MAIL_LIST) = (1, 0, 0, 0, 0, '', '', '', '', '', '', 'ttabruyn@janbe.jnj.com,mquirij1@janbe.jnj.com');
my ($cleantdt, $cleanmolcon, $tmp_tdt, $tmp_molcon) = (0, 0, '/tmp/tmptdt.' . $$ . '.tdt', '/tmp/' . $$ . '.tmpmolcon.B');


######################################
# Start of script
######################################
my $rc = 0;
unless (scalar(@ARGV)) {
   die "Usage : $0 -jnj|jrf -sdf|tdt|smi|Zfile infile -Zout outfile [-err errorFile ][-Zparam params] [-h]\n";
} else {
   while (@ARGV && ($_ = $ARGV[0])) {
      if (/^-(\w+)/) {
         CASE : {
              if ($1 =~ /jnj/) { $JNJ = 1; $JRF = 0; last CASE; }
              if ($1 =~ /jrf/) { $JNJ = 0; $JRF = 1; last CASE; }
              if ($1 =~ /^sdf/) { shift(@ARGV); $SDF_FILE = $ARGV[0]; $STATE = 0; last CASE; }
              if ($1 =~ /^tdt/) { shift(@ARGV); $TDT_FILE = $ARGV[0]; $STATE = 1; last CASE; }
              if ($1 =~ /^smi/) { shift(@ARGV); $SMI_FILE = $ARGV[0]; $STATE = 1; last CASE; }
              if ($1 =~ /^Zfile/) { shift(@ARGV); $MOLCON_FILE = $ARGV[0]; $STATE = 2; last CASE; }
              if ($1 =~ /^Zparam/) { shift(@ARGV); $MOLCON_PARAMS = $ARGV[0]; last CASE; }
              if ($1 =~ /^Zout/) { shift(@ARGV); $MOLCON_OUT = $ARGV[0]; last CASE; }
              if ($1 =~ /^err/) { shift(@ARGV); $ERR_OUT = $ARGV[0]; last CASE; }
              if ($1 =~ /^mail/) { $MAIL = 1; last CASE; }
              if ($1 =~ /^h/) { die "Usage : $0 -jrf|jnj -sdf|tdt|smi|Zfile infile -Zout outfile [-err errorFile ][-Zparam params] [-h]\n"; 
                                last CASE; 
                              }
         }
      } else {
         print "Oops: Unknown option : $_\n";
         die "Usage : $0 -jnj|jrf -sdf|tdt|smi|Zfile infile -Zout outfile [-err errorFile ][-Zparam params] [-h]\n";
      }
      shift(@ARGV);
   }
}
croak("Inputfile & outputfile are mandatory. Terminated.\n") if ($MOLCON_OUT eq '' && ($SDF_FILE eq '' or $TDT_FILE eq '' or $MOLCON_FILE eq '' or $SMI_FILE eq ''));
if ($ERR_OUT) {
   open(ERROR, "+>$ERR_OUT") || die "Could not open error output file $ERR_OUT\n";
}
# we need to convert the inputfile depending on type given..act as if we're a finite state machine
STATE : {
   if ($STATE == 0) {
      # inputfile is SDF file .. convert to SMI (we need smiles field)
      # SMI file is intermediate file .. cleanup when finished with it
      $cleantdt = 1;
      # now do your stuff
      $mol2smi_params = '-output_format TDT -write_2d FALSE -write_3d FALSE';
      if (ExecMol2Smi($mol2smi_params ,$SDF_FILE, $tmp_tdt, '/dev/null')) {
         unlink $tmp_tdt;
         croak("Could not convert SDF file to TDT file. Terminated"); 
      }
      $TDT_FILE = $tmp_tdt;
      $STATE++;
      redo;
   }
   if ($STATE == 1) {
      # inputfile is SMI file .. extract molconz info and create appropriate file
      my @chunks_tdt = ();
      @chunks_tdt = ExecReadTDT($TDT_FILE);
      open(MOLCON, "+>$tmp_molcon") || die "Could not create Molconn-Z inputfile : $!\n";
      foreach $chunk (@chunks_tdt) {
         next if $chunk =~ /^\$SMIG/;
         next if $chunk !~ /^(\$SMI|COMP_ID|\$RNR|\$NAM)/;
         $comp_nr = '';
         LASTID : foreach $id ('COMP_ID', '\$NAM', '\$RNR') {
            $comp_nr = &FindItem($chunk, $id);
            last LASTID if length($comp_nr);
         }
         if ($JRF) {
            if ($comp_nr =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
               $comp_nr = $1;
            } else {
               $comp_nr = ('0' x ($RNUM_LEN - length($comp_nr))) . $comp_nr unless length($comp_nr) == $RNUM_LEN;
            }
         } else {
            $comp_nr =~ /[0-9]{1,}/;
         }
         $smi = &FindItem($chunk,'\$SMI');
         $smiles = defined($smi) ? (length($smi) ? $smi : $ERR_SMILESNOTAVAIL) : $ERR_SMILESNOTAVAIL;
         if ($ERR_OUT) {
            print ERROR "$comp_nr : $ERR_SMILESNOTAVAIL .. probably not available in tdt file\n" if ! length($smiles) || $smiles eq $ERR_SMILESNOTAVAIL;
         }
         next if ! defined($smi) || $smiles eq $ERR_SMILESNOTAVAIL;
         if ($JRF) {
            print $smiles, ' R'. $comp_nr, "\n" if $DEBUG;
            print MOLCON $smiles, ' R'. $comp_nr, "\n";
         } else {
            print $smiles, ' '. $comp_nr, "\n" if $DEBUG;
            print MOLCON $smiles, ' '. $comp_nr, "\n";
         }
         undef $smi;
      }
      close(MOLCON);
      $MOLCON_FILE = $tmp_molcon;
      $cleanmolcon = 1;
      $STATE++;
      redo;
   }
   if ($STATE == 2) {
      # inputfile is in molconz format .. exec molconz
      $rc = ExecMolconnZ($MOLCON_FILE, $MOLCON_OUT, $MOLCON_PARAMS);
      if ($rc && $ERR_OUT) {
         print ERROR "ERROR: executing MolconnZ returned error [$rc]\n";
      }
      last STATE;
   }
}
unlink $TDT_FILE if $cleantdt;
unlink $MOLCON_FILE if $cleanmolcon;
if ($ERR_OUT) {
   close(ERROR);
   my $mailsubject = (-z $ERR_OUT) ? "molconZ finished OK" : "ERROR on molconz";
   qx{ /usr/sbin/Mail -s '$mailsubject' $MAIL_LIST < $ERR_OUT } if $MAIL;
}
exit $rc;
