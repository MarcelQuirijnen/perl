#!/usr/local/bin/perl

##############################################################################
#
# description
#
##############################################################################
# RCS ID: 
# 	$Id: physcalc.pl,v 1.4 2002/03/13 16:42:06 tmcwebadm Exp $
#
# RCS History:
#	$Log: physcalc.pl,v $
#	Revision 1.4  2002/03/13 16:42:06  tmcwebadm
#	added '-add_2d FALSE' to SMI2MOL so we do no longer get
#	  the "Invalid license: 'depict' toolkit not authorized.
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


# PHYSCALC.PL
# DESCRIPTION OF THE MOST IMPORTANT VARIABLES:
##############################################
#
# @NameList - A list variable containing the names of all molecule entries. This list is required
#	      to preserve the correct order of molecules, and to serve as an unique
#             identifier linking the different property hashes together.
#
my @NameList = ();
#
# %MOLECULEHash - An hash variable containing as value the Daylight molecule objects.
#                 The keys are the values in the @NameList.
#
my %MOLECULEHash = ();
#
# LIST CONTAINING ALL REQUESTED PROPERTIES:
###########################################
#
# @propertyList - A list variable containing all the to-be-calculated properties.
#
my @propertyList = ();
#
# PROPERTY CONTAINER VARIABLES:
###############################
#
# %CLOGPHash - An hash variable containing as value the clogp value.
#              The keys are the values in the @NameList.
my %CLOGPHash = ();
#
# %CLOGDHash - An hash variable containing as value the clogd value.
#              The keys are the values in the @NameList.
my %CLOGDHash = ();
#
# %CMRHash - An hash variable containing as value the cmr value.
#            The keys are the values in the @NameList.
my %CMRHash = ();
#
# %HBAHash - An hash variable containing as value the number of HBA's.
#            The keys are the values in the @NameList.
my %HBAHash = (); 
#
# %HBDHash - An hash variable containing as value the number of HBD's.
#            The keys are the values in the @NameList.
my $HBDHash = ();
#
# %RBHash - An hash variable containing as value the number of rotatable bonds.
#           The keys are the values in the @NameList.
my %RBHash = ();
#
# %EFHash - An hash variable containing as value the molecular formula.
#           The keys are the values in the @NameList.
my %EFHash = ();
#
# %MWHash - An hash variable containing as value the average molecular weight.
#           The keys are the values in the @NameList.
my %MWHash = ();
#
# %MIMHash - An hash variable containing as value the mono-isotopic mass.
#            The keys are the values in the @NameList.
my %MIMHash = ();
#
# %ROFHash - An hash variable containing as value the number of ROF violations.
#            The keys are the values in the @NameList.
my %ROFHash = ();
#
# %CHARGEHash - An hash variable containing as value the total charge at a given pH.
#               The keys are the values in the @NameList.
my %CHARGEHash = ();
#

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
use Modules::Clogp;

use CGI::Carp 'fatalsToBrowser';

# ENVIRONMENT VARIABLES
&SetupDaylightEnv;
&SetupPallasEnv;

# GENERAL
open(STDERR, ">/dev/null");

# SET UMASK: rw-------
umask 127;

# Upload limitation
my $MAX_SIZE_UPLOAD = 3000; # K, return an 'Internal Server Error' on oversized files
$CGI::POST_MAX=1024 * $MAX_SIZE_UPLOAD;
my $upload_file;

# DBI ORACLE DATABASE HANDLE
my $dbh;
# COMPOUND TYPE
my %compound = ();
# Mark as Not Found/Not calculated/not Available
my $NC = '-';
my $ROOTDIR = ($ENV{'SERVER_PORT'} == 81) ? '/data/www/dvl/cci/dat/' : '/data/www/rls/cci/dat/';
my $ERROR_LIMIT = 60;
my $pH_logd;

my %Properties  = ( 'CLOGP' => \&getCLOGP,
                    'EF'    => \&getEF,
                    'CLOGD' => \&getCLOGD,
                    'CMR'   => \&getCMR,
                    'HBA'   => \&getHBA,
                    'HBD'   => \&getHBD,
                    'PK'    => \&getPK,
                    'MW'    => \&getMW,
                    'MIM'   => \&getMIM,
                    'CHARGE'=> \&getCHARGE,
                    '3D'    => \&get3D,
                    'ROF'   => \&getROF,
                    'RB'    => \&getRB,
                    'FLEX'  => \&getFLEX,
                    'TPSA'  => \&getTPSA,
                    'SLOGP' => \&getSLOGP,
                    'SMR'   => \&getSMR,
                  );


