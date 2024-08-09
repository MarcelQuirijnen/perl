##############################################################################
#
# MDC perl module - general auxiliary functions
#
# 1.1 tom@020130:
#	- updated all paths to scripts to point to /usr/local/bin/scripts
#	- commented out XML library (use) and functions 
#
# 1.2 tom@020131:
#	added RemoveQuotesFromTDTFile sub, and call to this in ExecMol2Smi
#
# 1.3 tom@0202012:
#	same as 1.2, only under RCS version control
#
##############################################################################
# RCS ID: 
# 	$Id: TMCSubs.pm,v 1.6 2002/02/25 17:00:52 root Exp root $
#
# RCS History:
#	$Log: TMCSubs.pm,v $
#	Revision 1.6  2002/02/25 17:00:52  root
#	added Sdf2PallasSdf(), which is called before each pallas
#	  executable that operates on an .sdf file.
#	  Function: Replace '999 V2000' with '1   V2000'
#	corrected DEBUG printout msgs to have the prefix "DEBUG:" and
#	  a conditional if $DEBUG.
#
#	Revision 1.5  2002/02/22 16:18:30  root
#	Diabled DEBUG messages
#
#	Revision 1.4  2002/02/22 15:57:39  root
#	added "DEBUG: " in front of all DEBUG printout msgs.
#	NOTE: $DEBUG is still set
#
#	Revision 1.3  2002/02/12 21:48:09  root
#	same as 1.2, only under RCS version control
#
##############################################################################


package Modules::TMCSubs;


=head1 NAME

later

=head1 SYNOPSIS

	later

=head1 DESCRIPTION

	follows later

=head1 AUTHOR

Unix Sysmannen (5889)
JRF-IT 1999

=cut

require 5.000;
require Exporter;
use Time::localtime;
#use XML::Simple;
use Modules::TMCDefs;
#use Modules::Clogp;
use Carp;
use Env;

@ISA = qw(Exporter);

@EXPORT = qw(SetupPallasEnv SetupDaylightEnv SetupBCIEnv FindItem SplitSDF SetupCorinaEnv CheckConfig
             SplitTDT ExecCorina ExecFingerPrint ExecClogP ExecReadTDT ExecPrologD ExecPlogP
             ExecMol2Smi LogMsg ExecPkaPkb ExecSmr ExecHBond ExecAmw ExecLogP ExecCmr ExecSlogPv3 ExecSlogPv2
             $FINDRNN $FINDRNN_P $OPTCLUS $RNNCLUS $RNNCLUSNEW $MOL2SMI $PROLOGP $PKALC $SMI2MOL $PROLOGD $ADDMWT
             $CORINA $CLOGP $N_CLOGP_N $CLOGP_N $LISTCLUSTERS $TDTCAT $CMR $FINGERPRINT  ExecConnolly
             SetupQcpeEnv Tdt2Sdf ExecSmi2Mol GetPeriodicTable SetupMolconnZ ExecMolconnZ ExecCRPS
             ExecRotBond ExecFlexibility ExecTpsa TimeStamp SubName RemoveQuotesFromTDTFile Sdf2PallasSdf
            );	## removed WriteXMLError from EXPORT list

$VERSION = '1.1';

my $DEBUG = 1;

sub ExecUnknown
{
   croak "Oops..unknown subroutine call.\n";
}

sub ExecCRPS
{
   my ($proc, $ref) = @_;

   require IO::Socket;
   require RPC::pClient;

   croak("Must supply Remote Procedure. Terminated.") if (!defined($proc));
   if (!ref($ref)) {
      croak("Must supply RPC data as a reference. Terminated.");
   }

   my $MDC_APPLICATION = "CHARON Rapid Property Selection Server";
   my $MDC_VERSION = 1.0;
   # these values should be equal to those in /etc/propServer.conf
   my $MY_USER = "foo";
   my $MY_PASSWORD = "bar";
   my @results = ();

   #return (-1, undef) if ! scalar(@Rnos);
   # Connect to the server
   # there seems to be a problem with sockets on btmcs2 :-(
   my $sock = IO::Socket::INET->new('PeerAddr' => 'localhost',
                                    'PeerPort' => 9002,
                                    'Proto' => 'tcp');
   if (!defined($sock)) {
      return ($!, undef); #die "Cannot connect: $!\n";
   }
   my $client = RPC::pClient->new('sock' => $sock,
                                  'application' => $MDC_APPLICATION,
                                  'version' => $MDC_VERSION,
                                  'user' => $MY_USER,
                                  'password' => $MY_PASSWORD,
                                 );
   if (!ref($client)) {
      return ($client, undef);   #die "Cannot create client: $client\n";
   }
   @results = $client->Call($proc, $ref);
   #CASE : {
   #   if ($proc eq 'FP') { @results = $client->Call('FP', $ref); last CASE; }
   #   if ($proc eq 'UPDATE') { @results = $client->Call('UPDATE', $hashref); last CASE; }
   #}
   $rc = $client->error if $client->error;
   $client->Call('quit');
   return ($rc, @results);
}

