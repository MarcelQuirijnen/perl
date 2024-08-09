# Automation.pm
#
# @version $Id: Automation.pm 2015-04-03 14:21:18Z $
# @copyright 1999,2015, ShoreGroup, Inc.
package TKDB::Automation;
require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use DBI;
use lib '/usr/share/sg-macd-automation/lib/Perl';
use lib '/var/www/CaseSentry/lib/Perl';
use ConnectVars;
use feature "switch";
use SG::Logger;
use JSON;
use Data::Dumper;
use TKDevices::MACD::GatherTests;

use Exporter;

our @ISA = qw(Exporter);
our @EXPORT
  = qw{ load_standards_labels load_macd_actions validate_new_record get_gapi_lookup_cache_record get_all_hashref_auto
  get_standards_results get_standards_summary get_site_standards_summary get_standards_id_by_model
  get_automation_db_handle };
our @EXPORT_OK
  = qw{ load_standards_labels load_macd_actions validate_new_record get_gapi_lookup_cache_record get_all_hashref_auto
  get_standards_results get_standards_summary get_site_standards_summary get_standards_id_by_model
  insert_gapi_lookup_cache_record write_standard_results write_polled_results write_device_info
  write_interface_results write_bgp_results write_topology_results
  get_standards_results get_standards_summary get_site_standards_summary get_standards_id_by_model
  generate_standards_report insert_fex_results insert_result_record get_columns
  get_standards_results_for_report get_automation_db_handle insert_device_lldp insert_active_phones
  get_default_graphing_modules };
our %EXPORT_TAGS = (
    get => [
        qw{ get_gapi_lookup_cache_record get_all_hashref_auto get_standards_results get_standards_summary get_site_standards_summary get_standards_id_by_model get_standards_results_for_report get_automation_db_handle get_default_graphing_modules }
    ],
    write_results => [
        qw{ write_standard_results write_polled_results write_device_info write_interface_results write_bgp_results write_topology_results }
    ],
    standards => [
        qw{ load_standards_labels get_standards_results get_standards_summary get_site_standards_summary get_standards_id_by_model generate_standards_report }
    ],
);

our $dbhAutomation = getConnection('Automation') or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
$dbhAutomation->{AutoCommit} = 1;
$dbhAutomation->{'mysql_auto_reconnect'} = 1;

########################
# validate_new_record
#
# input - hashref containing the record you are trying to insert with a key mapping to the primary key of your table
# input - scalar containing the table name you're checking for
#
# output - Pass: ID of record in table
# output - Fail: undef
#
sub validate_new_record {
    my $table  = shift;
    my $record = shift;

    my $t;
    for ($table) {
        when (/gapi_lookup_cache/) {
            $t
              = $dbhAutomation->selectrow_array(
                "SELECT create_date FROM gapi_lookup_cache WHERE lookup_address='$record->{lookup_address}'")
              or ($DBI::errstr
                ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
                : SG::Logger->debug("[$$][validate_new_record][No record found for $record->{lookup_address}]"));
        }
    }
    if ($t) {
        return $t;
    } else {

        #Not needed
        #SG::Logger->debug("[validate_new_record][No record found in $table for ]"
        #      . ($record->{entity} ? $record->{entity} : $record->{name}));
        return;
    }
}

##############################################
# Location functions
##############################################

sub insert_gapi_lookup_cache_record {
    my $record = shift;

    my $when = validate_new_record('GapiLookupCacheRecord', $record);
    if ($when) {
        SG::Logger->err("[insert_gapi_lookup_cache_record][Lookup performed on: $when]");
        return -1;
    }
    my @columns = get_columns('gapi_lookup_cache', 'Automation');
    my (@insert_column, @insert_values);
    foreach my $column (@columns) {
        if (defined $record->{$column}) {
            push @insert_column, $column;
            push @insert_values, $record->{$column};
        }
    }
    my $sql
      = "INSERT INTO `gapi_lookup_cache` (`"
      . join("`,`", @insert_column)
      . "`) VALUES ('"
      . join("','", @insert_values) . "')";

    #SG::Logger->debug("[insert_gapi_lookup_cache_record][QUERY][$query]");
    $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
    return 1;
}

