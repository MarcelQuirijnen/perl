# CaseSentry.pm
#
# @version $Id: CaseSentry.pm 2015-04-03 14:21:18Z $
# @copyright 1999,2015, ShoreGroup, Inc.

package TKDB::CaseSentry;
require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

use lib '/usr/share/sg-macd-automation/lib/Perl';
use lib '/var/www/CaseSentry/lib/Perl';
use ConnectVars;
use feature "switch";
use SG::Logger;
use Term::ANSIColor qw(:constants);
use Data::Dumper;
use Data::Structure::Util;
use TKUtils::Utils;

use Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw{ validate_new_record validate_device_exists get_object_def_node_id get_locations get_location_id
  get_monitored_tests get_max_id get_duplicate_tests get_all_hashref get_standards_targets
  get_standards_targets_by_id get_standards_targets_info get_exceptions get_snmp_credential_by_ip
  get_snmp_credential_by_string get_snmp_credential_by_id add_axl_counter get_cred_id
  get_device_groups get_icm_credentials_by_ip validate_device_exists get_cs_version should_run_flaticon_conversion convert_to_flaticon
  get_release_tag_version};

our @EXPORT_OK = qw{ $dbhCaseSentry validate_new_record validate_device_exists update_location_id update_standards_id
  insert_object_def_record insert_snmp_credential_record insert_snmp_plugin_def_record
  insert_location_record insert_object_def_entity_group get_object_def_node_id get_locations get_location_id
  get_monitored_tests get_max_id get_duplicate_tests get_all_hashref get_standards_targets
  get_standards_targets_by_id get_standards_targets_info get_exceptions add_exception
  remove_exception get_snmp_credential_by_ip get_snmp_credential_by_string
  get_snmp_credential_by_id associate_snmp_credential get_device_groups
  associate_standards_object_def_templates remove_test update_test get_icm_credentials_by_ip insert_object_def_meta validate_device_exists
  get_mrtg_dir get_cs_version add_axl_counter get_cred_id
  get_release_tag_version};

our %EXPORT_TAGS = (
    get => [
        qw{ get_object_def_node_id get_locations get_location_id get_monitored_tests get_max_id
          get_duplicate_tests get_all_hashref get_standards_targets
          get_standards_targets_by_id get_standards_targets_info get_exceptions get_device_groups get_icm_credentials_by_ip validate_device_exists
          get_mrtg_dir get_cs_version get_cred_id get_release_tag_version}
    ],
    standards  => [qw{ get_standards_targets get_standards_targets_by_id get_standards_targets_info get_exceptions }],
    exceptions => [qw{ get_exceptions add_exception remove_exception }],
    inserts    => [
        qw{ insert_object_def_record insert_snmp_credential_record insert_snmp_plugin_def_record add_axl_counter
          insert_location_record insert_object_def_entity_group insert_object_def_meta }
    ],
    changes => [
        qw{ update_location_id update_standards_id insert_object_def_record insert_snmp_credential_record
          insert_snmp_plugin_def_record insert_location_record insert_object_def_entity_group add_exception add_axl_counter get_cred_id
          remove_exception associate_snmp_credential associate_standards_object_def_templates remove_test update_test insert_object_def_meta }
    ],
);

our $dbhCaseSentry = getConnection('Main') or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
$dbhCaseSentry->{AutoCommit} = 1;
$dbhCaseSentry->{'mysql_auto_reconnect'} = 1;

# Hash of instances that are banned for inserts
my @banned = qw{ agent-vm agent-alt CVP_VB };

################################################
# Validation functions
################################################

