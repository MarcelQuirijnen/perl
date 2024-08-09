#!/usr/local/bin/perl

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
my (%clogp_val, %clogp_err, %pka_val, %pkb_val,%clogd_val) = ((),(),(),(),());
my $fh = *STDOUT;
# on behalf of txt file
my (@heading, @data) = ((),());
my ($ID_COL, $SMILES_COL) = ('ID', 'SMILES');
my $compound_id = '';
my $pH_logd = 4;

####
# Determin ROFV value and print it
####
sub PrintOut
{
   print "COMP_ID\tSMILES\tCLOGD\tCLOGP\tPKA\tPKB\n";
   foreach $key (keys %compounds) {
         print $fh "$key\t$compounds{$key}\t", defined($clogd_val{$key}) ? $clogd_val{$key} : 'NC';
         print $fh "\t", defined($clogp_val{$key}) ? $clogp_val{$key} : '-';
         print $fh "\t", defined($pka_val{$key}) ? $pka_val{$key} : '-';
         print $fh "\t", defined($pkb_val{$key}) ? $pkb_val{$key} : '-';
         print $fh "\n";
   }
}

######################################
# Start of script
######################################
my $rc = 0;
unless (scalar(@ARGV)) {
   die "Usage : $0 [-jnj|jrf] -sdf|tdt|rno|smi|txt infile [-out outfile] [-full] [-table] [-h]\n";
} else {
   while (@ARGV && ($_ = $ARGV[0])) {
      if (/^-(\w+)/) {
         CASE : {
              if ($1 =~ /jnj/) { $JNJ = 1; $JRF = 0; last CASE; }
              if ($1 =~ /jrf/) { $JNJ = 0; $JRF = 1; last CASE; }
              if ($1 =~ /^sdf/) { shift(@ARGV); $SDF_FILE = $ARGV[0]; last CASE; }
              if ($1 =~ /^tdt/) { shift(@ARGV); $TDT_FILE = $ARGV[0]; $STATE = 1; last CASE; }
              if ($1 =~ /^rno/) { shift(@ARGV); $TDT_FILE = $ARGV[0]; $STATE = 2; last CASE; }
              if ($1 =~ /^smi/) { shift(@ARGV); $SMI_FILE = $ARGV[0]; $STATE = 0; last CASE; }
              if ($1 =~ /^txt/) { shift(@ARGV); $TXT_FILE = $ARGV[0]; $STATE = 0; $TABLE=1; last CASE; }
              if ($1 =~ /^out/) { shift(@ARGV); $OUT = $ARGV[0]; last CASE; }
              if ($1 =~ /^full/) { $FULL = 1; last CASE; }
              if ($1 =~ /^table/) { $TABLE = 1; last CASE; }
              if ($1 =~ /^h/) { die "Usage : $0 [-jrf|jnj] -sdf|tdt|rno|smi|txt infile [-out outfile] [-table] [-full] [-h]\n";
                                last CASE;
                              }
         }
      } else {
         print "Oops: Unknown option : $_\n";
         die "Usage : $0 [-jnj|jrf] -sdf|tdt|rno|smi|txt infile [-out outfile] [-table] [-full] [-h]\n";
      }
      shift(@ARGV);
   }
}
croak("InFile is mandatory. Terminated.\n") if ($SDF_FILE eq '' and $TDT_FILE eq '' and $SMI_FILE eq '' and $TXT_FILE eq '');
croak("Compound type (Rno or JNJ) is mandatory.\n") if (! $JNJ and ! $JRF);
if ($OUT) {
   $fh = FileHandle->new(">$OUT");
}

# we need to convert the inputfile depending on type given..act as if we're a finite state machine
STATE : {
   if ($STATE == 0) {
      if ($SMI_FILE) {
         open(SMI, "<$SMI_FILE") || die "Could not open $SMI_FILE : $!\n";
         open(TDT, "+>$tmp_tdt") || die "Cant open conversionfile $tmp_tdt : $!\n";
         while (<SMI>) {
            chomp;
            ($comp_nr, $smi, undef) = split(/\s+/, $_, 3);
            print TDT '$SMI<', $smi, ">\n";
            print TDT 'COMP_ID<', $comp_nr, ">\n|\n";
         }
         close(SMI);
         close(TDT);
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
         LASTID : foreach $id ('COMP_ID', '\$NAM', '\$RNR') {
            $key = &FindItem($chunk, $id);
            $compound_id = $id;
            last LASTID if length($key);
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
         LASTID : foreach $id ('COMP_ID', '\$NAM', '\$RNR') {
            $key = &FindItem($chunk, $id);
            last LASTID if length($key);
         }
         next if ! $key;
         $cp = &FindItem($chunk,'CP');
         next if ! $cp;
         ($value, $err, undef) = split(/;/, $cp, 3);
         $err_lim = $1 if $err =~ /([0-9]{1,})/;
         next if $err_lim >= 60;
         $clogp_val{$key} = $value; $clogp_err{$key} = $err;
      }
      # PKa PKb
      &SetupPallasEnv;
      &SetupDaylightEnv;
      qx { $SMI2MOL -input_format TDT <$TDT_FILE >$TDT_FILE.sdf 2>/dev/null };
      @pks = qx{ $PKALC -ityp sdf -idfld COMP_ID -det /dev/null -vert $TDT_FILE.sdf 2>/dev/null };
      foreach (@pks) {
         next if $_ !~ /^\d+/;
         ($key, $val, $s, $atom) = /^(\d+)\s+([\d\-\.]+)\s(Acid|Base)\s+(\d+)/;
         next if ! defined $key;
         if ($s eq 'Acid') {
            $pka_val{$key} .= (sprintf("%.2f", $val) . ' ');
         } else {
            $pkb_val{$key} .= (sprintf("%.2f", $val) . ' ');
         }
      }
      # CLOGD
      foreach $key (keys %compounds) {
         if (exists($clogp_val{$key})) {
            my $clogd = $clogp_val{$key};
            if (exists($pka_val{$key})) {
               $pka_val{$key} =~ s/^\s+//;
               my @pka = split(/\s+/, $pka_val{$key});
               foreach $pka (@pka) {
                 $clogd -= ( (log(1 + 10**($pH_logd - $pka))) / 2.30258 );
               }
            }
            if (exists($pkb_val{$key})) {
               $pkb_val{$key} =~ s/^\s+//;
               my @pkb = split(/\s+/, $pkb_val{$key});
               foreach $pkb (@pkb) {
                 $clogd -= ( (log(1 + 10**($pkb - $pH_logd))) / 2.30258 );
               }
            }
            $clogd_val{$key} = sprintf("%.2f", $clogd);
         }
      }
      &PrintOut;
      last STATE;
   }
}
#unlink $TDT_FILE if $cleantdt;
exit $rc;
