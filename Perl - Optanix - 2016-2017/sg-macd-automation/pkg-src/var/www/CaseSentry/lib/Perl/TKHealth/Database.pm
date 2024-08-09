#Module for specific database health/configuration checks

#jkulzer 10-20-2015

package TKHealth::Database;
require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use lib '/usr/share/sg-macd-automation/lib/Perl';
use lib '/var/www/CaseSentry/lib/Perl';
use JSON;
use ConnectVars;
use SG::Logger;
use DateTime;
use IPC::Open3;
use Array::Utils qw(:all);
use TKTools::Plugins::Implementation::TechLeadAudit;

sub syslogHealth {
    my $hDb = shift or die("[logsCheck] No database connection passed.");
    my $hasViewSyslog;
    eval { $hasViewSyslog = getNamedDBConnection('ViewSyslog') };
    if (defined($hasViewSyslog)) {
        my $trapDb = getConnection('snmptt') or do { SG::Logger->err($DBI::errstr); exit(1); };

        my $syslogSummarySql = q{    
            SELECT o.Name AS name, r.host AS host, COUNT(*) AS count 
            FROM CaseSentry.raw_syslog AS r
            LEFT JOIN CaseSentry.object_def AS o ON r.host = o.Ip_Addr_ipvx AND o.Instance='NODE'
            WHERE r.Gmt_Seconds > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 HOUR))
            GROUP BY r.host
            ORDER BY COUNT(*) LIMIT 50
        };
        my $syslogs = $hDb->selectall_hashref($syslogSummarySql, ['host']);
        if (defined $syslogs && keys($syslogs) > 0) {
            return (
                {
                    RESULT => "CHECK",
                    ERROR  => "Syslog information was found for the last hour, however will require manual review."
                }
            );
        } else {
            return (
                {
                    RESULT => "FAIL",
                    ERROR =>
                      "No syslog information found on the appliance in db_logins. Check configuration or determine if syslogs are required."
                }
            );
        }
    } else {
        return ({RESULT => "FAIL", ERROR => "No information was found for ViewSyslog in db_logins"});
    }
}

sub trapHealth {
    my $hDb = shift or die("[logsCheck] No database connection passed.");

#pull timestamp from either box
#grab snmptt and viewSyslog from appliance's db_logins for outputting purposes then use connectvars to grab the connection

    #Traps first
    my $hasSnmptt;
    eval { $hasSnmptt = getNamedDBConnection('snmptt') };
    if (defined($hasSnmptt)) {

        my $trapDb = getConnection('snmptt') or do { SG::Logger->err($DBI::errstr); exit(1); };

        my $trapSummarySql = q{    
            SELECT o.Name AS name, r.hostname AS host, COUNT(*) AS count
            FROM snmptt.snmptt AS r
            LEFT JOIN CaseSentry.object_def AS o ON r.hostname = o.Ip_Addr_ipvx AND o.Instance='NODE'
            WHERE r.Gmt_Seconds > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 HOUR))
            GROUP BY r.hostname
            ORDER BY COUNT(*) LIMIT 50
        };
        my $traps = $hDb->selectall_hashref($trapSummarySql, ['host']);
        if (defined $traps && keys($traps) > 0) {
            return (
                {
                    RESULT => "CHECK",
                    ERROR  => "Trap information was found for the last hour, however will require manual review."
                }
            );
        } else {
            return (
                {
                    RESULT => "FAIL",
                    ERROR =>
                      "No trap information found on the appliance in db_logins. Check configuration or determine if traps are required."
                }
            );
        }
    } else {
        return ({RESULT => "FAIL", ERROR => "No information was found for snmptt in db_logins"});
    }
}

