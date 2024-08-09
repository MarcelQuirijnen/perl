#!/usr/bin/perl
# tkdevices.pl
#
# @version $Id: tkdevices.pl 2015-04-03 14:21:18Z $
# @copyright 1999,2015, ShoreGroup, Inc.

require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use lib '/var/www/CaseSentry/lib/Perl';
use lib '/usr/share/sg-macd-automation/lib/Perl';
require TKUtils::Utils;
use Data::Dumper;
use Getopt::Long qw{ :config no_ignore_case no_auto_abbrev };
use TKDevices::Standards qw{ print_site_standards_results print_standards_help };
use SG::Logger;
use JSON;
use TKConfig qw{getConfigValue};
use Digest::MD5 qw(md5 md5_hex md5_base64);
use MIME::Base64;

use TKLowImpact::Manager::Helpers qw(send_opts);

# Our global vars
my $MODULES;
my @P_TYPES;
{
    use TKPoller;
    my $temp_poller = new TKPoller;
    $MODULES = ${$temp_poller->{MODULES}};
    @P_TYPES = $temp_poller->get_plugin_types();
}

my $OPTS;
$OPTS->{priority} = 3;

our $request;

# Print help if no arguments
&help() unless (@ARGV);

print "Running tkdevices with pid: $$\n";

# Enable logger
$main::DEBUG       = 1;
$main::DEBUG_LEVEL = 10;

$main::DEBUG_FILE = '/var/log/tkdevices.log';

GetOptions(

    'local' => \$OPTS->{local},

    # Modes
    'poll|p'         => \$OPTS->{poll},
    'single-poll|P'  => \$OPTS->{single_poll},
    'audit|A'        => \$OPTS->{audit},
    'make-changes|c' => \$OPTS->{make_changes},

    # Basic Options
    'help|?'               => \$OPTS->{help},
    'debug=i'              => \$OPTS->{debug},
    'all|a'                => \$OPTS->{all},
    'hostname|host|h=s{,}' => \@{$OPTS->{devices}},
    'ip|i=s{,}'            => \@{$OPTS->{ip_addrs}},
    'entity|e=s{,}'        => \@{$OPTS->{entity}},
    'entity-file|E=s'      => \$OPTS->{entity_file},
    'hostname-file|H=s'    => \$OPTS->{device_file},
    'ip-file|I=s'          => \$OPTS->{ip_file},

    # Graph options
    'graph|g'        => \$OPTS->{graph},
    'clean|C=s{,}'   => \@{$OPTS->{clean_cfgs}},
    'clean-file|D=s' => \$OPTS->{clean_file},

    # Poll Options
    'priority=i'    => \$OPTS->{priority},
    'module|m=s{,}' => \@{$OPTS->{modules}},
    'all-modules|M' => \$OPTS->{all_modules},

    # Poll module types
    'module-type|t=s{,}' => \@{$OPTS->{module_types}},
    'topology|topo'      => \$OPTS->{topology},
    'env'                => \$OPTS->{env},

    # Audit options
    'summary|device-summary' => \$OPTS->{device_summary},
    'site|site-audit'        => \$OPTS->{site_audit},
    'detailed'               => \$OPTS->{detailed},

    # MACD Options
    'overide|o'      => \$OPTS->{overide},
    'action=s'       => \$OPTS->{action},
    'status|s=s{,}'  => \@{$OPTS->{status}},
    'scope|S=s'      => \$OPTS->{scope},
    'add-sak=s'      => \$OPTS->{sak_file},
    'update-sku|sku' => \$OPTS->{usi},

    # Standards report
    'standards-report|audit-report=s' => \$OPTS->{generate_report},
    'email=s{,}'                      => \@{$OPTS->{emails}},

    # Misc
    'limit|l=s'                 => \$OPTS->{limit},
    'http-user=s'               => \$OPTS->{http_user},
    'http-password|http-pass=s' => \$OPTS->{http_pass},
    'rediscover'                => \$OPTS->{rediscover},
    'admin'                     => \$OPTS->{admin},
    'add-tests'                 => \$OPTS->{add_tests},

    # CCE Check
    'cce-check' => \$OPTS->{cce_check},
    'json'      => \$OPTS->{json},
);