sub validate_new_record {
    my $table  = shift;
    my $record = shift;

    my $t;
    for ($table) {
        when (/object_def/) {
            $t = $dbhCaseSentry->selectrow_array("SELECT id FROM object_def WHERE entity='$record->{entity}'")
              or ($DBI::errstr
                ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
                : SG::Logger->debug("[$$][No object_def record found for $record->{entity}]"));
        }
        when (/snmpPluginDef/) {
            $t = $dbhCaseSentry->selectrow_array("SELECT name FROM snmpPluginDef WHERE name='$record->{name}'")
              or ($DBI::errstr
                ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
                : SG::Logger->debug("[$$][No snmpPluginDef record found for $record->{name}]"));
        }
        when (/def_entity_correlation/) {
            $t
              = $dbhCaseSentry->selectrow_array(
                "SELECT id FROM def_entity_correlation WHERE entity='$record->{entity}'")
              or ($DBI::errstr
                ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
                : SG::Logger->debug("[$$][No def_entity_correlation record found for $record->{entity}]"));
        }
    }
    if ($t) {
        return $t;
    } else {
        return;
    }
}

sub validate_device_exists {
    my $ip = shift;
    if (!$ip) {
        SG::Logger->err("[validate_device_exists][No IP passed for lookup]");
        return;
    }
    my $id
      = $dbhCaseSentry->selectrow_array(
        "SELECT id FROM object_def WHERE ip_addr_ipvx='$ip' AND method='GRP' AND instance='NODE'")
      or ($DBI::errstr
        ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
        : SG::Logger->debug("[$$][validate_device_exists][No results for ip: $ip]"));
    if ($id) {
        return $id;
    } else {
        return;
    }
}

################################################
# Update functions
################################################

sub get_cred_id {
    my $ip = shift;

    my $cred_id = $dbhCaseSentry->selectrow_array(
        "SELECT ccm.id
        FROM CaseSentry.object_def o
        JOIN CaseSentry.def_ccm_credentials ccm ON ccm.entity = o.entity
        WHERE o.ip_addr_ipvx = '$ip'"
    );
    return $cred_id || 0;
}

# This function replaces the add_axl_counter used in legacy code in ccmEkgInclude.php
# Input: an array of hashes
#        each array element is a hash of a cred_id with an array of labels/counters to be updated/inserted
#        @myCounters = ( { cred_id => '5', counters => [ 'counter5', 'counter55', 'counter555' ] },
#                        { cred_id => '4', counters => [ 'counter4', 'counter44', 'counter444' ] }
#        this enables multiple db updates in one call and is a performance improvement on the legacy code
# Output: SUCCESS or FAILURE with a corresponding msg string
sub add_axl_counter {
    my ($axl_counters) = @_;
    my $noof_counters = 0;
    my $dbhCcmAxl = getConnection('ccmaxl') or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    $dbhCcmAxl->{AutoCommit} = 0;
    foreach my $axl_counter (@$axl_counters) {
        $noof_counters += scalar @{$axl_counter->{'counters'}};
        for my $i (0 .. scalar @{$axl_counter->{'counters'}} - 1) {
            SG::Logger->debug(
                "[add_axl_counter][UPDATE] : cred_id $axl_counter->{'cred_id'} with ${$axl_counter->{'counters'}}[$i]");

            ${$axl_counter->{'counters'}}[$i] =~ s/\\/\\\\/g;

            $dbhCcmAxl->do(
                sprintf(
                    q{ INSERT INTO `CaseSentry`.`ccm_axl_counter_info`(`cred_id`, `counter`)
                        SELECT '%d', '%s' FROM DUAL
                        WHERE NOT EXISTS ( SELECT * FROM `CaseSentry`.`ccm_axl_counter_info` WHERE `counter` = '%s' AND `cred_id` = '%d' ) },
                    $axl_counter->{'cred_id'}, ${$axl_counter->{'counters'}}[$i], ${$axl_counter->{'counters'}}[$i],
                    $axl_counter->{'cred_id'}
                )
              )
              or do {
                SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
                return {SUCCESS => 0, MSG => $DBI::errstr};
              };
        }
    }
    $dbhCcmAxl->commit;
    $dbhCcmAxl->{AutoCommit} = 1;
    return {SUCCESS => 1, MSG => sprintf(q{ updated %d counters }, $noof_counters)};
}

