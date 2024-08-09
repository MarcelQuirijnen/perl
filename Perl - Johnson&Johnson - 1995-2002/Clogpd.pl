#!/usr/local/bin/perl

##############################################################################
#
# - Continuous routine to pick-up new compounds from the labs and insert
#   them into CHAROn after calculation of their properties
#   All the data is archieved on disk & tape
# - This daemon routine starts at system startup, through /etc/init.d/rc
# - The routine does react to the typical Unix signals .. restart/stop/..
# - Input files : SD & TDT file
# - Clogp values >= -60P or 'ClogpNotAvailable' are filtered out
# - Detailed info on portal through secured login procedure
# - Author : M. Quirijnen
#
##############################################################################
require 5.000;

use IO::Handle;
use Env;
use Carp;
use POSIX qw(sys_wait_h strftime setsid getpid);
use Time::localtime;
use Unix::Syslog qw(:macros :subs);
use File::Basename;
use File::Copy;
use lib "/usr/local/bin/scripts/automation";
use Modules::TMCDefs;
use Modules::TMCSubs;
use sigtrap qw(die normal-signals error-signals);


my ($TEST, $NOMAIL, $KeepGoing) = (0, 0, 1);

if ($TEST) {
   ($MAIL_LIST, $SLEEPTIME, $HOME_DIR) = ('mquirij1@janbe.jnj.com', 30, '/tmp');
} else {
   ($MAIL_LIST, $SLEEPTIME, $HOME_DIR) = ('ttabruyn@janbe.jnj.com,mquirij1@janbe.jnj.com,mengels@janbe.jnj.com,tthielem@janbe.jnj.com', 300, (getpwuid($<))[7]);
}

$WHICHMAIL = '/usr/sbin/Mail';

$SMI_FILE       = $HOME_DIR . '/' . 'smi.tdt';
$PID_FILE       = $HOME_DIR . '/' . 'Clogpd.pid';
$LOG_FILE       = $HOME_DIR . '/' . 'Clogpd.log';
$CLOGP_SMI_FILE = $HOME_DIR . '/' . 'clogp.tdt';

$FTP_DIR   = $HOME_DIR . '/' . 'cheminfo/sdf';
$ARCH_DIR  = $HOME_DIR . '/' . 'daylight/rnum';
$CLOGP_DIR = $HOME_DIR . '/' . 'cheminfo/clogp';

$EOF_FTP    = $FTP_DIR . '/' . 'ftp_done.dat';
$SDF_FILE   = $FTP_DIR . '/' . 'rnum.sdf';
$TDT_FILE   = $FTP_DIR . '/' . 'rnum.tdt';
if ($TEST) {
   $CLOGP_FILE = $HOME_DIR . '/' . 'rnum.tab';
} else {
   $CLOGP_FILE = $CLOGP_DIR . '/' . 'rnum.tab';
}

$ARCH_SDF='';
$ARCH_TDT='';
$ARCH_SMI='';



##################################################
# Use : Execute given program as a child process #
# Params : see 'my'-list                         #
##################################################
sub ExecProgram
{
   my ($Dir, $Prog, $Params) = @_;
   LogMsg(*LOGFILE, "$Dir $Prog $Params");
   if (!($progpid = fork())) {
      exec("$Dir/$Prog $Params");
      print STDERR "Failed to exec $Dir/$Prog with $Params : $!\n";
      syslog(LOG_INFO, "Failed to exec $Dir/$Prog with $Params : $!\n"); 
      LogMsg(*LOGFILE, "Failed to exec $Dir/$Prog with $Params : $!\n"); 
      exit;
   }
   push(@childpids, $progpid);
}

##################################################
# Use : Cleanup dead processes                   #
# Params : None                                  #
##################################################
sub Reaper
{
   local($pid);
   do {    
      $pid = waitpid(-1, &WNOHANG);
      @childpids = grep { $_ != $pid } @childpids;
   } while($pid > 0);
}

