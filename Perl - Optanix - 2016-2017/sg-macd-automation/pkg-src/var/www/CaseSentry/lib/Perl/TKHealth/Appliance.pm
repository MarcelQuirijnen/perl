#Module for specific Appliance checks, no database connection required


package TKHealth::Appliance;
require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use lib '/usr/share/sg-macd-automation/lib/Perl';
use lib '/var/www/CaseSentry/lib/Perl';
use ConnectVars;
use SG::Logger;
use DateTime;
use IPC::Open3;
use TKUtils::RemoteCommand;

sub diagHealth {
    my $CONN    = shift;
    my $command = "/var/www/CaseSentry/bin/health_checks.pl";
    run_command($CONN, $command);
    my @lines;
    foreach (@{${$CONN}->{RESPONSE}}) {

        #skip lines if empty or contains healthcheck results
        next if (/^$/);
        next if (/healthcheck results/i);
        if ($_ =~ m/FAIL/) { $_ =~ s/:.*//; chomp($_); push(@lines, $_); }
    }

    if (@lines && scalar(@lines) > 0) {
        my $line = join(", ", @lines);
        return ({RESULT => "FAIL", ERROR => $line});
    } else {
        return ({RESULT => "PASS", ERROR => undef});
    }
}

sub ghostHealth {
    my $CONN    = shift;
    my $command = "dpkg -l | grep libc-bin";
    run_command($CONN, $command);
    my @lines;
    foreach (@{${$CONN}->{RESPONSE}}) {
        next if (/^$/);
        if (m/(2\.15-0ubuntu10\.10)/i) { push(@lines, $1); }
    }

    if (@lines && scalar(@lines) > 0) {
        return ({RESULT => "PASS", ERROR => undef});
    } else {
        return ({RESULT => "FAIL", ERROR => "Correct version not found"});
    }
}

sub poodleHealth {
    my $CONN    = shift;
    my $command = "grep SSLv /etc/apache2/mods-enabled/ssl.conf";
    run_command($CONN, $command);
    my @lines;
    foreach (@{${$CONN}->{RESPONSE}}) {
        next if (/^$/);
        if ($_ =~ m/sslv3/i) { push(@lines, $_); }
    }

    if (@lines && scalar(@lines) > 0) {
        return ({RESULT => "PASS", ERROR => undef});
    } else {
        return ({RESULT => "FAIL", ERROR => "Correct version not found"});
    }
}

sub leapHealth {
    my $CONN    = shift;
    my $command = "dpkg -l | grep tzdata";
    run_command($CONN, $command);
    my @lines;
    foreach (@{${$CONN}->{RESPONSE}}) {
        next if (/^$/);
        if ($_ =~ s/.*(2015a[\w\d\-\.]+)\s.*/$1/i) { push(@lines, $_); }
    }

    if (@lines && scalar(@lines) > 0) {
        return ({RESULT => "PASS", ERROR => undef});
    } else {
        return ({RESULT => "FAIL", ERROR => "Correct version not found"});
    }
}

sub mailHealth {
    my $CONN    = shift;
    my $command = "tail -n 500 /var/log/mail.log | grep status";
    run_command($CONN, $command);
    my @lines;

    my $failing;
    foreach (@{${$CONN}->{RESPONSE}}) {
        next if (/^$/);
        if ($_ =~ m/status/) { $_ =~ s/(.*)status=//; chomp($_); push(@lines, $_); }
    }

    if (@lines && scalar(@lines) > 0) {
        return ({RESULT => "PASS", ERROR => undef});
    } else {
        return ({RESULT => "FAIL", ERROR => "Nothing with \"status=\" found in the mail log"});
    }
}

sub cronHealth {

    my @crons = shift;
    my @lines;
    my $cronList;
    foreach (@crons) {
        my $cron    = $_;
        my $command = "ls -l /etc/cron.d/ | grep -i $cron";
        my $pid     = open3('<&CHILD_STDIN', my $stout, '>&STDERR', $command,);

        while (<$stout>) {
            next if (/^$/);
            $_ =~ s/.*\s(.*_$cron)$/$1/;
            chomp($_);
            push @lines, $_;
        }

        waitpid($pid, 0);
        close($stout);
    }
    if (@lines && scalar(@lines) > 0) {
        print colored(['green on_black'], "Found the following crons: " . join(", ", @lines)) . "\n\n";
        my $cron;
        foreach (@lines) {
            $cron = $_;
            my $command = "cat /etc/cron.d/$_";
            my $pid = open3('<&CHILD_STDIN', my $stout, '>&STDERR', $command,);

            while (<$stout>) {
                next if (/^$/);
                if   ($_ =~ m/^#.*/) { $cronList->{$cron}->{commented} = 1; }
                else                 { $cronList->{$cron}->{commented} = 0; }
            }

            waitpid($pid, 0);
            close($stout);
        }

        foreach my $key (keys $cronList) {
            if ($cronList->{$key}->{commented}) {
                print colored(['bright_red on_black'], $key . " - COMMENTED") . "\n";
            } else {
                print colored(['green on_black'], $key . " - UNCOMMENTED") . "\n";
            }
        }
    }
}