sub SubName  { (caller(1))[3] }		# returns the name of the subroutine that called this sub

sub TimeStamp
{
    $tm = localtime;
    local ($DAY, $MONTH, $YEAR, $HOURS, $MIN) = (
						(($tm->mday < 10) ? ('0'. int($tm->mday)) : $tm->mday),
						(($tm->mon+1 < 10) ? ('0'. int($tm->mon+1)) : $tm->mon+1), 
						$tm->year+1900, 
						(($tm->hour < 10) ? ('0'. int($tm->hour)) : $tm->hour),
						(($tm->min < 10) ? ('0'. int($tm->min)) : $tm->min)
						);
    return ("$YEAR$MONTH$DAY" . "_" . "$HOURS$MIN");

}

sub LogMsg
{
   my $handle = shift(@_);

   croak ("Must supply a logfile handle.") unless defined($handle);
   $tm = localtime;
   local ($DAY, $MONTH, $YEAR, $HOURS, $MIN) = ($tm->mday, (($tm->mon+1 < 10) ? ('0'. int($tm->mon+1)) : $tm->mon+1), $tm->year+1900, $tm->hour, $tm->min);
   print $handle "$0 $DAY/$MONTH/$YEAR $HOURS:$MIN @_\n";
   ##print "$0 $DAY/$MONTH/$YEAR $HOURS:$MIN @_\n" if $DEBUG;
}

sub Tdt2Sdf
{
   return 0;
}

################################################################
#
# Replace '999 V2000' with '1   V2000' in an sdf file
#
# needed for Pallas soft to be able to read the (newer) sdf files
# that no longer have a linecount (as produced by the latest 
# daylight soft) 
#
################################################################
sub Sdf2PallasSdf
{
   my ($in, $out) = @_;
   print "DEBUG: Sdf2PallasSdf $in > $out\n" if $DEBUG;
   open (IN, "<$in") || die "Could not open $in\n";
   open (OUT, ">$out") || die "Could not open $out\n";
   while (<IN>) {
	s/999 V2000/1   V2000/;
	print OUT;
   }
   close OUT;
   close IN;
}

sub SplitTDT
{
   local ($TDTfile, $outputDir) = @_;
   local $/ = undef;
   my @listOfSplits = ();

   croak("Must supply TDT file and where-to-split absolute path.") unless defined($TDTfile) && defined($outputDir);
   open (TDT, "<$TDTfile") || die "Could not open $TDTfile\n";
   @chunks_tdt = split(/(?)\|/, <TDT>);
   close(TDT);
   $count = 0;
   foreach $chunk (@chunks_tdt) {
      next if length($chunk) <= 1;
      next if $chunk =~ /\$SMIG/;
      next if $chunk =~ /^$/;
      chomp($chunk);
      $count++;
      open(O_TDT, "+>$outputDir/$count.tdt") || die "Could not open/create TDT split file\n";
      print O_TDT "$chunk";
      print O_TDT "|";
      close(O_TDT);
      push @listOfSplits,$outputDir . "/" . $count . ".tdt";
   }
   return wantarray ? @listOfSplits : scalar(@listOfSplits);
}

sub SplitSDF
{
   local ($SDFfile, $outputDir) = @_;
   local $/ = undef;
   my @listOfSplits = ();

   croak("Must supply SD file and where-to-split absolute path.") unless defined($SDFfile) && defined($outputDir);
   open (SDF, "<$SDFfile") || die "Could not open $SDFfile\n";
   @chunks_sdf = split(/^[\$]{4}$/m, <SDF>);
   close(SDF);
   $count = 0;
   foreach $chunk (@chunks_sdf) {
      next if length($chunk) <= 1;
      chomp($chunk);
      $count++;
      open(O_SDF, "+>$outputDir/$count.sdf") || die "Could not open/create SDF split file : $!\n";
      print O_SDF "$chunk\$\$\$\$\n";
      close(O_SDF);
      push @listOfSplits, $outputDir . "/" . $count . ".sdf";
   }
   #return (wantarray ? @listOfSplits : join(' ',@listOfSplits));
   return wantarray ? @listOfSplits : scalar(@listOfSplits);
}

