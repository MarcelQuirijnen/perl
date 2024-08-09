# TKInventory.pm
#
# @version $Id: TKInventory.pm 2015-04-03 14:21:18Z $
# @copyright 1999,2015, ShoreGroup, Inc.
package TKInventory;
require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use lib '/usr/share/sg-macd-automation/lib/Perl';
use lib '/var/www/CaseSentry/lib/Perl';
use SG::Logger;
use Data::Dumper;

# required modules
use TKPoller qw{ :all };
use TKInventory::Actions qw{perform_actions populate_modules populate_inventory };
use TKDevices::MACD;
use TKDevices::MACD::Depend qw{ update_uptime_depends };
use TKDevices::Config;
use TKDevices::Standards;
use TKConfig;

# Database modules
use TKDB::CaseSentry;
use TKDB::Automation;

# Helpers
use TKUtils::Location;
use TKDevices::MACD::GatherTests;

# Package exporting
use Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw{};
our @EXPORT_OK
  = qw{ process_results add_devices add_ips add_full_inventory add_from_json add_from_sak poll_all get_device_count enable_all_modules parse_results write_results add_user_pass_to_all_devices add_user_pass_to_all_devices_creds_not_defined };
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# Enable logger
# $main::DEBUG       = 1;
# $main::DEBUG_LEVEL = 8;
# $main::DEBUG_FILE  = '/var/log/toolkit.log';

#LEVELS => {
#   0 => 'EMERG',
#   1 => 'ALERT',
#   2 => 'CRIT',
#   3 => 'ERR',
#   4 => 'WARN',
#   5 => 'ENTEREXIT',
#   6 => 'NOTICE',
#   7 => 'INFO',
#   8 => 'DEBUG',
#   9 => 'DEPRECATED',
#   10 => 'VARDUMP'
#}

my $CSVersion = TKDB::CaseSentry::get_cs_version();

my $DEVICE_SQL = q{
    SELECT od.name, od.ip_addr_ipvx ip, od.ip_addr_ipvx,
    IF (di.model_num != '', di.model_num, od.model_num) AS `model_num`,
    IF (di.serial_num != '', di.serial_num, od.serial_num) AS `serial_num`,
    od.description, di.pollable as POLLABLE, di.poll_time POLL_TIME, od.standards_sku_id, od.standards_device_id, od.vendor,
    loc.name AS site_name, loc.address1 AS street_address, loc.city, loc.region AS state, loc.postal_code AS zip_code, loc.country,
    od.location, dcc.version AS def_ccm_version, dcc.type AS def_ccm_type
    FROM CaseSentry.object_def od
    LEFT JOIN Automation.device_info di ON od.ip_addr_ipvx=di.ip_addr_ipvx
    LEFT JOIN CaseSentry.location loc ON od.location_id=loc.id
    LEFT JOIN CaseSentry.def_ccm_credentials dcc ON od.entity=dcc.entity
    WHERE od.name != '~CaseSentry' and od.instance = 'NODE'
};

sub new {
    my $class = shift;
    my $this = {POLLER => new TKPoller,};
    $this->{DEVICES} = $this->{POLLER}->{DEVICES};
    $this->{MODULES} = $this->{POLLER}->{MODULES};
    bless($this, $class);
    return $this;
}

# Poll directly
sub execute {
    my $this = shift;
    $this->{POLLER}->validate_snmp();
    $this->{POLLER}->execute();
    $this->process_results();
    return ${$this->{DEVICES}};
}

sub process_results {
    my $this = shift;

    # Gather monitored tests, so parse_results can make informed decsions
    TKDevices::MACD::GatherTests::gather_monitored_tests($this->{DEVICES});

    # Parsing results is now done either in tkpollerd or above in a local poll
    $this->parse_results();

    # Update our uptimes to the correct values
    TKDevices::MACD::Depend::update_uptime_depends($this->{DEVICES});

    # Now lets write our results
    $this->write_results();
}