&help() if ($OPTS->{help});

# Process and setup arguments
&process_args();

my $host            = getConfigValue('MANAGER', 'HOST');
my $tkm_enabled     = getConfigValue('MANAGER', 'ENABLED');
my $default_modules = getConfigValue('TKTOOLS', 'DEFAULT_MODULES');
$OPTS->{rediscover_module_types} = getConfigValue('TKTOOLS', 'REDISCOVER_MODULE_TYPES');

foreach my $module (split /,/, $default_modules) {
    my $existing = 0;
    foreach my $existing_module (@{$OPTS->{modules}}) {
        if (uc($existing_module) eq uc($module)) { $existing = 1; }
    }
    if (!$existing) {
        push @{$OPTS->{modules}}, $module;
    }
}

#print to_json($OPTS), "\n";
if ($OPTS->{local} || $OPTS->{detailed} || ($OPTS->{single_poll} || ($host eq '127.0.0.1' && $tkm_enabled eq '0'))) {
    &run_local();
}

# TODO: Enable sak file add via Manager
elsif ($OPTS->{sak_file}) {
    &run_local();
} else {
    send_opts(\$OPTS);
}

exit;

sub run_local() {
    print "Making new inventory\n";
    use TKInventory;
    $request = new TKInventory;
    $request->perform_actions($OPTS);
    &encode_devices($request) if $OPTS->{json};
}

sub process_args() {
    if ($OPTS->{debug}) {
        $main::DEBUG_LEVEL = $OPTS->{debug};
    }

    # If we want to single poll, enable polling
    if ($OPTS->{single_poll}) {
        $OPTS->{poll} = 1;
    }

    # Capitalize scope just incase
    if ($OPTS->{scope}) {
        $OPTS->{scope} = uc($OPTS->{scope});
    }

    if ($OPTS->{graph}) {
        $OPTS->{poll} = 1;
        push @{$OPTS->{module_types}}, 'GRAPH';
    }

    @{$OPTS->{emails}} = split(/,/, join(',', @{$OPTS->{emails}}));
    @{$OPTS->{modules}}      = split(/,/, uc(join(',', @{$OPTS->{modules}})));
    @{$OPTS->{module_types}} = split(/,/, uc(join(',', @{$OPTS->{module_types}})));
    @{$OPTS->{devices}}  = split(/,/, join(',', @{$OPTS->{devices}}));
    @{$OPTS->{ip_addrs}} = split(/,/, join(',', @{$OPTS->{ip_addrs}}));
    @{$OPTS->{entity}}   = split(/,/, join(',', @{$OPTS->{entity}}));
    @{$OPTS->{status}} = split(/,/, uc(join(',', @{$OPTS->{status}})));
    @{$OPTS->{clean_cfgs}} = split(/,/, join(',', @{$OPTS->{clean_cfgs}}));

    TKUtils::Utils::parse_files($OPTS->{device_file}, $OPTS->{devices})    if $OPTS->{device_file};
    TKUtils::Utils::parse_files($OPTS->{ip_file},     $OPTS->{ip_addrs})   if $OPTS->{ip_file};
    TKUtils::Utils::parse_files($OPTS->{entity_file}, $OPTS->{entity})     if $OPTS->{entity_file};
    TKUtils::Utils::parse_files($OPTS->{clean_file},  $OPTS->{clean_cfgs}) if $OPTS->{clean_file};
}

