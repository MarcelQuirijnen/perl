#!/usr/bin/perl

use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use lib "/var/www/CaseSentry/lib/Perl";
use Getopt::Long;
use ConnectVars;
use csSnmp;
use Data::Dumper;
use JSON;
use MIME::Base64;
use SNMP_LowImpact2;
use IO::Socket::INET;
use processLock;

my $GROUP_LIKE        = 0;
my $CATEGORY_NAME     = 0;
my $SUB_CATEGORY_NAME = 0;
my $SUB_CATEGORY_ID;
my $REAL_POLL       = 0;
my $FORMATTED_TRAPS = 0;

my $help   = 0;
my $debug  = 0;
my $input  = 0;
my $output = 0;
my $all    = 0;

GetOptions(
    "help"            => \$help,
    "debug"           => \$debug,
    "data=s"          => \$input,
    "out=s"           => \$output,
    "all"             => \$all,
    "category=s"      => \$CATEGORY_NAME,
    "sub-category=s"  => \$SUB_CATEGORY_NAME,
    "group-like=s"    => \$GROUP_LIKE,
    "real-poll"       => \$REAL_POLL,
    "formatted-traps" => \$FORMATTED_TRAPS,
);

sub help {
    print "USAGE:\n$0 --out <TSV FILE> <ip> <ip> <ip> ...\n",
      "$0 --out <TSV FILE> --all [--category <Category Name>] [--sub-category <Category Name>] [--group-like <Group Name>]\n",
      "Required Flags:\n", "\t --out          : File that TSV will be outputed to\n", "Optional Flags:\n",
      "\t --all          : Gather list of devices from object_def\n",
      "\t --real-poll    : Do not use raw_status of SNMP:agent\n",
      "\t --category     : Only validate devices in this category (enables --all by default)\n",
      "\t --sub-category : Includes Y/N if device is in this sub category\n",
      "\t --group-like   : Includes Y/N if device is in a group like the string passed\n",
      "\t --formatted-traps : Reach out to sampson-trapcollrvip and gathers IPs from formatted traps\n",
      "\t --debug        : enables debug output\n",;
    exit;
}

help() if ($help);

if (!$output && !$input) {
    print "Please include an output file using --out\n";
    help();
}

our $devices;
our $batch = new SNMP_LowImpact;
our %traps;

if ($FORMATTED_TRAPS) {
    print "Gathering traps from trapcoll... " if $debug;
    my $time = scalar(time);
    &get_trap_ips();
    print &time_to_execute(\$time), "\n" if $debug;
}

if ($CATEGORY_NAME and !$all) {
    warn "Did not specify --all with --category, enabling --all and disregaring any ips passed in as agruments.\n";
    $all = 1;
}

# Code for GUI audit tool
if ($input) {
    my $data = decode_json(decode_base64($input));
    my @ip_addrs;
    foreach my $device (@$data) {
        $devices->{$device->{ip_addr_ipvx}} = $device;
        push @ip_addrs, $device->{ip_addr_ipvx};

        #Set default values
        $devices->{$device->{ip_addr_ipvx}}->{ping}   = 0;
        $devices->{$device->{ip_addr_ipvx}}->{syslog} = 0;
        $devices->{$device->{ip_addr_ipvx}}->{snmptt} = 0;
        $devices->{$device->{ip_addr_ipvx}}->{snmp}   = 0;
        $devices->{$device->{ip_addr_ipvx}}->{axl}    = 0;
        $devices->{$device->{ip_addr_ipvx}}->{cdr}    = 0;
    }
    while (my @ips = splice(@ip_addrs, 0, 50)) {
        poll_devices(\@ips);
    }

    # encode a hash to pass back t GUI for results
    print encode_base64(encode_json($devices)) unless $debug;
    exit(1);
}