sub update_location_id {
    my $name   = shift;
    my $loc_id = shift;
    $dbhCaseSentry->do(
        sprintf(q{UPDATE object_def SET location_id=%d WHERE name = '%s' AND instance='NODE'}, $loc_id, $name))
      or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return 0 if ($DBI::errstr);
    return 1;
}

sub update_standards_id {
    my $name                = shift;
    my $standards_sku_id    = shift;
    my $standards_device_id = shift;
    $dbhCaseSentry->do(
        sprintf(
            q{UPDATE object_def SET standards_sku_id = %d, standards_device_id = %d WHERE name='%s' and standards_sku_id=0 AND instance='NODE';},
            $standards_sku_id, $standards_device_id, $name
        )
    ) or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return 0 if ($DBI::errstr);
    return 1;
}

sub update_test {
    my $name       = shift;
    my $method     = shift;
    my $instance   = shift;
    my $test_ref   = shift;
    my $values_ref = \${$test_ref}->{UPDATE_INFO}->{'object_def'};

    ${$test_ref}->{entity} = "$name:$method:$instance" unless (defined ${$test_ref}->{entity});

    my $id = validate_new_record('object_def', ${$test_ref});

    if ($id) {
        my @updates;
        foreach my $column (keys ${$values_ref}) {
            push @updates, sprintf(q{`%s`='%s'}, $column, ${$values_ref}->{$column});
        }

        SG::Logger->debug(
            sprintf(
                q{[%d][update_test][%s:%s:%s][Updating object_def values to: %s]},
                $$, $name, $method, $instance, join(', ', @updates)
            )
        );

        $dbhCaseSentry->do(
            sprintf(
                q{UPDATE `CaseSentry`.`object_def` SET %s WHERE `name`='%s' AND `method`='%s' AND `instance`='%s' AND `id`=%d},
                join(',', @updates),
                $name, $method, $instance, $id
            )
          )
          or do {
            SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
            return {SUCCESS => 0, MSG => $DBI::errstr};
          };
        return {SUCCESS => 1, MSG => sprintf(q{updated %s}, join(', ', sort(keys ${$values_ref})))};
    } else {
        return {SUCCESS => 0, MSG => 'Test missing from object_def'};
    }
}

sub convert_to_flaticon {
    $dbhCaseSentry->do(q{CALL `update_icons_to_flaticon`()}) or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return 0 if ($DBI::errstr);
    return 1;
}

################################################
# Insert functions
################################################

sub insert_object_def_record {
    my $record = shift;
    my $id = validate_new_record('object_def', $record);
    if ($id) {
        SG::Logger->err("[$$][insert_object_def_record][Device already exists: od_id: $id]");
        return {SUCCESS => 0, MSG => 'Device already exists'};
    }

    # OVERIDE: Filter to never insert specific tests
    if ($record->{instance} ~~ @banned) {
        return {SUCCESS => 0, MSG => 'Test is banned from tool-kit'};
    }

    my @columns = &get_columns('object_def', 'CaseSentry');
    my (@insert_column, @insert_values);

    foreach my $column (@columns) {
        if (defined $record->{$column}) {

            # Add sanitization to escape qoutes
            $record->{$column} =~ s/\'/\\'/g;
            push @insert_column, $column;
            push @insert_values, $record->{$column};
        }
    }
    my $query
      = "INSERT INTO `object_def` (`"
      . join("`,`", @insert_column)
      . "`) VALUES ('"
      . join("','", @insert_values) . "')";

    # Unqoute now()
    $query =~ s/'now\(\)'/now()/g;
    SG::Logger->debug("[$$][insert_object_def_record][QUERY][$query]");
    $dbhCaseSentry->do($query) or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return {SUCCESS => 0, MSG => 'Mysql Error'} if ($DBI::errstr);
    return {SUCCESS => 1};
}