##############################################
# Functions for adding devices to inventory
##############################################
# Add devices from object_def based on device name
sub add_devices {
    my $this  = shift;
    my @names = @_;

    my $sql = $DEVICE_SQL;
    $sql .= q{ AND od.name IN ('} . join(q{','}, @names) . q{') };
    $sql .= q{ GROUP BY od.name };

    # Gather devices
    my $hashref = get_all_hashref($sql, ['ip']);

    foreach my $ip (keys $hashref) {
        ${$this->{DEVICES}}->{$ip} = $hashref->{$ip};
    }

    unless (&standardize_hash($this)) { exit(1); }
    TKDevices::MACD::GatherTests::gather_and_append_cce_results($this->{DEVICES});
    return 1;
}

# Add devices from object_def based on IP
sub add_ips {
    my $this = shift;
    my @ips  = @_;

    # Gather devices
    my $sql = $DEVICE_SQL;
    $sql .= q{ AND od.ip_addr_ipvx IN ('} . join(q{','}, @ips) . q{') };
    $sql .= q{ GROUP BY od.name };

    # Gather devices
    my $hashref = get_all_hashref($sql, ['ip']);
    foreach my $ip (keys $hashref) {
        ${$this->{DEVICES}}->{$ip} = $hashref->{$ip};
    }

    unless (&standardize_hash($this)) { exit(1); }
    TKDevices::MACD::GatherTests::gather_and_append_cce_results($this->{DEVICES});

    return 1;
}

# Add all devices from object_def (can include a limit)
sub add_full_inventory {
    my $this  = shift;
    my $limit = shift;

    my $sql = $DEVICE_SQL;
    $sql .= q{ GROUP BY od.name };
    $sql .= " LIMIT $limit" if defined $limit && $limit > 0;

    # Gather devices
    ${$this->{DEVICES}} = get_all_hashref($sql, ['ip']);
    unless (&standardize_hash($this)) { exit(1); }
    TKDevices::MACD::GatherTests::gather_and_append_cce_results($this->{DEVICES});
    return 1;
}

# Adds devices from SAK file
sub add_from_sak {
    my $this = shift;
    my $file = shift;

    unless (-e $file) {
        SG::Logger->err("[$$][add_from_sak][$file does not exist]");
        return 0;
    }

    # Parse the SAK
    use TKUtils::ParseExcel;
    my $json = parseExcel($file);
    unless ($this->add_from_json($json))        { return 0; }
    unless (&duplicate_sak_values_check($this)) { return 0; }
    return 1;
}

# Add devices from SAK JSON
sub add_from_json {
    my $this = shift;
    my $json = shift;
    unless (&initilize_devices($this, $json)) { return 0; }
    return 1;
}

##############################################
# Functions for processing and keeping
# device hash in order
##############################################
# Function to standardize the hash into the format we expect
sub initilize_devices {
    my $this = shift;
    my $json = shift;
    use JSON;
    ${$this->{DEVICES}} = from_json($json);
    return &standardize_hash($this);
}