sub SetupPallasEnv
{
   open(PALLAS,"<$PALLAS_ENV") || die "Could not initialize PALLAS env : $!\n";
   while (<PALLAS>) {
     next if (! /^setenv/ && ! /^alias/);
     chomp;
     ($undef, $var, $val) = split(/[ \t]+/);
     $ENV{'CDRPROGS_DIR'} = $val if $var eq 'CDRPROGS_DIR';
     $ENV{'BABEL_DIR'} = $val if $var eq 'BABEL_DIR';
     ($PROLOGP = $val) =~ s/\$CDRPROGS_DIR/$ENV{'CDRPROGS_DIR'}/ if $var eq 'prologp';
     ($PROLOGD = $val) =~ s/\$CDRPROGS_DIR/$ENV{'CDRPROGS_DIR'}/ if $var eq 'prologd';
     ($PKALC = $val) =~ s/\$CDRPROGS_DIR/$ENV{'CDRPROGS_DIR'}/ if $var eq 'pkalc';
   }  
   close(PALLAS);
   return 0;
}

sub SetupQcpeEnv
{
   open(QCPE, "<$QCPE_ENV") || die "Could not initialize QCPE env : $!\n";
   while (<QCPE>) {
      chomp;
      (undef, $prog, $fullpath) = split(/[ \t]+/);
      $CONNOLLY = $fullpath if $prog eq 'connolly'; 
   }
   close(QCPE);
   return defined($CONNOLLY) ? 0 : 1;
}

sub SetupBCIEnv 
{
   open(BCI,"<$BCI_ENV") || die "Could not initialize BCI env : $!\n";
   while (<BCI>) {
     next if (! /^setenv/ && ! /^alias/);
     chomp;
     ($undef, $var, $val) = split(/[ \t]+/);
     #print "var=$var ", "val = $val\n";
     $FINDRNN = $val if $var eq 'findrnn';
     $FINDRNN_P = $val if $var eq 'findrnn64_para';
     $OPTCLUS = $val if $var eq 'optclus';
     $RNNCLUS = $val if $var eq 'rnnclus';
     $RNNCLUSNEW = $val if $var eq 'rnnclusnew';
   }
   close(BCI);
   return 0;
}

sub SetupCorinaEnv 
{
   my (@libs, @dlibs) = ((),());
   open(CORINA, "<$CORINA_ENV") || die "Could not initialize CORINA env : $!\n";
   while(<CORINA>) {
     chomp;
     ($undef, $var, $undef, $undef, $val) = split(/[ \t]+/);
     if ($val =~ /corina/) {
        $val =~ s/[\)]//;
        @libs = split(/:/, $ENV{uc $var});
        @dlibs = grep(/$ENV{uc $var}/, @libs);
        unless (scalar(@dlibs)) {
           $ENV{uc $var} .= (':' . $val);
        }
     } else {
        die "Could not find path to Corina software\n";
     }
   }
   close(CORINA);
   $CORINA = $val . '/corina';
   return 0;
}

sub SetupMolconnZ
{
   open(MOLCON, "<$MOLCONZ_ENV") || die "Could not initialize MolconnZ env through $MOLCONZ_ENV: $!\n";
   while(<MOLCON>) {
      next if (! /^source/);
      chomp;
      (undef, $source) = split(/[ \t]+/);
   }
   close(MOLCON);
   open(MOLCON, "<$source") || die "Could not initialize MolconnZ env through $source: $!\n";
   while (<MOLCON>) {
     next if ! /^setenv/;
     chomp;
     ($shellcmd, $var, $val) = split(/[ \t]+/);
     $ENV{'EDUSOFT_ROOT'} = $val if $var eq 'EDUSOFT_ROOT';
     $ENV{'EDUSOFT_PROD2'} = $val if $var eq 'EDUSOFT_PROD2';
     ($ENV{'DY_LICENSEDATA'} = $val) =~ s/\$EDUSOFT_ROOT/$ENV{'EDUSOFT_ROOT'}/ if $var eq 'DY_LICENSEDATA';
   }
   close(MOLCON);
   open(SOURCE, "<$ENV{'EDUSOFT_ROOT'}/$ENV{'EDUSOFT_PROD2'}/lib/cshrc_r8") || die "Could not initialize MolconnZ env through $ENV{'EDUSOFT_ROOT'}/$ENV{'EDUSOFT_PROD2'}/lib/cshrc_r8: $!\n";
   while (<SOURCE>) {
      next if ! /^setenv/;
      chomp;
     (undef, $var, $val) = split(/[ \t]+/);
      if ($var eq 'MCONN_RUN') {
         $val =~ s/\$EDUSOFT_ROOT/$ENV{'EDUSOFT_ROOT'}/;
         $val =~ s/\$EDUSOFT_PROD2/$ENV{'EDUSOFT_PROD2'}/;
         $ENV{'MCONN_RUN'} = $val;
      }
      ($ENV{'MCONN_OPT'} = $val) =~ s/\$HOME/$ENV{'EDUSOFT_ROOT'}/ if $var eq 'MCONN_OPT';
      ($ENV{'MCONN_LICENSE'} = $val) =~ s/\$EDUSOFT_ROOT/$ENV{'EDUSOFT_ROOT'}/ if $var eq 'MCONN_LICENSE';
      $ENV{'MCONN_SMILES'} = $val if $var eq 'MCONN_SMILES';
      ($ENV{'MCONN_SCRATCH'} = $val) =~ s/\$HOME/$ENV{'EDUSOFT_ROOT'}/ if $var eq 'MCONN_SCRATCH';
   }
   close(SOURCE);
   return 0;
}

