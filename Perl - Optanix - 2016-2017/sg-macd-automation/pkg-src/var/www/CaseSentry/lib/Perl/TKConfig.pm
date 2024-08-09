# TKConfig.pm
#
# @version $Id: Standards.pm 2015-04-03 14:21:18Z $
# @copyright 1999,2015, ShoreGroup, Inc.
package TKConfig;
require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use lib '/usr/share/sg-macd-automation/lib/Perl';
use lib '/var/www/CaseSentry/lib/Perl';
use SG::Logger;
use Data::Dumper;

#use Config::IniFiles;
use ConnectVars;

my $dbhAutomation = getConnection('Main') or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
our @ISA       = qw(Exporter);
our @EXPORT    = qw{getConfigValue getConfigParms sort_by_poll_time };
our @EXPORT_OK = qw{$TK_CONFIG getConfigValue getConfigParms updateParm refreshConfig sort_by_poll_time};

our $TK_CONFIG = &getConfigs();

unless (defined $TK_CONFIG) {
    warn "Can't Load configs!";
    exit(1);
}

sub getConfigs {

    my $new_conf;
    my $sql = q{select * from `Automation`.`macd_automation_config`};

    my $query = $dbhAutomation->prepare($sql);
    $query->execute();

    while (my $hash = $query->fetchrow_hashref()) {
        unless (defined $new_conf->{$hash->{parm_group}}->{$hash->{parm}}) {
            $new_conf->{$hash->{parm_group}}->{$hash->{parm}} = $hash->{value};
        } elsif (ref $new_conf->{$hash->{parm_group}}->{$hash->{parm}} eq 'Array') {
            push @{$new_conf->{$hash->{parm_group}}->{$hash->{parm}}}, $hash->{value};
        } else {
            my $tmp = $new_conf->{$hash->{parm_group}}->{$hash->{parm}};
            $new_conf->{$hash->{parm_group}}->{$hash->{parm}} = [$tmp, $hash->{value}];
        }
    }

    return $new_conf;
}

sub getConfigValue {
    my $parm_group = shift;
    my $parm       = shift;
    return $TK_CONFIG->{$parm_group}->{$parm} || 0;
}

sub getConfigParms {
    my $parm_group = shift;
    return $TK_CONFIG->{$parm_group} || 0;
}

sub updateParm {
    my $parm_group = shift;
    my $parm       = shift;
    my $value      = shift;
    my $sql = qq{UPDATE `Automation`.`macd_automation_config` SET `value`= ? WHERE `parm_group` = ? and `parm` = ?};
    my $statement = $dbhAutomation->prepare($sql)
      or SG::Logger->err("[$$][updateParm] Cannot prepare $sql: " . $dbhAutomation->errstr);
    $statement->execute($value, $parm_group, $parm)
      or SG::Logger->err("[$$][updateParm] Cannot update $parm_group $parm to $value : " . $dbhAutomation->errstr);
}

sub refreshConfig {
    $TK_CONFIG = getConfigs();
}

sub sort_by_poll_time {
    my $devices = shift;
    no warnings 'uninitialized';
    return sort { ${$devices}->{$b}->{INFO}->{POLL_TIME} <=> ${$devices}->{$a}->{INFO}->{POLL_TIME} } keys ${$devices};
}

1;