sub help() {
    #<<<  do not let perltidy touch this
    print "Usage: $0 <MODE> <OPTIONS>\n",
    sprintf('  --%-19s%s%s', 'local', ' ' x 10, 'Runs script locally and not over ZMQ'), "\n",

    "\nSingle Modes:\n",
    sprintf('  -%-1s, --%-15s%s%s', 'p', 'poll', ' ' x 10, 'Poll the device for the enabled modules, uses ZMQ poller (tkpollerd)'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'P', 'single-poll', ' ' x 10, 'Poll the device for the enabled modules, polls without tkpollerd (localhost)'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'A', 'audit', ' ' x 10, 'Run standards audit against devices, combine with poll for best results. Results placed in `automation`.`standards_results`.'), "\n",
    sprintf('  --%-19s%s%s', 'graph', ' ' x 10, 'Enable the reading and writing of CFGs (note will not write unless -c is used)'), "\n",

    "\nCombined MACD Modes:\n",
    sprintf('  --%-19s%s%s', 'rediscover', ' ' x 10, 'Polls devices and performs MACD SCOPE: DEFAULT on provided devices.'), "\n",
    sprintf('  --%-19s%s%s', 'add-tests', ' ' x 10, 'Adds tests provided with -e or file -E regardless of status. Must be NAME:METHOD:INSTANCE and in automation.standards_results.'), "\n",
    sprintf('  --%-19s%s%s', 'add-sak=[file]', ' ' x 10, 'Performs SCOPE: ADD_DEVICE on provided sak. Accepts .xlsx and .xls files.'), "\n",
    sprintf('  --%-19s%s%s', 'cce-check', ' ' x 10, 'Polls for CCE targets and performs various checks use with --http-user --http-pass'), "\n",
    ;

    print "\nAudit Options:\n",
    sprintf('  --%-19s%s%s', 'site-audit', ' ' x 10, 'Displays a summary of audit results for entire site.'), "\n",
    sprintf('  --%-19s%s%s', 'summary', ' ' x 10, 'Displays a summary of audit results for specified devices.'), "\n",
    sprintf('  --%-19s%s%s', 'detailed', ' ' x 10, 'Print a detailed list of audit results printing individual tests.'), "\n",
    sprintf('  --%-19s%s%s', 'audit-report=[file]', ' ' x 10, 'Generates xls file of audit results. Combine with --email=[address] to email file after generation.'), "\n",
    ;

    print sprintf('  -%-1s, --%-15s%s%s', 'c', 'make-changes', ' ' x 10, 'Perform MACD changes. Use with --overide, --status, or --scope.'), "\n" if($OPTS->{admin});
    print
    "\nBasic Options:\n",
    sprintf('  -%-1s, --%-15s%s%s', '?', 'help', ' ' x 10, 'Display this help and exit.'), "\n",
    sprintf('  --%-19s%s%s', 'debug[=#]', ' ' x 10, 'Enables and sets debug to level specified'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'a', 'all',  ' ' x 10, 'Adds all devices from object_def'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'h', 'hostname|host', ' ' x 10, 'Add single or multple devices by object_def names here.'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'H', 'hostname-file', ' ' x 10, 'Define a file to read hostnames from. (must be 1 hostname per line)'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'i', 'ip',      ' ' x 10, 'Add single or multple devices by ip_addr_ipvx here.'),  "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'I', 'ip-file', ' ' x 10, 'Define a file to read ip_addr_ipvx from. (must be 1 ip_addr_ipvx per line)'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'e', 'entity', ' ' x 10, 'Add single or multple entities.'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'E', 'entity-file', ' ' x 10, 'Define a file to read entities from.'), "\n",
    ;

    print    "\nPoll Options:\n",
    sprintf('  --%-19s%s%s', 'priority=[1-5]', ' ' x 10, 'Sets the ZMQ queue priority 1-5'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'm', 'module', ' ' x 10, 'Define single or multple modules to poll here.'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'M', 'all-modules', ' ' x 10, 'Enables all polling modules.'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 't', 'module-type', ' ' x 10, 'Enables polling plugins for defined types.'), "\n",
    sprintf('  --%-19s%s%s', 'topology|topo', ' ' x 10, 'Enables Topology type plugins'), "\n",
    sprintf('  --%-19s%s%s', 'env', ' ' x 10, 'Enables Environmental type plugins.'), "\n",
    sprintf('  --%-19s%s%s', 'graph', ' ' x 10, 'Enables Graph type plugins.'), "\n",
    "\nPolling Modules:\n  ", join(', ', keys($MODULES)), "\n",
    "\nPolling Module Types:\n ",  join(', ', @P_TYPES), "\n",
    ;

    &admin_help() if($OPTS->{admin});

    print "\nExample Commands:\n",
      "  Poll Interfaces:\n",
      "     tkdevices --poll -m IF -i <ip_addr> <ip_addr>\n",
      "  Poll and Audit Device:\n",
      "     tkdevices --poll --audit -i <ip_addr> <ip_addr>\n",
      "  Rediscover devices (Adds tests):\n",
      "     tkdevices --rediscover -i <ip_addr> <ip_addr>\n",
      "  Audit whole site (No polling):\n",
      "     tkdevices --all --audit\n",
      "  Audit whole site (With polling):\n",
      "     tkdevices --all --audit --poll\n",
      "  Add new devices:\n",
      "     tkdevices --add-sak=/path/to/file.xlsx\n",
      "  Generate audit excel report:\n",
      "     tkdevices --audit-report=/path/to/file.xls\n",
      "  Generate audit excel report and Email it:\n",
      "     tkdevices --audit-report=/path/to/file.xls --email person\@cisco.com person2\@shoregroup.com\n",
      ;
    #>>>
    exit(0);
}