sub ExecMolconnZ
{
   my ($inputfile, $outputfile, $params) = @_;

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   $rc = &SetupMolconnZ;
   #while (($key,$value) = each %ENV) {
   #   print "$key=$value\n" if $key =~ /MCON/ || $key =~ /DY_LICENSEDA/;
   #}
   #print "$ENV{'MCONN_RUN'}/molconnz $params $inputfile $outputfile\n";
   qx { $ENV{'MCONN_RUN'}/molconnz $params $inputfile $outputfile 2>/dev/null } unless $rc;
   print ("DEBUG: $ENV{'MCONN_RUN'}/molconnz $params $inputfile $outputfile 2>/dev/null\n") if $DEBUG;
   $rc += $?;
   return $rc;
}

sub SetupDaylightEnv 
{
   open(DAYLIGHT, "<$DAYLIGHT_ENV") || die "Could not initialize DAYLIGHT env : $!\n";
   while (<DAYLIGHT>) {
     next if (! /^setenv/ && ! /^alias/);
     chomp;
     ($undef, $var, $val) = split(/[ \t]+/);
     $ENV{'DY_HOME'} = $val if $var eq 'DY_HOME';
     ($ENV{'DY_ROOT'} = $val) =~ s/\$DY_HOME/$ENV{'DY_HOME'}/ if $var eq 'DY_ROOT';
     ($ENV{'DY_LICENSEDATA'} = $val) =~ s/\$DY_HOME/$ENV{'DY_HOME'}/ if $var eq 'DY_LICENSEDATA';
     ($ENV{'DY_PASSWORDS'} = $val) =~ s/\$DY_ROOT/$ENV{'DY_ROOT'}/ if $var eq 'DY_PASSWORDS';
     ($ENV{'DY_SYSPROFILE'} = $val) =~ s/\$DY_HOME/$ENV{'DY_HOME'}/ if $var eq 'DY_SYSPROFILE';
     ($MOL2SMI = $val) =~ s/\$DY_ROOT/$ENV{'DY_ROOT'}/ if $var eq 'mol2smi';
     ($SMI2MOL = $val) =~ s/\$DY_ROOT/$ENV{'DY_ROOT'}/ if $var eq 'smi2mol';
   }
   @libs = split(/:/, $ENV{'LD_LIBRARY_PATH'});
   @dy_libs = grep(/$ENV{'DY_ROOT'}/, @libs);
   unless (scalar(@dy_libs)) {
      $ENV{'LD_LIBRARY_PATH'} = $ENV{'DY_ROOT'} . '/lib:' . $ENV{'DY_ROOT'} . '/libo32:' . $ENV{'LD_LIBRARY_PATH'};
   }
   @libs = split(/:/, $ENV{'LD_LIBRARYN32_PATH'});
   @dy_libs = grep(/$ENV{'DY_ROOT'}/, @libs);
   unless (scalar(@dy_libs)) {
      $ENV{'LD_LIBRARYN32_PATH'} = $ENV{'DY_ROOT'} . '/lib:' . $ENV{'LD_LIBRARYN32_PATH'};
   }
   @libs = split(/:/, $ENV{'LD_LIBRARY64_PATH'});
   @dy_libs = grep(/$ENV{'DY_ROOT'}/, @libs);
   unless (scalar(@dy_libs)) {
      if ($ENV{'LD_LIBRARY64'}) {
         $ENV{'LD_LIBRARY64'} = $ENV{'DY_ROOT'} . '/lib64:' . $ENV{'LD_LIBRARY64'};
      } else {
         $ENV{'LD_LIBRARY64'} = $ENV{'DY_ROOT'} . '/lib64:';
      }
   }

   #$ENV{'LD_LIBRARY_PATH'} = $ENV{'DY_ROOT'} . '/lib:' . $ENV{'DY_ROOT'} . '/libo32:' . $ENV{'LD_LIBRARY_PATH'};
   #$ENV{'LD_LIBRARYN32_PATH'} = $ENV{'DY_ROOT'} . '/lib:' . $ENV{'LD_LIBRARYN32_PATH'};
   #if ($ENV{'LD_LIBRARY64'}) {
   #   $ENV{'LD_LIBRARY64'} = $ENV{'DY_ROOT'} . '/lib64:' . $ENV{'LD_LIBRARY64'};
   #} else {
   #   $ENV{'LD_LIBRARY64'} = $ENV{'DY_ROOT'} . '/lib64:';
   #}

   $CLOGP = $ENV{'DY_ROOT'} . '/bin/clogp';
   $CMR = $ENV{'DY_ROOT'} . '/bin/cmr';
   $CLOGP_N = $ENV{'DY_ROOT'} . '/bin/Clogp';
   $ADDMWT = $ENV{'DY_ROOT'} . '/contrib/src/c/thor/addmwt';
   $LISTCLUSTERS = $ENV{'DY_ROOT'} . '/bin/listclusters';
   $FINGERPRINT = $ENV{'DY_ROOT'} . '/bin/fingerprint';
   $TDTCAT = $ENV{'DY_ROOT'} . '/bin/tdtcat';
   close(DAYLIGHT);
   #$ENV{'DY_HOME'} = "/sw/daylight";
   #$ENV{'DY_ROOT'} = $ENV{'DY_HOME'} . "/v461";
   #$ENV{'DY_LICENSEDATA'} = $ENV{'DY_HOME'} . "/local/dy_license.dat";
   #$ENV{'DY_PASSWORDS'} = $ENV{'DY_ROOT'} . "/etc/dy_passwords.dat";
   #$ENV{'DY_SYSPROFILE'} = $ENV{'DY_HOME'} . "/local/dy_sysprofile.opt";
   #$MOL2SMI = $ENV{'DY_ROOT'} . "/contrib/src/applics/convert/molfiles/mol2smi";
   return 0;
}