# Function to standardize the hash into the format we expect
sub standardize_hash {
    my $this = shift;

    unless (defined ${$this->{DEVICES}}) {
        SG::Logger->err("[$$][standardize_hash][Tried to standardize without any devices!]");
        return 0;
    }
    SG::Logger->info(sprintf('[%s][standardize_hash][Standardizing device hash]', $$));

    my @object_def = qw{ name ip_addr_ipvx telnet_login telnet_pw term_pw
      snmp_ro snmp_rw snmp_port snmp_version web_url
      web_login web_pw model_num model_oid vendor
      serial_num location location_id poller_group_id
      product_type_id standards_sku_id standards_device_id
      description nat_addr_ipvx
    };
    my @locations       = qw{ location_name site_name street_address city state country zip_code latitude longitude };
    my @snmp_credential = qw{ snmp_credential_id };
    my @misc            = qw{ device_type sub_type category version manufacturer
      model_num serial_num access_method domain device_username device_password
      critical_interfaces critical_pris http_user http_pass entity_groups
      sec_name auth_pass_phrase priv_pass_phrase security_level authentication_protocol privacy_protocol
    };

    my @info            = qw{ POLLABLE POLL_TIME MODEL_NUM SERIAL_NUM };
    my @def_ccm         = qw{ def_ccm_type def_ccm_version };
    my @object_def_meta = qw{ SiteWatcherSiteID SiteWatcherDeviceID };
    my @support_program = qw{ smartnet_contract service_level contract_expiration };

    # Place our sub hash keys here, so we dont move them into MISC
    my @ignore
      = qw{ object_def locations snmp_credential csSnmp macd MISC POLL_RESULTS POLLED_TESTS INFO STANDARDS_RESULT BGP UNKNOWN CCE_CHECK TOPOLOGY DEF_CCM};

    foreach my $ip (keys ${$this->{DEVICES}}) {
        foreach my $key (keys ${$this->{DEVICES}}->{$ip}) {

            # Delete NULL or undefined values
            unless (defined ${$this->{DEVICES}}->{$ip}->{$key}) {
                delete ${$this->{DEVICES}}->{$ip}->{$key};
                next;
            }

            # Extra chomping
            ${$this->{DEVICES}}->{$ip}->{$key} =~ s/(^\s+|\s+$)//;

            # Added validate for only name and ip_addr_ipvx for now, we can expand later
            &validate_data($key, ${$this->{DEVICES}}->{$ip}->{$key}) if ($key =~ /^(name|ip_addr_ipvx)$/);
            if ($key ~~ @ignore) { next; }

            # Add special model_num serial_num copying
            if ($key eq 'model_num' || $key eq 'serial_num') {
                ${$this->{DEVICES}}->{$ip}->{object_def}->{$key} = ${$this->{DEVICES}}->{$ip}->{$key};
                ${$this->{DEVICES}}->{$ip}->{INFO}->{uc($key)} = ${$this->{DEVICES}}->{$ip}->{$key};
                delete ${$this->{DEVICES}}->{$ip}->{$key};
                next;
            }

            if ($key ~~ @object_def) {
                ${$this->{DEVICES}}->{$ip}->{object_def}->{$key} = ${$this->{DEVICES}}->{$ip}->{$key};
                delete ${$this->{DEVICES}}->{$ip}->{$key};
            } elsif ($key ~~ @locations) {
                ${$this->{DEVICES}}->{$ip}->{locations}->{$key} = ${$this->{DEVICES}}->{$ip}->{$key};
                delete ${$this->{DEVICES}}->{$ip}->{$key};
            } elsif ($key ~~ @snmp_credential) {
                ${$this->{DEVICES}}->{$ip}->{snmp_credential}->{$key} = ${$this->{DEVICES}}->{$ip}->{$key};
                delete ${$this->{DEVICES}}->{$ip}->{$key};
            } elsif ($key ~~ @misc) {
                ${$this->{DEVICES}}->{$ip}->{MISC}->{$key} = ${$this->{DEVICES}}->{$ip}->{$key};
                delete ${$this->{DEVICES}}->{$ip}->{$key};
            } elsif ($key ~~ @info) {
                ${$this->{DEVICES}}->{$ip}->{INFO}->{$key} = ${$this->{DEVICES}}->{$ip}->{$key};
                delete ${$this->{DEVICES}}->{$ip}->{$key};
            } elsif ($key ~~ @def_ccm) {
                ${$this->{DEVICES}}->{$ip}->{DEF_CCM}->{$key} = ${$this->{DEVICES}}->{$ip}->{$key};
                delete ${$this->{DEVICES}}->{$ip}->{$key};
            } elsif ($key ~~ @object_def_meta) {
                ${$this->{DEVICES}}->{$ip}->{object_def_meta}->{$key} = ${$this->{DEVICES}}->{$ip}->{$key};
                delete ${$this->{DEVICES}}->{$ip}->{$key};
            } elsif ($key ~~ @support_program) {
                ${$this->{DEVICES}}->{$ip}->{support_program}->{$key} = ${$this->{DEVICES}}->{$ip}->{$key};
                delete ${$this->{DEVICES}}->{$ip}->{$key};
            } else {
                ${$this->{DEVICES}}->{$ip}->{UNKNOWN}->{$key} = ${$this->{DEVICES}}->{$ip}->{$key};
                delete ${$this->{DEVICES}}->{$ip}->{$key};
            }
        }
    }

    # Cycle through again and clense our hash of false devices
    foreach my $ip (keys ${$this->{DEVICES}}) {
        unless (TKUtils::Utils::validate_ipv4_string($ip)) {
            delete ${$this->{DEVICES}}->{$ip};
            next;
        }
    }

    return 1;
}

