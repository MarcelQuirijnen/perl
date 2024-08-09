#!/usr/local/bin/perl
#####################################################################################
# @(#)FILE      : PropServer"                                                       #
# @(#)TYPE FILE : Executable perl5 script"                                          #
# @(#)EXECUTED  : At system reboot, by /etc/init/rc routine"                        #
# @(#)ENVRONMENT: Daylight + Molconn-Z                                              #
# @(#)PARAMS    : None                                                              #
# @(#)AUTHOR    : M. Quirijnen                                     DATE: 05/01/00"  #
# @(#)USAGE     : Takes a snapshot of CHAROn into Shmem"                            #
#                 Routine ends either with error code or Termination signal         #
#                 The routine sends an email to $MAIL_LIST to notify its ready for  #
#                 usage (or it has failed)                                          #
#                 Calls to this routine are done through RPC calls                  #
#####################################################################################
require 5.0004;
use strict;

use Carp;
use Socket;
use IO::Socket();
use Fcntl ':flock';
use DBI;
use POSIX qw(strftime setsid getpid waitpid);
use Unix::Syslog qw(:macros :subs);
use RPC::pServer;
use IPC::Shareable;
use DayPerl;
#use Data::Dumper;
use lib "/usr/local/bin/scripts/automation";
use Modules::TMCDefs;
use Modules::TMCOracle;


my $MDC_APPLICATION = "CHAROn Rapid Property Selection Server";
my $MDC_VERSION = 1.0;
my $MAIL_LIST = 'mquirij1@janbe.jnj.com';
# also used in /data/clogp/UploadCharon.pl
my $PID_FILE = '/tmp/propServer.pid';

# dont init this datastruct here
my %CharonData;

##################################################
# authorise certain users..all for now
# all = those specified in /etc/propServer.conf
##################################################
sub IsAuthorizedUser($$$)
{
   my($con, $user, $passwd) = @_;
   #print Dumper($con);
   return ($user eq $con->{'authorizedClients'}[1]->{'AuthUser'} && 
           $passwd eq $con->{'authorizedClients'}[1]->{'AuthPwd'}) ? 1 : 0;
}

##################################################
# Use : Handle 'kill -TERM' signals              #
# Params : None                                  #
##################################################
sub TermHandler
{
   syslog(LOG_INFO, "CHAROn propServer terminated by TERM signal.");
   if (@childpids) {
      #$len = @childpids;
      kill('TERM', @childpids);
   }
   IPC::Shareable->clean_up;
   qx { rm -f $PID_FILE };
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
   # doesnt work with perl -T

   IPC::Shareable->clean_up;
   qx { rm -f $PID_FILE };
   open(SOURCE, $0);
   <SOURCE> =~ /^#!(\S+)/;
   my $ipath = $1;
   close(SOURCE);
   syslog(LOG_INFO, "Got restart signal.");
   exec($ipath, $0, @ARGV);
   die "Failed to restart $0 using $ipath";
}

################################
# client syas : I'm done
################################
sub quit ($$) {
   my($con, $data) = @_;
   my ($runRef) = $data->{'running'};
   $$runRef = 0;
   (1, "Bye!");
}

################################
# get fingerprints from shared mem
################################
sub fingerprint($$$) 
{
   my($con, $ref, $args) = @_;
   my $m;
   my %fps = ();
   foreach $m (@$args) {
      $fps{$m} = $CharonData{$m};
   }
   %fps;
}

################################
# update shmem area when CHAROn has been updated by CLOGP mechanism
################################
sub update($$$)
{
   my ($con, $data, $hashref) = @_;
   my $key;
   foreach $key (keys %$hashref) {
      $CharonData{$key} = $hashref->{$key};
   }
   $con->Log('notice', "propServer Data updated.\n"); 
   (1, "Ok");
}

################################
# This function is called for any valid connection to a client
# In a loop it processes the clients requests.
#
################################
sub Server ($@) {
   my($con) = shift;
   my($configFile, %funcTable);
   my $running = 1;

   # First, create the servers function table. Note the
   # references to the handle hash in entries that access
   # the handle functions.
   my($funcTable) = {
            'quit'    => { 'code' => \&quit,
                           'running' => \$running, },
            'FP'      => { 'code' => \&fingerprint },
            'UPDATE'  => { 'code' => \&update },
   };

   $con->{'funcTable'} = $funcTable;
   while($running) {
      if ($con->{'sock'}->eof()  ||  $con->{'sock'}->error) {
         $con->Log('err', "Exiting.\n");
         exit 10;
      }
      $con->Loop();
   }
   $con->Log('notice', "RPC call done. Client quits.\n");
   exit 0;
}