my %Parameters = ( 'structures' => 'CHEMISTRY',
                   'rb_flag'    => 'RB',
                   'ef_flag'    => 'EF',
                   'logp_flag'  => 'CLOGP',
                   'logd_flag'  => 'CLOGD',
                   'mr_flag'    => 'CMR',
                   'hb_flag'    => 'HBA',
                   'pk_flag'    => 'PK',
                   'mw_flag'    => 'MW',
                   'charge_flag' => 'CHARGE',
                   '3d_flag'    => '3D',
                   'rof_flag'   => 'ROF',
                   'flex_flag'  => 'FLEX',
                   '_tpsa_flag' => 'TPSA',     # underscore because of reverse sort order .. structure must be 2nd column
                 );

############################################################################
#                                                                          #
# PROCESS THE INPUT AND PUT THE MOLECULE NAMES IN A LIST CALLED 'nameList' #
#                                                                          #
############################################################################

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
    #push(@nameList, sprintf("R%d", $_));
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
    push(@nameList, $key);
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
        $buf =~ s/\r\n/\n/g;   # substitute \r\n into \n .. damn this Gates guy
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
            if (ExecMol2Smi($mol2smi_params ,"$fullpath", "$fullpath.tdt", '/dev/null')) {
               unlink $fullpath.tdt, $fullpath;
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
               LASTID : foreach $id ('COMPNAME', 'COMP_NAME', 'JNJ', 'JNJS', 'COMPID', 'COMP_ID', '\$NAM', '\$RNR') {
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
               push(@nameList, dt_cansmiles($molecule, 1));
               dt_dealloc($molecule);
            }
         } elsif (param('filetype') eq 'smiles') {
            open(SMI, "<$fullpath") || printError('Error', "Could not open SMILES file.", 0);
            while (<SMI>) {
               chomp;
               ($smi, $key, undef) = split(/\s+/, $_, 3);
               printError('Data Entry', "Invalid smiles encoutered.\n", 0) if dt_smilin($smi) == NULL_OB; 
               push(@nameList, $smi);
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
               push(@nameList, $key);
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
      push(@nameList, dt_cansmiles($molecule, 1));
      dt_dealloc($molecule);
   }
}
if (param('smi')) {
  # SECOND CASE: INPUT FROM THE CLIENT IS A SMILES STRING -> USE THE SMILES STRING
  # AS THE MOLECULE NAME
  # CANONICALIZE THE SMILES STRING
  $molecule = dt_smilin(param('smi'));
  # ADD IT TO THE nameList  
  push(@nameList, dt_cansmiles($molecule, 1));
  # DEALLOCATE MOLECULE
  dt_dealloc($molecule);
}
if (!param('rlist') && ! param('smi') && !param('slist') && !param('file')) {
  printError('Data Entry Error', "Error. File size exceeded $MAX_SIZE_UPLOAD K. Please try SMILES format.\n", 0) if cgi_error();
  # THIRD CASE: AN ERROR OCCURED 
  printError('Data Entry Error', "Error. No molecules submitted. Try again.\n", 0);
}

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

#############################
#                           #
# FILL UP THE MOLECULEHash  #
#                           #
#############################
# filter out doubles ..
my %tempHash = ();
foreach $entry (@nameList) {
   $tempHash{$entry} = $entry;
}
@nameList = keys(%tempHash);
undef %tempHash;

foreach $entry (@nameList) {
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
    if (defined($smiles) && $smiles ne $ERR_SMILESNOTAVAIL) {
       # Convert smiles to Daylight molecule objects
       #my $mol = dt_smilin($smiles);
       # Store molecule objects in %MOLECULEHash
       #$MOLECULEHash{$molecule} = $mol if $mol != NULL_OB;
       #dt_dealloc($mol);
       $MOLECULEHash{$molecule} = $smiles;
    } else {
       if (defined($smiles)) {
          $MOLECULEHash{$molecule} = $ERR_SMILESNOTAVAIL;
       } else {
          #printError('CHAROn Data Error', "CHAROn Data Error : Compound not found or SMILES not available\n", 1);
          $MOLECULEHash{$molecule} = $ERR_SMILESNOTAVAIL;
       }
    }
    $compound{$molecule} = $comp_type;
  } else {
    # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
    # THE ENTRY NAME IS NOTHING MORE THAN THE CANONONICAL SMILES ITSELF.
    # CHECK IF VALID SMILES
    #if (NULL_OB != ($molecule = dt_smilin($entry))) {
    #  dt_dealloc($molecule);
    #  $MOLECULEHash{$entry} = dt_smilin($entry);
    $MOLECULEHash{$entry} = $entry;
    #}
  }
}