# Backend validation code
else {
    # Check for process lock
    my $sScriptName = '';
    getScriptName(\$sScriptName);
    my $sLockFile = checkLock($sScriptName);

    my $hDb = getConnection('Object');
    $hDb->{AutoCommit} = 1;
    $hDb->{'mysql_auto_reconnect'} = 1;
    my @ip_addrs;

    unless ($all) {
        while (my $ip = shift) {
            chomp($ip);
            if ($ip =~ m/^(?:\d{1,3}\.){3}\d{1,3}/) {
                push @ip_addrs, $ip;
            }
        }
    } else {
        my $sql = q{SELECT o.ip_addr_ipvx FROM object_def AS o };
        $sql
          .= q{JOIN object_def_category odc ON o.id = odc.object_def_id }
          . qq{JOIN lu_case_category lcc ON odc.category_id = lcc.id AND lcc.case_category = '$CATEGORY_NAME'}
          if $CATEGORY_NAME;
        $sql .= q{WHERE o.instance = "NODE" AND o.name NOT LIKE "%CaseSentry%" GROUP BY o.ip_addr_ipvx};
        my $mainquery = $hDb->prepare($sql) or die "Query Prepartion Failed!";
        $mainquery->execute() or die "Database query not made: $DBI::errstr";

        #print "Queueing devices\n";
        while (my ($ip) = $mainquery->fetchrow_array()) {
            push @ip_addrs, $ip;
        }

        if ($SUB_CATEGORY_NAME) {
            ($SUB_CATEGORY_ID)
              = $hDb->selectrow_array(qq{SELECT id FROM lu_case_category WHERE case_category = '$SUB_CATEGORY_NAME'});
            unless ($SUB_CATEGORY_ID) {
                print "Sub Category: $SUB_CATEGORY_NAME - ID Not found.\n";
                exit(0);
            }
        }
    }

    if (scalar(@ip_addrs) == 0) {
        warn "No ips!\n";
        help();
        exit;
    }

    # Build header
    my $header = "Name\tIp\tModel Number\t";
    $header .= ucfirst($GROUP_LIKE) . " Group\t" if $GROUP_LIKE;
    $header .= "$SUB_CATEGORY_NAME\t"            if $SUB_CATEGORY_NAME;
    $header .= "ICMP\tSNMP\tSyslog\tTraps\tSSH/Telnet\tWeb\n";

    # Print Header
    open FH, '>', $output;
    print FH $header;
    close FH;

    while (my @ips = splice(@ip_addrs, 0, 50)) {
        $devices = undef;
        build_hash(\@ips, $hDb);
        poll_devices(\@ips);
        print_tsv($hDb);
    }
    $hDb->disconnect();
}