sub get_gapi_lookup_cache_record {
    my $address = shift;

    my $record = $dbhAutomation->selectrow_hashref("
            SELECT
                formatted_address,
                street_number,
                route,
                locality,
                administrative_area_level_1,
                administrative_area_level_2,
                country,
                postal_code
            FROM
                gapi_lookup_cache
            WHERE
                lookup_address='$address'
            AND
                FROM_UNIXTIME(create_time) > DATE_SUB(NOW(), INTERVAL 2 WEEK)")
      or ($DBI::errstr
        ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
        : SG::Logger->debug("[checkGAPICache][No results for lookup: $address"));

    if ($record) {
        return $record;
    } else {
        return 0;
    }
}

##############################################
# Database functions
##############################################

sub get_automation_db_handle {
    return $dbhAutomation;
}

#######################
# get_columns
#
# arguments: scalar - table name to get columns for
# arguments: scalar - db name to get columns for
#
# return: array - list of columns in provided db.table
sub get_columns {
    my $table         = shift;
    my $database_name = shift;

    my @return;
    my $sql
      = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='$table' AND TABLE_SCHEMA='$database_name'";
    my $query = $dbhAutomation->prepare($sql);

    #SG::Logger->debug("[get_columns][QUERY][$sql]");
    $query->execute() or SG::Logger->err("[$$][$DBI::errstr][$sql]");
    while (my $column = $query->fetchrow_array()) {
        push @return, $column;
    }
    return @return;
}

sub get_all_hashref_auto {
    my $sql  = shift;
    my @args = @_;
    my $hash = $dbhAutomation->selectall_hashref($sql, @args) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
    return $hash || 0;
}

##############################################
# Functions to write results
##############################################

# Test function for ContactCenter.pm
sub insert_result_record {
    my $record = shift;

    #print Dumper $record;
    my (@insert_column, @insert_values);
    foreach my $column (@{${$record->{TABLE_INFO}}->{COLUMNS}}) {
        if (defined ${$record->{VALUES}}->{$column}) {
            push @insert_column, $column;
            push @insert_values, ${$record->{VALUES}}->{$column};
        }

        # Check to see if its provided in the $record hash
        elsif (defined $record->{$column}) {
            push @insert_column, $column;
            push @insert_values, ${$record->{$column}};
        }

        # Check for modify_time and create_time
        elsif ($column =~ /modify_time|create_time/) {
            push @insert_column, $column;
            push @insert_values, 'UNIX_TIMESTAMP()';
        }
    }

    my $sql = sprintf(
        q{INSERT INTO `%s`.`%s` (`%s`) VALUES ('%s') },
        ${$record->{TABLE_INFO}}->{SCHEMA}, ${$record->{TABLE_INFO}}->{TABLE},
        join(q{`,`}, @insert_column), join(q{','}, @insert_values),
    );
    $sql =~ s/'UNIX_TIMESTAMP\(\)'/UNIX_TIMESTAMP()/gi;

    if (defined ${$record->{TABLE_INFO}}->{EXTRA_SQL}) {
        $sql .= ' ' . ${$record->{TABLE_INFO}}->{EXTRA_SQL};
    }

    if (defined ${$record->{TABLE_INFO}}->{ON_UPDATE}) {
        $sql .= ' ' . ${$record->{TABLE_INFO}}->{ON_UPDATE};
    }

    SG::Logger->debug("[insert_result_record][QUERY][$sql]");
    $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
    return 1;
}

sub write_standard_results {
    my $ip      = shift;
    my $name    = shift;
    my $results = shift;
    my @values;
    my %deletes;
    return 0 unless defined ${$results}->{$name};

    while (my ($method, $instances) = each ${$results}->{$name}) {
        while (my ($instance, $values) = each $instances) {
            $values->{DUPLICATE} = 0 unless $values->{DUPLICATE};
            push @values,
              sprintf(
                q{('%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP())},
                $name,               $ip,                    $method,               $instance,
                $values->{TYPE},     $values->{STATUS},      $values->{MONITORED},  $values->{EXCEPTION},
                $values->{STANDARD}, $values->{CLIENT_RULE}, $values->{DISCOVERED}, $values->{DUPLICATE},
              );
            $deletes{$ip} = 1;
        }
    }

    my @del = keys(%deletes);
    while (my @batch = splice(@del, 0, 50)) {
        $dbhAutomation->do(
            q{DELETE FROM `Automation`.`standards_results` WHERE `ip_addr_ipvx` IN ('} . join(q{','}, @batch) . q{')});
    }

    while (my @batch = splice(@values, 0, 50)) {
        my $sql
          = q{INSERT IGNORE INTO `Automation`.`standards_results` (`name`, `ip_addr_ipvx`, `method`, `instance`, `type`, `status`, `is_monitored`, `is_exception`, `is_standard`, `is_crules`, `is_dynamic`,  `duplicate`, `modify_time`, `create_time`) VALUES }
          . join(',', @batch)
          . q{ ON DUPLICATE KEY UPDATE `type`=VALUES(`type`), `status`=VALUES(`status`), `duplicate`=VALUES(`duplicate`),  `modify_time`=UNIX_TIMESTAMP();};

        SG::Logger->debug("[$$][write_standard_results][QUERY][$sql]");
        $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
    }
}

sub get_polled_results {
    my $toReturn = 0;
    my $name     = shift;
    my $method   = shift;
    my $instance = shift;
    my $query    = "SELECT * FROM `polled_targets` WHERE `name` = ? AND `method` = ? AND `instance` = ?";
    my $sth      = $dbhAutomation->prepare($query);
    my $results  = $sth->execute($name, $method, $instance) or SG::Logger->err("[$$][$DBI::errstr][$query]");
    if ($results) {
        $toReturn = $sth->fetchrow_hashref;
    }
    return $toReturn;
}

sub get_snmp_plugin_def {
    my $toReturn = 0;
    my $instance = shift;
    my $query
      = "SELECT `description`,`oid`,`normalValues`,`criticalValues`,`warningValues` FROM `CaseSentry`.`snmpPluginDef` WHERE `name` = ?";
    my $sth = $dbhAutomation->prepare($query);
    my $results = $sth->execute($instance) or SG::Logger->err("[$$][$DBI::errstr][$query]");
    if ($results) {
        $toReturn = $sth->fetchrow_hashref;
    }
    return $toReturn;
}

sub write_polled_results {
    my $devices = shift;
    my @values;
    my %deletes;
    no warnings 'uninitialized';

    foreach my $ip (keys ${$devices}) {
        next unless defined ${$devices}->{$ip}->{POLLED_TESTS};
        foreach my $method (keys ${$devices}->{$ip}->{POLLED_TESTS}) {
            next unless $method =~ /(SNMP|PROCESS|SERVICE|ISDNPRI)/;
            $deletes{$ip} = 1;
            while (my ($instance, $hash) = each ${$devices}->{$ip}->{POLLED_TESTS}->{$method}) {

                foreach my $key (keys $hash) {
                    $hash->{$key} =~ s/'//g;
                }

                next
                  unless (defined ${$devices}->{$ip}->{object_def}->{name}
                    && defined $ip
                    && defined $method
                    && defined $instance
                    && defined $hash->{test_descr}
                    && defined $hash->{icon}
                    && defined $hash->{raw_status}
                    && defined $hash->{norm_val}
                    && defined $hash->{crit_val}
                    && defined $hash->{depend}
                    && defined $hash->{oid});

                push @values,
                  sprintf(
                    q{( '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() )},
                    ${$devices}->{$ip}->{object_def}->{name},
                    $ip, $method, $instance, $hash->{test_descr}, $hash->{icon}, $hash->{raw_status},
                    $hash->{norm_val}, $hash->{crit_val}, $hash->{depend}, $hash->{oid}
                  );
            }
        }
    }

    my @del = keys(%deletes);
    while (my @batch = splice(@del, 0, 50)) {
        $dbhAutomation->do(
            q{DELETE FROM `Automation`.`polled_targets` WHERE `ip_addr_ipvx` IN ('} . join(q{','}, @batch) . q{')});
    }

    while (my @batch = splice(@values, 0, 50)) {
        my $sql
          = q{INSERT IGNORE INTO `Automation`.`polled_targets` (}
          . q{`name`, `ip_addr_ipvx`, `method`, `instance`, `description`, `icon`, `raw_status`, `norm_val`, `crit_val`,}
          . q{`depend`, `oid`, `modify_time`, `create_time`}
          . q{) VALUES };
        $sql .= join(',', @batch);
        $sql
          .= q{ ON DUPLICATE KEY UPDATE `description`=VALUES(`description`), `icon`=VALUES(`icon`), }
          . q{`raw_status`=VALUES(`raw_status`), `norm_val`=VALUES(`norm_val`), `crit_val`=VALUES(`crit_val`), }
          . q{`depend`=VALUES(`depend`), `oid`=VALUES(`oid`), `depend`=VALUES(`depend`), `modify_time`=UNIX_TIMESTAMP();};
        $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
    }
}

sub write_device_info {
    my $devices = shift;
    my @values;
    no warnings 'uninitialized';

    foreach my $ip (keys ${$devices}) {
        next unless defined ${$devices}->{$ip}->{INFO};

        my $icmp               = ${$devices}->{$ip}->{INFO}->{ICMP}                          || 0;
        my $pollable           = ${$devices}->{$ip}->{INFO}->{POLLABLE}                      || 0;
        my $uptime             = ${$devices}->{$ip}->{INFO}->{UPTIME}                        || 0;
        my $serial_num         = ${$devices}->{$ip}->{INFO}->{SERIAL_NUM}                    || '';
        my $model_num          = ${$devices}->{$ip}->{INFO}->{MODEL_NUM}                     || '';
        my $snmp_credential_id = ${$devices}->{$ip}->{snmp_credential}->{snmp_credential_id} || 0;
        my $poll_time          = ${$devices}->{$ip}->{INFO}->{AVG_POLL_TIME}                 || 0;

        push @values,
          sprintf(
            q{( '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() )},
            ${$devices}->{$ip}->{object_def}->{name},
            $ip, $icmp, $pollable, $poll_time, $uptime, $serial_num, $model_num, $snmp_credential_id
          );
    }

    while (my @batch = splice(@values, 0, 50)) {
        my $sql
          = q{INSERT IGNORE INTO `Automation`.`device_info` (`name`,`ip_addr_ipvx`,`icmp`,`pollable`,`poll_time`,`uptime`,`serial_num`,`model_num`,}
          . q{`snmp_credential_id`,`modify_time`,`create_time`) VALUES };
        $sql .= join(',', @batch);
        $sql
          .= q{ ON DUPLICATE KEY UPDATE `icmp`=VALUES(`icmp`), `pollable`=VALUES(`pollable`), `poll_time`=VALUES(`poll_time`), `uptime`=VALUES(`uptime`),}
          . q{ `serial_num`=VALUES(`serial_num`), `model_num`=VALUES(`model_num`), `snmp_credential_id`=VALUES(`snmp_credential_id`),}
          . q{ `modify_time`=UNIX_TIMESTAMP();};
        $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
    }
}

sub write_interface_results {
    my $devices = shift;
    my @values;
    my %deletes;
    no warnings 'uninitialized';

    foreach my $ip (keys ${$devices}) {
        next unless defined ${$devices}->{$ip}->{POLLED_TESTS};
        foreach my $method (keys ${$devices}->{$ip}->{POLLED_TESTS}) {
            next unless $method =~ /IF/;
            $deletes{$ip} = 1;
            while (my ($instance, $hash) = each ${$devices}->{$ip}->{POLLED_TESTS}->{$method}) {

                foreach my $key (keys $hash) {
                    $hash->{$key} =~ s/'//g;
                }

                push @values,
                  sprintf(
                    q{( '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() )},
                    ${$devices}->{$ip}->{object_def}->{name}, $ip,
                    $hash->{test_name},                       $hash->{ifIndex},
                    $hash->{ifName},                          $hash->{ifOperStatus},
                    $hash->{ifAdminStatus},                   $hash->{ifDescr},
                    $hash->{ifPhysAddress},                   $hash->{ifAlias},
                    $hash->{ifType},                          $hash->{cdpCacheDeviceId},
                    $hash->{cdpCachePlatform},                $hash->{cdpCacheDevicePort},
                    $hash->{cdpCacheAddress},                 $hash->{ipAdEntAddr},
                    $hash->{ipAdEntNetMask},                  $hash->{redundant},
                    $hash->{is_trunking},
                  );
            }
        }
    }

    my @del = keys(%deletes);
    while (my @batch = splice(@del, 0, 50)) {
        $dbhAutomation->do(
            q{DELETE FROM `Automation`.`interfaces` WHERE `ip_addr_ipvx` IN ('} . join(q{','}, @batch) . q{')});
    }

    while (my @batch = splice(@values, 0, 50)) {
        my $sql
          = q{INSERT IGNORE INTO `Automation`.`interfaces` (`name`,`ip_addr_ipvx`,`terse`,`ifIndex`,`ifName`,`ifOperStatus`,}
          . q{`ifAdminStatus`,`ifDescr`,`ifPhysAddress`,`ifAlias`,`ifType`,`cdpCacheDeviceId`,`cdpCachePlatform`,}
          . q{`cdpCacheDevicePort`, `cdpCacheAddress`,`ipAdEntAddr`,`ipAdEntNetMask`,`redundant`,`is_trunking`,`modify_time`,`create_time`) VALUES };
        $sql .= join(',', @batch);
        $sql
          .= q{ ON DUPLICATE KEY UPDATE `ifOperStatus`=VALUES(`ifOperStatus`), `ifAdminStatus`=VALUES(`ifAdminStatus`),}
          . q{ `ifDescr`=VALUES(`ifDescr`), `ifPhysAddress`=VALUES(`ifPhysAddress`), `ifAlias`=VALUES(`ifAlias`),}
          . q{ `ifType`=VALUES(`ifType`), `cdpCacheDeviceId`=VALUES(`cdpCacheDeviceId`), `cdpCachePlatform`=VALUES(`cdpCachePlatform`),}
          . q{ `cdpCacheDevicePort`=VALUES(`cdpCacheDevicePort`), `cdpCacheAddress`=VALUES(`cdpCacheAddress`),}
          . q{ `ipAdEntAddr`=VALUES(`ipAdEntAddr`), `ipAdEntNetMask`=VALUES(`ipAdEntNetMask`), `redundant`=VALUES(`redundant`), `is_trunking`=VALUES(`is_trunking`), `modify_time`=UNIX_TIMESTAMP();};
        $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
    }
}

sub write_bgp_results {
    my $devices = shift;
    no warnings 'uninitialized';
    my @bgp_values;
    my @cbgp_values;
    foreach my $ip (keys ${$devices}) {
        next unless defined ${$devices}->{$ip}->{BGP};
        if (defined ${$devices}->{$ip}->{BGP}->{INFO}) {
            my $sql = sprintf(
                q{INSERT IGNORE INTO `Automation`.`bgp_info` VALUES ('%s','%s','%s','%s',UNIX_TIMESTAMP(),UNIX_TIMESTAMP())}
                  . q{ ON DUPLICATE KEY UPDATE `bgpLocalAs`=VALUES(`bgpLocalAs`),`bgpIdentifier`=VALUES(`bgpIdentifier`),`modify_time`=UNIX_TIMESTAMP();},
                ${$devices}->{$ip}->{object_def}->{name},
                $ip,
                ${$devices}->{$ip}->{BGP}->{INFO}->{bgpLocalAs},
                ${$devices}->{$ip}->{BGP}->{INFO}->{bgpIdentifier}
            );
            $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
        }

        if (defined ${$devices}->{$ip}->{BGP}->{DATA}) {
            while (my ($index, $hash) = each ${$devices}->{$ip}->{BGP}->{DATA}) {
                push @bgp_values,
                  sprintf(
                    q{( '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s',  UNIX_TIMESTAMP(), UNIX_TIMESTAMP() )},
                    ${$devices}->{$ip}->{object_def}->{name}, $ip,
                    $index,                                   $hash->{bgpPeerIdentifier},
                    $hash->{bgpPeerState},                    $hash->{bgpPeerAdminStatus},
                    $hash->{bgpPeerLocalAddr},                $hash->{bgpPeerRemoteAs},
                    $hash->{bgpPeerLastError},                $hash->{bgpPeerFsmEstablishedTime},
                  );
            }
        }
    }

    if (@bgp_values) {
        while (my @batch = splice(@bgp_values, 0, 50)) {
            my $sql
              = q{INSERT IGNORE INTO `Automation`.`bgp_peer` (`name`, `ip_addr_ipvx`, `index`, `bgpPeerIdentifier`,}
              . q{ `bgpPeerState`, `bgpPeerAdminStatus`, `bgpPeerLocalAddr`, `bgpPeerRemoteAs`, `bgpPeerLastError`,}
              . q{ `bgpPeerFsmEstablishedTime`, `modify_time`, `create_time`) VALUES };
            $sql .= join(',', @batch);
            $sql
              .= q{ ON DUPLICATE KEY UPDATE `bgpPeerIdentifier`=VALUES(`bgpPeerIdentifier`), }
              . q{`bgpPeerState`=VALUES(`bgpPeerState`), `bgpPeerAdminStatus`=VALUES(`bgpPeerAdminStatus`), }
              . q{`bgpPeerLocalAddr`=VALUES(`bgpPeerLocalAddr`), `bgpPeerRemoteAs`=VALUES(`bgpPeerRemoteAs`), }
              . q{`bgpPeerLastError`=VALUES(`bgpPeerLastError`), `bgpPeerFsmEstablishedTime`=VALUES(`bgpPeerFsmEstablishedTime`), }
              . q{ `modify_time`=UNIX_TIMESTAMP();};
            $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
        }
    }
    if (@cbgp_values) {
        while (my @batch = splice(@cbgp_values, 0, 50)) {
            my $sql
              = q{INSERT IGNORE INTO `Automation`.`cbgp_peer` (`name`, `ip_addr_ipvx`, `index`, `cbgpPeer2RemoteIdentifier`,}
              . q{ `cbgpPeer2State`, `cbgpPeer2AdminStatus`, `cbgpPeer2LocalAddr`, `cbgpPeer2RemoteAs`, `cbgpPeer2LastError`,}
              . q{ `cbgpPeer2FsmEstablishedTime`, `modify_time`, `create_time`) VALUES };
            $sql .= join(',', @batch);
            $sql
              .= q{ ON DUPLICATE KEY UPDATE `cbgpPeer2RemoteIdentifier`=VALUES(`cbgpPeer2RemoteIdentifier`), }
              . q{`cbgpPeer2State`=VALUES(`cbgpPeer2State`), `cbgpPeer2AdminStatus`=VALUES(`cbgpPeer2AdminStatus`), }
              . q{`cbgpPeer2LocalAddr`=VALUES(`cbgpPeer2LocalAddr`), `cbgpPeer2RemoteAs`=VALUES(`cbgpPeer2RemoteAs`), }
              . q{`cbgpPeer2LastError`=VALUES(`cbgpPeer2LastError`), `cbgpPeer2FsmEstablishedTime`=VALUES(`cbgpPeer2FsmEstablishedTime`), }
              . q{`modify_time`=UNIX_TIMESTAMP();};
            $dbhAutomation->do($sql) or SG::Logger->err("[$DBI::errstr][$sql]");
        }
    }
}

sub write_topology_results {
    my $devices = shift;
    no warnings 'uninitialized';
    foreach my $ip (keys ${$devices}) {

        # Topology inserts
        if (defined ${$devices}->{$ip}->{TOPOLOGY}) {
            my $name = '';
            unless (defined ${$devices}->{$ip}->{TOPOLOGY}->{SYS}->{sysName}) {
                $name = ${$devices}->{$ip}->{object_def}->{name};
            } else {
                $name = ${$devices}->{$ip}->{TOPOLOGY}->{SYS}->{sysName};
            }
            &insert_fdb_arp($ip, \${$devices}->{$ip}->{TOPOLOGY});
        }
    }
}

sub insert_fdb_arp {
    my $ip   = shift;
    my $topo = shift;

    my @VLAN;
    my @B_PORT;
    my @FDB;
    my @ARP;
    if (defined ${$topo}->{VTP}) {
        foreach my $vlan (keys ${$topo}->{VTP}) {
            next unless defined ${$topo}->{VTP}->{$vlan}->{PORT};
            foreach my $port (keys ${$topo}->{VTP}->{$vlan}->{PORT}) {

                if (defined ${$topo}->{VTP}->{$vlan}->{DesignatedRootAddress}
                    && ${$topo}->{VTP}->{$vlan}->{DesignatedRootAddress} ne '00:00:00:00:00:00')
                {
                    push @VLAN,
                      sprintf(
                        q{('','%s','%s','%s','%s','%s')},
                        $ip,
                        ${$topo}->{VTP}->{$vlan}->{vtpVlanName},
                        ${$topo}->{VTP}->{$vlan}->{IsRootBridge} || 0,
                        ${$topo}->{VTP}->{$vlan}->{DesignatedRootAddress},
                        ${$topo}->{VTP}->{$vlan}->{DesignatedRootPriority} || 0,
                      );
                }

                if (defined ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{DesignatedBridgeAddress}
                    && ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{DesignatedBridgeAddress} ne '00:00:00:00:00:00')
                {
                    push @B_PORT,
                      sprintf(
                        q{('','%s','%s','%s','%s','%s','%s','%s','%s')},
                        $ip,
                        ${$topo}->{VTP}->{$vlan}->{vtpVlanName},
                        $port,
                        ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{IsDesignatedPort} || 0,
                        ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{DesignatedBridgeAddress},
                        ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{DesignatedBridgePriority} || 0,
                        ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{DesignatedPortBridgePort} || 0,
                        ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{DesignatedPortPriority}   || 0,
                      );
                }

                next unless defined ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{FDB};
                foreach my $mac (keys ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{FDB}) {

                    # Extra logic for Q-BRIDGE-MIB
                    my $vtpVlanIfIndex = 0;

                    if (defined ${$topo}->{VTP}->{$vlan}->{vtpVlanIfIndex}) {
                        $vtpVlanIfIndex = ${$topo}->{VTP}->{$vlan}->{vtpVlanIfIndex};
                    } elsif (defined ${$topo}->{PORT_MAP} && defined ${$topo}->{PORT_MAP}->{$port}) {
                        $vtpVlanIfIndex = ${$topo}->{PORT_MAP}->{$port};
                    }

                    push @FDB,
                      sprintf(
                        q{ ('', '%s', '%s', %d, %d, %d, '%s', '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP()) },
                        $ip,
                        ${$topo}->{VTP}->{$vlan}->{vtpVlanName} || sprintf('VLAN%04s', $vlan),
                        $vtpVlanIfIndex,
                        $port,
                        ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{dot1dBasePortIfIndex} || 0,
                        ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{dot1dStpPortState}    || 'unknown',
                        $mac,
                        ${$topo}->{VTP}->{$vlan}->{PORT}->{$port}->{FDB}->{$mac}->{dot1dTpFdbStatus} || 'unknown',
                      );
                }
            }
        }
    }

    if (defined ${$topo}->{Interfaces}) {
        foreach my $ifIndex (keys ${$topo}->{Interfaces}) {
            next unless defined ${$topo}->{Interfaces}->{$ifIndex}->{ARP};
            while (my ($ipNetToMediaNetAddress, $ipNetToMediaPhysAddress)
                = each ${$topo}->{Interfaces}->{$ifIndex}->{ARP})
            {
                push @ARP,
                  sprintf(q{ ('', '%s', '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP()) },
                    $ip, $ipNetToMediaNetAddress, $ipNetToMediaPhysAddress);
            }
        }
    }

    if (@VLAN) {
        $dbhAutomation->do(sprintf(q{DELETE FROM `Automation`.`device_vlan` WHERE `ip_addr_ipvx`='%s'}, $ip));

        while (my @batch = splice(@VLAN, 0, 50)) {
            my $sql = q{INSERT IGNORE INTO `Automation`.`device_vlan` VALUES };
            $sql .= join(',', @batch);
            $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");

        }
    }

    if (@B_PORT) {
        $dbhAutomation->do(sprintf(q{DELETE FROM `Automation`.`device_bridgeport` WHERE `ip_addr_ipvx`='%s'}, $ip));

        while (my @batch = splice(@B_PORT, 0, 50)) {
            my $sql = q{INSERT IGNORE INTO `Automation`.`device_bridgeport` VALUES };
            $sql .= join(',', @batch);
            $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");

        }
    }

    if (@FDB) {
        $dbhAutomation->do(sprintf(q{DELETE FROM `Automation`.`device_fdb` WHERE `ip_addr_ipvx`='%s'}, $ip));

        while (my @batch = splice(@FDB, 0, 50)) {
            my $sql = q{INSERT IGNORE INTO `Automation`.`device_fdb` VALUES };
            $sql .= join(',', @batch);
            $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");

        }
    }

    if (@ARP) {
        $dbhAutomation->do(sprintf(q{DELETE FROM `Automation`.`device_arp` WHERE `ip_addr_ipvx`='%s'}, $ip));

        while (my @batch = splice(@ARP, 0, 50)) {
            my $sql = q{INSERT IGNORE INTO `Automation`.`device_arp` VALUES };
            $sql .= join(',', @batch);
            $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");

        }
    }
}

sub insert_fex_results {
    my $ip     = shift;
    my $values = shift;
    $dbhAutomation->do(sprintf(q{DELETE FROM `Automation`.`fex_results` WHERE `ip_addr_ipvx`='%s'}, $ip));

    while (my @batch = splice(@{$values}, 0, 50)) {
        my $sql
          = q{INSERT IGNORE INTO `Automation`.`fex_results` (`name`, `ip_addr_ipvx`, `cefexBindingExtenderIndex`, `ifIndex`, `oid`, `modify_time`, `create_time`) VALUES };
        $sql .= join(',', @batch);
        $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
    }
}

sub insert_device_lldp {
    my $ip     = shift;
    my $record = shift;

    while (my @batch = splice(@{$record->{connections}}, 0, 50)) {
        my $sql = q{INSERT IGNORE INTO `Automation`.`device_lldp` (
              `ip_addr_ipvx`,`lldpLocChassisId`,`lldpLocSysName`,`lldpLocManAddrIfId`,
              `lldpRemChassisId`,`lldpRemSysName`,`lldpRemPortId`
            ) VALUES ('%s','%s','%s','%s','%s','%s','%s' )};

        foreach my $conn (@batch) {
            $dbhAutomation->do(
                sprintf($sql,
                    $ip,                           $record->{lldpLocChassisId}, $record->{lldpLocSysName},
                    $record->{lldpLocManAddrIfId}, $conn->{lldpRemChassisId},   $conn->{lldpRemSysName},
                    $conn->{lldpRemPortId})
            );
        }
    }
}

sub insert_active_phones {
    my $ip     = shift;
    my $phones = shift;

    my $now = TKUtils::Utils::mysqlNow();

    my @phoneNames = keys $phones;
    while (my @batch = splice(@phoneNames, 0, 50)) {
        my @inserts;
        my $sql = q{INSERT IGNORE INTO `Automation`.`active_phones` (
                    `cucm_ip_ipvx`,`device_name`,`device_ip_ipvx`,`device_description`,`device_status`,
                    `device_type`,`device_mac`,`last_poll_time`,`last_status_change`) VALUES
                    };
        foreach my $phone (@{$phones}{@batch}) {
            $phone->{last_status_change} = $now if !$phone->{last_status_change};
            my $values = sprintf(
                "('%s','%s','%s','%s','%s','%s','%s','%s','%s')",
                $ip,                   $phone->{name},   $phone->{ip_addr_ipvx},
                $phone->{description}, $phone->{status}, $phone->{DeviceType},
                $phone->{MAC},         $now,             $phone->{last_status_change}
            ) if $phone->{ip_addr_ipvx} && $phone->{MAC};
            push(@inserts, $values) if $values;
        }
        $dbhAutomation->do($sql
              . join(',', @inserts)
              . ' ON DUPLICATE KEY UPDATE `device_status`=VALUES(`device_status`), `last_poll_time`=VALUES(`last_poll_time`), `last_status_change`=VALUES(`last_status_change`) '
        );
    }
}

##############################################
# Functions for standards results
##############################################
# write_standard_results
#
# Takes results from TKDevices::Standards and inserts them into `Automation`.`standards_results`

sub get_standards_results {
    my $name = shift;
    my $sql  = qq{SELECT concat(s.name,':', s.method,':', s.instance) AS entity, s.* FROM standards_results s };
    $sql
      .= q{ WHERE s.method NOT IN ('GRAPH','CDR','SYNTHCALL','REPORT','DASHBOARD','BACKUP') AND s.instance NOT REGEXP '[*]' };
    $sql .= qq{AND s.name='$name' } if $name;
    my $results = &get_all_hashref_auto($sql, ['name', 'status', 'method', 'instance']);
    return $results || 0;
}

sub get_standards_results_for_report {
    my $sql = q{SELECT 
        od.id, od.name, od.ip_addr_ipvx, sr.method, sr.instance, od.description, 
        IFNULL(ss.device_type, 'Not set') `standards_sku`, 
        IFNULL(sd.description, 'Not set') `standards_device`,
        sr.status, IF(sr.duplicate=1, 'Yes', 'No') `duplicate`,
        IFNULL(se.notes, '') `exception`
        FROM `CaseSentry`.`object_def` od
        JOIN `Automation`.`standards_results` sr ON od.name=sr.name
        LEFT JOIN `CaseSentry`.`standards_exceptions` se ON od.id=se.object_def_id AND sr.method=se.method and sr.instance=se.instance
        LEFT JOIN `CaseSentry`.`standards_skus` ss ON od.standards_sku_id=ss.id
        LEFT JOIN `CaseSentry`.`standards_devices` sd ON od.standards_device_id=sd.id
        WHERE od.instance='NODE'
            AND sr.method NOT IN ('GRAPH','CDR','SYNTHCALL','REPORT','DASHBOARD','BACKUP') 
            AND sr.instance NOT REGEXP '[*]'
        };
    my $results = &get_all_hashref_auto($sql, ['name', 'method', 'instance']);
    return $results || 0;
}

sub get_standards_summary {
    my $name = shift;
    my $sql  = q{select s.name, s.status, count(*) AS num from standards_results s };
    $sql
      .= q{WHERE s.method NOT IN ('GRAPH','CDR','SYNTHCALL','REPORT','DASHBOARD','BACKUP') AND s.instance NOT REGEXP '[*]' };
    $sql .= qq{AND s.name='$name' } if $name;
    $sql .= q{GROUP BY s.name, s.status};
    my $results = &get_all_hashref_auto($sql, ['name', 'status']);
    return $results || 0;
}

sub get_site_standards_summary {
    my $sql = q{select s.status, count(*) AS num from standards_results s };
    $sql
      .= q{WHERE s.method NOT IN ('GRAPH','CDR','SYNTHCALL','REPORT','DASHBOARD','BACKUP') AND s.instance NOT REGEXP '[*]' };
    $sql .= q{GROUP BY s.status};
    my $results = &get_all_hashref_auto($sql, ['status']);
    return $results || 0;
}

sub get_standards_id_by_model {
    my $sql
      = q{select di.model_num, od.standards_sku_id, od.standards_device_id, count(*) as `count` FROM device_info di JOIN CaseSentry.object_def od ON od.name=di.name AND od.instance='NODE' GROUP BY di.model_num, od.standards_sku_id, od.standards_device_id;};
    my $results = &get_all_hashref_auto($sql, ['model_num', 'count']);
    return $results || 0;
}

sub generate_standards_report {
    my $file_name = shift;
    `rm $file_name` if -e $file_name;
    my $sql = qq{SELECT concat(s.name,':', s.method,':', s.instance) AS entity, s.*
        FROM standards_results s
        INTO OUTFILE '$file_name'};
    $dbhAutomation->do($sql) or SG::Logger->err("[$$][$DBI::errstr][$sql]");
}

# Loads the macd_actions from the database
# Returns a JSON String that can be evaluated
# and converted to a Perl object. See MACD.pm

sub load_macd_actions {
    my $sql         = q{SELECT name, description, function FROM macd_action};
    my $macdActions = &get_all_hashref_auto($sql, ['name']);
    my @a           = ("{ ");
    foreach my $macd_action_key (keys %$macdActions) {
        @a[scalar @a] = $macdActions->{$macd_action_key}{name};
        @a[scalar @a] = "  => {DESCRIPTION => '";
        @a[scalar @a] = $macdActions->{$macd_action_key}{description};
        @a[scalar @a] = "' , FUNCTION => sub {";
        @a[scalar @a] = $macdActions->{$macd_action_key}{function};
        @a[scalar @a] = "(\@_);}";
        @a[scalar @a] = "},\n";
    }
    @a[(scalar @a) - 1] = " }};";
    return join("", @a) || "{}";
}

# Loads the standards_label from the database
# Returns a JSON String that can be evaluated
# and converted to a Perl object. See Standards.pm
# each label looks like the one below
# MONITORED_STANDARD => {
#        DESCRIPTION => 'Test that is in monitoring and meets standards',
#        ACTION      => 'No Action Needed',
#        COLOR       => [BOLD BLACK ON_GREEN],
#        MACD_ACTION => ['NONE'],
#    }

sub load_standards_labels {
    my $sql
      = q{SELECT sl.name LABEL, sl.color COLOR, sl.description DESCRIPTION, sl.action_description ACTION, GROUP_CONCAT(ma.name) MACD_ACTION 
FROM standards_label sl
JOIN macd_action_standards_label masl ON sl.id = masl.standards_label_id  
JOIN macd_action ma ON ma.id = masl.macd_action_id  GROUP BY LABEL;};
    my $stdLabels = &get_all_hashref_auto($sql, ['LABEL']);
    foreach my $label (keys $stdLabels) {
        my @actions = split(',', $stdLabels->{$label}->{MACD_ACTION});
        $stdLabels->{$label}->{MACD_ACTION} = \@actions;
    }

    return $stdLabels;
}

# Update status in sak_upload table
sub update_sak_upload_status($) {
    my $sak_id = shift;
    $dbhAutomation->do("UPDATE `Automation`.`sak_upload` SET `state` = 3 WHERE `id` = ?", undef, $sak_id);
    print "SAK UPLOAD ID: " . $sak_id . "\n";
}

# Update manager request status
sub update_req_status($$) {
    my $req_id = shift;
    my $status = shift;
    my $id     = 0;

    # Adding ID column to macd_req_status requires to modify this update routine
    my $sql = "SELECT id FROM `macd_req_status` WHERE req_id = '$req_id'";
    SG::Logger->debug("[update_req_status][QUERY][$sql]");
    my $rec_exists = &get_all_hashref_auto($sql, ['id']);

    foreach my $macd_rec (keys %$rec_exists) {
        $id = $rec_exists->{$macd_rec}->{id};
    }
    if ($id) {
        SG::Logger->debug("[update_req_status][UPDATE][id] : $id, $req_id, $status");
        $dbhAutomation->do(
            "REPLACE INTO `macd_req_status` (`id`,`req_id`,`status`,`created`) VALUES(?,?,?,UNIX_TIMESTAMP(NOW()))",
            undef, $id, $req_id, $status);
    } else {
        SG::Logger->debug("[update_req_status][INSERT] : $req_id, $status");
        $dbhAutomation->do(
            "INSERT INTO `macd_req_status` (`req_id`,`status`,`created`) VALUES(?,?,UNIX_TIMESTAMP(NOW()))",
            undef, $req_id, $status);
    }
}

sub get_default_graphing_modules {
    my @return;
    my $sql   = q{SELECT `name` FROM `default_modules` WHERE `enabled` = 1};
    my $query = $dbhAutomation->prepare($sql);
    $query->execute() or SG::Logger->err("[$$][$DBI::errstr][$sql]");
    while (my $name = $query->fetchrow_array()) {
        push @return, $name;
    }
    return @return;
}

1;