##############################################
# Poll Functions
##############################################
sub poll_all {
    my $this  = shift;
    my $limit = shift;
    $this->add_full_inventory($limit);
    $this->enable_all_modules();
    return 1;
}

##############################################
# MISC Functions
##############################################
# Function to return device count in hash
sub get_device_count {
    my $this = shift;
    return 0 if (!defined $this->{DEVICES} || !defined ${$this->{DEVICES}});
    return scalar(keys(${$this->{DEVICES}}));
}

sub add_user_pass_to_all_devices {
    my $this      = shift;
    my $http_user = shift;
    my $http_pass = shift;

    return 0 if (!defined ${$this->{DEVICES}} || !defined $http_user || !defined $http_pass);
    foreach my $ip (keys ${$this->{DEVICES}}) {
        ${$this->{DEVICES}}->{$ip}->{MISC}->{http_user} = $http_user;
        ${$this->{DEVICES}}->{$ip}->{MISC}->{http_pass} = $http_pass;
    }
}

sub add_user_pass_to_all_devices_creds_not_defined {
    my $this = shift;

    return 0 if (!defined ${$this->{DEVICES}});
    foreach my $ip (keys ${$this->{DEVICES}}) {
        my $credentials = TKDB::CaseSentry::get_icm_credentials_by_ip($ip);
        next if (!defined $credentials);
        ${$this->{DEVICES}}->{$ip}->{MISC}->{http_user} = $credentials->{$ip}->{user};
        ${$this->{DEVICES}}->{$ip}->{MISC}->{http_pass} = $credentials->{$ip}->{pass};
    }
}

sub duplicate_sak_values_check {
    my $this = shift;
    my $exit_value;
    foreach my $ip (keys ${$this->{DEVICES}}) {

        if (validate_device_exists($ip)) {
            print "IP address already exists in object_def: " . $ip . "\n";
            $exit_value = 1;
        }

        if (defined ${$this->{DEVICES}}->{$ip}->{object_def}->{name}) {
            if (get_object_def_node_id(${$this->{DEVICES}}->{$ip}->{object_def}->{name})) {
                print "HostName already exists in object_def: "
                  . ${$this->{DEVICES}}->{$ip}->{object_def}->{name} . "\n";
                $exit_value = 1;
            }
        } else {
            print "No name for: " . $ip . "\n";
            $exit_value = 1;
        }
    }
    if ($exit_value) {
        print "Duplicate SAK value found!\n";
        return 0;
    }
    return 1;
}

sub validate_data {
    my $key   = shift;
    my $value = shift;
    if ($value =~ /[\$#@~!&*()\[\]?^`\\\/'"]+/) {
        print "\n\nInvalid characters in the string: " . $value . " - For key: " . $key . "\n\n";
        SG::Logger->err("[$$][validate_data][Invalid characters foudn in hash.][(Key: $key)(Value: $value)]");
        exit(1);
    }
}

1;
