#!/usr/local/bin/perl

##############################################################################
#
# qsarcalc.pl: CGI script for CCI
#
# 0.1: marcel
#	- initial version
# 0.2: tom@011219
#	- added HERG calculation and links to HERGtemplate (XLS and TXT file)
# 0.3: tom@011220
#	- limited display (in Excel file and on-screen) of PKA to a single MIN
#		value, and PKB to a single MAX value
#
##############################################################################
# RCS ID: 
# 	$Id: qsarcalc.pl,v 1.4 2002/03/13 16:46:14 tmcwebadm Exp $
#
# RCS History:
#	$Log: qsarcalc.pl,v $
#	Revision 1.4  2002/03/13 16:46:14  tmcwebadm
#	added '-add_2d FALSE' to SMI2MOL so we do no longer get
#	  the "Invalid license: 'depict' toolkit not authorized."
#	  message
#
#	Revision 1.3  2002/03/12 20:29:22  root
#	'bs' spec in serverroot path removed
#
#	Revision 1.2  2002/03/12 20:24:54  tmcwebadm
#	replace /db/www with /data/www for the hardcoded server root path
#
#	Revision 1.1  2002/03/04 20:23:24  root
#	Initial revision
#
##############################################################################


################################################################################
#                                                                              #
# VARIABLES                                                                    #
#                                                                              #
################################################################################

# MODULES
use FileUpload;
use DBI;
use Env;
use DayPerl;
use CGI qw(-private_tempfiles :standard);
use File::MkTemp;
use IO::Handle;
use IO::File;
use lib "/usr/local/bin/scripts/automation";
use Modules::TMCDefs;
use Modules::TMCSubs;
use Modules::TMCOracle;
use lib "/usr/people/mengels/src/perl/chemtools";
use MY_TOOLS;
use DU_LIB5;
require DU_TLIB5;


use CGI::Carp 'fatalsToBrowser';

# ENVIRONMENT VARIABLES
&SetupDaylightEnv;
&SetupPallasEnv;

my $ROOTDIR = ($ENV{'SERVER_PORT'} == 81) ? '/data/www/dvl/cci/dat/' : '/data/www/rls/cci/dat/';
my ($TDTfileName, $SDFfileName);
my $ERROR_LIMIT = 60;
my $pH_logd = 7.4;
my $pH_charge;

# FILE NAMES
$CUBISTfileName = "Cubist/t183.o1.general";

open(STDERR, ">/dev/null");
# SET UMASK: rw-------
umask(127);

# Upload limitation
my $MAX_SIZE_UPLOAD = 3000; # K, return an 'Internal Server Error' on oversized files
$CGI::POST_MAX=1024 * $MAX_SIZE_UPLOAD;
my $upload_file;

# DBI ORACLE DATABASE HANDLE
my $dbh;

# COMPOUND & PROPERTY hashes
my (%compound, @moleculeList, @propertyList) = ((),(),());
my (%smilesHash, %HERGHash, %EFHash, %CLOGPHash, %LOGDHash, %CMRHash, %SMRHash, %HBAHash) = ((),(),(),(),(),(),(),());
my (%HBDHash, %PKAHash, %PKBHash, %MWHash, %MIMHash, %CHARGEHash, %ROFHash, %RBHash) = ((),(),(),(),(),(),(),());
my (%FLEXHash, %QTHash, %TPSAHash, %BBBHash) = ((),(),(),());

# Mark as Not Found/Not calculated/not Available
my $NC = '-';

my %Properties  = ( 'CLOGP' => \&getCLOGP,
                    'SLOGP' => \&getSLOGP,
                    'LOGD'  => \&getLOGD,
                    'EF'    => \&getEF,
                    'CMR'   => \&getCMR,
                    'SMR'   => \&getSMR,
                    'HB'    => \&getHB,
                    'PK'    => \&getPK,
                    'MW'    => \&getMW,       # MW, MIM
                    'CHARGE'=> \&getCHARGE,
                    'QT'    => \&getQT,
                    'ROF'   => \&getROF,
                    'RB'    => \&getRB,
                    'FLEX'  => \&getFLEX,
                    'BBB'   => \&getBBB,
                    'TPSA'  => \&getTPSA,
                    'HERG'  => \&getHERG,
                  );

my %Parameters = ( 'structures' => 'CHEMISTRY',
                   'ef_flag'    => 'EF',
                   'logd_flag'  => 'LOGD',
                   'cmr_flag'   => 'CMR',
                   '_smr_flag'  => 'SMR',
                   'hb_flag'    => 'HB',
                   'pk_flag'    => 'PK',
                   'mw_flag'    => 'MW',
                   'charge_flag' => 'CHARGE',
                   'rb_flag'    => 'RB',
                   'flex_flag'  => 'FLEX',
                   'rof_flag'   => 'ROF',
                   'qt_flag'    => 'QT',
                   'bbb_flag'   => 'BBB',
                   '_tpsa_flag' => 'TPSA',  # underscore because of reverse sort order .. structure must be 2nd column
                   'herg_flag'  => 'HERG',
                   'clogp_flag'  => 'CLOGP',
                   '_slogp_flag'  => 'SLOGP',
                 );

################################################################################
#                                                                              #
# PROCESS THE INPUT AND PUT THE MOLECULE NAMES IN A LIST CALLED 'MOLECULELIST' #
#                                                                              #
################################################################################

