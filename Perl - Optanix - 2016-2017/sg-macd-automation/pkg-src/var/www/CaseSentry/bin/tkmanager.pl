#!/usr/bin/perl
# tkmanager.pl
#
# @version $Id: tkmanager.pl 2015-04-03 14:21:18Z $
# @copyright 1999,2015, ShoreGroup, Inc.
require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use feature "switch";
use lib '/var/www/CaseSentry/lib/Perl';
use lib '/usr/share/sg-macd-automation/lib/Perl';
use TKLowImpact::Manager;
use Getopt::Long qw{ :config no_ignore_case no_auto_abbrev };
use TKConfig qw{ getConfigParms updateParm getConfigValue };

# Add process lock
my @pids = `pgrep tkmanager | grep -v $$`;
if (@pids) {
    print "Found " . scalar(@pids) . " copies of tkmanager running\n";
    exit(1);
}

# Enable debug
$main::DEBUG = 1;
my $debug      = $main::DEBUG_LEVEL = 7;
my $debug_file = $main::DEBUG_FILE  = '/var/log/tkmanager.log';
my $setEnabled = 0;
my $setDisabled = 0;

GetOptions('debug=s' => \$debug, 'debug-file' => \$debug_file, 'enable' => \$setEnabled, 'disable' => \$setDisabled,);

if ($setEnabled) {
    print "Enabled\n";
    updateParm('MANAGER', 'ENABLED', '1');
    exit;
}
if ($setDisabled) {
    updateParm('MANAGER', 'ENABLED', '0');
    print "Disabled\n";
    exit;
}

my $enabled = getConfigValue('MANAGER', 'ENABLED');
unless ($enabled) {
    warn "MANAGER is not enabled in tkconfig\n";
    exit(0);
}

$main::DEBUG_LEVEL = $debug      if $debug != $main::DEBUG_LEVEL;
$main::DEBUG_FILE  = $debug_file if $debug_file;

open(STDOUT, '+>>/var/log/tkmanager.stdout');
open(STDERR, '+>>/var/log/tkmanager.stderr');

###########################
# Run
my $manager = new TKLowImpact::Manager;
$manager->main();