##################################################
# Use : Handle 'kill -TERM' signals              #
# Params : None                                  #
##################################################
sub TermHandler
{
   if (@childpids) {
      $len = @childpids;
      kill('TERM', @childpids);
   }
   LogMsg(*LOGFILE, "Clogpd terminated by TERM signal.");
   close(LOGFILE);
   syslog(LOG_INFO, "Clogpd terminated by TERM signal.");
   qx{ $WHICHMAIL -s 'Clogp mechanism logfile' $MAIL_LIST < $LOG_FILE } unless $NOMAIL;
   qx { rm -f $PID_FILE $LOG_FILE '/tmp/mol2smi.clogpd.log' };
   exit(1);
}

##################################################
# Use : Handle 'kill -HUP' signals               #
#       Used to restart the daemon               #
# Params : None                                  #
##################################################
sub RestartProcess
{
   # Called when a SIGHUP is received to restart this daemon process. This is done
   # by exec()ing perl with the same command line as was originally used

   open(SOURCE, $Program);
   <SOURCE> =~ /^#!(\S+)/; 
   $ipath = $1;
   close(SOURCE);
   syslog(LOG_INFO, "Clogpd restarted by HUP signal.");
   LogMsg(*LOGFILE, "Clogpd restarted by HUP signal.");
   close(LOGFILE);
   qx{ $WHICHMAIL -s 'Clogp mechanism logfile' $MAIL_LIST < $LOG_FILE } unless $NOMAIL;
   qx { rm -f $PID_FILE $LOG_FILE };
   exec($ipath, $Program, @ARGV);
   die "Failed to restart $Program using $ipath";
}

##################################################
# Use : Archive FTP data files on a weekly base  #
# Params : See 'my-list'                         #
##################################################
sub ArchiveDataFiles
{
   my ($sdf_file, $tdt_file, $smi_file, $arch_moment) = @_;

   ($sdf_name, $sdf_dir, $sdf_ext) = fileparse($sdf_file, '\..*');
   ($tdt_name, $tdt_dir, $tdt_ext) = fileparse($tdt_file, '\..*');
   ($smi_name, $smi_dir, $smi_ext) = fileparse($smi_file, '\..*');
   $ARCH_SDF = $ARCH_DIR . '/' . $sdf_name . '.' . $arch_moment . $sdf_ext;
   $ARCH_TDT = $ARCH_DIR . '/' . $tdt_name . '.' . $arch_moment . $tdt_ext;
   $ARCH_SMI = $ARCH_DIR . '/' . $smi_name . '.' . $arch_moment . $smi_ext;
   copy($sdf_file, $ARCH_SDF);
   copy($tdt_file, $ARCH_TDT);
   copy($smi_file, $ARCH_SMI);
   LogMsg(*LOGFILE, "Archived SD file to $ARCH_SDF");
   LogMsg(*LOGFILE, "Archived TDT file to $ARCH_TDT");
   LogMsg(*LOGFILE, "Archived SMILES/CLOGP file to $ARCH_SMI");
   qx { rm -f $smi_file };
}

