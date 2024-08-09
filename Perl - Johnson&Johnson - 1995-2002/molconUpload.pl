#!/usr/local/bin/perl -w
#####################################################################################
# @(#)FILE      : molconUpload"                                                     #
# @(#)TYPE FILE : Executable perl5 script, datafiles need to be present"            #
# @(#)EXECUTE   : Should only be called by UploadCharon routine                     #
# @(#)ENVRONMENT: Daylight + Molconn-Z                                              #
# @(#)AUTHOR    : M. Quirijnen                                     DATE: 05/07/00"  #
# @(#)USAGE     : Calculate chemical parameters using the Molconn-Z environment"    #
# @(#)Molconn-Z file format :                                                       #
#           CCOC(=O)N1CCc2c(C1)c(=O)[nH]c3ccccc23 R0027725                          #
#           CCOC(=O)N1CCc2c(C1)c(=O)c3ccccc23 R0027726                              #
# @(#)RETURN CODES :                                                                #
#   0  = normal successfull completion                                              #
#   -1 = there was an error                                                         #
# REMARKS : Molcon-Z file contains multi-line records, each record is 48 lines      #
#           Lots of info in this file is useless because some functionalities       #
#           aren't implemented in Molcon-Z yet .. it's for future implementations   #
#####################################################################################
require 5.000;

use Env;
use Carp;
use DBI;
use Time::localtime;
use IO::Handle;
use lib "/usr/local/bin/scripts/automation";
use Modules::TMCDefs;
use Modules::TMCSubs;
use Modules::TMCOracle;


use sigtrap qw(die normal-signals error-signals);

my %readMolconRecs = ( '1'  => \&readMz1,
                       '2'  => \&readMz2_3,
                       '4'  => \&readMz4,
                       '5'  => \&readMz5,
                       '6'  => \&readMz6_7,
                       '8'  => \&readMz8,
                       '9'  => \&readMz9_14,
                       '15' => \&readMz15_21,
                       '22' => \&readMz22_28,
                       '29' => \&readMz29_34,
                       '35' => \&readMz35,
                       '36' => \&readMz36,
                       '37' => \&readMz37_39,
                       '40' => \&readMz40,
                       '41' => \&readMz41_43,
                       '44' => \&readMz44_46,
                       '47' => \&readMzrest,
                     );

my ($DEBUG, $comp_id, $comp_type, $MAIL_LIST, $NOMAIL) = (0, 0, 'R', 'ttabruyn@janbe.jnj.com,mquirij1@janbe.jnj.com', 1);
my ($JRF, $JNJ, $INFILE) = ( 1, 0, '' );
my $count = 1;
my $dbh;


######################################
# Actual upload routine 
# Since some datafields might not be present, or in a different order
# the update/insert sql string has to be buildup on the fly
# Gathering table column info is done through the SYS.dba_* tables
######################################
sub Upload2Oracle
{
   ($table, $dataarr) = @_;
   my (@s_columns, @columns, @row) = ((),(),());
   my ($upd_str, $upd, $cols, $select_str, $select, $delete_str, $delete, $ins, $ins_str);

   #LogMsg(*LOGFILE, "Upload2Oracle : Data for table tmc.$table");
   # get the Oracle table columns (too much to type in)
   $cols = $dbh->prepare("select column_name from SYS.dba_tab_columns where table_name=? order by column_id");
   $cols->execute(uc($table));
   @columns = ();
   while (@row = $cols->fetchrow_array) {
      push @columns, $row[0];
   }
   @s_columns = @columns;
   undef @columns;
   # check if compound is already there
   $select_str = "SELECT COMP_NR from tmc." . $table . " where COMP_NR = ? and COMP_TYPE = ?";
   $select = $dbh->prepare($select_str);
   $select->execute($comp_id, $comp_type) || die $dbh->errstr;
   @row = $select->fetchrow_array;
   if (scalar(@row)) {
      #unshift @$dataarr, $comp_id, $comp_type;
      # compound is in CHARON already .. update it
      $upd_str = 'UPDATE TMC.' . $table . ' SET ';
      for ($x=0; $x < scalar(@s_columns); $x++) {
         next if $x < 2;
         if ($x == scalar(@s_columns) -1) {
            $upd_str .= ($s_columns[$x] . '=' . $$dataarr[$x-2]);
         } else {
            $upd_str .= ($s_columns[$x] . '=' . $$dataarr[$x-2] . ',');
         }
      }
      $upd_str .= ' WHERE comp_nr = ? and comp_type = ?';
      #LogMsg(*LOGFILE, "Upload2Oracle : update str = $upd_str\n");
      $upd = $dbh->prepare($upd_str);
      $upd->execute($comp_id, $comp_type);
   } else {
      # compound isn't in CHAROn yet, so insert it
      $ins_str = 'INSERT INTO TMC.' . $table . ' values (';
      for ($x=1; $x < scalar(@s_columns); $x++) {
         $ins_str .= '?,';
      }
      $ins_str .= '?)';
      $ins = $dbh->prepare($ins_str);
      unshift @$dataarr, $comp_id, $comp_type;
      #LogMsg(*LOGFILE, "Upload2Oracle : insert str = $ins_str\n");
      $ins->execute(@$dataarr);
   }
   $dbh->commit;
   return 0;
}