sub FindItem
{
   local ($_, $tag) = @_;
   return ( /$tag<(.*?)>.*/ ) ? $1 : "";
}

sub CheckConfig {
   my $prog = shift;
   croak("Must supply program. Terminated.") if not defined($prog);
   qx { /sbin/chkconfig $prog };
   return $?;
}

sub ExecCorina
{
   my ($params, $inputfile, $outputfile) = @_;
   my $rc = 0;

   croak("Must supply input AND output filename. Terminated.") if (!defined($inputfile) or !defined($outputfile));
   $rc = &SetupCorinaEnv;
   $rc = qx { $CORINA $params $inputfile $outputfile } unless $rc;
   print "DEBUG: $CORINA $params $inputfile $outputfile\n" if $DEBUG;
   unless ($rc) {
      $rc = 99 if -z $outputfile;
   }
   return $rc;
}

sub ExecFingerPrint
{
   my ($params, $inputfile) = @_;
   my @fingerprints = ();
   my $version;
  
   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply fingerprint parameters. Terminated.") if (!defined($params));
   $rc = &SetupDaylightEnv;
   ##qx{ $ENV{'DY_ROOT'}/bin/fingerprint -b $CLUSTERSIZE -c $CLUSTERSIZE -z $inputfile 2>/dev/null };
   @fingerprints = qx { $FINGERPRINT $params $inputfile 2>/dev/null } unless $rc;
   print ("DEBUG: $FINGERPRINT $params $inputfile 2>/dev/null\n") if $DEBUG;
   chomp(@fingerprints);
   if ($fingerprints[0] =~ /^\$FPG/) {
      (undef, undef, undef, undef, $vertmp) = split(/;/, $fingerprints[0]);
      (undef, undef, $version, undef) = split(/,/, $vertmp);
   }
   $result = join(" ", @fingerprints);
   @fingerprints = split(/\|/, $result);
   ($version, @fingerprints);
   #return wantarray ? @fingerprints : scalar(@fingerprints);
}

sub ExecLogP
{
   my ($logp, $params, $inputfile, $cmr_too, $timeout) = @_;
   my @logp = ();
   my $remove = 0;
   my %LogPs = ( 'PlogP'     => \&ExecPlogP,
                 'SlogPv2'   => \&ExecSlogPv2,
                 'SlogPv3'   => \&ExecSlogPv3,
                 'ClogP'     => \&ExecClogP,
                 '_default_' => \&ExecUnknown,
               );

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply params. Terminated.") if (!defined($params));
   croak("Must supply logP-flag. Terminated.") if (!defined($logp));

   if (exists $LogPs{$logp}) {
      $rsub = $LogPs{$logp};
      @logp = &$rsub($params, $inputfile, $cmr_too, $timeout);
   } else {
      $rsub = $LogPs{"_default_"};
      &$rsub();
   }
   @logp;
}