sub insert_snmp_credential_record {
    my $record = shift;
    my @columns = &get_columns('snmp_credential', 'CaseSentry');

    my (@insert_column, @insert_values);
    foreach my $column (@columns) {
        if (defined $record->{$column}) {
            push @insert_column, $column;
            push @insert_values, $record->{$column};
        }
    }
    my $query
      = "INSERT INTO `snmp_credential` (`"
      . join("`,` ", @insert_column)
      . "`) VALUES ('"
      . join("',' ", @insert_values) . "') ";

    # Unqoute now()
    $query =~ s/'now\(\)'/now()/gi;
    SG::Logger->debug("[$$][insert_snmp_credential_record][QUERY][$query]");
    my $sth = $dbhCaseSentry->prepare($query);
    $sth->execute() or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    my $insert_id = $sth->{mysql_insertid};
    return 0 if ($DBI::errstr);
    return $insert_id;
}

sub insert_snmp_plugin_def_record {
    my $record = shift;

    my $name = validate_new_record('snmpPluginDef', $record);
    if ($name) {
        SG::Logger->warn("[$$][insert_snmp_plugin_def_record][Record already found: $name]");
        return -1;
    }
    my @columns = &get_columns('snmpPluginDef', 'CaseSentry');
    my (@insert_column, @insert_values);
    foreach my $column (@columns) {
        if (defined $record->{$column}) {
            push @insert_column, $column;
            push @insert_values, $record->{$column};
        }
    }
    my $query
      = "INSERT IGNORE INTO `snmpPluginDef` (`"
      . join("`,`", @insert_column)
      . "`) VALUES ('"
      . join("','", @insert_values) . "')"
      . 'ON DUPLICATE KEY UPDATE `normalValues`=VALUES(`normalValues`), `criticalValues`=VALUES(`criticalValues`), `oid`=VALUES(`oid`), `type`=VALUES(`type`) ';

    if ('processName' ~~ @insert_column) {
        $query .= q{, `processName`=VALUES(`processName`)};
    }

    # Unqoute now()
    $query =~ s/'now\(\)'/now()/g;
    SG::Logger->debug("[$$][insert_snmp_plugin_def_record][QUERY][$query]");
    $dbhCaseSentry->do($query) or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return 1;
}

sub insert_location_record {
    my $record = shift;
    my @columns = &get_columns('location', 'CaseSentry');
    my (@insert_column, @insert_values);
    foreach my $column (@columns) {
        if (defined $record->{$column}) {
            push @insert_column, $column;
            push @insert_values, $record->{$column};
        }
    }
    my $query
      = "INSERT IGNORE INTO `location` (`"
      . join("`,`", @insert_column)
      . "`) VALUES ('"
      . join("',' ", @insert_values) . "')";

    SG::Logger->debug("[$$][insert_location_record][QUERY][$query]");
    $dbhCaseSentry->do($query) or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return 1;
}

sub insert_object_def_entity_group {
    my $object_def_id = shift;
    my $eGroup_id     = shift;
    $dbhCaseSentry->do(sprintf(q{INSERT IGNORE def_entity_grouping_type VALUES ('',%d,%d)}, $eGroup_id, $object_def_id))
      or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return 0 if ($DBI::errstr);
    return 1;
}

sub insert_object_def_meta {
    my $object_def_id = shift;
    my $meta_key      = shift;
    my $meta_value    = shift;
    $dbhCaseSentry->do("INSERT IGNORE INTO object_def_meta VALUES (NULL, $object_def_id, '$meta_key', '$meta_value')")
      or SG::Logger->err(sprintf(q{[%d][%s]}, $$ . $DBI::errstr));
    return 0 if ($DBI::errstr);
    return 1;
}

################################################
# Remove functions
################################################

sub remove_test {
    my $name     = shift;
    my $method   = shift;
    my $instance = shift;
    my $sql      = qq{DELETE FROM object_def WHERE `method`='$method' AND `instance`='$instance' AND `name`='$name';};
    SG::Logger->debug("[$$][add_exception][QUERY][$sql]");
    $dbhCaseSentry->do($sql);

    # TODO: ungroup test

    check_for_method_correlation($name, $method, $instance);

    if ($DBI::errstr) {
        SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
        return {SUCCESS => 0, MSG => $DBI::errstr};
    } elsif (&validate_new_record('object_def', {entity => "$name:$method:$instance"})) {
        return {SUCCESS => 0, MSG => 'Failed to remove test'};
    } else {
        return {SUCCESS => 1};
    }
}