sub print_tsv {
    my $hDb = shift;
    open FH, '>>', $output;

    #print FH "Name\tIp\tICMP\tSNMP\tSyslog\tTraps\tSSH\tTelnet\tWeb\n";
    foreach my $device (values $devices) {
        my $string = '';

        #Name
        $string .= $device->{name} . "\t";

        #Ip
        $string .= $device->{ip_addr_ipvx} . "\t";

        #Model Num
        $string .= $device->{model_num} . "\t";

        # Group
        if ($GROUP_LIKE) {
            my ($count)
              = $hDb->selectrow_array(
                    qq{SELECT count(*) FROM dependency_edges WHERE child like '\%$GROUP_LIKE%' AND parent like '}
                  . $device->{name}
                  . q{:icmp:'});
            if ($count) {
                $string .= "Y\t";
            } else {
                $string .= "N\t";
            }
        }

        #Sub category
        if ($SUB_CATEGORY_NAME) {
            if ($device->{sub_cat}) {
                $string .= "Y\t";
            } else {
                $string .= "N\t";
            }
        }

        #ICMP
        if ($device->{ping}) {
            $string .= "Y\t";
        } else {
            $string .= "N\t";
        }

        #SNMP
        if ($device->{snmp} eq 'N/A') {
            $string .= "N/A\t";
        } elsif ($device->{snmp}) {
            $string .= "Y\t";
        } else {
            $string .= "N\t";
        }

        #Syslog
        if ($device->{syslog}) {
            $string .= "Y\t";
        } else {
            $string .= "N\t";
        }

        #Traps
        if ($device->{snmptt}) {
            $string .= "Y\t";
        } else {
            $string .= "N\t";
        }

        #SSH/Telnet
        if ($device->{ports}->{tcp}->{22}->{open} or $device->{ports}->{tcp}->{23}->{open}) {
            $string .= "Y\t";
        } else {
            $string .= "N\t";
        }

        #Web
        if ($device->{ports}->{tcp}->{22}->{open}) {
            $string .= "Y\t";
        } else {
            $string .= "N\t";
        }
        print FH $string . "\n";
    }
    close FH;
}

sub build_hash {
    my @ip_addrs = @{$_[0]};
    my $hDb      = $_[1];
    foreach my $ip (@ip_addrs) {
        my $query
          = 'SELECT o.name, o.model_num, odc.category_id, os.status_level FROM object_def o '
          . q{LEFT JOIN object_status os ON o.name = os.name AND os.method = 'SNMP' }
          . q{AND (os.instance = 'agent' OR os.instance = 'agent-alt') AND os.status_type = 1 }
          . 'LEFT JOIN object_def_category odc ON o.id = odc.object_def_id ';
        $query .= qq{ AND odc.category_id = $SUB_CATEGORY_ID} if $SUB_CATEGORY_ID;
        $query .= q{ WHERE o.ip_addr_ipvx = ? AND o.instance = "NODE" AND o.name != '~CaseSentry' GROUP BY o.name};

        my $statement = $hDb->prepare($query) or die "Query Prepartion Failed!";
        $statement->execute($ip) or die "Database query not made: $DBI::errstr";
        my ($name, $model_num, $sub_cat, $status_level) = $statement->fetchrow_array();

        if ($name) {
            $devices->{$ip}->{name} = $name;
        } else {
            $devices->{$ip}->{name} = $ip;
        }
        $devices->{$ip}->{ip_addr_ipvx} = $ip;

        # Check to see if it is a member of the Sub Category
        if ($SUB_CATEGORY_ID) {
            if ($sub_cat && $sub_cat eq $SUB_CATEGORY_ID) {
                $devices->{$ip}->{sub_cat} = 1;
            } else {
                $devices->{$ip}->{sub_cat} = 0;
            }
        }

        # Check status level of SNMP:agent
        if ($status_level && $status_level == 2) {
            $devices->{$ip}->{status_level} = 1;
        } else {
            $devices->{$ip}->{status_level} = 0;
        }

        #Set default values
        $devices->{$ip}->{model_num} = $model_num || '';
        $devices->{$ip}->{ping}      = 0;
        $devices->{$ip}->{syslog}    = 0;
        $devices->{$ip}->{snmptt}    = 0;
        $devices->{$ip}->{snmp}      = 0;
        $devices->{$ip}->{axl}       = 0;
        $devices->{$ip}->{cdr}       = 0;

        my $csSnmpSessionParms = getCsSnmpSessionParms($hDb, $ip);
        unless ($csSnmpSessionParms) {
            $devices->{$ip}->{snmp}   = 'N/A';
            $devices->{$ip}->{csSnmp} = 'N/A';
        } elsif ($devices->{$ip}->{model_num} =~ /1721/) {
            $devices->{$ip}->{snmp}   = 'N/A';
            $devices->{$ip}->{csSnmp} = 'N/A';
        } else {
            $devices->{$ip}->{csSnmp} = {
                DestHost       => $ip,
                Timeout        => 5_000_000,
                Retries        => $csSnmpSessionParms->{'Retries'},
                UseEnums       => 1,
                UseSprintValue => 1,
                RemotePort     => $csSnmpSessionParms->{'RemotePort'} || 161,
                Version        => $csSnmpSessionParms->{'Version'} || 1,
                Community      => $csSnmpSessionParms->{'Community'} || 'public',
                SecName        => $csSnmpSessionParms->{'SecName'},
                SecLevel       => $csSnmpSessionParms->{'SecLevel'},
                AuthProto      => $csSnmpSessionParms->{'AuthProto'},
                AuthPass       => $csSnmpSessionParms->{'AuthPass'},
                PrivProto      => $csSnmpSessionParms->{'PrivProto'},
                PrivPass       => $csSnmpSessionParms->{'PrivPass'}
            };
            $devices->{$ip}->{snmp_ro} = $csSnmpSessionParms->{'Community'} || 'public';
        }
    }
}

sub poll_devices {
    my @ip_addrs = @{$_[0]};
    $batch = new SNMP_LowImpact;

    my $time = scalar(time);

    # Check ping
    print "Checking Ping... " if $debug;
    foreach my $line (split("\n", `fping @ip_addrs 2>/dev/null`)) {
        my ($ip, $result) = $line =~ m/([\d\.]+)\sis\s(\w+)/;
        $devices->{$ip}->{ping} = ($result eq 'alive') ? 1 : 0;
    }
    print &time_to_execute(\$time), "\n" if $debug;

    # Syslog
    print "Checking Syslog... " if $debug;
    my $syslogQuery
      = 'SELECT host, COUNT(host) FROM raw_syslog WHERE host IN ("' . join('","', @ip_addrs) . '") GROUP BY host';
    my $dbh = getConnection('ViewSyslog');
    my $statement = $dbh->prepare($syslogQuery) or die("Could not prepare statement. Error:" . $dbh->errstr . "\n");
    $statement->execute() or die("Could not execute statement. Error:" . $statement->errstr . "\n");

    while (my (@row) = $statement->fetchrow_array) {
        $devices->{$row[0]}->{syslog} = $row[1];
    }
    $dbh->disconnect();
    print &time_to_execute(\$time), "\n" if $debug;

    # Traps
    print "Checking Traps... " if $debug;
    my $snmpttQuery
      = 'SELECT hostname, COUNT(hostname) FROM snmptt WHERE hostname IN ("'
      . join('","', @ip_addrs)
      . '") GROUP BY hostname';
    my $snmpttdbh = getConnection('snmptt');
    $statement = $snmpttdbh->prepare($snmpttQuery)
      or die("Could not prepare statement. Error:" . $snmpttdbh->errstr . "\n");
    $statement->execute() or die("Could not execute statement. Error:" . $statement->errstr . "\n");

    while (my (@row) = $statement->fetchrow_array) {
        $devices->{$row[0]}->{snmptt} = $row[1];
    }
    $snmpttdbh->disconnect();
    foreach my $ip (@ip_addrs) {
        if (exists $traps{$ip}) {
            $devices->{$ip}->{snmptt} = 1;
        }
    }

    print &time_to_execute(\$time), "\n" if $debug;

    print "Checking Ports... " if $debug;
    foreach my $ip (@ip_addrs) {

        # If we cant ping it skip it
        unless ($devices->{$ip}->{ping} == 1) {
            next;
        }

        # Check ports
        $devices->{$ip}->{ports} = poll_ports($ip);

        # Check axl
        if ($devices->{$ip}->{ports}->{tcp}->{8443}->{open} == 1) {
            if (`curl -k https://$ip:8443/perfmonservice/services/PerfmonPort?wsdl 2>/dev/null`
                =~ m/requires HTTP auth/)
            {
                $devices->{$ip}->{axl} = 1;
            }
        }

        # Perform SNMP check
        my $poll = 1;    # variable to control if we want to add request or not
        if ($devices->{$ip}->{csSnmp} eq 'N/A' && $devices->{$ip}->{snmp} eq 'N/A') {

            # Do Nothing!
            $poll = 0;
        } elsif ($devices->{$ip}->{status_level} and $devices->{$ip}->{csSnmp}->{Version} and !$REAL_POLL) {
            $devices->{$ip}->{snmp} = $devices->{$ip}->{csSnmp}->{Version};
            $poll = 0;
        } elsif ($devices->{$ip}->{csSnmp}) {
            $devices->{$ip}->{csSnmp}->{Timeout} *= 1_000_000 if $devices->{$ip}->{csSnmp}->{Timeout} < 10;
            $batch->add_host($devices->{$ip}->{csSnmp});
        } else {
            $batch->add_host(
                {
                    DestHost   => $ip,
                    Timeout    => 5_000_000,
                    RemotePort => 161,
                    Version    => '2c',
                    Community  => $devices->{$ip}->{snmp_ro},
                }
            );
        }

        $batch->add_get_request($ip, {OIDS => ['.1.3.6.1.2.1.1.5.0'], CALLBACK => \&getOidsCallback}) if $poll;
    }
    print &time_to_execute(\$time), "\n" if $debug;

    print "Checking Snmp... " if $debug;

    #print Dumper $batch if $debug;
    $batch->execute;
    print &time_to_execute(\$time), "\n" if $debug;
}

sub getOidsCallback {
    my $host = shift;
    my ($ip) = split(':', $host->{ARG}->{DestHost});

    #print Dumper $host if $debug;
    # If we have a REPLY set snmp to the version of the reply
    if ($host->{REPLY_DATA}) {
        $devices->{$ip}->{snmp} = $host->{ARG}->{Version}
          unless $host->{REPLY_DATA}->{'.1.3.6.1.2.1.1.5.0'} eq 'noSuchObject';
    }

    # If we have no REPLY and its v2c try v1
    elsif ($host->{ARG}->{Version} eq '2c') {
        $host->{ARG}->{Version} = '1';
        $batch->add_host($host->{ARG});
        $batch->add_get_request($ip, {OIDS => ['.1.3.6.1.2.1.1.5.0'], CALLBACK => \&getOidsCallback});
    }
}

# Ports
sub poll_ports {
    my $ip    = shift;
    my %check = (
        tcp => {
            80   => {name => 'Apache',},
            443  => {name => 'SSL Apache',},
            23   => {name => 'Telnet',},
            22   => {name => 'SSH',},
            8443 => {name => 'perfmon',},
        },

        #       udp => {
        #           161 => {
        #               name => 'snmp',
        #           },
        #       },
    );
    check_ports($ip, 2, \%check);

    #print Dumper $ip if $debug;
    #print Dumper %check if $debug;
    return \%check;
}

# Taken from IO::Socket::PortState
sub check_ports {
    my ($ip, $to, $pmhr, $proc) = @_;
    my $hr = defined wantarray ? {} : $pmhr;
    for my $prot (keys %{$pmhr}) {
        for (keys %{$pmhr->{$prot}}) {
            $hr->{$prot}->{$_}->{name} = $pmhr->{$prot}->{$_}->{name};
            if (ref $proc eq 'CODE') {
                $proc->($hr->{$prot}->{$_}, $ip, $_, $prot, $to);
            } else {
                my $sock = IO::Socket::INET->new(PeerAddr => $ip, PeerPort => $_, Proto => $prot, Timeout => $to);
                $hr->{$prot}->{$_}->{open} = !defined $sock ? 0 : 1;
                $hr->{$prot}->{$_}->{note} = 'builtin()';
            }
        }
    }
    return $hr;
}

sub time_to_execute {
    my $time = shift;
    my $ttc  = scalar time - $$time;
    $$time = scalar time;
    return "($ttc) Secs";
}

sub get_trap_ips {
    my $command = q{cat /var/log/formattedTraps | grep -A 1 "Previous Entry" | grep -v \\\\-\\\\- | sort -u};
    my @output  = `/usr/bin/ssh -C -i /home/sampson/.ssh/id_rsa -lsampson sampson-trapcollrvip '$command' 2>/dev/null`;
    foreach (@output) {
        chomp;
        $traps{$_} = 1;
    }
    $command = q{zcat /var/log/formattedTraps.* | grep -A 1 "Previous Entry" | grep -v \\\\-\\\\- | sort -u};
    @output  = `/usr/bin/ssh -C -i /home/sampson/.ssh/id_rsa -lsampson sampson-trapcollrvip '$command' 2>/dev/null`;
    foreach (@output) {
        chomp;
        $traps{$_} = 1;
    }
}