################################################################################
#                                                                              #
# CREATE A PROPERTYLIST TO STORE THE LIST OP PROPERTIES                        #
#                                                                              #
################################################################################

foreach $parameter (sort { $b cmp $a } keys %Parameters) {
  if (param($parameter)) {
     if ($parameter eq 'mr_flag') {
        push(@propertyList, $Parameters{$parameter});
        push(@propertyList, 'SMR');
     } elsif ($parameter eq 'mw_flag') {
        push(@propertyList, $Parameters{$parameter});
        push(@propertyList, 'MIM');
     } elsif ($parameter eq 'rb_flag') {
        push(@propertyList, $Parameters{$parameter});
        push(@propertyList, 'FLEX');
     } elsif ($parameter eq 'hb_flag') {
        push(@propertyList, $Parameters{$parameter});
        push(@propertyList, 'HBD');
     } elsif ($parameter eq 'logp_flag') {
        push(@propertyList, $Parameters{$parameter});
        push(@propertyList, 'SLOGP');
     } else {
        push(@propertyList, $Parameters{$parameter});
     }
  }
}

################################################################################
#                                                                              #
# GO THROUGH THE LIST OF REQUIRED PROPERTIES AND CALCULATE THE PROPERTY        #
# OF EACH MOLECULE WHICH HAS A VALID SMILES STRING.                            #
# STORE EACH PROPERTY IN ITS DEDICATED HASH:-                                  #
#    CLOGP  ->      CLOGPHASH                                                  #
#    CLOGD   ->     CLOGDHASH                                                  #
#    CMR    ->      CMRHASH                                                    #
#    HBx    ->      HBAHASH, HBDHASH                                           #
#    PK     ->      PKAHASH, PKBHASH                                           #
#    MW     ->      MWHASH, NUMBEROFATOMSHASH                                  #
#    MIM    ->      MIMHASH                                                    #
#    EF     ->      EFHASH                                                     #
#    CHARGE ->      CHARGEHASH                                                 #
#    3D     ->      3DHASH                                                     #
#    ROF    ->      ROFHASH                                                    #
#    RB     ->      RBHASH                                                     #
#                                                                              #
################################################################################
foreach $property (@propertyList) {
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
print "<head><title>Physicochemical calculations</title>\n";
print "<link rel=\"stylesheet\" href=\"/css/cci.css\" type=\"text/css\">\n</head>\n";

### tom@020205 - MARVIN: add script links
print "<body BGCOLOR=\"#ffffff\" onLoad=\"links_set_search(location.search)\">\n";

print "<script LANGUAGE=\"JavaScript1.1\" SRC=\"/marvin/marvin.js\"></script>\n";

# OPEN THE EXCEL FILE
my $EXCELfileName = '../dat/' . time . '.xls';
open (XLSFILE, ">$EXCELfileName");

# PRINT THE HEADER TO THE EXCEL FILE
print XLSFILE "COMPOUND";
foreach $property (@propertyList) {
  if ($property eq 'CLOGD') {
    print XLSFILE "\t$property", " [$pH_logd]";
  } elsif ($property eq 'CHARGE') {
    print XLSFILE "\t$property", " [$pH_charge]";
  } elsif ($property eq 'PK') {
    print XLSFILE "\tPKa_ACID\tPKa_BASE";
  } else {
    print XLSFILE "\t$property";
  }
}
print XLSFILE "\n";

# GO THROUGH THE LIST OF MOLECULES AND PRINT THE PROPERTIES TO THE EXCEL FILE
foreach $entry (@nameList) {
  next if not defined $MOLECULEHash{$entry};
  if (param('file') && param('filetype') eq 'sdf') {
     print XLSFILE $compound{$entry};
  } else {
     print XLSFILE $compound{$entry},$entry;
  }
  #if (param('file') && param('filetype') eq 'sdf' && param('structures')) {
  #   print XLSFILE $compound{$entry};
  #} elsif (param('file') && param('filetype') eq 'sdf' && !param('structures')) {
  #   print XLSFILE $entry;
  #} else {
  #   print XLSFILE $compound{$entry},$entry;
  #}
  foreach $property (@propertyList) {
    if ($property eq 'EF') {
      if ($EFHash{$entry} && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        chomp($EFHash{$entry});
        print XLSFILE "\t", $EFHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'CLOGP') {
      if (defined($CLOGPHash{$entry})) {
         print XLSFILE "\t", $CLOGPHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'CLOGD') {
      if (defined($CLOGDHash{$entry}) && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $CLOGDHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'CMR') {
      if ($CMRHash{$entry}) {
        print XLSFILE "\t", $CMRHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'HBA') {
      if (($HBAHash{$entry} || $HBAHash{$entry} eq '0') && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $HBAHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'HBD') {
      if (($HBDHash{$entry} || $HBDHash{$entry} eq '0') && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $HBDHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'PK') {
      if ($PKAHash{$entry} && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $PKAHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
      if ($PKBHash{$entry} && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $PKBHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'MW') {
      if ($MWHash{$entry} && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $MWHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'MIM') {
      if ($MIMHash{$entry} && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $MIMHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'CHARGE') {
      if (($CHARGEHash{$entry} || $CHARGEHash{$entry} eq '0') && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $CHARGEHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'ROF') {
      if (($ROFHash{$entry} || $ROFHash{$entry} eq '0') && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $ROFHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'RB') {
      if (($RBHash{$entry} || $RBHash{$entry} eq '0') && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $RBHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'CHEMISTRY') {
       print XLSFILE "\t", $MOLECULEHash{$entry};
    } elsif ($property eq 'FLEX') {
      if ($FLEXHash{$entry} && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $FLEXHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'TPSA') {
      if ($TPSAHash{$entry} && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $TPSAHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'SLOGP') {
      if ($SLOGPHash{$entry} && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $SLOGPHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    } elsif ($property eq 'SMR') {
      if ($SMRHash{$entry} && $MOLECULEHash{$entry} ne $ERR_SMILESNOTAVAIL) {
        print XLSFILE "\t", $SMRHash{$entry};
      } else {
        print XLSFILE (($MOLECULEHash{$entry} eq $ERR_SMILESNOTAVAIL) ? "\tNC" : "\t$NC");
      }
    }
  }
  print XLSFILE "\n";
}   

# CLOSE THE EXCEL FILE
close(XLSFILE);

# OPEN THE EXCEL FILE FOR READING
open(XLSFILE, "$EXCELfileName");

# READ THE FIRST LINE FROM THE EXCEL FILE AND PRINT TO STDOUT IN TABLE FORMAT
$_ = <XLSFILE>;
@line = split(/\t+/);

print "<font face=\"Arial, Geneva\" size=\"+2\" color=\"#000066\">\n";
print "<b>PHYSCALC RESULTS</b><br>\n";
print "</font>\n";
print "<font face=\"Arial, Geneva\" size=\"0\" color=\"#000066\">\n";
print "Click on the <b>compound<\/b> entry to view the CORINA 3D geometry.<br>\n";
print "(WebLab Viewer needs to be installed on your PC: <a href=\"/download.shtml\">install</a>)<p>\n";
print "</font>\n";
print "<table border=\"0\" frame=\"vsides\" rules=\"cols\" cellpadding=\"3\" cellspacing=\"0\">\n";
print "  <tr>\n";
$column = 0;
foreach (@line) {
  $column++;
  if ($column == 1) {
    $class = "head1L";
  } elsif ($column == 2) {
    $class = "head1C";
  } else {
    $class = "head1R";
  }
  chomp;
  print "    <td class=$class>$compound{$_}$_</td><td></td>\n";
}
print "  </tr>\n";
print "  <tr>\n";
print "    <td height=\"4\"></td>\n";
print "  </tr>\n";

# READ THE REST OF THE LINES AND PRINT TO STDOUT IN TABLE FORMAT
$row = 0;
my $molecule;
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
         $temp_smiles = $MOLECULEHash{$molecule};
      } else {
         if (param('structures')) {
            $temp_smiles = $line[1];
         } else {
            $temp_smiles = $MOLECULEHash{$molecule};
         }
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
         if ($MOLECULEHash{$molecule} eq '') {
           print "      $NC\n";
         } else {
           if ($MOLECULEHash{$molecule} eq $ERR_SMILESNOTAVAIL) {
              print "      <a href=\"#\"><img src=\"/icons/nosmiles.gif\" border=\"0\"></a>\n";
           } else {
              $smileshex = a2hex($MOLECULEHash{$molecule});
              #print "      <a href=\"/bin/smi2gif-big-cop\?$smileshex\" target=\"_blank\">\n";
              #print "      <a href=\"http://ppr-jcf/bin/structure/us/showstructure.asp?type=R&name=$molecule&width=750&height=375\" target=\"_blank\">\n";
              print "<script LANGUAGE=\"JavaScript1.1\">\n";
	      print "<!--\n";
	      print "mview_begin(\"/marvin\", 120, 100);\n";
	      print "mview_param(\"molbg\", \"#ffffff\");\n";
	      print "mview_param(\"rows\", \"1\");\n";
	      print "mview_param(\"cols\", \"1\");\n";
	      print "mview_param(\"cell0\", \"|$MOLECULEHash{$molecule}\");\n";
	      print "mview_end();\n";
	      print "//-->\n";
	      print "</script>";
	      #print "      <img src=\"/bin/smi2gif-small-cop\?$smileshex\" width=\"96\" height=\"64\"></a>\n";
              #print "      <img src=\"http://ppr-jcf/bin/structure/us/showstructure.asp?type=R&name=$molecule&width=150&height=75\"";
              #print "      <img src=\"http://jcf/bin/structure/us/showstructure.asp?type=R&name=$molecule&width=300&height=150\"";
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
if (%MOLECULEHash) {
  print "<font face=\"Arial, Geneva\" size=\"+1\" color=\"#0000FF\">\n";
  print "<p><a href=\"$EXCELfileName\" target=\"_blank\">Excel spreadsheet</a>";
  print "</font>\n";
}
 


################################################################################
#                                                                              #
# FINISH OFF                                                                   #
#                                                                              #
################################################################################

# END HTML PAGE
#print p, end_html();

# DEALLOCATE ALL MOLECULES
foreach $entry (keys (%MOLECULEHash)) {
  dt_dealloc($MOLECULEHash{$entry});
}
$dbh->disconnect;
# EXIT
exit 0;


sub getCHEMISTRY {
   return 0;
}

sub getFLEX {
   my ($value, $error, $version, $entry);
   my @flex = ();

   my $TDTfileName = $ROOTDIR . 'flex' . time . '.tdt';
   foreach $entry (@nameList) {
      next if not defined $MOLECULEHash{$entry};
      if ($entry =~ /^([0-9]{1,})$/) {
         $molecule = $1;
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
         open (TDTFILE, "+>$TDTfileName");
         print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n|\n";
         close TDTFILE;
         @flex = ExecFlexibility('-tdt -id COMP_ID', $TDTfileName);
         chomp(@flex);
         $error = 0;
         (undef, $value, undef) = split(/\s+/, $flex[0], 3);
         $value = $NC if $value eq 'NA';
         $FLEXHash{$entry} = sprintf("%.1f", $value);
      }
   }
   unlink $TDTfileName;
}


sub getTPSA {
   my ($value, $error, $version, $entry);
   my @tpsa = ();

   my $TDTfileName = $ROOTDIR . 'tpsa' . time . '.tdt';
   foreach $entry (@nameList) {
      next if not defined $MOLECULEHash{$entry};
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
         open (TDTFILE, "+>$TDTfileName");
         print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n|\n";
         close TDTFILE;
         @tpsa = ExecTpsa('-tdt -id COMP_ID', $TDTfileName);
         chomp(@tpsa);
         (undef, $value, undef) = split(/\s+/, $tpsa[0], 3);
         $value = $NC if $value eq 'NA';
         $TPSAHash{$entry} = sprintf("%.1f", $value);
      }
   }
   unlink $TDTfileName;
}


sub getSLOGP {
   my ($value, $error, $version, $entry);
   my @slogp = ();

   my $TDTfileName = $ROOTDIR . 'slogp' . time . '.tdt';
   foreach $entry (@nameList) {
      next if not defined $MOLECULEHash{$entry};
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
         open (TDTFILE, "+>$TDTfileName") || printError('Conversion Error', "Could not create TDT file : $!\n", 1);
         print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n|\n";
         close (TDTFILE);
         @slogp = qx{ /usr/local/bin/slogpv2.pl -q -s -id COMP_ID < $TDTfileName };
         #chomp(@slogp);
         (undef, $value, undef) = split(/\s+/, $slogp[0], 3);
         $SLOGPHash{$entry} = sprintf("%.1f", $value);
      }
   }
   unlink $TDTfileName;
}


sub getSMR {
   my ($value, $error, $version, $entry);
   my @smr = ();

   my $TDTfileName = $ROOTDIR . 'smr' . time . '.tdt';
   foreach $entry (@nameList) {
      next if not defined $MOLECULEHash{$entry};
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
         open (TDTFILE, "+>$TDTfileName");
         print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n|\n";
         close(TDTFILE);
         @smr = ExecSmr("-MR -q -s -id 'COMP_ID'", $TDTfileName);
         (undef, $value, undef) = split(/\s+/, $smr[1], 3);
         $SMRHash{$entry} = sprintf("%.1f", $value);
      }
   }
   unlink $TDTfileName;
}

################################################################################
#                                                                              #
# SUBROUTINE TO CALCULATE THE CLOGP                                            #
#                                                                              #
################################################################################

sub getCLOGP {
  my ($clogp, $error, $version, $entry);

  my $TDTfileName = $ROOTDIR . 'clogp' . time . '.tdt';
  foreach $entry (@nameList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $MOLECULEHash{$entry};
    
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

      open (TDTFILE, "+>$TDTfileName") || printError('File Error', "Could not open file $TDTfileName : $!\n",1);
      TDTFILE->autoflush(1);
      print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n|\n";
      close TDTFILE;

      @clogp = ();
      @clogp = ExecClogP('-i', $TDTfileName, 0);
      #@clogp = Clogp($TDTfileName, 10);
      foreach $chunk (@clogp) {
         chomp($chunk);
         next if $chunk =~ /\$SMIG/;
         next if $chunk =~ /^$/;
         $key = &FindItem($chunk, 'COMP_ID');
         next if ! $key;
         $cp = &FindItem($chunk,'CP');
         next if ! $cp;
         ($value, $err, undef) = split(/;/, $cp, 3);
         $err = $1 if $err =~ /\-([0-9]{1,}).*/;
         $CLOGPHash{$entry} = (defined($err) && $err < $ERROR_LIMIT) ? sprintf("%.1f", $value) : 'NC';
      }
      unlink $TDTfileName;
    }
  }
}


################################################################################
#                                                                              #
# SUBROUTINE TO CALCULATE THE CMR                                              #
#                                                                              #
################################################################################

sub getCMR {
  my ($cmr, $error, $version, $entry);

   my $TDTfileName = $ROOTDIR . 'cmr' . time . '.tdt';
  foreach $entry (@nameList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $MOLECULEHash{$entry};
    
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
       $CMRHash{$molecule} = (defined($error) && $error < $ERROR_LIMIT ) ? sprintf("%.1f", 10 * $value) : 'NC';
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE CMR
      open (TDTFILE, "+>$TDTfileName");
      print TDTFILE "\$SMI<$entry>\n\$COMP_ID<$entry>\n|\n";
      close TDTFILE;
      my @clogp = ();
      @clogp = ExecLogP('ClogP', '-i', $TDTfileName, 1);
      foreach $chunk (@clogp) {
         chomp;
         next if $chunk =~ /\$SMIG/;
         next if $chunk =~ /^$/;
         $key = &FindItem($chunk, 'COMP_ID');
         next if ! $key;
         $cr = &FindItem($chunk,'CR');
         next if ! $cr;
         ($value, $err, undef) = split(/;/, $cr, 3);
         $err = $1 if $err =~ /\-([0-9]{1,}).*/;
         if (defined($err) && ($err <= 0)) {
	   $CMRHash{$entry} = sprintf("%.1f", 10 * $cr);
         } else {
           $CMRHash{$entry} = 'NC';
         }
      }
    }
  }
  unlink $TDTfileName;
}



################################################################################
#                                                                              #
# SUBROUTINE TO COUNT THE NUMBER OF HYDROGEN BOND ACCEPTORS                    #
#                                                                              #
################################################################################

sub getHBA {
  my ($smartspattern, $paths, $path_count, $entry);

  foreach $entry (@nameList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $MOLECULEHash{$entry};

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
       $select->execute($molecule, $prop{'HBA'}) || printError('CHAROn Error', "CHAROn Error::$DBI::err::$DBI::errstr\n", 1);
       ($value, $error, $version) = $select->fetchrow_array;
       printError('CHAROn retrieval error', "CHAROn retrieval error::$DBI::err::$DBI::errstr\n", 1) if $DBI::err;
       $HBAHash{$molecule} = (defined($error) && $error <= 0 ) ? $value : $NC;
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE NUMBER OF HBA
      $smartspattern = dt_smartin("[#7,#8]");
      $HBAHash{$entry} = 0;
      my $mol = dt_smilin($MOLECULEHash{$entry});
      $paths = dt_stream(dt_umatch($smartspattern, $mol, 0), TYP_PATH);
      $path_count = dt_count($paths, TYP_PATH);
      $HBAHash{$entry} = $path_count if $path_count > 0;
      dt_dealloc($paths);
    }
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO COUNT THE NUMBER OF HYDROGEN BOND DONORS                       #
#                                                                              #
################################################################################


sub getHBD {
  my ($i, @smartspattern, $paths, $path_count, $entry);

  foreach $entry (@nameList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $MOLECULEHash{$entry};

    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE NUMBER OF HBD FROM DATABASE (TB_COMPOUND_PROP)
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
    } else {
      # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
      # CALCULATE THE NUMBER OF HBD
      $smartspattern[1] = dt_smartin("[#7,#8;H1]");
      $smartspattern[2] = dt_smartin("[#7,#8;H2]");
      $smartspattern[3] = dt_smartin("[#7,#8;H3]");
      my $mol = dt_smilin($MOLECULEHash{$entry});
      $HBDHash{$entry} = 0;
      for ($i = 1; $i <= 3; $i++) {
        $paths = dt_stream(dt_umatch($smartspattern[$i], $mol, 0), TYP_PATH);
        $path_count = dt_count($paths, TYP_PATH);
        if ($path_count > 0) { $HBDHash{$entry} += ($i * $path_count); }
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

sub getRB {
  my ($smartspattern, $paths, $path_count, $entry);

  foreach $entry (@nameList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $MOLECULEHash{$entry};

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
      # CALCULATE THE NUMBER OF RB's
      # GENERAL PART
      $RBHash{$entry} = 0;
      my $mol = dt_smilin($MOLECULEHash{$entry});
      $smartspattern = dt_smartin('[!$(*#*)&!D1]-&!@[!$(*#*)&!D1]');
      $paths = dt_stream(dt_umatch($smartspattern, $mol, 0), TYP_PATH);
      $path_count = dt_count($paths, TYP_PATH);
      if ($path_count > 0) {
        $RBHash{$entry} = $path_count;
      }
      dt_dealloc($paths);
      
      # CORRECTION FOR SECONDARY AMIDES
      $smartspattern = dt_smartin('C(=[O,S,N])-&!@[NH1]');
      $paths = dt_stream(dt_umatch($smartspattern, $mol, 0), TYP_PATH);
      $path_count = dt_count($paths, TYP_PATH);
      if ($path_count > 0) {
        $RBHash{$entry} -= $path_count;
      }
      dt_dealloc($paths);
    }
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO GET THE EMPIRICAL FORMULA                                      #
#                                                                              #
################################################################################

sub getEF {
  my ($entry, $atom, $atoms, %element, $key, $value);

  foreach $entry (@nameList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $MOLECULEHash{$entry};

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
       $EFHash{$molecule} = (defined($mf)) ? $mf : $NC;
    } else {
       # SECOND CASE: COMPOUND COMES FROM MOLECULAR EDITOR.
       # CALCULATE THE EF.
      # LOOP OVER ALL ATOMS
      my $mol = dt_smilin($MOLECULEHash{$entry});
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
  
  # READ THE MASS DATA
  while (<DATA>) {
    #undef $element, $avgMass, $mimMass;
    ($element, $avgMass, $mimMass) = split;
    $avgMassHash{$element} = $avgMass;
    $mimMassHash{$element} = $mimMass;
  }

  foreach $entry (@nameList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $MOLECULEHash{$entry};
    %element = (); 
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
      my $mol = dt_smilin($MOLECULEHash{$entry});
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
  }
}


################################################################################
#                                                                              #
# SUBROUTINE TO GET THE MONO-ISOTOPIC MASS                                     #
#                                                                              #
################################################################################

sub getMIM {
  my ($contrib, $entry, $atom, $atoms, %element, $element, $avgMass, $mimMass, $key, $value, $mol);
    
  # READ THE MASS DATA
  while (<DATA>) {
    #undef $element, $avgMass, $mimMass;
    ($element, $avgMass, $mimMass) = split;
    $avgMassHash{$element} = $avgMass;
    $mimMassHash{$element} = $mimMass;
  }
    
  foreach $entry (@nameList) {
    $contrib = 0.0;
    %element = ();
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $MOLECULEHash{$entry};

    # LOOP OVER ALL ATOMS
    $mol = dt_smilin($MOLECULEHash{$entry});
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

  # CALCULATE THE ROF
  foreach $entry (@nameList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $MOLECULEHash{$entry};

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
      # CALCULATE THE MW

      my @list = keys(%MWHash);
      getMW() if ! scalar(@list);

      @list = keys(%HBAHash);
      getHBA() if ! scalar(@list);

      @list = keys(%HBDHash); 
      getHBD() if ! scalar(@list);

      @list = keys(%CLOGPHash);
      getCLOGP() if ! scalar(@list);

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
# SUBROUTINE TO GET THE CHARGE                                                 #
#                                                                              #
################################################################################

sub getCHARGE {
  my ($entry, $atom, $atoms, @pka_list, @pkb_list, $pk, $Qa, $Qb, $t, $mol);
  
  # 1. CALCULATE FORMAL CHARGE
  foreach $entry (@nameList) {
    next if not defined $MOLECULEHash{$entry};
    
    $CHARGEHash{$entry} = 0;
    $mol = dt_smilin($MOLECULEHash{$entry});
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
 
  my @list1 = keys(%PKAHash);
  my @list2 = keys(%PKBHash);
  getPK() if ! scalar(@list1) || ! scalar(@list2);

  foreach $entry (@nameList) {
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
# SUBROUTINE TO GET THE CLOGD                                                  #
#                                                                              #
################################################################################

sub getCLOGD {
  my ($entry, $clogd, $pka, $pkb, @pka, @pkb);
  
  # 1. DEFAULT pH
  if (param('pH_logd')) {
    $pH_logd = param('pH_logd');
  } else {
    $pH_logd = 7.4;
  }
  # 2. RETRIEVE THE CLOGP
  my @list = keys(%CLOGPHash);
  getCLOGP() if ! scalar(@list);

  # 3. RETRIEVE THE ACID AND BASE CONSTANTS
  @list = keys(%PKAHash);
  my @list2 = keys(%PKBHash);
  getPK() if ! scalar(@list) || ! scalar(@list2);
  
  # 4. CALCULATE CLOGD
  ENTRY: foreach $entry (@nameList) {
    next if not defined $MOLECULEHash{$entry};
    
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
      $CLOGDHash{$entry} = sprintf("%.1f", $clogd);
      
    } else {
      $CLOGDHash{$entry} = 'NC';
      next ENTRY;
    }
  }
}



################################################################################
#                                                                              #
# SUBROUTINE TO GET THE PK                                                     #
#                                                                              #
################################################################################

sub getPK {
  my ($entry, @result, $cmp, $value, $type);
  my (@pka, @pkb) = ((),());

  my $TDTfileName = $ROOTDIR . 'pk' . time . '.tdt';
  my $SDFfileName = $ROOTDIR . 'pk' . time . '.sdf';
  foreach $entry (@nameList) {
    # SKIP TO NEXT ENTRY IF CURRENT ENTRY IS NOT DEFINED
    next if not defined $MOLECULEHash{$entry};

    # FIRST CASE: COMPOUND IS R-NUMBER.
    # RETRIEVE PKA AND PKB FROM DATABASE (TB_COMPOUND_PROP)
    if ($entry =~ /^([0-9]{1,})$/) {
       $molecule = $1;
       my @pk = ();
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
       foreach $pk (sort @pk) {
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
      open (TDTFILE, "+>$TDTfileName");
      print TDTFILE "\$SMI<$entry>\nCOMP_ID<$entry>\n\|\n";
      close TDTFILE;
      my @result = ();
      my @pk = ();
      qx { $SMI2MOL -input_format TDT -add_2d FALSE < $TDTfileName > $SDFfileName 2>/dev/null }; 
      #@result = ExecPkaPkb('-vert -ityp sdf -idfld COMP_ID -lpKa 0 -hpKa 14 -nohd -det /dev/null', $SDFfileName);
      @result = ExecPkaPkb('-vert -ityp sdf -idfld COMP_ID -nohd -det /dev/null', $SDFfileName);
      chomp(@result);
      $PKAHash{$entry} = $PKBHash{$entry} = '';
      @pka = @pkb = ();
      foreach (@result) {
        ($cmp, $value, $type, undef) = /^(.*)\s+([\d\-\.]+)\s+(Acid|Base)\s+(\d+)/;
        next if ! defined($cmp);
        if ($type eq 'Acid') {
           push @pka, sprintf("%.1f", $value);
        } else {
           push @pkb, sprintf("%.1f", $value);
        }
      }
      foreach $pk (sort { $a <=> $b } @pka) {
         $PKAHash{$entry} .= (sprintf("%.1f", $pk) . ' ');
      }
      $PKAHash{$entry} = $NC if $PKAHash{$entry} eq '';
      foreach $pk (sort { $b <=> $a } @pkb) {
         $PKBHash{$entry} .= (sprintf("%.1f", $pk) . ' ');
      }
      $PKBHash{$entry} = $NC if $PKBHash{$entry} eq '';
    }
  }
  unlink $SDFfileName, $TDTfileName;
}

sub printError {
   my ($title, $msg, $disconnect) = @_;

   &printPageHeader($title);
   print $msg;
   &printPageFooter;
   $dbh->disconnect if $disconnect;
   exit 1;
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

sub printPageFooter {
  print "</body></html>\n";
}

sub printEnv {
  &printPageHeader('');
  while (($key, $val) = each %ENV) {
     print "$key = $val<BR>\n";
  }
  &printPageFooter;
}

sub printMsg {
  my ($line) = @_;

  print $line, "<br>\n";
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