################################
# setup data struct
################################
sub Initialise
{
   require Modules::TMCOracle;
   my $rc = 0;
   my ($dbh, $sth);
   my @row;
   my ($dayObj, $fpObj);
   #
   # create shared mem segment
   #
   syslog(LOG_INFO, "propServer : Initialising shared memory...\n");

   open(PIDFILE, "<$PID_FILE");
   flock(PIDFILE, LOCK_EX|LOCK_NB);
 
   my $shmem = tie (%CharonData, 'IPC::Shareable', "CHAROn",
                                 { 'create'  => 'yes', 
                                   'destroy' => 'yes',
                                   'size'    => 2000*725,     
                                   'mode'    => 0666,
                                 }
                   ) or return 1;
   $shmem->shlock;
   %CharonData = ();
   syslog(LOG_INFO, "propServer : Shared memory initialisation done\n");
   syslog(LOG_INFO, "propServer : Retrieving CHAROn data ... will take a while.\n");

   #
   # get the Oracle stuff
   #
   $dbh = DBI->connect($Modules::TMCOracle::ORA_SID, $Modules::TMCOracle::ORA_RW_USER, $Modules::TMCOracle::ORA_RW_PWD, 'Oracle');
   if ($DBI::err) {
      syslog(LOG_ERR, "Unable to connect to $Modules::TMCOracle::ORA_SID. Terminated.\n");
      syslog(LOG_ERR, "$DBI::errstr\n");
      $shmem->shunlock;
      IPC::Shareable->clean_up;
      die;
   }
   $sth = $dbh->prepare("SELECT comp_nr, comp_type, fp, smiles FROM TMC.TB_SMILES");
   if ($dbh->err) {
      syslog(LOG_ERR, "Error preparing CHAROn data retrieval : $DBI::err\n$DBI::errstr\n");
      syslog(LOG_ERR, "Abandoned due to error.\n");
      qx { echo "Check SYSLOG" | /usr/sbin/Mail -s 'propServer Error : no data retrieved' $MAIL_LIST };
      $rc = 1;
   } else {
      $sth->execute;
      while (@row = $sth->fetchrow_array) {
         # make daylight molecule object
         $dayObj = dt_smilin($row[3]);
         # make fingerprint object from this mol object
         $fpObj = dt_fp_generatefp($dayObj, 0, 7, $CLUSTERSIZE); 
         $CharonData{$row[1] . $row[0]} = $fpObj;
         dt_dealloc($dayObj);
      }
      if ($dbh->err) {
         syslog(LOG_WARNING, "Oracle retrieval done with errors : $DBI::err\n$DBI::errstr\n");
         qx { echo "Check SYSLOG" | /usr/sbin/Mail -s 'propServer Error : Oracle retrieval errors' $MAIL_LIST };
      } else {
         syslog(LOG_INFO, "Oracle retrieval done.");
         qx { echo "Check SYSLOG" | /usr/sbin/Mail -s 'propServer : ready for usage' $MAIL_LIST };
      }
   }
   $dbh->disconnect();
   $shmem->shunlock;
   
   # release lock on pidfile .. users know now its available for them
   flock(PIDFILE, LOCK_UN);
   close(PIDFILE); 

   return $rc;
}

##################################################
# Use : Cleanup dead processes                   #
#       Avoid Zombie ball ...                    #
# Params : None                                  #
##################################################
sub Reaper
{
   #my $pid = wait; 
   #$SIG{CHLD} = \&Reaper;

   my($pid);
   do {
      $pid = waitpid(-1, &POSIX::WNOHANG);
      @childpids = grep { $_ != $pid } @childpids;
   } while($pid > 0);
}

################################
# Now for main
################################
my ($sock, $cl);
my @childpids = ();
my $con;

$rc = &CheckConfig('propserver');
unless ($rc) {
   croak "Oops .. CHAROn propServer is already running. Bye.\n" if -r $PID_FILE;
   print "Starting MDC propServer\n";
   # Split from the controlling terminal, be a daemon :-)
   if (fork()) { exit; }
   setsid();

   # write out the PID file
   # keep a lock on it while the system is not ready for usage yet.
   open(PIDFILE, "> $PID_FILE");
   printf PIDFILE "%d\n", getpid();
   close(PIDFILE);

   $sock = IO::Socket::INET->new('Proto' => 'tcp',
                                 'Listen' => SOMAXCONN,
                                 'LocalPort' => 9002,
                                 'LocalAddr' => 'localhost',
                                );

   $SIG{'HUP'} = "RestartProcess";
   $SIG{'TERM'} = "TermHandler";
   $SIG{'CHLD'} = "Reaper";

   unless (&Initialise) {
      while (1) {
         # Wait for a client establishing a connection
         $con = new RPC::pServer('sock' => $sock, 
                                 'configFile' => '/etc/propServer.conf',
                                 #'debug' => 1,
                                 #'stderr' => 1,
                                );
         if (!ref($con)) {
            syslog(LOG_ERR, "Cannot create RPC Server.\n");
         } else {
             $con->Log('notice', "connecting to $con->{'application'}\n");
             if ($con->{'application'} ne $MDC_APPLICATION) {
                # Whatever this client wants to connect to:
                # It's not us :-)
                $con->Deny("This is a $MDC_APPLICATION server. Go away");
             } elsif ($con->{'version'} > $MDC_VERSION) {
                # We are running an old version of the protocol :-(
                $con->Deny("Sorry, but this is version $MDC_VERSION");
             } elsif (!IsAuthorizedUser($con, $con->{'user'}, $con->{'password'})) {
                # somethings wrong in this area ..think Berkley sockets software on SGI isnt what its supposed to be :-(
                $con->Deny("Access denied");
             } else {
                # Ok, we accept the client. Spawn a child and let
                # the child do anything else.
                my $pid = fork();
                if (!defined($pid)) {
                     $con->Deny("Cannot fork: $!");
                } elsif ($pid == 0) {
                   # I am the child
                   $con->Accept("Welcome to the ultimate pleasure dome of CHAROn...");
                   Server($con);
                } else {
                   push(@childpids, $pid);
                }
             }
         }
      }                       
   } else {
      print STDERR "Cannot initialise shared memory segment with CHAROn data: terminated.\n";
      unlink $PID_FILE;
      exit 1;
   }
} else {
   print STDERR "CHAROn Rapid Property Selection Server can not run on this machine .. not enabled.\n";
   exit 1;
}
exit 0;