sub ExecClogP
{
   my ($params, $inputfile, $cmr, $timeout) = @_;
   my (@tdtfiles, @clogp, @logprec) = ((),(),());

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   $cmr = 0 if ! defined($cmr);
   $_ = qx { grep '|' $inputfile | wc -l };
   s/\s+//g;
   $noof_records = $_;
   if ($noof_records > 1) {
      $remove = 1;
      mkdir "/tmp/clogp$$", 0777;
      mkdir "/tmp/clogp$$/tdt", 0777;
      @tdtfiles = SplitTDT($inputfile, "/tmp/clogp$$/tdt");
   } else {
      push @tdtfiles, $inputfile;
   }

   $rc = &SetupDaylightEnv;
   unless ($rc) {
      foreach $tdtfile (@tdtfiles) {
         @logprec = ($cmr) ? qx { $CLOGP_N $params $tdtfile | $CMR 2>/dev/null } : qx { $CLOGP_N $params $tdtfile };
         chomp(@logprec);
         $result = join("\n", @logprec);
         push @clogp, $result;
      }
   }
   qx { rm -r "/tmp/clogp$$" } if $remove;
   chomp(@clogp);
   $result = join(" ", @clogp);
   @clogp = split(/\|/, $result);
   return wantarray ? @clogp : scalar(@clogp);
}

sub ExecTpsa
{
   my ($params, $inputfile) = @_;
   my @tpsa = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   $rc = &SetupDaylightEnv;
   @tpsa = qx{ /usr/local/bin/scripts/tpsa.pl $params <$inputfile 2>/dev/null };
   print ("DEBUG: /usr/local/bin/scripts/tpsa.pl $params <$inputfile 2>/dev/null\n") if $DEBUG;
   return wantarray ? @tpsa : scalar(@tpsa);
}

sub ExecFlexibility
{
   my ($params, $inputfile) = @_;
   my @flex = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   $rc = &SetupDaylightEnv;
   @flex = qx{ /usr/local/bin/scripts/flexibility.pl $params <$inputfile 2>/dev/null };
   print ("DEBUG: /usr/local/bin/scripts/flexibility.pl $params <$inputfile 2>/dev/null\n") if $DEBUG;
   return wantarray ? @flex : scalar(@flex);
}

sub ExecRotBond
{
   my ($params, $inputfile) = @_;
   my @rotbonds = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   $rc = &SetupDaylightEnv;
   @rotbonds = qx{ /usr/local/bin/scripts/RotBond.pl $params <$inputfile 2>/dev/null }; 
   print ("DEBUG: /usr/local/bin/scripts/RotBond.pl $params <$inputfile 2>/dev/null\n") if $DEBUG;
   return wantarray ? @rotbonds : scalar(@rotbonds);
}

sub ExecCmr
{
   my ($params, $inputfile) = @_;
   my @cmr = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   $rc = &SetupDaylightEnv;
   @cmr = ExecClogP($params, $inputfile, 1); 
   return wantarray ? @cmr : scalar(@cmr);
}

sub ExecReadTDT
{
   my @tdtchunks = ();
   my $inputfile = shift(@_);

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   open(TDT, "<$inputfile") || die "Could not read TDT-file $inputfile : $!\n";
   # this line of code should replace the chunk following it .. doesnt seem to work though.
   #@tdtchunks = split(/^\|$/m, <TDT>);
   # start of chunk
   while (<TDT>) {
      s/\| /\|/;   #remove exsessive blanks after record separator
      push @tdtchunks, $_;
   }
   close(TDT);
   chomp(@tdtchunks);
   $result = join('', @tdtchunks);
   @tdtchunks = split(/\|/, $result);
   # end of chunk
   return wantarray ? @tdtchunks : scalar(@tdtchunks);
}

sub ExecMol2Smi
{
   my ($params, $inputfile, $outputfile, $logfile) = @_; 

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply outputfile. Terminated.") if (!defined($outputfile));

   $logfile = (length($logfile) > 0) ? $logfile : '/tmp/mol2smi' . $$ . '.log';
   $rc = SetupDaylightEnv;
   #qx { $MOL2SMI -output_format TDT -write_2d FALSE -write_3d FALSE < $file > $tmp_file 2>$tmp_file.log };
   qx { $MOL2SMI $params < $inputfile > $outputfile 2>$logfile } unless $rc;
   print ("DEBUG: $MOL2SMI $params < $inputfile > $outputfile 2>$logfile\n") if $DEBUG;
   my $rc = $?;
   RemoveQuotesFromTDTFile($outputfile);
   return $rc;
}

sub RemoveQuotesFromTDTFile
{
	my ($tdtfile) = @_;
   	croak("Must supply inputfile. Terminated.") if (!defined($tdtfile));

	open (MYFILE, "<$tdtfile") or croak ("Cannot read $tdtfile. Terminated.");
	my @lines = <MYFILE>;
	close (MYFILE);
	open (MYFILE, ">$tdtfile") or croak ("Cannot write $tdtfile. Terminated.");
	foreach (@lines) {
		s/<\"/</;
		s/\">/>/;
		print MYFILE;
	}
	close (MYFILE);
}