####################
# Read line #1
####################
sub readMz1
{
   my $fileref = shift;
   my @line = ();
   my $rc = 0;

   return 1 if (eof $fileref);
   #LogMsg(*LOGFILE, "readMz1 : Reading line 1");
   chomp(@line = split(/\s+/, <$fileref>));

   # we need to remove some crap from the molconn-z file
   # this molconn-z guy is a cobol mainframe programmer..doesnt know what a text file is

   shift(@line); #pop(@line);
   # crap removed (a load of SOH chars)
   if ($JRF) {
      if ($line[scalar(@line)-1] =~ /([R])([0-9]{$RNUM_LEN})/) {
         $comp_id = $2;
         $comp_type = $1;
         print $comp_type, ' ', $comp_id, "\n" if $DEBUG;
      } else {
         warn "comp_id = $line[scalar(@line)-1]\n";
         $comp_id = pop(@line);
         $comp_type = '';
      }
   } else {
      warn "comp_id = $line[scalar(@line)-1]\n";
      $comp_id = pop(@line);
      $comp_type = '';
   }
   #LogMsg(*LOGFILE, "readMz1 : recordno = $count, COMP_ID = $comp_id, COMP_TYPE = $comp_type");
   $count++;
   # remove ID, ANAME value from @line .. serve no purpose.
   shift(@line); pop(@line);
   # save data into CHARON
   $rc = Upload2Oracle('mz1', \@line);
   #LogMsg(*LOGFILE, "readMz1 : Line 1 processed : $rc");
   return $rc;
}

####################
# Read lines #2->3
####################
sub readMz2_3
{
   my $fileref = shift;
   my @fline = ();
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz2_3 : Reading lines 2..3");
   for (2..3) {
      chomp($line = <$fileref>);
      push(@fline, $line);
   }
   $result = join('', @fline);
   @line = unpack("a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10", $result);
   #@line = split(/[ \t]+/, $result);
   # remove first crap record...
   #shift(@line);
   $rc = Upload2Oracle('mz2_3', \@line);
   #LogMsg(*LOGFILE, "readMz2_3 : Line 2..3 processed : $rc");
   return $rc;
}

####################
# Read line #4
####################
sub readMz4
{
   my $fileref = shift;
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz4 : Reading line 4");
   #chomp(@line = split(/[ \t]+/, <$fileref>));
   # remove first crap record...
   #shift(@line);
   $line = <$fileref>;
   @line = unpack("a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10", $line);
   $rc = Upload2Oracle('mz4', \@line);
   #LogMsg(*LOGFILE, "readMz4 : Line 4 processed : $rc");
   return $rc;
}

####################
# Read line #5
####################
sub readMz5
{
   my $fileref = shift;
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz5 : Reading line 5");
   #chomp(@line = split(/[ \t]+/, <$fileref>));
   # remove first crap record...
   #shift(@line);
   $line = <$fileref>;
   @line = unpack("a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10", $line);
   $rc = Upload2Oracle('mz5', \@line);
   #LogMsg(*LOGFILE, "readMz5 : Line 5 processed : $rc");
   return $rc;
}

####################
# Read lines #6->7
####################
sub readMz6_7
{
   my $fileref = shift;
   my @fline = ();
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz6_7 : Reading lines 6..7");
   for (6..7) {
      chomp($line = <$fileref>);
      push(@fline, $line);
   }
   $result = join('', @fline);
   @line = unpack("a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10 a10", $result);
   $rc = Upload2Oracle('mz6_7', \@line);
   #LogMsg(*LOGFILE, "readMz6_7 : Lines 6..7 processed : $rc");
   return $rc;
}