######################################
# Start of script                    #
######################################
my $rc = 0;
my @childpids = @clogps = ();
my $need_restart = 0;
$Program = $0;
print $Program, "\n";
croak "Oops .. Clogpd is already running. Bye.\n" if -r $PID_FILE;
$rc = &CheckConfig('clogp');
unless ($rc) {
   #change to the users home directory
   chdir $HOME_DIR;
   if ($TEST) {
      mkdir 'cheminfo', 0777;
      mkdir 'cheminfo/sdf', 0777;
      mkdir 'cheminfo/clogp', 0777;
      mkdir 'daylight', 0777;
      mkdir 'daylight/rnum', 0777;
   }
   if ($TEST) {
      syslog(LOG_INFO, "$0 started in test mode.");
   } else {
      syslog(LOG_INFO, "$0 started.");
   }

   #create and open log file
   open(LOGFILE, "+>$LOG_FILE") || die "$0::main : Can't open log file $LOG_FILE : $!\n";
   LOGFILE->autoflush(1);

   if ($TEST) {
      LogMsg(*LOGFILE, "TEST mode");
   }

   # Split from the controlling terminal, be a daemon :-)
   if (fork()) { exit; }
   setsid();

   # write out the PID file
   open(PIDFILE, "> $PID_FILE");
   printf PIDFILE "%d\n", getpid();
   close(PIDFILE);

   #Setup signal handlers
   $SIG{'CHLD'} = "Reaper";
   $SIG{'HUP'} = "RestartProcess";
   $SIG{'TERM'} = "TermHandler";
   $SIG{'PIPE'} = sub { syslog(LOG_INFO, "ignoring SIGPIPE"); };

   while ($KeepGoing) {
      LogMsg(*LOGFILE, "Going to sleep ...") unless -r $EOF_FTP;
      while (! -r $EOF_FTP) { 
         # no ftp data yet .. stay in bed
         sleep $SLEEPTIME; 
      }
      # start processing
      $moment = strftime("%Y%m%d.%H%M", 0,localtime->min(),localtime->hour(),
                                        localtime->mday(),localtime->mon(),localtime->year(),
                                        0,0,0);
      LogMsg(*LOGFILE, "Woke up at $moment");
      LogMsg(*LOGFILE, "Received $SDF_FILE and is readable.") if -r $SDF_FILE;
      LogMsg(*LOGFILE, "Received $TDT_FILE and is readable.") if -r $TDT_FILE;
      
      # dirty hook for JNJ CHAROn DB CLOGP mechanism - tom@011120
      LogMsg(*LOGFILE, "Sending $SDF_FILE and $TDT_FILE to JNJ CHAROn DB CLOGP mechanism for TEST");
      qx { /usr/local/bin/scripts/sdf2jnj.pl -in $SDF_FILE -out /data/clogp/daylight/jnj/in/jnjrnum.sdf };
      qx { /usr/local/bin/scripts/tdt2jnj.pl -in $TDT_FILE -out /data/clogp/daylight/jnj/in/jnjrnum.tdt };
      qx { cp $EOF_FTP  /data/clogp/daylight/jnj/in/ftp_done.dat };

      # 2nd dirty hook for bmdcs1 CLOGP mechanism - tom@020225
      LogMsg(*LOGFILE, "Sending $SDF_FILE and $TDT_FILE to bmdcs1 CLOGP mechanism for TEST");
      qx { cp $SDF_FILE  /data_new/clogp/cheminfo/sdf/rnum.sdf};
      qx { cp $TDT_FILE  /data_new/clogp/cheminfo/sdf/rnum.tdt};
      qx { cp $EOF_FTP   /data_new/clogp/cheminfo/sdf/ftp_done.dat};

            
      # Check noof records transfered
      open(FILE, "<$EOF_FTP");
      @lines = <FILE>; 
      close(FILE);
      (undef, undef, undef, undef, $ftped, undef) = split(/\s+/, $lines[0], 6);
      LogMsg(*LOGFILE, "VAX says : Noof records ftp-ed : $ftped");
      $count = 0;
      open(FILE, "<$TDT_FILE");
      $count += tr/\|/\|/ while sysread(FILE, $_, 2 ** 16);
      close(FILE);
      LogMsg(*LOGFILE, "MDC says : TDT file contains $count records.");
      $count = 0;
      open(FILE, "<$SDF_FILE");
      $count += tr/\$/\$/ while sysread(FILE, $_, 2 ** 16);
      $count /= 4;
      close(FILE);
      LogMsg(*LOGFILE, "MDC says : SDF file contains $count records.");

      # process stuff
      $mol2smi_params = '-output_format TDT -write_2d FALSE -write_3d FALSE';
      $rc = ExecMol2Smi($mol2smi_params ,$SDF_FILE, $SMI_FILE, '/tmp/mol2smi.clogpd.log');
      if ($rc) {
         LogMsg(*LOGFILE, "Mol2Smi failed : $rc");
         LogMsg(*LOGFILE, "Dummy clogp.tab file created to send back .. continuing anyway");
         qx{ $WHICHMAIL -s 'Clogp mechanism failure : Mol2Smi failed' $MAIL_LIST </tmp/mol2smi.clogpd.log };
         open(CLOGP_EMPTY, "+>$CLOGP_FILE");
         close(CLOGP_EMPTY);
      } else {
         LogMsg(*LOGFILE, "Calculating ClogP values..");
         @clogps = ExecLogP('ClogP', '-i', $SMI_FILE, 0);  # no cmr values needed
         LogMsg(*LOGFILE, "Creating Clogp file ($CLOGP_FILE) to send back ..");
         open(CLOGP, "+>$CLOGP_FILE");
         open(SMI_CLOGP, "+>$CLOGP_SMI_FILE");
         foreach $chunk (@clogps) {
            next if $chunk =~ /\$SMIG/;
            next if $chunk =~ /^$/;
            chomp($chunk);
            print SMI_CLOGP $chunk, "\n|";
            $key = &FindItem($chunk,'COMP_ID');
            if ($key =~ /[0-9]{1,}([0-9]{$RNUM_LEN})/) {
               $key = $1;
            } else {
               $key = ('0' x ($RNUM_LEN - length($key))) . $key unless length($key) == $RNUM_LEN;
            }
            $cp = &FindItem($chunk,'CP');
            ($val, $err, $version) = split(/;/, $cp, 3);
            LogMsg(*LOGFILE, "\tR$key\t$val\t$err\t$version");
            if ($val > -10000 && $err ne $ERR_CLOGPNOTAVAIL) {
               printf CLOGP "%06d\t%05f\t%s\n", $key, $val, $err;
            } else {
               printf CLOGP "R%07d\n", $key;
            }
         }
         close(CLOGP);
         print SMI_CLOGP "\n";
         close(SMI_CLOGP);
      }

      LogMsg(*LOGFILE, "Archiving TDT, SDF & Clogp file to $ARCH_DIR.");
      ArchiveDataFiles($SDF_FILE, $TDT_FILE, $CLOGP_SMI_FILE, $moment);

      # at the end of this round all tmp- and datafiles are removed. To avoid locking (and waiting for un-lock)
      # we use the archived data files from now on ..
      # Use archived data files .. no need for 'avoid-to-remove-by-parent' locking
      # might be a lazy attitude or kinda simplistic .. but I like to keep things simple :-)

      LogMsg(*LOGFILE, "Uploading CHARON in background ..");
      ExecProgram($HOME_DIR, 
                  'UploadCharon.pl',
                  "-jrf -sdf $ARCH_SDF -tdt $ARCH_TDT"
                 );

      LogMsg(*LOGFILE, "Uploading INTRASITE databases in background ..");
      ExecProgram('/db/www/compound_db/tools',
                  'sdf2db',
                  $ARCH_SDF
                 );

      #LogMsg(*LOGFILE, "Uploading DAYLIGHT database in background ..");
      #ExecProgram($HOME_DIR,
      #            'UpdateThorDB.sh',
      #            "-d rnum -u $ARCH_SDF -c $ARCH_TDT -p $ARCH_SMI -M -B"
      #           );

      # end of this round
      LogMsg(*LOGFILE, "End of current Clogp cycle. .. I better start a new one, huh :-)");
      close(LOGFILE) || warn "Close log file $LOG failed : $!";
      qx { $WHICHMAIL -s 'Clogp mechanism logfile' $MAIL_LIST < $LOG_FILE } unless $NOMAIL;
      qx { rm -r $SMI_FILE $EOF_FTP $SDF_FILE $TDT_FILE '/tmp/mol2smi.clogpd.log' }; #unlink doesn't do rmdir :-(
      if ($TEST) {
         #Do this just once while we're testing .. don't be a real daemon
         $KeepGoing--;
      } else {
         open(LOGFILE, ">$LOG_FILE") || die "Clogpd.pl::main : Can't open log file $LOG_FILE : $!\n";
         LOGFILE->autoflush(1);
      }
   }
} else {
   print STDOUT "Clogp is not enabled or not available on this machine. Terminating.\n";
   syslog(LOG_INFO, "Clogp is not enabled or not available on this machine. Terminating.");
}
unlink $PID_FILE;
exit 1;