sub check_for_method_correlation {
    my $name     = shift;
    my $method   = shift;
    my $instance = shift;
    my $entity   = "$name:$method:$instance";

    if (validate_new_record('def_entity_correlation', {entity => $entity})) {
        SG::Logger->debug(
            sprintf(
                q{[%d][check_for_method_correlation][Found Correlation][Sending entityDeleted message for %s]},
                $$, $entity
            )
        );
        require DecisionEngine;
        DecisionEngine::sendDecisionEngineMessage($name, 'ALARM', $method, 'entityDeleted', $entity, $dbhCaseSentry);
    }
}

# Checks if we should use flaticons. We should only use flaticons if the
# patch level is 5.2+
sub should_run_flaticon_conversion {
    my $cs_version  = &get_cs_version();
    my $release_tag = &get_release_tag_version();
    my ($major_version, $minor_version) = split(/\./, $release_tag);

    # If the CS version is greater than 4,
    # and if the CS version and the major version match,
    # and if the minor version is greater or equal to 2,
    # then use flaticons
    if ($cs_version > 4 && $cs_version == $major_version && $minor_version >= 2) {
        return 1;
    }

    return 0;
}

################################################
# Get functions
################################################

sub get_object_def_node_id {
    my $name = shift;

    if (!$name) {
        SG::Logger->err("[$$][get_object_def_node_id][No name passed for lookup]");
        return 0;
    } else {
        my $id
          = $dbhCaseSentry->selectrow_array(
            "SELECT id FROM object_def WHERE `name` = '$name' AND `method`='GRP' AND `instance`='NODE'")
          or ($DBI::errstr
            ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
            : SG::Logger->debug("[No results for name: $name]"));
        if ($id) {
            return $id;
        } else {
            SG::Logger->err("[$$][get_object_def_node_id][No NODE id found for $name]");
            return 0;
        }
    }
}

sub get_locations {
    my $where = shift || '';
    my $locations
      = $dbhCaseSentry->selectall_hashref(
        "SELECT id, address1, address2, city, region, postal_code, name, country FROM location", ['name'])
      or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return $locations || 0;
}

sub get_location_id {
    my $location_name = shift;
    my $location_id   = $dbhCaseSentry->selectrow_array("SELECT id FROM location WHERE name = '$location_name'")
      or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return (defined $location_id) ? $location_id : 0;
}

sub get_columns {
    my $table = shift;
    my $db    = shift;
    my @return;
    my $sql   = "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = ? AND TABLE_SCHEMA = ? ";
    my $query = $dbhCaseSentry->prepare($sql);
    SG::Logger->debug("[$$][get_columns][QUERY][$sql]");
    $query->execute($table, $db) or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));

    while (my $column = $query->fetchrow_array()) {
        push @return, $column;
    }
    $query->finish();
    return @return;
}

sub get_monitored_tests {
    my $device_name = shift;

    # TODO: Possibly change DB to Object and not main
    my $tests = &get_all_hashref(
        qq{SELECT o.method, o.instance, o.normal_status, o.caseworthy, o.depend
                FROM object_def o
                WHERE o.name = '$device_name' AND o.instance != 'node'}, ['method', 'instance']
    );
    return $tests;
}

sub get_max_id {
    my $table = shift;
    my $id    = $dbhCaseSentry->selectrow_array("SELECT max(id) FROM $table");
    return $id;
}

