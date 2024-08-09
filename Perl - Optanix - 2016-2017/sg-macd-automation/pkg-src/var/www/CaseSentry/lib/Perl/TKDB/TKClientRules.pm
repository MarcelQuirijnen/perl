# TKClientRules.pm
#
# @version $Id: TKClientRules.pm 2015-04-03 14:21:18Z $
# @copyright 1999,2015, ShoreGroup, Inc.

package TKDB::TKClientRules;
require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use lib '/usr/share/sg-macd-automation/lib/Perl';
use lib '/var/www/CaseSentry/lib/Perl';
use SG::Logger;
use JSON;
use Data::Dumper;
use TKDB::Automation qw{ :get };

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT
  = qw( get_all_rule_groups get_rule_group get_rule_group_by_name get_all_actions get_rule_actions get_rule_actions_by_name );

my $dbh = get_automation_db_handle();

my $RULE_GROUPS;
my $RULE_ACTIONS;

&init();

sub init {

    my $sql = q{select * from `Automation`.`view_rules`};

    my $query = $dbh->prepare($sql);
    $query->execute();

    while (my $hash = $query->fetchrow_hashref()) {

        # Make initial group hash
        unless (defined $RULE_GROUPS->{$hash->{group_id}}) {
            $RULE_GROUPS->{$hash->{group_id}}
              = {enabled => $hash->{enabled}, name => $hash->{group_name}, id => $hash->{group_id},};
        }

        # Make initial rules hash
        unless (defined $RULE_GROUPS->{$hash->{group_id}}->{rules}->{$hash->{rule_id}}) {
            $RULE_GROUPS->{$hash->{group_id}}->{rules}->{$hash->{rule_id}} = {
                id                   => $hash->{rule_id},
                name                 => $hash->{rule_name},
                match_on             => $hash->{rule_match_on},
                stop_processing_more => $hash->{stop_processing_more},
            };
        }

        # Add filter
        unless (
            defined $RULE_GROUPS->{$hash->{group_id}}->{rules}->{$hash->{rule_id}}->{components}
            ->{$hash->{component_id}})
        {
            $RULE_GROUPS->{$hash->{group_id}}->{rules}->{$hash->{rule_id}}->{components}->{$hash->{component_id}} = {
                id         => $hash->{component_id},
                name       => $hash->{component_name},
                match_on   => $hash->{component_match_on},
                dont_match => $hash->{dont_match},
            };
        }

        # Add values
        $RULE_GROUPS->{$hash->{group_id}}->{rules}->{$hash->{rule_id}}->{components}->{$hash->{component_id}}->{tests}
          ->{$hash->{test_id}}
          = {type => $hash->{type}, lvalue => $hash->{lvalue}, opperand => uc($hash->{opperand}),
            rvalue => $hash->{rvalue},};
    }

    $sql = q{
        SELECT vra.*, IFNULL(sti.norm_val,spd.normalValues) as norm_val, IFNULL(sti.crit_val,spd.criticalValues) as crit_val,
            IFNULL(sti.oid,spd.oid) as oid, IFNULL(IFNULL(st.description, sti.description),spd.description) as test_descr,
            sti.depend as test_depend, sti.icon as test_icon
        FROM `Automation`.`view_rule_actions` vra
        LEFT JOIN `Automation`.`snmp_test_info` sti ON vra.instance=sti.name AND vra.instance != '*'
        LEFT JOIN `CaseSentry`.`snmpPluginDef` spd ON vra.instance=spd.name AND vra.instance != '*'
        LEFT JOIN `CaseSentry`.`standards_targets` st ON vra.method=st.method AND vra.instance=st.method AND vra.instance != '*' AND vra.method != '*'
        ORDER BY 1
    };

    $query = $dbh->prepare($sql);
    $query->execute();

    while (my $hash = $query->fetchrow_hashref()) {
        unless (defined $RULE_ACTIONS->{$hash->{rule_id}}) {
            $RULE_ACTIONS->{$hash->{rule_id}} = {id => $hash->{rule_id}, name => $hash->{rule_name},};
        }

        $RULE_ACTIONS->{$hash->{rule_id}}->{actions}->{$hash->{action}}->{$hash->{action_id}} = {
            id       => $hash->{action_id},
            action   => $hash->{action},
            variable => $hash->{variable},
            value    => $hash->{value},
            method   => $hash->{method},
            instance => $hash->{instance},
        };

        # Populate test info if available
        if ($hash->{method} ne '*' and $hash->{method} and $hash->{instance} ne '*' and $hash->{instance}) {
            $RULE_ACTIONS->{$hash->{rule_id}}->{actions}->{$hash->{action}}->{$hash->{action_id}}->{test_descr}
              = $hash->{test_descr}
              if (defined $hash->{test_descr} && $hash->{test_descr});
            $RULE_ACTIONS->{$hash->{rule_id}}->{actions}->{$hash->{action}}->{$hash->{action_id}}->{test_depend}
              = $hash->{test_depend}
              if (defined $hash->{test_depend} && $hash->{test_depend});
            $RULE_ACTIONS->{$hash->{rule_id}}->{actions}->{$hash->{action}}->{$hash->{action_id}}->{norm_val}
              = $hash->{norm_val}
              if (defined $hash->{norm_val} && $hash->{norm_val});
            $RULE_ACTIONS->{$hash->{rule_id}}->{actions}->{$hash->{action}}->{$hash->{action_id}}->{crit_val}
              = $hash->{crit_val}
              if (defined $hash->{crit_val} && $hash->{crit_val});
            $RULE_ACTIONS->{$hash->{rule_id}}->{actions}->{$hash->{action}}->{$hash->{action_id}}->{test_icon}
              = $hash->{test_icon}
              if (defined $hash->{test_icon} && $hash->{test_icon});
            $RULE_ACTIONS->{$hash->{rule_id}}->{actions}->{$hash->{action}}->{$hash->{action_id}}->{oid} = $hash->{oid}
              if (defined $hash->{oid} && $hash->{oid});
            $RULE_ACTIONS->{$hash->{rule_id}}->{actions}->{$hash->{action}}->{$hash->{action_id}}->{oid} = $hash->{oid}
              if (defined $hash->{oif} && $hash->{oid});
        }
    }

    #print to_json({RULE_GROUPS => $RULE_GROUPS, RULE_ACTIONS => $RULE_ACTIONS,});
}

sub get_all_rule_groups {
    return $RULE_GROUPS;
}

sub get_rule_group {
    my $group_id = shift;
    return (defined $RULE_GROUPS->{$group_id}) ? $RULE_GROUPS->{$group_id} : undef;
}

sub get_rule_group_by_name {
    my $group_name = shift;
    foreach my $id (keys $RULE_GROUPS) {
        if ($RULE_GROUPS->{$id}->{name} eq $group_name) {
            return $RULE_GROUPS->{$id};
        }
    }
    return undef;
}

sub get_all_actions {
    return $RULE_ACTIONS;
}

sub get_rule_actions {
    my $rule_id = shift;
    return (defined $RULE_ACTIONS->{$rule_id}) ? $RULE_ACTIONS->{$rule_id}->{actions} : undef;
}

sub get_rule_actions_by_name {
    my $rule_name = shift;
    foreach my $id (keys $RULE_ACTIONS) {
        if ($RULE_ACTIONS->{$id}->{name} eq $rule_name) {
            return $RULE_ACTIONS->{$id}->{actions};
        }
    }
    return undef;
}

1;
