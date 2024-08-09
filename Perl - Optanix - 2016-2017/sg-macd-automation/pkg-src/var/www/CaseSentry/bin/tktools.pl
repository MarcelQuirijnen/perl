#!/usr/bin/perl
# tktools.pl
#
# @version $Id: tktools.pl 2015-04-03 14:21:18Z $
# @copyright 1999,2015, ShoreGroup, Inc.

require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use lib '/usr/share/sg-macd-automation/lib/Perl';
use lib '/var/www/CaseSentry/lib/Perl';
use Getopt::Long qw{ :config no_ignore_case no_auto_abbrev };
use SG::Logger;

require TKUtils::Utils;

$main::DEBUG       = 1;
$main::DEBUG_LEVEL = 7;
$main::DEBUG_FILE  = '/var/log/tktools.log';

my $OPTS;
my $TOOLS_DEF;

# Load our plugins
use Module::Pluggable search_path => ['TKTools::Plugins',], require => 1, instantiate => 'new';

for my $module (plugins()) {
    $TOOLS_DEF->{$module->{name}} = $module;
}

# Load base tools here
require TKTools::FixCommit;
my $module = new TKTools::FixCommit;
$TOOLS_DEF->{$module->{name}} = $module;

require TKTools::FixDevices;
$module = new TKTools::FixDevices;
$TOOLS_DEF->{$module->{name}} = $module;

require TKTools::Grouper;
$module = new TKTools::Grouper;
$TOOLS_DEF->{$module->{name}} = $module;

my $TOOL = shift;

if (!defined $TOOL || $TOOL eq '--help' || $TOOL eq '-?' || $TOOL eq '--hidden') {
    $OPTS->{hidden} = 1 if (defined $TOOL && $TOOL eq '--hidden');
    &help();
    exit;
}

# Strip -- off incase someone adds it
$TOOL =~ s/^--//;

sub help {
    print "Usage: $0 <TOOL> <OPTIONS>\n";

    my $tools_list;

    foreach my $tool (sort keys $TOOLS_DEF) {
        next if ($TOOLS_DEF->{$tool}->{hidden} && !$OPTS->{hidden});
        $tools_list->{(defined $TOOLS_DEF->{$tool}->{type}) ? $TOOLS_DEF->{$tool}->{type} : 'Unknown'}->{$tool}
          = $TOOLS_DEF->{$tool}->{desc};
    }

    foreach my $type (sort keys $tools_list) {
        print "\n$type Tools:\n";
        foreach my $tool (sort keys $tools_list->{$type}) {
            printf('  %-20s - %s', $tool, $TOOLS_DEF->{$tool}->{desc});
            print "\n";
        }
    }

    print "\nTool Specific Options: $0 <TOOL> --help\n";
    #<<<  do not let perltidy touch this
    print "\nCommon Options:\n", sprintf('  -%-1s, --%-15s%s%s', '?', 'help', ' ' x 10, 'Display this help and exit.'), "\n",
    sprintf('  --%-19s%s%s', 'debug[=#]', ' ' x 10, 'Enables and sets debug to level specified'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'a', 'all',  ' ' x 10, 'Sets tool to all mode'),                      "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'h', 'hostname|host', ' ' x 10, 'Add single or multple devices by object_def names here.'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'H', 'hostname-file', ' ' x 10, 'Define a file to read hostnames from. (must be 1 hostname per line)'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'i', 'ip',      ' ' x 10, 'Add single or multple devices by ip_addr_ipvx here.'),  "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'I', 'ip-file', ' ' x 10, 'Define a file to read ip_addr_ipvx from. (must be 1 ip_addr_ipvx per line)'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'e', 'entity', ' ' x 10, 'Add single or multple entities.'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'E', 'entity-file', ' ' x 10, 'Define a file to read entities from.'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'd', 'dir',  ' ' x 10, 'Define single or multple directories here.'), "\n",
    sprintf('  -%-1s, --%-15s%s%s', 'f', 'file', ' ' x 10, 'Define single or multple files here.'),       "\n",
    ;
    #>>>
    exit();
}

GetOptions(
    'help|?'  => \$OPTS->{help},
    'debug=i' => \$OPTS->{debug},
    'all|a'   => \$OPTS->{all},
    'hidden'  => \$OPTS->{hidden},    # Shows hidden tools

    # Basic input types
    'dir|d=s{,}'           => \@{$OPTS->{dir}},
    'files|file|f=s{,}'    => \@{$OPTS->{files}},
    'hostname|host|h=s{,}' => \@{$OPTS->{devices}},
    'ip|i=s{,}'            => \@{$OPTS->{ip_addrs}},
    'entity|e=s{,}'        => \@{$OPTS->{entites}},
    'hostname-file|H=s'    => \$OPTS->{device_file},
    'ip-file|I=s'          => \$OPTS->{ip_file},
    'username|u=s'         => \$OPTS->{username},
    'password|p=s'         => \$OPTS->{password},

    # For change scripts
    'old|o=s' => \$OPTS->{old},
    'new|n=s' => \$OPTS->{new},
    'rotate'  => \$OPTS->{rotate},
    'config'  => \$OPTS->{config},
    'poll'    => \$OPTS->{poll},
    'ucs'     => \$OPTS->{ucs},
    'esx'     => \$OPTS->{esx},

    #Audit::Deviation.pm
    'test=s'       => \$OPTS->{test},
    'multiplier=s' => \$OPTS->{multiplier},
    'filter=s'     => \$OPTS->{filter},
);

if ($OPTS->{debug}) {
    $main::DEBUG_LEVEL = $OPTS->{debug};
}

@{$OPTS->{dir}}      = split(/,/, join(',', @{$OPTS->{dir}}));
@{$OPTS->{files}}    = split(/,/, join(',', @{$OPTS->{files}}));
@{$OPTS->{devices}}  = split(/,/, join(',', @{$OPTS->{devices}}));
@{$OPTS->{ip_addrs}} = split(/,/, join(',', @{$OPTS->{ip_addrs}}));
@{$OPTS->{entites}}  = split(/,/, join(',', @{$OPTS->{entites}}));

TKUtils::Utils::parse_files($OPTS->{device_file}, $OPTS->{devices})  if defined $OPTS->{device_file};
TKUtils::Utils::parse_files($OPTS->{ip_file},     $OPTS->{ip_addrs}) if defined $OPTS->{ip_file};

if (!$TOOL || (!$TOOL && $OPTS->{help})) {
    &help();
    exit;
}

unless (defined $TOOLS_DEF->{$TOOL}) {
    print "$TOOL is not a defined module\n";
    exit;
}

# Pass opts to tool
$TOOLS_DEF->{$TOOL}->run(\$OPTS);