####################
# Read line #8
####################
sub readMz8
{
   my $fileref = shift;
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz8 : Reading line 8");
   #chomp(@line = split(/[ \t]+/, <$fileref>));
   # remove first crap record...
   #shift(@line);
   $line = <$fileref>;
   @line = unpack("a9 a9 a9 a9 a9 a9 a9 a9 a16 a11 a11 a11 a9", $line);
   $rc = Upload2Oracle('mz8', \@line);
   #LogMsg(*LOGFILE, "readMz8 : Line 8 processed : $rc");
   return $rc;
}

####################
# Read lines #9-14
####################
sub readMz9_14
{
   my $fileref = shift;
   my @fline = ();
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz9_14 : Reading lines 9..14");
   for (9..14) {
      chomp($line = <$fileref>);
      push(@fline, $line);
   }
   $result = join('', @fline);
   @line = unpack("a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8", $result);
   $rc = Upload2Oracle('mz9_14', \@line);
   #LogMsg(*LOGFILE, "readMz9_14 : Lines 9..14 processed : $rc");
   return $rc;
}

####################
# Read lines #15->21
####################
sub readMz15_21
{
   my $fileref = shift;
   my @fline = ();
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz15_21 : Reading lines 15..21");
   for (15..21) {
      chomp($line = <$fileref>);
      push(@fline, $line);
   }
   $result = join('', @fline);
   @line = unpack("a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9", $result);
   $rc = Upload2Oracle('mz15_21', \@line);
   #LogMsg(*LOGFILE, "readMz15_21 : Lines 15..21 processed : $rc");
   return $rc;
}

####################
# Read lines #22->28
####################
sub readMz22_28
{
   my $fileref = shift;
   my @fline = ();
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz22_28 : Reading lines 22..28");
   for (22..28) {
      chomp($line = <$fileref>);
      push(@fline, $line);
   }
   $result = join('', @fline);
   @line = unpack("a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9 a9", $result);
   $rc = Upload2Oracle('mz22_28', \@line);
   #LogMsg(*LOGFILE, "readMz22_28 : Lines 22..28 processed : $rc");
   return $rc;
}

####################
# Read lines #29->34
####################
sub readMz29_34
{
   my $fileref = shift;
   my @fline = ();
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz29_34 : Reading lines 29..34");
   for (29..34) {
      chomp($line = <$fileref>);
      push(@fline, $line);
   }
   $result = join('', @fline);
   @line = unpack("a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8 a8", $result);
   $rc = Upload2Oracle('mz29_34', \@line);
   #LogMsg(*LOGFILE, "readMz29_34 : Lines 29..34 processed : $rc");
   return $rc;
}

####################
# Read line #35
####################
sub readMz35
{
   my $fileref = shift;
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz35 : Reading line 35");
   #chomp(@line = split(/[ \t]+/, <$fileref>));
   # remove first crap record...
   #shift(@line);
   $line = <$fileref>;
   @line = unpack("a13 a13 a13 a13 a10 a9 a9 a10 a9 a9 a4 a4 a4 a4", $line);
   $rc = Upload2Oracle('mz35', \@line);
   #LogMsg(*LOGFILE, "readMz35 : Line 35 processed : $rc");
   return $rc;
}

####################
# Read line #36
####################
sub readMz36
{
   my $fileref = shift;
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz36 : Reading line 36");
   #chomp(@line = split(/[ \t]+/, <$fileref>));
   # remove first crap record...
   $line = <$fileref>;
   @line = unpack("a5 a5 a5 a5 a5 a5 a5 a5 a5 a5 a4 a4 a4 a3 a3 a3 a3 a3 a3 a3 a3 a10 a4 a4 a4 a4 a6", $line);
   #foreach $elem (@line) {
   #   $elem =~ s/[ ]+//;
   #   push @lines, , $elem;
   #}
   $rc = Upload2Oracle('mz36', \@line);
   #LogMsg(*LOGFILE, "readMz36 : Line 36 processed : $rc");
   return $rc;
}

####################
# Read lines #37->39
####################
sub readMz37_39
{
   my $fileref = shift;
   my @fline = ();
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz37_39 : Reading lines 37..39");
   for (37..39) {
      chomp($line = <$fileref>);
      push(@fline, $line);
   }
   $result = join('', @fline);
   @line = unpack("a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4", $result);
   $rc = Upload2Oracle('mz37_39', \@line);
   #LogMsg(*LOGFILE, "readMz37_39 : Lines 37..39 processed : $rc");
   return $rc;
}