sub replicationHealth {
    my $hostIP  = shift;
    my $command = "mysql -h sampson-web2 -e \"show slave status\\G\" | grep 'Seconds_Behind'";
    my $pid     = open3('<&CHILD_STDIN', my $stout, '>&STDERR', $command,);
    my @lines;
    while (<$stout>) {
        next if (/^$/);
        if ($_ =~ m/Seconds_Behind_Master/) { $_ =~ s/(.*): //; chomp($_); push(@lines, $_); }
    }
    waitpid($pid, 0);
    close($stout);
    if (@lines && scalar(@lines) > 0) {
        if ($lines[0] eq 'NULL') {
            return ({RESULT => "FAIL", ERROR => "Replication is behind or stopped."});
        } elsif ($lines[0] <= 600) {
            return ({RESULT => "PASS", ERROR => "Replication is " . $lines[0] . " seconds behind."});
        }
    } else {
        return ({RESULT => "FAIL", ERROR => "Unable to obtain replication status"});
    }
}

sub cdrDataHealth {
    my $hDb = shift or die("[cdrDateCheck] No database connection passed.");
    my $dt = shift;

    my $hasCDR;
    eval { $hasCDR = getNamedDBConnection('CDR') };
    if (defined($hasCDR)) {
        my $cdrDb     = getConnection('CDR') or do { SG::Logger->err($DBI::errstr); exit(1); };
        my $yearMonth = $dt->year() . "_" . $dt->month();
        my $cdrHome   = "CDR_" . $yearMonth;
        my $query
          = qq{SELECT publisher, MAX(FROM_UNIXTIME(dateTimeConnect)) AS maxTime FROM $cdrHome.CallDetailRecord group by publisher};
        my $cdrData = $cdrDb->selectall_hashref($query, ['publisher'])
          or return ({RESULT => "FAIL", ERROR => "No database exists for the given month - $yearMonth"});
        if (defined $cdrData && keys($cdrData) > 0) {
            return ({RESULT => "PASS", ERROR => $cdrData});
        } else {
            return ({RESULT => "FAIL", ERROR => "There was no data found in CDR_" . $yearMonth});
        }
    } else {
        return ({RESULT => "FAIL", ERROR => "Not able to connect to information found in db_logins shown above"});
    }
}

sub dbLoginsHealth {
    my $host = shift or die("[dbLoginsHealth] No Appliance IP Was passed");
    my $configFile = "/etc/CaseSentry/db_logins.conf";
    my @lines;
    my @LOCAL_IPS = TKTools::Plugins::Implementation::TechLeadAudit::gather_nic_ips(undef);
    push(@LOCAL_IPS, '127.0.0.1');
    my $cmd = 'cat ' . $configFile;
    if (!defined $host || $host ~~ @LOCAL_IPS) {
        $host  = '127.0.0.1';
        @lines = `$cmd`;
    } else {
        my $remote_command = "/usr/bin/ssh -C -i /home/sampson/.ssh/id_rsa -lsampson " . $host . " '" . $cmd . "'";
        @lines = `$cmd`;
    }
    my $confData = join('', @lines);
    my $jsonData = eval { from_json($confData) };
    if (!$jsonData) {
        $jsonData = from_json('{}');
    }
    return $jsonData;
}

sub autoOpenThresholdHealth {
    my $hDb        = shift or die("[autoOpenThreshCheck] No database connection passed.");
    my $query      = q{ SELECT * FROM CaseSentryConfig WHERE parm = 'suppress auto_open'};
    my $supression = $hDb->selectall_hashref($query, ['parm']);
    if (defined $supression && keys($supression) > 0) {
        if ($supression->{'suppress auto_open'}->{value} == 1) {
            return (
                {
                    RESULT => "CHECK",
                    ERROR =>
                      "suppress auto_opend - is enabled in CaseSentryConfig! VERIFY THESE SETTINGS IN CaseSentryConfig, should it be enabled?"
                }
            );
        } elsif ($supression->{'suppress auto_open'}->{value} == 0) {
            return (
                {
                    RESULT => "CHECK",
                    ERROR =>
                      "suppress auto_opend - is installed, however disabled. VERIFY THESE SETTINGS IN CaseSentryConfig, should it be disabled?"
                }
            );
        }
    } else {
        return ({RESULT => "CHECK", ERROR => "This feature is not installed in CaseSentryConfig, should it be?"});
    }
}

sub oidHealth {
    my $hDb = shift or die("[oidCheck] No database connection passed.");

    my $query
      = q{ SELECT spd.name, pt.oid, spd.oid FROM CaseSentry.snmpPluginDef spd  JOIN Automation.polled_targets pt ON spd.name=pt.instance AND pt.method='SNMP' WHERE pt.oid != spd.oid GROUP BY spd.name };
    my $oids = $hDb->selectall_hashref($query, ['name']);

    if (defined $oids && keys($oids) > 0) {
        return (
            {
                RESULT => "FAIL",
                ERROR =>
                  "Mismatched OID's exist. SELECT spd.name, pt.oid, spd.oid FROM CaseSentry.snmpPluginDef spd  JOIN Automation.polled_targets pt ON spd.name=pt.instance AND pt.method='SNMP' WHERE pt.oid != spd.oid GROUP BY spd.name"
            }
        );
    } else {
        return ({RESULT => "PASS", ERROR => "No mismatched ID's found"});
    }
}

#TODO: enhnce check to fail on if BOTH queues exist OR if one queue is missing a user login
sub tacQueueHealth {
    my $hDb = shift or die("[checkTacQueue] No database connection passed.");
    my $custType = shift;
    my @base;
    if ($custType eq "CaseSentry") {
        @base = qw( SG_ICM SG_IPT1 SG_IPT2 sgmap SG_Foundation );
    } else {
        @base = qw( ROS_ICM ROS_IPT1 ROS_IPT2 ROS_MAP ROS_Foundation );
    }
    my @retrieved;
    my $query = "SELECT login FROM user WHERE login IN ('" . join("', '", @base) . "') AND deleted != 'T'";
    my $sql = $hDb->prepare($query);
    $sql->execute();
    while (my $login = $sql->fetchrow_array()) {
        push @retrieved, $login;
    }
    if (@retrieved && scalar(@retrieved) > 0) {
        my @comparison = array_minus(@base, @retrieved);
        if (@comparison && scalar(@comparison) > 0) {
            return (
                {
                    RESULT => "FAIL",
                    ERROR  => "Found missing user queues from the user database, or they are set to deleted: ('"
                      . join("', '", @comparison) . "')"
                }
            );
        } else {
            return (
                {RESULT => "PASS", ERROR => "Found all logins for user queue: ('" . join("', '", @retrieved) . "')"});
        }
    } else {
        return ({RESULT => "FAIL", ERROR => "Found no user logins for the appropriate Queues!"});
    }
}

sub axlCredsHealth {
    my $hDb = shift or die("[axlCheck] No database connection passed.");
    my $count;
    my @devices;
    my $query
      = q{SELECT IF(INSTR(entity, ':'), LEFT(entity, INSTR(entity, ':') - 1), 'NULL'), axlusername, axlpassword FROM def_ccm_credentials};
    my $sql = $hDb->prepare($query);
    $sql->execute();
    while (my ($name, $username, $password) = $sql->fetchrow_array()) {
        if ($password eq '' || $username eq '') {
            $count++;
            push @devices, $name;
        }
    }
    if (!$count) {
        return ({RESULT => "PASS", ERROR => "All CUCM devices appear to have non-null entires for username/password"});
    } else {
        return ({RESULT => "FAIL", ERROR => "CUCM's are missing credentials" . join(", ", @devices)});
    }
}