# FIRST CASE: INPUT FROM THE CLIENT IS A LIST OF R-NUMBERS
if (param('rlist')) {
  $_ = param('rlist');
  # IF THERE IS AN HYPHEN AT THE START, REPLACE IT WITH "1 - "
  s/^\-/1 - /;
  # REMOVE ALL NON-DIGIT CHARACTERS AT THE BEGINNING
  s/^\D+//;
  # REPLACE ALL NON-DIGITS (EXCEPT THE HYPHEN) WITH WHITESPACE
  s/[^\-\d]/ /g;
  # EMBED HYPHENS WITH WHITESPACE
  s/\-/ \- /g;
  # LOOK FOR THE OCCURENCE OF SUBSEQUENT HYPHENS
  s/\s+\-\s+\-/ \- /g;
  # TRANSFORM THE STRING INTO AN LIST
  @t = split;
  # SCAN THE LIST FOR POSSIBLE HYPHENS
  $hyphen = 0;
  for ($i = 0; $i <= $#t; $i++) {
    if ($t[$i] eq '-') {
      $hyphen = $i;
      last;
    }
  }
  # IF A HYPHEN HAS BEEN FOUND
  while ($hyphen) {
    # COPY THE STRING PRECEDING THE HYPHEN TO @TEMP
    undef @temp;
    for ($i = 0; $i < $hyphen - 1; $i++) {
      push(@temp, $t[$i]);
    }
    # EXPAND THE HYPHEN
    $start = $t[$hyphen - 1];
    $stop = $t[$hyphen + 1];
    if ($start > $stop) {
      $temp = $start;
      $start = $stop;
      $stop = $temp;
    }
    for ($i = $start; $i <= $stop; $i++) {
      push(@temp, $i);
    }
    # ADD THE REST OF THE LIST
    for ($i = $hyphen +2; $i <= $#t; $i++) {
      push(@temp, $t[$i]);
    }
    # START NEW ROUND
    @t = @temp;
    undef (@temp);
    $hyphen = 0;
    for ($i = 0; $i <= $#t; $i++) {
      if ($t[$i] eq '-') {
        $hyphen = $i;
        last;
      }
    }
  }
  foreach (@t) {
    #push(@moleculeList, sprintf("R%d", $_));
    if (/^([0-9]{1,})$/) {
       $key = $1;
       # we now have numeric part .. if > 6, take only 6 right most chars
       #                             if < 6, padd with zeros (for now)
       if (length($key) > $RNUM_LEN) {
          $key = $1 if $key =~ /[0-9]*([0-9]{$RNUM_LEN})/;
       } else {
          $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
       }
    }
    push(@moleculeList, $key);
  }
}
if (param('file')) {
   my ($n2, $buf);

   $_ = $file_query = param('file');
   s/\w://;
   s/([^\/\\]+)$//;
   $_ = $1;
   s/\.\.+//g;
   s/\s+//g;
   $source_file = $_;
   if (!$source_file) {
      printError('Data Entry', "Error. Invalid source file\n",0);
   } else {
      my $targ_file_name = File::Spec->catfile(mktemp(tempXXXXXX));
      my $fullpath = $ROOTDIR . $targ_file_name . '.' . param('filetype');
      open(TARGET, "+>$fullpath") || printError('Data Entry',"Error opening file $fullpath for writing, error $!",0);
      binmode TARGET;
      while (read($file_query, $buf, 1024)) {
        $buf =~ s/\r\n/\n/g;   # substitute \r\n into \r .. damn this Gates guy
        print TARGET $buf;
      }
      close(TARGET);
      if ((stat "$fullpath")[7] <= 0) {
         printError('Data Entry', "Nothing uploaded\n", 0);
      } else {
         #printError('Data Entry', "Upload OK\n", 0);
         # I do this conversion, just for easy Rno retrieval
         if (param('filetype') eq 'sdf') {
            # do some elementary checks on valid input
            open(TARGET, "<$fullpath");
            @data = <TARGET>;
            close(TARGET);
            @dollars = grep (/\$\$\$\$/, @data);
            printError('Data Entry', "Not a valid SD file\n", 0) if !scalar(@dollars);
            my $mol2smi_params = '-output_format TDT -write_2d FALSE -write_3d FALSE -id COMPID';
            if (ExecMol2Smi($mol2smi_params , "$fullpath", "$fullpath.tdt", '/dev/null')) {
               unlink "$fullpath.tdt", "$fullpath";
               printError('Mol2Smi', "Could not convert SDF file to TDT file.", 0);
            }
            my @chunks_tdt = ();
            @chunks_tdt = ExecReadTDT("$fullpath.tdt");
            foreach $chunk (@chunks_tdt) {
               chomp($chunk);
               next if $chunk =~ /^\$SMIG/;
               $smi = &FindItem($chunk, '\$SMI');
               $smi = $ERR_SMILESNOTAVAIL if ! $smi;
               $key = '';
               LASTID : foreach $id ('COMPNAME', 'JNJS', 'JNJ', 'COMPID', 'COMP_ID', '\$NAM', '\$RNR') {
                  $key = &FindItem($chunk, $id);
                  last LASTID if length($key);
               }
               unless ($key) {
                  $compound{$smi} = $smi;
               }  else {
                  $compound{$smi} = $key;
               }
               printError('Data Entry', "Invalid smiles encoutered.\n", 0) if dt_smilin($smi) == NULL_OB;
               $molecule = dt_smilin($smi);
               push(@moleculeList, dt_cansmiles($molecule, 1));
               dt_dealloc($molecule);
            }
         } elsif (param('filetype') eq 'smiles') {
            open(SMI, "<$fullpath") || printError('Error', "Could not open SMILES file.", 0);
            while (<SMI>) {
               chomp;
               ($smi, $key, undef) = split(/\s+/, $_, 3);
               printError('Data Entry', "Invalid smiles encoutered.\n", 0) if dt_smilin($smi) == NULL_OB;
               push(@moleculeList, $smi);
            }
            close(SMI);
         } else {
           # must be compound ids
           # this is a free format list r1, r2, r3  or r1-r5 or a compound spec per line
           open(RNO, "<$fullpath") || printError('Error', "Could not open COMPOUND file $fullpath", 0);
           my @tmp = <RNO>;
           $data = grep(!/R?[0-9]+/, @tmp);
           printError('Data Entry', "Invalid compound id list.\n",0) if $data;
           @data = grep(/[A-QS-Z]/, @tmp);
           printError('Data Entry', "Invalid compound id list.\n",0) if scalar(@data);
           close(RNO);
           $_ = join('',@tmp);
           chomp;
           s/,/ /g;
           # this code is a copy of CASE 1
           s/^\-/1 - /;
           s/^\D+//;
           s/[^\-\d]/ /g;
           s/\-/ \- /g;
           s/\s+\-\s+\-/ \- /g;
           @t = split;
           $hyphen = 0;
           for ($i = 0; $i <= $#t; $i++) {
             if ($t[$i] eq '-') {
               $hyphen = $i;
               last;
             }
           }
           while ($hyphen) {
             my @temp = ();
             for ($i = 0; $i < $hyphen - 1; $i++) {
               push(@temp, $t[$i]);
             }
             $start = $t[$hyphen - 1];
             $stop = $t[$hyphen + 1];
             if ($start > $stop) {
               $temp = $start;
               $start = $stop;
               $stop = $temp;
             }
             for ($i = $start; $i <= $stop; $i++) {
               push(@temp, $i);
             }
             for ($i = $hyphen +2; $i <= $#t; $i++) {
               push(@temp, $t[$i]);
             }
             @t = @temp;
             undef (@temp);
             $hyphen = 0;
             for ($i = 0; $i <= $#t; $i++) {
               if ($t[$i] eq '-') {
                 $hyphen = $i;
                 last;
               }
             }
           }
           foreach $key (@t) {
               if ($key =~ /^[rR]?([0-9]{1,})$/) {
                  $key = $1;
                  # we now have numeric part .. if > 6, take only 6 right most chars
                  #                             if < 6, padd with zeros (for now)
                  if (length($key) > $RNUM_LEN) {
                     $key = $1 if $key =~ /[0-9]*([0-9]{$RNUM_LEN})/;
                  } else {
                     $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
                  }
               }
               push(@moleculeList, $key);
           }
         }
      }
   }
}
if (param('slist')) {
   $_ = param('slist');
   s/,/ /g;
   @t = split /\s+/;
   for ($i = 0; $i < scalar(@t); $i++) {
      $molecule = dt_smilin($t[$i]);
      push(@moleculeList, dt_cansmiles($molecule, 1));
      dt_dealloc($molecule);
   }
}
if (param('smi')) {
  # CANONICALIZE THE SMILES STRING
  $molecule = dt_smilin(param('smi'));
  # ADD IT TO THE nameList
  #push(@moleculeList, param('smi'));
  push(@moleculeList, dt_cansmiles($molecule, 1));
  # DEALLOCATE MOLECULE
  dt_dealloc($molecule);
}

if (!param('rlist') && ! param('smi') && !param('slist') && !param('file')) {
  # THIRD CASE: AN ERROR OCCURED
  printError('Data Entry Error', "Error. No molecules submitted. Try again.\n", 0);
}


################################################################################
#                                                                              #
# FILL UP THE SMILESHASH                                                       #
#                                                                              #
################################################################################
# Connect to Oracle for CHAROn data
&SetupOracleEnv;
#DBI->trace(2);
$dbh = DBI->connect("DBI:Oracle:$ORA_SID", $ORA_R_USER, $ORA_R_PWD, { RaiseError => 1, AutoCommit => 0 });
printError('CHAROn connect error', "Error. Unable to connect to $ORA_SID\n", 0) if $DBI::err;

# Get list of properties from CHAROn
my $select = $dbh->prepare( q{  SELECT PROP_MEMO, PROP_ID
                                FROM TMC.TB_PROPERTY
                             }
                          ) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
$select->execute || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
while (($name, $id) = $select->fetchrow_array) {
   printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
   $prop{$name} = $id;
}

# filter out doubles ..
my %tempHash = ();
foreach $entry (@moleculeList) {
   $tempHash{$entry} = $entry;
}
@moleculeList = keys(%tempHash);
undef %tempHash;

foreach $entry (@moleculeList) {
  # FIRST CASE: COMPOUND IS R-NUMBER.
  # RETRIEVE SMILES FROM CHARON AND CONVERT IT TO MOLECULE OBJECT
  if ($entry =~ /^[Rr]?([0-9]{1,})$/) {
    $molecule = $1;
    # Get the smiles from CHAROn
    my $select = $dbh->prepare( q{ SELECT SMILES, COMP_TYPE
                                   FROM TMC.TB_SMILES
                                   WHERE COMP_NR = ?
                                 }
                              ) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
    $select->execute($molecule) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
    ($smiles, $comp_type) = $select->fetchrow_array;
    printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
    $smilesHash{$molecule} = ((defined($smiles) && $smiles ne $ERR_SMILESNOTAVAIL) ? $smiles : $ERR_SMILESNOTAVAIL);
    $compound{$molecule} = $comp_type;
  } else {
    # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
    # THE ENTRY NAME IS NOTHING MORE THAN THE CANONONICAL SMILES ITSELF.
    $smilesHash{$entry} = $entry;
  }
}


################################################################################
#                                                                              #
# CREATE A PROPERTYLIST TO STORE THE LIST OP PROPERTIES                        #
#                                                                              #
################################################################################
my $been_here = 0;
foreach $parameter (sort { $b cmp $a } keys %Parameters) {
  if (param($parameter)) {
     push(@propertyList, $Parameters{$parameter});
     if ($parameter eq 'qt_flag' && param('qt_flag') && param('all')) {
        push(@propertyList, $Parameters{'logd_flag'});
        push(@propertyList, $Parameters{'hb_flag'});
        push(@propertyList, $Parameters{'rb_flag'});
     }
     if ($parameter eq 'herg_flag' && param('herg_flag') && param('all')) {
        push(@propertyList, $Parameters{'cmr_flag'});
        push(@propertyList, $Parameters{'_tpsa_flag'});
     }
     if (param('all') && ($parameter eq 'qt_flag' or $parameter eq 'herg_flag') && !$been_here) {
        push(@propertyList, $Parameters{'clogp_flag'});
        push(@propertyList, $Parameters{'pk_flag'});
        $been_here = 1;
     }
  }
}

################################################################################
#                                                                              #
# GO THROUGH THE LIST OF REQUIRED PROPERTIES AND CALCULATE THE PROPERTY        #
# OF EACH MOLECULE WHICH HAS A VALID SMILES STRING.                            #
# STORE EACH PROPERTY IN ITS DEDICATED HASH:-                                  #
#    CLOGP   ->      LOGPHASH                                                   #
#    SLOGP   ->      LOGPHASH                                                   #
#    LOGD   ->      LOGDHASH                                                   #
#    CMR     ->      MRHASH                                                     #
#    SMR     ->      MRHASH                                                     #
#    HBA    ->      HBAHASH, HBDHASH                                           #
#    HBD    ->      HBAHASH, HBDHASH                                           #
#    PKA    ->      PKAHASH, PKBHASH                                           #
#    PKB    ->      PKAHASH, PKBHASH                                           #
#    MW     ->      MWHASH, NUMBEROFATOMSHASH                                  #
#    MIM    ->      MIMHASH                                                    #
#    EF     ->      EFHASH                                                     #
#    CHARGE ->      CHARGEHASH                                                 #
#    ROF    ->      ROFHASH                                                    #
#    QT     ->      QTHASH                                                     #
#    RB     ->      RBHASH                                                     #
#    FLEX   ->      FLEXHASH                                                     #
#                                                                              #
################################################################################
foreach $property (sort @propertyList) {
  if (exists $Properties{$property}) {
     &{$Properties{$property}}();
  }
}