####################
# Read lines #40
####################
sub readMz40
{
   my $fileref = shift;
   my $rc = 0;
   
   #LogMsg(*LOGFILE, "readMz40 : Reading line 40");
   #chomp(@line = split(/[ \t]+/, <$fileref>));
   # remove first crap record...
   #shift(@line);
   $line = <$fileref>;
   @line = unpack("a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4", $line);
   $rc = Upload2Oracle('mz40', \@line);
   #LogMsg(*LOGFILE, "readMz40 : Line 40 processed : $rc");
   return $rc;
}

####################
# Read lines #41->43
####################
sub readMz41_43
{
   my $fileref = shift;
   my @fline = ();
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz41_43 : Reading lines 41..43");
   for (41..43) {
      chomp($line = <$fileref>);
      push(@fline, $line);
   }
   $result = join('', @fline);
   @line = unpack("a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4", $result); 
   $rc = Upload2Oracle('mz41_43', \@line);
   #LogMsg(*LOGFILE, "readMz41_43 : Lines 41..43 processed : $rc");
   return $rc;
}

####################
# Read lines #44->46
####################
sub readMz44_46
{
   my $fileref = shift;
   my @fline = ();
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMz44_46 : Reading lines 44..46");
   for (44..46) {
      chomp($line = <$fileref>);
      push(@fline, $line);
   }
   $result = join('', @fline);
   @line = unpack("a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4 a4", $result);
   $rc = Upload2Oracle('mz44_46', \@line);
   #LogMsg(*LOGFILE, "readMz44_46 : Lines 44..46 processed : $rc");
   return $rc;
}

####################
# Read lines #47->48
####################
sub readMzrest
{
   my $fileref = shift;
   my $line;
   my $rc = 0;

   #LogMsg(*LOGFILE, "readMzrest : Reading rest of record lines (47->48)");
   for (47..48) {
      chomp($line = <$fileref>);
      #push(@fline, $line);
   }
   #$result = join('', @fline);
   #@line = split(/[ \t]+/, $result);
   # remove first crap record...
   #shift(@line);
   #these lines dont have to be stored in database
   #$rc = Upload2Oracle('mzrest', \@line);
   #LogMsg(*LOGFILE, "readMzrest : Rest of lines processed : $rc");
   return $rc;
}

######################################
# Start of script
######################################
my $rc = 0;

if (scalar(@ARGV)) {
   while (@ARGV && ($_ = $ARGV[0])) {
      if (/^-(\w+)/) {
         CASE : {
              if ($1 =~ /jnj/) { $JNJ = 1; $JRF = 0; last CASE; }
              if ($1 =~ /jrf/) { $JNJ = 0; $JRF = 1; last CASE; }
              if ($1 =~ /infile/) { shift(@ARGV); $INFILE = $ARGV[0]; last CASE; }
              if ($1 =~ /nomail/) { $NOMAIL=1; last CASE; }
         }
      } else {
         print "Oops: Unknown option : $_\n";
         die "Usage : $0 -jnj|jrf -infile <infile.S>\n";
      }
      shift(@ARGV);
   }
}
$LOG = '/usr/tmp/molcon_upload_' . $$ . '.log';
open(LOGFILE, "+>$LOG") || die "Can't open log file $LOG : $!";
LOGFILE->autoflush(1);
LogMsg(*LOGFILE, "Processing $INFILE");

open (FILE, "<$INFILE") || die "Could not open inputfile $INFILE : !$\n";
$dbh = DBI->connect($ORA_SID, $ORA_RW_USER, $ORA_RW_PWD, 'Oracle') || die "Unable to connect to $ORA_SID\n";
while (! $rc) {
   # keep reading & processing file until we get an error code (which could be an eof)
   foreach $key (sort { $a <=> $b } keys %readMolconRecs) {
     $rc = &{$readMolconRecs{$key}}(\*FILE);
     last if $rc;
   }
}
close(FILE) || die "Close inputfile $INFILE failed : $!\n";;
$dbh->disconnect();

close(LOGFILE) || die "Close log file $LOG failed : $!\n";

qx{ /usr/sbin/Mail -s 'MolconUpload.pl logfile' $MAIL_LIST < $LOG } unless $NOMAIL;

qx{ rm -f $LOG /tmp/*.MSG };
exit $rc;