sub get_duplicate_tests {
    my $name  = shift;
    my $tests = &get_all_hashref(
        qq{
        SELECT z.method, z.key, z.tests, z.Count
        FROM (
        SELECT o.method, p.oid as `key`, GROUP_CONCAT(DISTINCT(p.Name) SEPARATOR ',') AS tests, COUNT(*) AS Count
        FROM CaseSentry.object_def AS o
        JOIN CaseSentry.snmpPluginDef AS p ON o.instance = p.Name AND o.method != 'THRESH'
        WHERE p.Type != 'process'
        AND o.name = '$name'
        GROUP BY o.name, p.oid

        UNION ALL

        SELECT o.method, p.ProcessName as `key`, GROUP_CONCAT(DISTINCT(p.Name) SEPARATOR ',') AS test, COUNT(*) AS Count
        FROM CaseSentry.object_def AS o
        JOIN CaseSentry.snmpPluginDef AS p ON o.instance = p.Name AND o.method != 'THRESH'
        WHERE p.Type = 'process'
        AND o.name = '$name'
        GROUP BY o.name, p.ProcessName

        UNION ALL

        SELECT o.method, p.sCommandLine as `key`, GROUP_CONCAT(DISTINCT(p.sName) SEPARATOR ',') AS Tests, COUNT(*) AS Count
        FROM CaseSentry.object_def AS o
        JOIN CaseSentry.lu_plugin AS p ON o.instance = p.sName  AND o.method != 'THRESH'
        AND o.name = '$name'
        GROUP BY o.name, p.sCommandLine
        ) AS z
        WHERE Count > 1
    }, ['method', 'key']
    ) or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return $tests;
}

sub get_all_hashref {
    my $sql  = shift;
    my @args = @_;
    my $hash = $dbhCaseSentry->selectall_hashref($sql, @args)
      or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return $hash || 0;
}

sub get_device_groups {
    my $device_name = shift;
    my $sql         = q{SELECT `child` FROM `dependency_edges` WHERE `child` LIKE '%:GRP:%' AND `parent`= ? };
    my @children;
    my $query = $dbhCaseSentry->prepare($sql);
    $query->execute("$device_name:ICMP:") or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    while (my $child = $query->fetchrow_array()) {
        push @children, $child;
    }

    my @groups;

    # Cycle through all the children till we have nothing left
    while ($_ = shift @children) {

        if (s/:grp:$//i) {

            # skip if its already in groups to prevent infinite loops
            next if ($_ ~~ @groups);
            push @groups, $_;
        }

        my $query = $dbhCaseSentry->prepare($sql);
        $query->execute($_) or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
        while (my $child = $query->fetchrow_array()) {
            push @children, $child;
        }
    }

    return @groups;
}

sub get_mrtg_dir {
    use ConfigTable qw( getCSConfigValue );

    return getCSConfigValue($dbhCaseSentry, 'CFGs', 'MrtgDirectories');
}

sub get_cs_version {
    my $csVersion = $dbhCaseSentry->selectrow_array(q{ SELECT value FROM constants WHERE name='SAMPSON_VERSION' });

    return $csVersion;
}

sub get_release_tag_version {
    my $releaseTag = '';
    my $patchLevel = $dbhCaseSentry->selectrow_array(q{ SELECT `value` FROM `sys_param` WHERE `param` = 'PatchLevel' });

    if ($patchLevel =~ /-(\d+\.\d+(?:\.\d+)?)-?/) {
        $releaseTag = $1;
    }

    return $releaseTag;
}