################################################################################
#                                                                              #
# OUTPUT SECTION                                                               #
#                                                                              #
################################################################################

print "Content-type: text/html\n\n";
print "<html>\n";
print "<head><title>Qsar predictions</title>\n";
print "<link rel=\"stylesheet\" href=\"/css/cci.css\" type=\"text/css\">\n</head>\n";

### tom@020205 - MARVIN: add script links
print "<body BGCOLOR=\"#ffffff\" onLoad=\"links_set_search(location.search)\">\n";

print "<script LANGUAGE=\"JavaScript1.1\" SRC=\"/marvin/marvin.js\"></script>\n";

# OPEN THE EXCEL FILE
my $fileName = File::Spec->catfile(mktemp(tempXXXXXX));
my $EXCELfileName =  '../dat/' . $fileName . '.xls';
open (XLSFILE, ">$EXCELfileName");

print XLSFILE "COMPOUND";

foreach $property (@propertyList) {
  if ($property eq 'LOGD') {
    print XLSFILE "\t$property", " [$pH_logd]";
  } elsif ($property eq 'CHARGE') {
    print XLSFILE "\t$property", " [$pH_charge]";
  } elsif ($property eq 'PK') {
    print XLSFILE "\tPKa_BASE(MAX)";
    if (param('all') && param('herg_flag')) {
       print XLSFILE "\tPKa_ACID(MIN)";
    }
  } elsif ($property eq 'QT') {
    print XLSFILE "\tT183.O1 [%HRF] GENERAL";
  } elsif ($property eq 'HERG') {
    print XLSFILE "\tHERG pIC > 6.9";
  } elsif ($property eq 'MW') {
    print XLSFILE "\tMW\tMIM";
  } elsif ($property eq 'HB') {
    print XLSFILE "\tHBD";
  } else {
    print XLSFILE "\t$property";
  }
}
print XLSFILE "\n";