sub admin_help() {
    #<<<  do not let perltidy touch this
    print "\nMACD Options:\n",
    sprintf('  -%-1s, --%-15s%s%s', 'o', 'overide', ' ' x 10, 'Everide default MACD actions with defined --action. Must declare --entity to perform actions on.'), "\n",
    sprintf('  --%-19s%s%s', 'action', ' ' x 10, 'What action you want to perform on --entites.'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 's', 'status', ' ' x 10, 'Perform default actions just on specified audit status. (i.e. NON_MONITORED_STANDARD)'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'S', 'scope', ' ' x 10, 'Perform specified SCOPE on provided devices and or test'), "\n",
    sprintf('  --%-19s%s%s', 'update-sku|sku', ' ' x 10, 'Updates sku ids using polled model number comparison.'), "\n",
    ;
    #>>>
    require TKDevices::MACD;
    TKDevices::MACD::print_macd_help();
    TKDevices::Standards::print_standards_help();
}

sub encode_devices {
    use JSON;
    my $tkinv = shift;
    my @devices;
    foreach my $ip (keys ${$tkinv->{DEVICES}}) {

        my $d = {name => ${$tkinv->{DEVICES}}->{$ip}->{object_def}->{name}, ip_addr_ipvx => $ip,};

        if (defined ${$tkinv->{DEVICES}}->{$ip}->{locations}) {
            $d->{location} = ${$tkinv->{DEVICES}}->{$ip}->{locations};
        }

        if (defined ${$tkinv->{DEVICES}}->{$ip}->{object_def}->{location}
            && ${$tkinv->{DEVICES}}->{$ip}->{object_def}->{location})
        {
            $d->{location}->{full_location} = ${$tkinv->{DEVICES}}->{$ip}->{object_def}->{location};
        }

        # Gather polled tests
        if (defined ${$tkinv->{DEVICES}}->{$ip}->{POLLED_TESTS}) {
            foreach my $method (keys ${$tkinv->{DEVICES}}->{$ip}->{POLLED_TESTS}) {

                # Interfaces
                if ($method eq 'IF') {
                    foreach my $terse (keys ${$tkinv->{DEVICES}}->{$ip}->{POLLED_TESTS}->{IF}) {
                        push @{$d->{interfaces}}, ${$tkinv->{DEVICES}}->{$ip}->{POLLED_TESTS}->{IF}->{$terse};
                    }
                } else {
                    foreach my $test (keys ${$tkinv->{DEVICES}}->{$ip}->{POLLED_TESTS}->{$method}) {
                        push @{$d->{snmp_targets}}, ${$tkinv->{DEVICES}}->{$ip}->{POLLED_TESTS}->{$method}->{$test};
                    }
                }
            }
        }

        push @devices, $d;
    }
    print "\n", to_json(\@devices), "\n";
}