sub ExecSmi2Mol
{
   my ($params, $inputfile, $outputfile) = @_; 

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply outputfile. Terminated.") if (!defined($outputfile));

   $rc = SetupDaylightEnv;
   qx { $SMI2MOL $params < $inputfile > $outputfile 2>/dev/null } unless $rc;
   print ("$SMI2MOL $params < $inputfile > $outputfile 2>/dev/null\n");
   return $?;
}

sub ExecPlogP
{
   my ($params, $inputfile) = @_;
   my @plogp = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply params. Terminated.") if (!defined($params));

   $rc = &SetupPallasEnv;

   &Sdf2PallasSdf("$inputfile", "$inputfile.pallas");

   #@plogp = qx{ $PROLOGP -ityp sdf -idfld COMP_ID -det /dev/null $SDF_FILE 2>/dev/null }; 
   @plogp = qx{ $PROLOGP $params $inputfile.pallas 2>/dev/null } unless $rc; 
   print ("DEBUG: $PROLOGP $params $inputfile.pallas 2>/dev/null\n") if $DEBUG;
   return wantarray ? @plogp : scalar(@plogp);
}

sub ExecPkaPkb
{
   my ($params, $inputfile) = @_;
   my @results = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply params. Terminated.") if (!defined($params));

   $rc = &SetupPallasEnv;
   #@results = qx { $PKALC -ityp sdf -idfld COMP_ID -det /tmp/prologp -vert $SDF_FILE 2>/dev/null };

   &Sdf2PallasSdf("$inputfile", "$inputfile.pallas");

   @results = qx { $PKALC $params $inputfile.pallas 2>/dev/null };
   print ("DEBUG: $PKALC $params $inputfile.pallas 2>/dev/null\n") if $DEBUG;
   chomp(@results);
   return wantarray ? @results : scalar(@results);
}

sub ExecSlogPv3
{
   my ($params, $inputfile) = @_;
   my @slogp = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply params. Terminated.") if (!defined($params));
   
   $rc = &SetupDaylightEnv;
   @slogp = qx { /usr/local/bin/scripts/slogpv3.pl $params < $inputfile 2>/dev/null };
   print ("/usr/local/bin/scripts/slogpv3.pl $params < $inputfile 2>/dev/null\n");
   return wantarray ? @slogp : scalar(@slogp);
}

sub ExecSlogPv2
{
   my ($params, $inputfile) = @_;
   my @slogp = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply params. Terminated.") if (!defined($params));

   $rc = &SetupDaylightEnv;
   #@slogp = qx{ /usr/local/bin/scripts/slogpv2.pl -q -s -id 'COMP_ID' <$tmp_file 2>/dev/null };
   @slogp = qx { /usr/local/bin/scripts/slogpv2.pl $params < $inputfile };
   print ("DEBUG: /usr/local/bin/scripts/slogpv2.pl $params < $inputfile\n") if $DEBUG;
   return wantarray ? @slogp : scalar(@slogp);
}

sub ExecSmr
{
   my ($params, $inputfile) = @_;
   my @smr = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply params. Terminated.") if (!defined($params));

   #@smr = qx{ /usr/local/bin/scripts/slogpv2.pl -MR -q -s -id 'COMP_ID' <$tmp_file 2>/dev/null };
   #@smr = qx{ /usr/local/bin/scripts/slogpv2.pl $params < $inputfile 2>/dev/null };
   @smr = &ExecSlogPv2($params, $inputfile);
   return wantarray ? @smr : scalar(@smr);
}

sub ExecHBondA
{
   my ($params, $inputfile) = @_;
   my @hba = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply params. Terminated.") if (!defined($params));

   #@hba = qx{ /usr/local/bin/scripts/hbond.pl -hba -id 'COMP_ID' <$tmp_file 2>/dev/null };
   @hba = qx{ /usr/local/bin/scripts/hbond.pl -hba $params < $inputfile 2>/dev/null };
   print ("DEBUG: /usr/local/bin/scripts/hbond.pl -hba $params < $inputfile 2>/dev/null\n") if $DEBUG;
   return wantarray ? @hba : scalar(@hba);
}

sub ExecHBondD
{
   my ($params, $inputfile) = @_;
   my @hbd = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply params. Terminated.") if (!defined($params));

   #@hbd = qx{ /usr/local/bin/scripts/hbond.pl -hbd -id 'COMP_ID' <$tmp_file 2>/dev/null };
   @hbd = qx { /usr/local/bin/scripts/hbond.pl -hbd $params < $inputfile 2>/dev/null };
   print ("DEBUG: /usr/local/bin/scripts/hbond.pl -hbd $params < $inputfile 2>/dev/null\n") if $DEBUG;
   return wantarray ? @hbd : scalar(@hbd);
}