# GO THROUGH THE LIST OF MOLECULES AND PRINT THE PROPERTIES TO THE EXCEL FILE
foreach $entry (sort { $a <=> $b } @moleculeList) {
  next if not defined $smilesHash{$entry};
  if (param('file') && param('filetype') eq 'sdf') {
     print XLSFILE $compound{$entry};
  } else {
     print XLSFILE $compound{$entry},$entry;
  }
  foreach $property (@propertyList) {
    if ($property eq 'HERG') {
      if ($HERGHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        chomp($HERGHash{$entry});
        print XLSFILE "\t", $HERGHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'EF') {
      if ($EFHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        chomp($EFHash{$entry});
        print XLSFILE "\t", $EFHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'CLOGP') {
      if (defined($CLOGPHash{$entry})) {
         print XLSFILE "\t", $CLOGPHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'SLOGP') {
      if ($SLOGPHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $SLOGPHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'LOGD') {
      if (defined($LOGDHash{$entry}) && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $LOGDHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'CMR') {
      if ($CMRHash{$entry}) {
        print XLSFILE "\t", $CMRHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'SMR') {
      if ($SMRHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $SMRHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'HB') {
      #if (($HBAHash{$entry} || $HBAHash{$entry} eq '0') && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
      #  print XLSFILE "\t", $HBAHash{$entry};
      #} else {
      #  print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      #}
      if (($HBDHash{$entry} || $HBDHash{$entry} eq '0') && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $HBDHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'PK') {
       if ($PKBHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
	  ($dummy) = sort { $b <=> $a } (split(/ /, $PKBHash{$entry}));		## get the MAX value
          print XLSFILE "\t$dummy";
       } else {
          print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
       }
       if (param('all') && param('herg_flag')) {
          if ($PKAHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
	    ($dummy) = sort { $a <=> $b } (split(/ /, $PKAHash{$entry}));	## get the MIN value
            print XLSFILE "\t$dummy";
          } else {
            print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
          }
       }
    } elsif ($property eq 'MW') {
      if ($MWHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $MWHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
      if ($MIMHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $MIMHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'CHARGE') {
      if (($CHARGEHash{$entry} || $CHARGEHash{$entry} eq '0') && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $CHARGEHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'ROF') {
      if (($ROFHash{$entry} || $ROFHash{$entry} eq '0') && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $ROFHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'RB') {
      if (($RBHash{$entry} || $RBHash{$entry} eq '0') && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $RBHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'FLEX') {
      if ($FLEXHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $FLEXHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'QT') {
      if ($QTHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
         print XLSFILE "\t", $QTHash{$entry};
      } else {
         print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'CHEMISTRY') {
      print XLSFILE "\t", $smilesHash{$entry};
    } elsif ($property eq 'TPSA') {
      if ($TPSAHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $TPSAHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'BBB') {
      if ($BBBHash{$entry} && $smilesHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $BBBHash{$entry};
      } else {
        print XLSFILE (($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    }
  }
  print XLSFILE "\n";
}

# CLOSE THE EXCEL FILE
close(XLSFILE);

# OPEN THE EXCEL FILE FOR READING
open(XLSFILE, "<$EXCELfileName");

# READ THE FIRST LINE FROM THE EXCEL FILE AND PRINT TO STDOUT IN TABLE FORMAT
$_ = <XLSFILE>;
@line = split(/\t+/);

print "<font face=\"Arial, Geneva\" size=\"+2\" color=\"#000066\">\n";
print "<b>QSARCALC RESULTS</b><br>\n";
print "</font>\n";
print "<font face=\"Arial, Geneva\" size=\"0\" color=\"#000066\">\n";
print "Click on the <b>compound<\/b> entry to view the CORINA 3D geometry.<br>\n";
print "(WebLab Viewer needs to be installed on your PC: <a href=\"/download.shtml\">install</a>)<p>\n";
print "</font>\n";
print "<table border=\"0\" frame=\"vsides\" rules=\"cols\" cellpadding=\"3\" cellspacing=\"0\">\n"; ## table 1

print "  <tr>\n";
$column = 0;


foreach (@line) {
  $anchor_begin = "";
  $anchor_end = "";
  if (/T183\.O1 \[\%HRF\] GENERAL/) {
    $anchor_begin = "<a style=\"color: white\" target=\"_blank\" href=\"/help_qsarcalc_t183_o1.html\">";
    $anchor_end = "</a>";
  }
  if (/HERG pIC/) {
     $anchor_begin = "<a style=\"color: white\" target=\"_blank\" href=\"/doc/decision_tree_model.ppt\">";
     $anchor_end = "</a>";
  }
  $column++;
  if ($column == 1) {
    $class = "head1L";
  } elsif ($column == 2) {
    $class = "head1C";
  } else {
    $class = "head1R";
  }
  chomp;
  print "    <td class=$class nowrap>${anchor_begin}$_${anchor_end}</td><td></td>\n";
}
print "  </tr>\n";
print "  <tr>\n";
print "    <td height=\"4\"></td>\n";
print "  </tr>\n";

# READ THE REST OF THE LINES AND PRINT TO STDOUT IN TABLE FORMAT
$row = 0;
while (<XLSFILE>) {
  $row++;
  if (($row % 2) == 0) { $entry = 1 } else { $entry = 2 }
  @line = split(/\t+/);
  print "  <tr>\n";
  $column = 0;
  foreach (@line) {
    $column++;
    chomp;
    if ($column == 1) {
      # filter off the 'R'-part to find the corresponding smiles entry in the hash
      if ($line[0] =~ /^[rR]?([0-9]{1,})$/) {
         $molecule = $1;
      } else {
         $molecule = $line[0];
      }
      if (param('filetype') ne 'sdf') {
         $temp_smiles = $smilesHash{$molecule};
      } else {
         $temp_smiles = (param('structures')) ? $line[1] : $smilesHash{$molecule};
      }
      $temp_smiles =~ s/\+/x/g;
      $temp_smiles =~ s/\#/y/g;
      $class = "entry" . $entry . "L";
      print "    <td class=$class nowrap>\n";
      print "      <a href=\"/bin/smi23d.pl\?smi=$temp_smiles\&rnr=$compound{$_}$_\">$_</a>\n";
      print "    </td><td></td>\n";
    } elsif (($column == 2) && (param('structures') eq "1")) {
      $class = "entry" . $entry . "C";
      print "    <td class=$class>\n";
      if (param('filetype') eq 'sdf' && param('file')) {
         $smileshex = a2hex($line[1]);
         print "      <a href=\"/bin/smi2gif-big-cop\?$smileshex\" target=\"_blank\">\n";
         print "      <img src=\"/bin/smi2gif-small-cop\?$smileshex\" width=\"96\" height=\"64\"></a>\n";
      } else {
         if ($smilesHash{$molecule} eq '') {
           print "      $NC\n";
         } else {
           if ($smilesHash{$molecule} eq $ERR_SMILESNOTAVAIL) {
              print "      <a href=\"#\"><img src=\"/icons/nosmiles.gif\" border=\"0\"></a>\n";
           } else {
	              #$smileshex = a2hex($smilesHash{$molecule});
	              #print "      <a href=\"/bin/smi2gif-big-cop\?$smileshex\" target=\"_blank\">\n";
	              #print "      <img src=\"/bin/smi2gif-small-cop\?$smileshex\" width=\"96\" height=\"64\"></a>\n";
	              print "<script LANGUAGE=\"JavaScript1.1\">\n";
		      print "<!--\n";
		      print "mview_begin(\"/marvin\", 120, 100);\n";
		      print "mview_param(\"molbg\", \"#ffffff\");\n";
		      print "mview_param(\"rows\", \"1\");\n";
		      print "mview_param(\"cols\", \"1\");\n";
		      print "mview_param(\"cell0\", \"|$smilesHash{$molecule}\");\n";
		      print "mview_end();\n";
		      print "//-->\n";
		      print "</script>";	             
           }
         }
      }
      print "    </td><td></td>\n";
    } else {
      $class = "entry" . $entry . "R";
      print "    <td class=$class nowrap>$compound{$_}$_</td><td></td>\n";
    }
  }
  print "  </tr>\n";
}
print "</table>\n";
close (XLSFILE);

# PRINT THE EXCEL HYPERLINK
if (%smilesHash) {
  print "<font face=\"Arial, Geneva\" size=\"+1\" color=\"#0000FF\">\n";
  print "<p><a href=\"$EXCELfileName\" target=\"_blank\">Excel spreadsheet</a>";
  print "</font>\n";
}



###START HERG TEST ADDITION (tom@011219) ####################################################

if (! (param('all') && param('herg_flag')) ) {			## only run when all parameters have been calculated
  	print "<font face=\"Arial, Geneva\" color=\"#0000FF\">\n";
       	print "<p>Note: Check <I>Herg channel</I> in \"toxicological properties\" and \n";
	print "<I>related parameters</I> in \"output\" on the previous screen to enable the HERG TEST\n";
  	print "</font>\n";
} else {

	$EXCELTemplate="../doc/ccitest.xls";

	# OPEN THE $EXCELTemplateInput FILE
	my $fileName = File::Spec->catfile(mktemp(tempXXXXXX));
	my $EXCELTemplateInput =  '../dat/' . $fileName . '.txt';
	open (TXTFILE, ">$EXCELTemplateInput");

	# GO THROUGH THE LIST OF MOLECULES AND CALCULATE PC1 and PC2
	foreach $entry (sort { $a <=> $b } @moleculeList) {
	  	next if not defined $smilesHash{$entry};

		undef($pc1);
		undef($pc2);
		undef($lv1);
		undef($lv2);


		if ( defined($CLOGPHash{$entry}) ) {
			$nclogp = ($CLOGPHash{$entry} - 3.8654)/2.0459;
		} else {
			$pc1 = $pc2 = '-';
		}

		if ( defined($CMRHash{$entry}) ) {
			$ncmr = ($CMRHash{$entry} - 110.4111)/34.0445;
		} else {
			$pc1 = $pc2 = '-';
		}

		if ( defined($TPSAHash{$entry}) || $TPSAHash{$entry} >= 0 ) {
			$ntpsa = ($TPSAHash{$entry} - 72.4755)/34.4644;
		} else {
			$pc1 = $pc2 = '-';
		}

		if ( defined($PKBHash{$entry})  ) {
			$PKBHash{$entry} = 0 if ($PKBHash{$entry} eq "-");
			$npkb = ($PKBHash{$entry} - 5.2235)/3.7809;
		}

		if ( defined($PKAHash{$entry}) ) {
			$PKAHash{$entry} = 14 if ($PKAHash{$entry} eq "-");
			$npka = ($PKAHash{$entry} - 12.8046)/2.9303;
		}

		if (! defined ($pc1) ) {		## pc1 has not been filled with a '-' yet
			$pc1 =
				- 0.6200 * $nclogp
				- 0.7011 * $ncmr
				- 0.1595 * $npka
				- 0.3025 * $npkb
				- 0.0840 * $ntpsa ;
			$pc2 =
				+ 0.0657 * $nclogp
				- 0.2470 * $ncmr
				+ 0.5886 * $npka
				+ 0.3207 * $npkb
				- 0.6967 * $ntpsa ;
			$lv1 =
				+ 0.6709 * $nclogp
				+ 0.4500 * $ncmr
				+ 0.3138 * $npka
				+ 0.1592 * $npkb
				+ 0.4728 * $ntpsa ;
			$lv2 =
				- 0.2765 * $nclogp
				- 0.2130 * $ncmr
				- 0.1741 * $npka
				+ 0.9037 * $npkb
				- 0.1766 * $ntpsa ;
		}

		print TXTFILE "$pc1\t$pc2\t$lv1\t$lv2\t### $entry: "
					. "clogp:$CLOGPHash{$entry} -> $nclogp  "
					. "cmr:$CMRHash{$entry} -> $ncmr  "
					. "pka:$PKAHash{$entry} -> $npka  "
					. "pkb:$PKBHash{$entry} -> $npkb  "
					. "tpsa:$TPSAHash{$entry} -> $ntpsa  "
					. "\n";
	}

	# CLOSE THE EXCEL FILE
	close(TXTFILE);

	# PRINT THE EXCEL HYPERLINK
	if (%smilesHash) {
      print "<BR><font face=\"Arial, Geneva\" color=\"#000000\">\n";
	  print "<p><a href=\"$EXCELTemplate\" target=\"_blank\">TEST: Excel HERG template (.xls)</a>";
	  print "<BR><a href=\"$EXCELTemplateInput\" target=\"_blank\">TEST: Excel HERG inputfile (.txt)</a>";
      print "<BR>These 2 files are still in a test phase. Contact " . 
      	    "<a href=\"mailto:cbuyck\@janbe.jnj.com\">cbuyck\@janbe.jnj.com</A> for more info";
	  print "</font>\n";
	}

###$$$




}



### END HERG TEST ADDITION ##########################################################################




################################################################################
#                                                                              #
# FINISH OFF                                                                   #
#                                                                              #
################################################################################

#print p, end_html();
# DEALLOCATE ALL MOLECULES
foreach $entry (keys (%smilesHash)) {
  dt_dealloc($smilesHash{$entry});
}
$dbh->disconnect;
exit 0;


sub getCHEMISTRY
{
   return 0;
}


sub getBBB
{
  @list = keys(%BBBHash);
  return if scalar(@list);

   foreach $entry (@moleculeList) {
      next if not defined $smilesHash{$entry};
      if ($entry =~ /^([0-9]{1,})$/) {
         $molecule = $1;
      } else {
         $BBBHash{$entry} = $NC;
      }
      $BBBHash{$entry} = $NC;
   }
}

sub getHERG
{
   my (@pkb, $pkbm);

  @list = keys(%HERGHash);
  return if scalar(@list);

   foreach $entry (@moleculeList) {
      next if not defined $smilesHash{$entry};

      my @list = keys(%CMRHash);
      getCMR() if ! scalar(@list);

      @list = keys(%PKBHash);
      getPK() if ! scalar(@list);

      @list = keys(%CLOGPHash);
      getCLOGP() if ! scalar(@list);

      $HERGHash{$entry} = 'N';
      if ($smilesHash{$entry} eq $ERR_SMILESNOTAVAIL && $CLOGPHash{$entry} eq 'NC' && $PKBHash{$entry} eq '-' &&
          $CMRHash{$entry} eq 'NC' && $CLOGPHash{$entry} eq '-' && $CMRHash{$entry} eq '-') {
         $HERGHash{$entry} = $NC;
      } else {
         # remember : CMR is multiplied by 10 before it is used.
         @pkb = split(/\s+/, $PKBHash{$entry});
         $pkbm = -99;
         foreach $pkb (@pkb) {
            $pkbm = $pkb if $pkb > $pkbm;
         }
         if ($CMRHash{$entry} =~ /[0-9]+/ && $CLOGPHash{$entry} =~ /[0-9]+/ && $pkbm =~ /[0-9]+/) {
            $HERGHash{$entry} = 'Y' if ($CMRHash{$entry} < 179.0 &&
                                        $CMRHash{$entry} >= 102.55 &&
                                        $CLOGPHash{$entry} >= 3.665 &&
                                        $pkbm >= 7.295);
         }
      }
   }
}


sub getTPSA
{
   my ($value, $error, $version, $entry, $TDTfileName);
   my @tpsa = ();

  @list = keys(%TPSAHash);
  return if scalar(@list);

   foreach $entry (@moleculeList) {
      next if not defined $smilesHash{$entry};
      if ($entry =~ /^([0-9]{1,})$/) {
         $molecule = $1;
         my $select = $dbh->prepare( q{ SELECT VALUE, ERROR_CODE, VERSION
                                        FROM TMC.TB_COMPOUND_PROP
                                        WHERE COMP_NR = ? AND
                                              PROP_ID = ?
                                      }
                                   );
         $select->execute($molecule, $prop{'TPSA'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
         ($value, $error, $version) = $select->fetchrow_array;
         printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
         $TPSAHash{$molecule} = sprintf("%.1f", $value);
      } else {
         $TDTfileName = $ROOTDIR . 'tpsa' . time . '.tdt';
         open (TDTFILE, "+>$TDTfileName");
         print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n|\n";
         close TDTFILE;
         @tpsa = ();
         @tpsa = qx{ /usr/local/bin/scripts/tpsa.pl -tdt -id COMP_ID < "$TDTfileName" 2>/dev/null };
         chomp(@tpsa);
         (undef, $value, undef) = split(/\s+/, $tpsa[0], 3);
         $value = $NC if $value eq 'NA';
         $TPSAHash{$entry} = sprintf("%.1f", $value);
         unlink $TDTfileName;
      }
   }
}


################################################################################
#                                                                              #
# SUBROUTINE TO CALCULATE THE LOGP                                             #
#                                                                              #
################################################################################
sub getSLOGP {
  my ($value, $error, $version, $entry, $TDTfileName);

  @list = keys(%SLOGPHash);
  return if scalar(@list);

  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $smilesHash{$entry};
    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE CLOGP FROM DATABASE (TB_COMPOUND_PROP)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my $select = $dbh->prepare( q{ SELECT VALUE, ERROR_CODE, VERSION
                                      FROM TMC.TB_COMPOUND_PROP
                                      WHERE COMP_NR = ? AND
                                            PROP_ID = ?
                                    }
                                 );
       $select->execute($molecule, $prop{'SLOGP'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($value, $error, $version) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $SLOGPHash{$molecule} = sprintf("%.1f", $value);
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE CLOGP
      $TDTfileName = $ROOTDIR . time . '.tdt';
      open (TDTFILE, "+>$TDTfileName");
      print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n|\n";
      close TDTFILE;
      @slogp = ExecSlogPv2("-s -id 'COMP_ID'", "$TDTfileName");
      (undef, $value, undef) = split(/\s+/, $slogp[1], 3);
      $SLOGPHash{$entry} = sprintf("%.1f", $value);
      unlink "$TDTfileName";
    }
  }
}

sub getCLOGP {
  my ($value, $key, $cp, $error, $version, $entry, $TDTfileName);
  my @clogp = ();

  @list = keys(%CLOGPHash);
  return if scalar(@list);

  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $smilesHash{$entry};
    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE CLOGP FROM DATABASE (TB_COMPOUND_PROP)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my $select = $dbh->prepare( q{ SELECT VALUE, ERROR_CODE, VERSION
                                      FROM TMC.TB_COMPOUND_PROP
                                      WHERE COMP_NR = ? AND
                                            PROP_ID = ?
                                    }
                                 );
       $select->execute($molecule, $prop{'CLOGP'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($value, $error, $version) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $error = $1 if $error =~ /\-([0-9]{1,}).*/;
       if (defined($error) && $error < $ERROR_LIMIT && $error ne 'ClogPNotAvailable') {
          $CLOGPHash{$molecule} = sprintf("%.1f", $value);
       } else {
          $CLOGPHash{$molecule} = 'NC';
       }
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE CLOGP
      $TDTfileName = $ROOTDIR . 'clogp' . time . '.tdt';
      open (TDTFILE, "+>$TDTfileName");
      print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n|\n";
      close TDTFILE;
      @clogp = ();
      @clogp = ExecLogP('ClogP', '-i', "$TDTfileName", 0);
      foreach $chunk (@clogp) {
         chomp;
         next if $chunk =~ /\$SMIG/;
         next if $chunk =~ /^$/;
         $key = &FindItem($chunk, 'COMP_ID');
         next if ! $key;
         $cp = &FindItem($chunk,'CP');
         next if ! $cp;
         ($value, $error, undef) = split(/;/, $cp, 3);
         #($clogp, $error, $version) = /CP<([^\;]+)\;\-([^\;]+)P\;([^\;]+)>/;
         $error = $1 if $error =~ /\-([0-9]{1,}).*/;
         $CLOGPHash{$entry} = (defined($error) && $error < $ERROR_LIMIT) ? sprintf("%.1f", $value) : 'NC';
      }
      unlink $TDTfileName;
    }
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO CALCULATE THE MR                                               #
#                                                                              #
################################################################################

sub getSMR {
  my ($value, $error, $version, $entry, $TDTfileName);
  my @smr = ();

  @list = keys(%SMRHash);
  return if scalar(@list);

  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $smilesHash{$entry};
    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE CMR FROM DATABASE (TB_COMPOUND_PROP)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my $select = $dbh->prepare( q{ SELECT VALUE, ERROR_CODE, VERSION
                                      FROM TMC.TB_COMPOUND_PROP
                                      WHERE COMP_NR = ? AND
                                            PROP_ID = ?
                                    }
                                 );
       $select->execute($molecule, $prop{'SMR'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($value, $error, $version) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $SMRHash{$molecule} = sprintf("%.1f", $value);
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE CMR
      @smr = ();
      $TDTfileName = $ROOTDIR . 'smr'. time . '.tdt';
      open (TDTFILE, "+>$TDTfileName");
      print TDTFILE "\$SMI<$entry>\n\$COMP_ID<$entry>\n|\n";
      close TDTFILE;

      @smr = ExecSmr("-MR -q -s -id 'COMP_ID'", "$TDTfileName");
      (undef, $value, undef) = split(/\s+/, $smr[1], 3);
      $SMRHash{$entry} = sprintf("%.1f", $value);

      unlink $TDTfileName;
    }
  }
}

sub getCMR {
  my ($value, $cr, $key, $error, $version, $entry, $TDTfileName);
  my @clogp = ();

  @list = keys(%CMRHash);
  return if scalar(@list);

  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $smilesHash{$entry};
    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE CMR FROM DATABASE (TB_COMPOUND_PROP)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my $select = $dbh->prepare( q{ SELECT VALUE, ERROR_CODE, VERSION
                                      FROM TMC.TB_COMPOUND_PROP
                                      WHERE COMP_NR = ? AND
                                            PROP_ID = ?
                                    }
                                 );
       $select->execute($molecule, $prop{'CMR'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($value, $error, $version) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $error = $1 if $error =~ /\-([0-9]{1,}).*/;
       if (defined($error) && $error < $ERROR_LIMIT ) {
          $CMRHash{$molecule} = sprintf("%.1f", 10 * $value);
       } else {
          $CMRHash{$molecule} = 'NC';
       }
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE CMR
      @clogp = ();
      $TDTfileName = $ROOTDIR . 'cmr' . time . '.tdt';
      open (TDTFILE, "+>$TDTfileName");
      print TDTFILE "\$SMI<$entry>\n\$COMP_ID<$entry>\n|\n";
      close TDTFILE;

      @clogp = ExecLogP('ClogP', '-i', "$TDTfileName", 1);
      foreach $chunk (@clogp) {
         chomp;
         next if $chunk =~ /\$SMIG/;
         next if $chunk =~ /^$/;
         $key = &FindItem($chunk, 'COMP_ID');
         next if ! $key;
         $cr = &FindItem($chunk,'CR');
         next if ! $cr;
         ($value, $error, undef) = split(/;/, $cr, 3);
         $error = $1 if $error =~ /\-([0-9]{1,}).*/;
         $CMRHash{$entry} = (defined($error) && ($error <= 0)) ? sprintf("%.1f", 10 * $value) : 'NC';
      }
      unlink $TDTfileName;
    }
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO COUNT THE NUMBER OF HYDROGEN BOND ACCEPTORS                    #
#                                                                              #
################################################################################

sub getHB {
  my ($smartspattern, $paths, $path_count, $entry);

  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $smilesHash{$entry};

    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE NUMBER OF HBA FROM DATABASE (TB_COMPOUND_PROP)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my $select = $dbh->prepare( q{ SELECT VALUE, ERROR_CODE, VERSION
                                      FROM TMC.TB_COMPOUND_PROP
                                      WHERE COMP_NR = ? AND
                                            PROP_ID = ?
                                    }
                                 );
       $select->execute($molecule, $prop{'HBD'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($value, $error, $version) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $HBDHash{$molecule} = (defined($error) && $error <= 0 ) ? $value : $NC;

       $select->execute($molecule, $prop{'HBA'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($value, $error, $version) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $HBAHash{$molecule} = (defined($error) && $error <= 0 ) ? $value : $NC;

    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE NUMBER OF HBA
      $smartspattern = dt_smartin("[#7,#8]");
      $HBAHash{$entry} = $HBDHash{$entry} = 0;
      my $mol = dt_smilin($smilesHash{$entry});
      $paths = dt_stream(dt_umatch($smartspattern, $mol, 0), TYP_PATH);
      $path_count = dt_count($paths, TYP_PATH);
      $HBAHash{$entry} = $path_count if $path_count > 0;
      $smartspattern[1] = dt_smartin("[#7,#8;H1]");
      $smartspattern[2] = dt_smartin("[#7,#8;H2]");
      $smartspattern[3] = dt_smartin("[#7,#8;H3]");
      dt_dealloc($paths);
      for ($i = 1; $i <= 3; $i++) {
        $paths = dt_stream(dt_umatch($smartspattern[$i], $mol, 0), TYP_PATH);
        $path_count = dt_count($paths, TYP_PATH);
        $HBDHash{$entry} += ($i * $path_count) if $path_count > 0;
        #if ($path_count > 0) { $HBDHash{$entry} += ($i * $path_count); }
        dt_dealloc($paths);
      }
    }
  }
}

################################################################################
#                                                                              #
# SUBROUTINE TO COUNT THE NUMBER OF ROTATABLE BONDS                            #
#                                                                              #
################################################################################

sub getFLEX {
  return;
  my ($smartspattern, $paths, $path_count, $entry);
  my @flex = ();

  @list = keys(%FLEXHash);
  return if scalar(@list);

  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $smilesHash{$entry};

    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE NUMBER OF RB FROM DATABASE (TB_COMPOUND_PROP)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my $select = $dbh->prepare( q{ SELECT VALUE, ERROR_CODE, VERSION
                                      FROM TMC.TB_COMPOUND_PROP
                                      WHERE COMP_NR = ? AND
                                            PROP_ID = ?
                                    }
                                 );
       $select->execute($molecule, $prop{'FLEX'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($value, $error, $version) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $FLEXHash{$molecule} = sprintf("%.1f", $value);
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      $TDTfileName = $ROOTDIR . 'flex' . time . '.tdt';
      open (TDTFILE, "+>$TDTfileName");
      print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n|\n";
      close TDTFILE;
      @flex = ();
      @flex = ExecFlexibility('-tdt -id COMP_ID', "$TDTfileName");
      chomp(@flex);
      $error = 0;
      (undef, $value, undef) = split(/\s+/, $flex[0], 3);
      $value = $NC if $value eq 'NA';
      $FLEXHash{$entry} = sprintf("%.1f", $value);
      unlink $TDTfileName;
    }
  }
}

sub getRB {
  my ($smartspattern, $paths, $path_count, $entry);

  @list = keys(%RBHash);
  return if scalar(@list);

  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $smilesHash{$entry};

    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE NUMBER OF RB FROM DATABASE (TB_COMPOUND_PROP)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my $select = $dbh->prepare( q{ SELECT VALUE, ERROR_CODE, VERSION
                                      FROM TMC.TB_COMPOUND_PROP
                                      WHERE COMP_NR = ? AND
                                            PROP_ID = ?
                                    }
                                 );
       $select->execute($molecule, $prop{'ROTBOND'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($value, $error, $version) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $RBHash{$molecule} = (defined($error) && $error <= 0 ) ? $value : $NC;
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      $TDTfileName = $ROOTDIR . 'rb' . time . '.tdt';
      open (TDTFILE, "+>$TDTfileName");
      print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n|\n";
      close TDTFILE;
      $RBHash{$entry} = 0;
      my $mol = dt_smilin($smilesHash{$entry});
      #$smartspattern = dt_smartin('[!$(*#*)&!D1]-&!@[!$(*#*)&!D1]');
      #$paths = dt_stream(dt_umatch($smartspattern, $mol, 0), TYP_PATH);
      #$path_count = dt_count($paths, TYP_PATH);
      $path_count = &COUNT_SMARTS('[!$(*#*)&!D1]-&!@[!$(*#*)&!D1]',$mol);
      $RBHash{$entry} = $path_count if $path_count;
      #dt_dealloc($paths);

      # CORRECTION FOR SECONDARY AMIDES
      #$smartspattern = dt_smartin('C(=[O,S,N])-&!@[NH1]');
      #$paths = dt_stream(dt_umatch($smartspattern, $mol, 0), TYP_PATH);
      #$path_count = dt_count($paths, TYP_PATH);
      $path_count = &COUNT_SMARTS('C(=[O,S,N])-&!@[NH1]',$mol);
      $RBHash{$entry} -= $path_count if $path_count;
      #dt_dealloc($paths);
      unlink $TDTfileName;
    }
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO GET THE EMPIRICAL FORMULA                                      #
#                                                                              #
################################################################################

sub getEF {
  return;
  my ($entry, $atom, $atoms, %element, $key, $value);

  @list = keys(%EFHash);
  return if scalar(@list);

  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $smilesHash{$entry};

    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE NUMBER OF EF FROM DATABASE (TB_SMILES)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my $select = $dbh->prepare( q{ SELECT MF
                                      FROM TMC.TB_SMILES
                                      WHERE COMP_NR = ?
                                    }
                                 );
       $select->execute($molecule) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($mf) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $EFHash{$molecule} = defined($mf) ? $mf : $NC;
    } else {
       # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
       # CALCULATE THE EF.
      # LOOP OVER ALL ATOMS
      my $mol = dt_smilin($smilesHash{$entry});
      $atoms = dt_stream($mol, TYP_ATOM);
      $element{'H'} = 0;
      while (NULL_OB != ($atom = dt_next($atoms))) {
        $element{'H'} += dt_hcount($atom);
        if (exists $element{dt_symbol($atom)}) {
          $element{dt_symbol($atom)} += 1;
        } else {
          $element{dt_symbol($atom)} = 1;
        }
      }
      if ($element{'H'} == 0) {
        delete $element{'H'};
      }

      # PRINT IN ORDER OF C, H, O, N, S, FOLLOWED BY THE REST
      if (exists $element{'C'}) {
        $EFHash{$entry} = $element{'C'} > 1 ? ('C' . $element{'C'}) : 'C';
        delete $element{'C'};
      }
      if (exists $element{'H'}) {
        $EFHash{$entry} .= (($element{'H'} > 1) ? ('H' . $element{'H'}) : 'H');
        delete $element{'H'};
      }
      if (exists $element{'O'}) {
        $EFHash{$entry} .= (($element{'O'} > 1) ? ('O' . $element{'O'}) : 'O');
        delete $element{'O'};
      }
      if (exists $element{'N'}) {
        $EFHash{$entry} .= (($element{'N'} > 1) ? ('N' . $element{'N'}) : 'N');
        delete $element{'N'};
      }
      if (exists $element{'S'}) {
        $EFHash{$entry} .= (($element{'S'} > 1) ? ('S' . $element{'S'}) : 'S');
        delete $element{'S'};
      }
      while (($key, $value) = each(%element)) {
        $EFHash{$entry} .= ($key . $value);
      }
    }
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO GET THE MOLECULAR WEIGHT                                       #
#                                                                              #
################################################################################

sub getMW {
  my (%element, $entry, $atom, $atoms, $element, $avgMass, $mimMass, $key, $value);

  @list = keys(%MWHash);
  return if scalar(@list);

  # READ THE MASS DATA
  while (<DATA>) {
    undef $element, $avgMass, $mimMass;
    ($element, $avgMass, $mimMass) = split;
    $avgMassHash{$element} = $avgMass;
    $mimMassHash{$element} = $mimMass;
  }

  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $smilesHash{$entry};
    %element = ();
    $contrib = 0.0;
    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE NUMBER OF EF FROM DATABASE (TB_SMILES)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my $select = $dbh->prepare( q{ SELECT MW
                                      FROM TMC.TB_SMILES
                                      WHERE COMP_NR = ?
                                    }
                                 );
       $select->execute($molecule) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($mw) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $MWHash{$molecule} = defined($mw) ? sprintf("%3.1f", $mw) : $NC;
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE MW.
      # LOOP OVER ALL ATOMS
      my $mol = dt_smilin($smilesHash{$entry});
      $atoms = dt_stream($mol, TYP_ATOM);
      $element{'H'} = 0;
      while (NULL_OB != ($atom = dt_next($atoms))) {
        $element{'H'} += dt_hcount($atom);
        if (exists $element{dt_symbol($atom)}) {
          $element{dt_symbol($atom)} += 1;
        } else {
          $element{dt_symbol($atom)} = 1;
        }
      }
      if ($element{'H'} == 0) {
        delete $element{'H'};
      }

      # RESET TOTAL MW
      $MWHash{$entry} = 0.0;

      # SUM ATOMIC CONTRIBUTIONS
      while (($key, $value) = each(%element)) {
        $MWHash{$entry} += sprintf("%3.1f", ($value * $avgMassHash{$key}));
      }
      dt_dealloc($atoms);
    }

    # MIM part

    # LOOP OVER ALL ATOMS
    $mol = dt_smilin($smilesHash{$entry});
    $atoms = dt_stream($mol, TYP_ATOM);
    $element{'H'} = 0;
    while (NULL_OB != ($atom = dt_next($atoms))) {
      $element{'H'} += dt_hcount($atom);
      if (exists $element{dt_symbol($atom)}) {
        $element{dt_symbol($atom)} += 1;
      } else {
        $element{dt_symbol($atom)} = 1;
      }
    }
    if ($element{'H'} == 0) {
      delete $element{'H'};
    }

    # RESET TOTAL MIM
    $MIMHash{$entry} = 0.0;

    # SUM ATOMIC CONTRIBUTIONS
    while (($key, $value) = each(%element)) {
      $MIMHash{$entry} += ($value * $mimMassHash{$key});
    }
    $MIMHash{$entry} = sprintf("%3.1f", $MIMHash{$entry});
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO CHECK FOR RULE-OF-FIVE VIOLATIONS                              #
#                                                                              #
################################################################################

sub getROF {
  my ($entry, $loe_flag);

  # 2. CALCULATE THE ROF
  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $smilesHash{$entry};

    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE NUMBER OF EF FROM DATABASE (TB_COMPOUNDS_PROP)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my $select = $dbh->prepare( q{ SELECT VALUE, ERROR_CODE, VERSION
                                      FROM TMC.TB_COMPOUND_PROP
                                      WHERE COMP_NR = ? AND
                                            PROP_ID = ?
                                    }
                                 );
       $select->execute($molecule, $prop{'ROFV'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($value, $error, $version) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $ROFHash{$molecule} = (defined($error) && $error == 0 ) ? $value : '>=0';
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE MW.
      $ROFHash{$entry} = 0;
      if ($MWHash{$entry} > 500)   { $ROFHash{$entry}++ }
      if ($HBAHash{$entry} > 10)   { $ROFHash{$entry}++ }
      if ($HBDHash{$entry} > 5)    { $ROFHash{$entry}++ }
      if ($CLOGPHash{$entry} > 5)  { $ROFHash{$entry}++ }
      $loe_flag = 0;
      if ($MWHash{$entry} eq $NC)    {$loe_flag++};
      if ($HBAHash{$entry} eq $NC)   {$loe_flag++};
      if ($HBDHash{$entry} eq $NC)   {$loe_flag++};
      if ($CLOGPHash{$entry} eq $NC) {$loe_flag++};
      if ($loe_flag > 0) {
        $ROFHash{$entry} = ">= " . $ROFHash{$entry};
      }
      if ($loe_flag == 4) {
        $ROFHash{$entry} = '>=0';
      }
    }
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO CHECK FOR QT PROLONGATION (T183.O1)                            #
#                                                                              #
################################################################################

sub getQT {
  my ($qt, $molecule, $pkb_max, $pka_max, $mr, $CUBISTinput, $cmp, @result);

  # MAKE SURE THAT ALL REQUIRED PROPERTIES HAVE BEEN CALCULATED
  @list = keys(%CLOGPHash);
  getCLOGP() if ! scalar(@list);

  @list = keys(%LOGDHash);
  getLOGD() if ! scalar(@list);

  @list = keys(%MWHash);
  getMW() if ! scalar(@list);

  @list = keys(%CMRHash);
  getCMR() if ! scalar(@list);

  @list = keys(%PKBHash);
  getPK() if ! scalar(@list);

  @list = keys(%HBDHash);
  @list2 = keys(%HBAHash);
  getHB() if ! scalar(@list2) || ! scalar(@list);

  @list = keys(%RBHash);
  getRB() if ! scalar(@list);
  # GO THROUGH ALL MOLECULES
  $CUBISTinput = $CUBISTfileName . ".cases";
  open (CUBISTFILE, ">$CUBISTinput");
  foreach $molecule (@moleculeList) {
    if (! defined $smilesHash{$molecule}) {
      $QTHash{$molecule} = "NC";
      next;
    }
    if ((! defined $CLOGPHash{$molecule}) || ($CLOGPHash{$molecule} eq 'NC') || $CLOGPHash{$molecule} eq '-') {
      $QTHash{$molecule} = "NC";
      next;
    }
    if ((! defined $MWHash{$molecule}) || ($MWHash{$molecule} eq 'NC') || $MWHash{$molecule} eq '-') {
      $QTHash{$molecule} = "NC";
      next;
    }
    if ((! defined $CMRHash{$molecule}) || ($CMRHash{$molecule} eq 'NC') || $CMRHash{$molecule} eq '-') {
      $QTHash{$molecule} = "NC";
      next;
    }
    if ((! defined $LOGDHash{$molecule}) || ($LOGDHash{$molecule} eq 'NC') || $LOGDHash{$molecule} eq '-') {
      $QTHash{$molecule} = "NC";
      next;
    }
    if ((! defined $HBDHash{$molecule}) || ($HBDHash{$molecule} eq 'NC') || $HBDHash{$molecule} eq '-') {
      $QTHash{$molecule} = "NC";
      next;
    }
    if ((! defined $HBAHash{$molecule}) || ($HBAHash{$molecule} eq 'NC') || $HBAHash{$molecule} eq '-') {
      $QTHash{$molecule} = "NC";
      next;
    }
    if ((! defined $RBHash{$molecule}) || ($RBHash{$molecule} eq 'NC') || $RBHash{$molecule} eq '-') {
      $QTHash{$molecule} = "NC";
      next;
    }
    $pkb_max = -1;
    if ($PKBHash{$molecule} eq 'NC') {
      $QTHash{$molecule} = "NC";
      next;
    } else {
      $PKBHash{$molecule} =~ /^([\d\-\.]+)/;
      $pkb_max = $1 if $1 != '-';
      if ($pkb_max < -1) {
        $pkb_max = -1.;
      }
    }
    $pka_max = 15;
    if ($PKAHash{$molecule} eq 'NC') {
      $QTHash{$molecule} = "NC";
      next;
    } else {
      $PKAHash{$molecule} =~ /^([\d\-\.]+)/;
      $pka_max = $1 if $1 != '-';
      if ($pka_max > 15) {
        $pka_max = 15.;
      }
    }

    $mr = $CMRHash{$molecule}/10 if exists($CMRHash{$molecule});

    print CUBISTFILE
      "$molecule,$MWHash{$molecule},$mr,$CLOGPHash{$molecule},$LOGDHash{$molecule},$RBHash{$molecule}," . 
      "$pka_max,0,$pkb_max,0,0,0,?,$HBAHash{$molecule},$HBDHash{$molecule}\n";
  }
  close CUBISTFILE;

  # RUN CUBIST AND PROCESS RESULTS
  @result = `Cubist/CubistPredict -f $CUBISTfileName`;
  #chomp(@result);
  foreach $molecule (@moleculeList) {
    next if ! defined $smilesHash{$molecule};
    foreach (@result) {
       if (/^(\S+)\s+\?\s+([\d\-\.]*)/) {
          $cmp = $1; $value = $2;
          if ($molecule =~ /^\d+/) {
             $QTHash{$molecule} = sprintf("%d", $value) if $cmp eq $molecule;
          } else {
             $QTHash{$molecule} = sprintf("%d", $value) if index($molecule, $cmp) >= 0;
          }
       }
    }
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO GET THE CHARGE                                                 #
#                                                                              #
################################################################################

sub getCHARGE {
  my ($entry, $atom, $atoms, @pka_list, @pkb_list, $pk, $Qa, $Qb, $t, $mol);

  @list = keys(%CHARGEHash);
  return if scalar(@list);

  # 1. CALCULATE FORMAL CHARGE
  foreach $entry (@moleculeList) {
    next if ! defined $smilesHash{$entry};

    $CHARGEHash{$entry} = 0;
    $mol = dt_smilin($smilesHash{$entry});
    $atoms = dt_stream($mol, TYP_ATOM);
    while (NULL_OB != ($atom = dt_next($atoms))) {
      $CHARGEHash{$entry} += dt_charge($atom);
      #print dt_symbol($atom);
    }
  }

  # 2. ADD THE CHARGE DUE TO IONISATION
  if (param('pH_charge')) {
    $pH_charge = param('pH_charge');
  } else {
    $pH_charge = 7.4;
  }

  my @list = keys(%PKAHash);
  my @list2 = keys(%PKBHash);
  getPK() if ! scalar(@list) || ! scalar(@list2);

  foreach $entry (@moleculeList) {
    $Qa = 0.0;
    if (exists($PKAHash{$entry}) && $PKAHash{$entry} ne $NC) {
      $PKAHash{$entry} =~ s/^\s+//;
      @pka_list = split(/\s+/, $PKAHash{$entry});
      foreach $pk (@pka_list) {
        $t = 10 ** ($pH_charge - $pk);
        $Qa += (-$t) / ($t + 1);
      }
    }
    $Qb = 0.0;
    if (exists($PKBHash{$entry}) && $PKBHash{$entry} ne $NC) {
      $PKBHash{$entry} =~ s/^\s+//;
      @pkb_list = split(/\s+/, $PKBHash{$entry});
      foreach $pk (@pkb_list) {
        $t = 10 ** ($pk - $pH_charge);
        $Qb += ($t) / ($t + 1);
      }
    }
    # dont change following 2 lines in just 1 .. its shorter allright, but you'll loose the formatting.
    $CHARGEHash{$entry} += ($Qa + $Qb);
    $CHARGEHash{$entry} = sprintf("%03.03f", $CHARGEHash{$entry});
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO GET THE LOGD                                                   #
#                                                                              #
################################################################################

sub getLOGD {
  my ($entry, $clogd, $pka, $pkb, @pka, @pkb);

  @list = keys(%LOGDHash);
  return if scalar(@list);

  # 2. RETRIEVE THE CLOGP
  my @list = keys(%CLOGPHash);
  getCLOGP() if !scalar(@list);

  # 3. RETRIEVE THE ACID AND BASE CONSTANTS
  @list = keys(%PKAHash);
  my @list2 = keys(%PKBHash);
  getPK() if ! scalar(@list) || ! scalar(@list2);

  # 4. CALCULATE CLOGD
  ENTRY: foreach $entry (@moleculeList) {
    next if ! defined $smilesHash{$entry};

    if (exists $CLOGPHash{$entry} && $CLOGPHash{$entry} ne $NC) {
      $clogd = $CLOGPHash{$entry};

      # Acid groups
      if (exists($PKAHash{$entry}) && $PKAHash{$entry} ne $NC) {
        $PKAHash{$entry} =~ s/^\s+//;
        @pka = split(/\s+/, $PKAHash{$entry});
        foreach $pka (@pka) {
          $clogd -= ( (log(1 + 10**($pH_logd - $pka))) / 2.30258 );
        }
      }

      # Basic groups
      if (exists($PKBHash{$entry}) && $PKBHash{$entry} ne $NC) {
        $PKBHash{$entry} =~ s/^\s+//;
        @pkb = split(/\s+/, $PKBHash{$entry});
        foreach $pkb (@pkb) {
          $clogd -= ( (log(1 + 10**($pkb - $pH_logd))) / 2.30258 );
        }
      }
      $LOGDHash{$entry} = sprintf("%.1f", $clogd);
    } else {
      $LOGDHash{$entry} = 'NC';
    }
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO GET THE PK                                                     #
#                                                                              #
################################################################################

sub getPK {
  my (@pk, $entry, @result, $cmp, $value, $type, $TDTfileName, $SDFfileName);
  my (@pkb, @pka) = ((),());

  @list = keys(%PKAHash);
  @list2 = keys(%PKBHash);
  return if scalar(@list) || scalar(@list2);

  foreach $entry (@moleculeList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if ! defined $smilesHash{$entry};

    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE PKA AND PKB FROM DATABASE (TB_COMPOUND_PROP)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       @pk = ();
       my $select = $dbh->prepare( q{ SELECT VALUE, ERROR_CODE, VERSION
                                      FROM TMC.TB_COMPOUND_PROP
                                      WHERE COMP_NR = ? AND
                                            PROP_ID = ?
                                    }
                                 );
       $select->execute($molecule, $prop{'PKA'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       $PKAHash{$molecule} = '';
       while(($value, $error, $version) = $select->fetchrow_array) {
          printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
          if (defined($error) && $error <= 0) {
             push @pk, sprintf("%.1f", $value);
          }
       }
       foreach $pk (sort { $a <=> $b } @pk) {
          $PKAHash{$molecule} .= (sprintf("%.1f", $pk) . ' ');
       }
       $PKAHash{$molecule} = $NC if $PKAHash{$molecule} eq '';

       @pk = ();

       $select->execute($molecule, $prop{'PKB'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       $PKBHash{$molecule} = '';
       while (($value, $error, $version) = $select->fetchrow_array) {
          printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
          if (defined($error) && $error <= 0 ) {
             push @pk, sprintf("%.1f", $value);
          }
       }
       foreach $pk (sort { $b <=> $a } @pk) {
          $PKBHash{$molecule} .= (sprintf("%.1f", $pk) . ' ');
       }
       $PKBHash{$molecule} = $NC if $PKBHash{$molecule} eq '';
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE PKA AND PKB.
      $TDTfileName = $ROOTDIR . 'pk' . time . '.tdt';
      $SDFfileName = $ROOTDIR . 'pk' . time . '.sdf';
      open (TDTFILE, "+>$TDTfileName");
      print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n\|\n";
      close TDTFILE;
      my @result = ();
      qx { $SMI2MOL -input_format TDT -add_2d FALSE < "$TDTfileName" > "$SDFfileName" 2>/dev/null };
      #@result = ExecPkaPkb('-vert -ityp sdf -idfld COMP_ID -lpKa 0 -hpKa 14 -nohd -det /dev/null', $SDFfileName);
      @result = ExecPkaPkb('-vert -ityp sdf -idfld COMP_ID -nohd -det /dev/null', "$SDFfileName");
      chomp(@result);
      $PKAHash{$entry} = $PKBHash{$entry} = '';
      @pkb = @pka = ();
      foreach (@result) {
        ($cmp, $value, $type, undef) = /^(.*)\s+([\d\-\.]+)\s+(Acid|Base)\s+(\d+)/;
        next if ! defined($cmp);
        if ($type eq 'Base') {
           push @pkb, sprintf("%.1f", $value);
        } else {
           push @pka, sprintf("%.1f", $value)
        }
      }
      foreach $pk (sort { $b <=> $a } @pkb) {
         $PKBHash{$entry} .= (sprintf("%.1f", $pk) . ' ');
      }
      $PKBHash{$entry} = $NC if $PKBHash{$entry} eq '';
      foreach $pk (sort { $a <=> $b } @pka) {
         $PKAHash{$entry} .= (sprintf("%.1f", $pk) . ' ');
      }
      $PKAHash{$entry} = $NC if $PKAHash{$entry} eq '';
      unlink "$SDFfileName", "$TDTfileName";
    }
  }
}


################################################################################
#                                                                              #
# SUBROUTINE: Integer COUNTSUBSTRING(String bigstring, String searchstring)    #
#                                                                              #
################################################################################

sub countSubstring {
  my ($count, $searchstring);
  $_ = $_[1];
  s/([\[\]\+\-])/\\$1/g;
  $searchstring = $_;
  $_ = $_[0];
  $count = s/$searchstring//g;
  unless ($count) {
    $count = 0;
  }
  return $count;
}



################################################################################
#                                                                              #
# SUBROUTINE PRINTPAGEHEADER TO PRINT THE HTML HEADER TO STDOUT                #
#                                                                              #
################################################################################

sub printPageHeader {
  print "Content-type: text/html\n\n";
  print "<html>\n";
  print "<head><title>$_[0]</title>\n";
  print "</head>\n";
  print "<body>\n";
}

sub printPageFooter
{
  print "</body></html>\n";
}

sub printError
{
   my ($title, $msg, $disconnect) = @_;

   &printPageHeader($title);
   print $msg;
   &printPageFooter;
   $dbh->disconnect if $disconnect;
   exit 1;
}


################################################################################
#                                                                              #
# A2HEX: CONVERT ASCII STRING INTO HEXADECIMAL VALUE                           #
#                                                                              #
################################################################################

sub a2hex {

  my ($str) = @_;
  my ($hex, $i);

  for ($i = 0, $hex = ""; $i < length($str); ++$i) {
    $hex .= sprintf("%2x", ord(substr($str, $i, 1)));
  }

  return ($hex);
}



################################################################################
#                                                                              #
# AVERAGE- AND MONO-ISOTOPIC MASSES                                            #
#                                                                              #
################################################################################

__DATA__
T        3.01600000       3.01600000
D        2.01400000       2.01400000
H        1.00794000       1.00782504
He       4.00260200       4.00260325
Li       6.94100000       7.01600450
Be       9.01218200       9.01218250
B       10.81100000      11.00930530
C       12.01100000      12.00000000
N       14.00674000      14.00307401
O       15.99940000      15.99491464
F       18.99840320      18.99840325
Ne      20.17970000      19.99243910
Na      22.98976800      22.98976970
Mg      24.30500000      23.98504500
Al      26.98153900      26.98154130
Si      28.08550000      27.97692840
P       30.97376200      30.97376340
S       32.06600000      31.97207180
Cl      35.45270000      34.96885273
Ar      39.94800000      39.96238310
K       39.09830000      38.96370790
Ca      40.07800000      39.96259070
Sc      44.95591000      44.95591360
Ti      47.88000000      47.94794670
V       50.94150000      50.94396250
Cr      51.99610000      51.94050970
Mn      54.93805000      54.93804630
Fe      55.84700000      55.93493930
Co      58.93320000      58.93319780
Ni      58.69000000      57.93534710
Cu      63.54600000      62.92959920
Zn      65.39000000      63.92914540
Ga      69.72300000      68.92558090
Ge      72.61000000      73.92117880
As      74.92159000      74.92159550
Se      78.96000000      79.91652050
Br      79.90400000      78.91833610
Kr      83.80000000      83.91150640
Rb      85.46780000      84.91179960
Sr      87.62000000      87.90562490
Y       88.90585000      88.90585600
Zr      91.22400000      89.90470800
Nb      92.90638000      92.90637800
Mo      95.94000000      97.90540500
Tc      98.90620000      98.90620000
Ru     101.07000000     101.90434750
Rh     102.90550000     102.90550300
Pd     106.42000000     105.90347500
Ag     107.86820000     106.90509500
Cd     112.41100000     113.90336070
In     114.82000000     114.90387500
Sn     118.71000000     119.90219900
Sb     121.75000000     120.90382370
Te     127.60000000     129.90622900
I      126.90447000     126.90447700
Xe     131.29000000     131.90414800
Cs     132.90543000     132.90543300
Ba     137.32700000     137.90523600
La     138.90550000     138.90635500
Ce     140.11500000     139.90544200
Pr     140.90765000     140.90765700
Nd     144.24000000     141.90773100
Sm     150.36000000     151.91974100
Eu     151.96500000     152.92124300
Gd     157.25000000     157.92411100
Tb     158.92534000     158.92535000
Dy     162.50000000     163.92918300
Ho     164.93032000     164.93033200
Er     167.26000000     165.93035000
Tm     168.93421000     168.93422500
Yb     173.04000000     173.93887300
Lu     174.96700000     174.94078500
Hf     178.49000000     179.94656100
Ta     180.94790000     180.94801400
W      183.85000000     183.95095300
Re     186.20700000     186.95576500
Os     190.20000000     191.96148700
Ir     192.22000000     192.96294200
Pt     195.08000000     194.96478500
Au     196.96654000     196.96656000
Hg     200.59000000     201.97063200
Tl     204.38330000     204.97441000
Pb     207.20000000     207.97664100
Bi     208.98037000     208.98038800
Th     232.03810000     232.03805380
Pa     231.03588000     231.03588000
U      238.02890000     238.05078580