##############################
# Standards
##############################
sub get_standards_targets {
    my $device_name = shift;
    my $standards   = &get_all_hashref(
        qq{SELECT t.method AS method, t.instance AS instance,
            t.instance_regex AS regex, sdt.optional AS device_template_optional, stt.optional AS template_target_optional
            FROM object_def AS o
            JOIN standards_sku_devices AS ssd ON o.standards_sku_id = ssd.sku_id
            JOIN standards_devices AS sd ON ssd.device_id = sd.id AND sd.id = o.standards_device_id
            JOIN standards_device_templates AS sdt ON sd.id = sdt.device_id AND sdt.optional=0
            JOIN standards_templates AS st ON sdt.template_id = st.id
            JOIN standards_template_targets AS stt ON st.id = stt.template_id
            JOIN standards_targets AS t ON stt.target_id = t.id
            WHERE o.instance = 'NODE' AND t.method !='IF'
            AND o.name = '$device_name'

        UNION DISTINCT

        SELECT t.method AS method, t.instance AS instance, t.instance_regex AS regex, 0 AS device_template_optional, stt.optional AS template_target_optional
            FROM object_def AS o
            JOIN standards_object_def_templates AS sodt ON o.id = sodt.object_def_id
            JOIN standards_templates AS st ON sodt.standards_template_id = st.id
            JOIN standards_template_targets AS stt ON st.id = stt.template_id
            JOIN standards_targets AS t ON stt.target_id = t.id
            WHERE o.instance = 'NODE' AND t.method !='IF'
            AND o.name = '$device_name'}, ['method', 'instance']
    );
    return $standards;
}

sub get_standards_targets_by_id {
    my $standards_sku_id    = shift;
    my $standards_device_id = shift;
    my $standards           = &get_all_hashref(
        qq{SELECT t.method AS method, t.instance AS instance, t.instance AS test_name,
            t.instance_regex AS regex, sdt.optional AS device_template_optional, stt.optional AS template_target_optional
            FROM standards_sku_devices AS ssd
            JOIN standards_devices AS sd ON ssd.device_id = sd.id
            JOIN standards_device_templates AS sdt ON sd.id = sdt.device_id AND sdt.optional=0
            JOIN standards_templates AS st ON sdt.template_id = st.id
            JOIN standards_template_targets AS stt ON st.id = stt.template_id
            JOIN standards_targets AS t ON stt.target_id = t.id
            WHERE t.method !='IF' AND ssd.sku_id = $standards_sku_id AND sd.id = $standards_device_id
        }, ['method', 'instance']
    );
    return $standards;
}

sub get_standards_targets_info {
    return &get_all_hashref(q{SELECT * FROM standards_targets}, ['method', 'instance']);
}

##############################
# Exceptions
##############################

sub get_exceptions {
    my $device_name = shift;
    my $tests       = &get_all_hashref(
        qq{SELECT s.method, s.instance, s.notes
        FROM object_def AS o
        JOIN standards_exceptions AS s ON o.id = s.object_def_id
        WHERE o.instance = "NODE"
        AND o.name = '$device_name'
        ORDER BY LOWER(o.name), s.method, s.instance}, ['method', 'instance']
    );
    return $tests;
}

sub add_exception {
    my $name     = shift;
    my $method   = shift;
    my $instance = shift;
    my $notes    = shift;
    my $id       = get_object_def_node_id($name);

    $notes = 'Manually marked as an exception' unless $notes;

    if ($id) {

        my $sql
          = qq{INSERT IGNORE INTO standards_exceptions VALUES ($id, '$method', '$instance', 'cs-tool-kit', now(), '$notes')}
          . q{ ON DUPLICATE KEY UPDATE `user`=VALUES(`user`), `timestamp`=now(), `notes`= VALUES(`notes`)};
        SG::Logger->debug("[$$][add_exception][QUERY][$sql]");
        $dbhCaseSentry->do($sql);

        if ($DBI::errstr) {
            SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
            return 0;
        } else {
            return 1;
        }
    }
}

sub remove_exception {
    my $name     = shift;
    my $method   = shift;
    my $instance = shift;
    my $id       = get_object_def_node_id($name);
    if ($id) {
        my $sql
          = qq{DELETE FROM standards_exceptions WHERE `object_def_id`='$id' AND `method`='$method' AND `instance` = '$instance';};
        SG::Logger->debug("[$$][add_exception][QUERY][$sql]");
        $dbhCaseSentry->do($sql);
        if ($DBI::errstr) {
            SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
            return 0;
        } else {
            return 1;
        }
    } else {
        return 1;
    }
}

##############################
# SNMP Credentials
##############################

