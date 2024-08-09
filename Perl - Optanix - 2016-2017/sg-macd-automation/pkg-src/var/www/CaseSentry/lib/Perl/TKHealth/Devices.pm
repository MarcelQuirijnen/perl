#Module for specific device specific checks


package TKHealth::Devices;
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
use Array::Utils qw(:all);

sub caseworthyHealth {
    my $hDb = shift or die("[nonCaseworthyCheck] No database connection passed.");

    #get a count of entities non-caseworthy so we can display a limited amount of records
    my $count;
    my @entities;
    my $query
      = q{SELECT entity FROM object_def WHERE caseworthy='N' AND name NOT LIKE '%CaseSentry%' AND name NOT LIKE 'IP_%' AND name NOT LIKE '%localhost%'};
    my $sql = $hDb->prepare($query);
    $sql->execute();

    while (my $entity = $sql->fetchrow_array()) {
        push @entities, $entity;
    }

    if (@entities && scalar(@entities) > 0) {
        return ({RESULT => "FAIL", ERROR => scalar(@entities) . " entities are set to to non-caseworthy."});
    } else {
        return ({RESULT => "PASS", ERROR => "No entities in CaseSentry are non-caseworthy!"});
    }
}

sub deviceCount {
    my $hDb = shift or die("[groupCount] No database connection passed.");
    my $total
      = $hDb->selectrow_array(
        q{SELECT COUNT(*) FROM object_def WHERE instance = 'NODE' AND name NOT LIKE '%CaseSentry%' AND name NOT LIKE 'IP_%' AND name NOT LIKE '%localhost%'}
      );
    if ($total) {
        return (
            {
                RESULT => "CHECK",
                ERROR  => $total
                  . " entities were found with instance of NODE. Please check against SAK for total device count."
            }
        );
    } else {
        return ({RESULT => "FAIL", ERROR => "No entities are in monitoring for GRP:NODE."});
    }
}

sub interfaceCount {
    my $hDb = shift or die("[interfaceCheck] No database connection passed.");
    my $total = $hDb->selectrow_array(q{SELECT COUNT(*) FROM object_def WHERE method='IF'});
    if ($total > 0) {
        return (
            {RESULT => "CHECK", ERROR => "There are " . $total . " entities in monitoring for interfaces. Review."});
    } else {
        return ({RESULT => "FAIL", ERROR => "There are no entities in monitoring for interfaces!"});
    }
}

sub monitorOptionsHealth {
    my $hDb = shift or die("[nonCaseworthyCheck] No database connection passed.");

    #get a count of monitor options not equal to 1 so we can display a limited amount of records
    my $count;
    my @entities;
    my $query
      = q{SELECT entity FROM object_def WHERE monitor_options <>'1' AND name NOT LIKE '%CaseSentry%' AND name NOT LIKE 'IP_%' AND name NOT LIKE '%localhost%'};
    my $sql = $hDb->prepare($query);
    $sql->execute();

    while (my $entity = $sql->fetchrow_array()) {
        push @entities, $entity;
    }

    if (@entities && scalar(@entities) > 0) {
        return (
            {
                RESULT => "FAIL",
                ERROR  => scalar(@entities) . " entities are set to a monitor_options value not equal to 1."
            }
        );
    } else {
        return ({RESULT => "PASS", ERROR => "All entities have a monitor_options value of 1!"});
    }
}

sub unassignedHealth {
    my $hDb = shift or die("[unassignedCheck] No database connection passed.");
    my @names;
    my $query
      = q{SELECT DISTINCT o.name FROM object_def o LEFT OUTER JOIN dependency_edges d ON o.entity=d.parent WHERE d.child='~Unassigned:GRP:' order by o.name};
    my $sql = $hDb->prepare($query);
    $sql->execute();
    while (my $name = $sql->fetchrow_array()) {
        push @names, $name;
    }
    if (@names && scalar(@names) > 0) {
        return ({RESULT => "FAIL", ERROR => scalar(@names) . " unassigned entities exist."});
    } else {
        return ({RESULT => "PASS", ERROR => "No unassigned entities were found."});
    }
}

sub normalStatusHealth {
    my $hDb = shift or die("[normalStatusHealth] No database connection passed.");

    #get a count of entities non-caseworthy so we can display a limited amount of records
    my $count;
    my @entities;
    my $query
      = q{SELECT entity FROM object_def WHERE normal_status='0' AND name NOT LIKE '%CaseSentry%' AND name NOT LIKE 'IP_%' AND name NOT LIKE '%localhost%'};
    my $sql = $hDb->prepare($query);
    $sql->execute();

    while (my $entity = $sql->fetchrow_array()) {
        push @entities, $entity;
    }

    if (@entities && scalar(@entities) > 0) {
        return ({RESULT => "FAIL", ERROR => scalar(@entities) . " entities are set to to normal status DOWN."});
    } else {
        return ({RESULT => "PASS", ERROR => "No entities in CaseSentry are normal status DOWN."});
    }
}
