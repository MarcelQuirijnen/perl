#!/usr/bin/perl -w
  
use constant PIDFILE  => '/var/run/httpd.pid';
$MAIL                 =  '/bin/mail';
$WEBMASTER            =  'mjquiri';
  
open (PID,PIDFILE) || die PIDFILE,": $!\n";
$pid = <PID>;
close PID;
kill 0,$pid || qx { $MAIL -s "Web server is down" $WEBMASTER </dev/null };