sub ExecHBond
{
   my ($hbond, $params, $inputfile) = @_;
   my %Bonds = ( "HBA"       => \&ExecHBondA,
                 "HBD"       => \&ExecHBondD,
                 "_default_" => \&ExecUnknown,
               );
   my @hb = ();

   croak("Must supply bondtype. Terminated.") if (!defined($hbond));
   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply parameters for bond calculation. Terminated.") if (!defined($params));

   if (exists $Bonds{$hbond}) {
      $rsub = $Bonds{$hbond};
      @hb = &$rsub($params, $inputfile);
   } else {
      $rsub = $Bonds{"_default_"};
      &$rsub();
   }
   return wantarray ? @hb : scalar(@hb);
}

sub ExecAmw
{
   my $inputfile = shift(@_);
   my @amw = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));

   @amw = qx{ $ADDMWT < $inputfile 2>/dev/null };
   print ("DEBUG: $ADDMWT < $inputfile 2>/dev/null\n") if $DEBUG;
   chomp(@amw);
   $result = join(" ", @amw);
   @amw = split(/\|/, $result);
   return wantarray ? @amw : scalar(@amw);
}

sub ExecConnolly
{
   my ($datafile1, $datafile2, $inputfile) = @_;
   my @surface = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   $rc = &SetupQcpeEnv;
   unless ($rc) {
      $datafile1 = defined($datafile1) ? $datafile1 : './file1.dat';
      $datafile2 = defined($datafile2) ? $datafile2 : './file2.dat';
      @surface = qx{ $CONNOLLY $datafile1 $datafile2 $inputfile };
      print ("DEBUG: $CONNOLLY $datafile1 $datafile2 $inputfile\n") if $DEBUG; 
   }
   return wantarray ? @surface : scalar(@surface);
}

sub ExecPrologD
{
   my ($params, $inputfile) = @_;
   my @plogd = ();

   croak("Must supply inputfile. Terminated.") if (!defined($inputfile));
   croak("Must supply parameters. Terminated.") if (!defined($params));
   $rc = &SetupPallasEnv;

   &Sdf2PallasSdf("$inputfile", "$inputfile.pallas");

   #@plogd = qx{ $PROLOGD -ityp sdf -idfld COMP_ID -det /tmp/prologp_ttt -pH 7.4 $SDF_FILE 2>/dev/null };
   @plogd = qx{ $PROLOGD $params $inputfile.pallas 2>/dev/null } unless $rc;
   print ("DEBUG: $PROLOGD $params $inputfile.pallas 2>/dev/null\n") if $DEBUG;
   return wantarray ? @plogd : scalar(@plogd);
}

#sub WriteXMLError
#{
#  my ($source, $source_msg) = @_;
#  my ($line1, $line2, $errmsg, $error, $err_no, $err_context, $line);
#
#  ($line1, $line2, undef) = split(/\n/, $source_msg, 3);
#  if (length($line1)) {
#     (undef, $error, $errmsg) = split(/\s+/, $line1, 3);
#     if ($error =~ /ERROR-([0-9]{2,}):/) {
#        $err_no = $1;
#        if (length($line2)) {
#           (undef, undef, $err_context) = split(/\s+/, $line2, 3);
#        } else {
#           $err_context = $errmsg;
#        }
#     } else {
#        $err_no = 6; #unspecified XML error
#        $err_context = $errmsg = 'parsing problem';
#     }
#  } else {
#     if ($line2 =~ /(.*) (at line.*) at.*/) {
#        $err_no = 6;
#        $errmsg = $1;
#        $err_context = $2;
#     } else {
#        $err_no = 6; #unspecified XML error
#        $err_context = $errmsg = 'parsing problem';
#     }
#  }
#  my $xmlref = { error => {  source => $source,
#                             value => [ $err_no ],
#                             msg => [ $errmsg ],
#                             context => [ $err_context ],
#                          },
#               };
#  #my $xml = XMLout($xmlref, rootname => 'data');
#  #print STDERR $xml;
#  return XMLout($xmlref, rootname => 'data');
#}

sub GetPeriodicTable
{
   my ($elem, $param) = @_;
   # possible param values :
   #    'atom_no', 'atom_weight', 'group', 'period'

   croak("Must supply periodic table element. Terminated.") if (!defined($elem));
   croak("Must supply element attribute. Terminated.") if (!defined($param));
   if ($param ne 'atom_no' && $param ne 'atom_weight' && $param ne 'group' && $param ne 'period') {
      croak("Incorrect element attribute. Terminated.");
   }
   return exists($$PERIODIC_TABLE{$elem}) ? $$PERIODIC_TABLE{$elem}->{$param} : 0;
}

$| = 1;

1;