sub get_icm_credentials_by_ip {
    my $ip          = shift;
    my $credentials = $dbhCaseSentry->selectall_hashref(
        "SELECT d.ip_address AS ip, cr.username AS user, cr.password AS pass FROM ICM.devices d JOIN ICM.lu_credentials lc ON lc.dev_id = d.id JOIN ICM.credentials cr ON cr.id = lc.cred_id WHERE d.ip_address = '$ip'",
        ['ip']
      )
      or ($DBI::errstr
        ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
        : SG::Logger->debug("[$$][get_icm_credentials_by_ip][No results for ip: $ip"));
    if (defined $credentials && keys $credentials) {
        return $credentials;
    } else {
        return;
    }
}

sub get_snmp_credential_by_ip {
    use csSnmp;
    my $ip = shift;
    return getCsSnmpSessionParms($dbhCaseSentry, $ip);
}

sub get_snmp_credential_by_string {
    my $community = shift;
    if (!$community) {
        SG::Logger->err("[$$][get_snmp_credential_by_string][No Community passed for lookup]");
        return;
    }
    my $credentials
      = $dbhCaseSentry->selectall_hashref("SELECT * FROM snmp_credential WHERE `community`='$community'", ['id'])
      or ($DBI::errstr
        ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
        : SG::Logger->debug("[$$][get_snmp_credential_by_string][No results for string: $community]"));
    if (keys $credentials) {
        return $credentials;
    } else {
        return;
    }
}

sub get_snmp_credential_by_id {
    my $id = shift;
    my $credentials = $dbhCaseSentry->selectrow_hashref("SELECT * FROM snmp_credential WHERE id='$id'", ['id'])
      or ($DBI::errstr
        ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
        : SG::Logger->debug("[$$][get_snmp_credential_by_id][No results for id: $id]"));
    return to_json($credentials);
}

sub associate_snmp_credential {
    my $name    = shift;
    my $snmp_id = shift;

    if (!$name) {
        SG::Logger->err("[$$][add_snmp_credential][No name passed for lookup]");
        return 0;
    } elsif (!$snmp_id) {
        SG::Logger->err("[$$][add_snmp_credential][No snmp id passed for lookup]");
        return 0;
    }

    my $id
      = $dbhCaseSentry->selectrow_array(
        "SELECT id FROM object_def WHERE `name` = '$name' AND `method`='GRP' AND `instance`='NODE'")
      or ($DBI::errstr
        ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
        : SG::Logger->debug("[$$][associate_snmp_credential][No results for name: $name]"));

    $dbhCaseSentry->do(sprintf('INSERT INTO lu_object_def_snmp_credential VALUES (%s,%s)', $id, $snmp_id));

    if ($DBI::errstr) {
        SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
        return 0;
    }
    return 1;
}

sub associate_standards_object_def_templates {
    my $name        = shift;
    my $template_id = shift;
    my $id          = &get_object_def_node_id($name);
    unless ($id) {
        SG::Logger->err(
            sprintf(q{[%d][associate_standards_object_def_templates][No object_def id for name: %s]}, $$, $name));
    } else {
        my $standards_template_id = $dbhCaseSentry->selectrow_array(
            sprintf(
                q{SELECT standards_template_id FROM standards_object_def_templates WHERE object_def_id = %d AND standards_template_id = %d},
                $id, $template_id
            )
        );
        if ($standards_template_id) {
            SG::Logger->debug(
                sprintf(
                    q{[%d][associate_standards_object_def_templates][%s][object_def_id: %d is already associated to standards_template_id: %d]},
                    $$, $name, $id, $template_id
                )
            );
            return;
        } else {
            SG::Logger->debug(
                sprintf(
                    q{[%d][associate_standards_object_def_templates][%s][Associating object_def_id: %d to standards_template_id: %d]},
                    $$, $name, $id, $template_id
                )
            );
            $dbhCaseSentry->do(
                sprintf(
                    q{INSERT IGNORE INTO `CaseSentry`.`standards_object_def_templates` VALUES (%d, %d)},
                    $id, $template_id
                )
            ) or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
        }
    }
}

1;
