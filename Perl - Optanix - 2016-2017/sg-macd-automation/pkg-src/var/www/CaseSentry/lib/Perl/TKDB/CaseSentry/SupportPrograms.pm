# SupportPrograms.pm
#
# @version $Id: SupportPrograms.pm 2015-04-03 14:21:18Z homans $
# @copyright 1999,2015, ShoreGroup, Inc.
package TKDB::CaseSentry::SupportPrograms;
require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use lib '/var/www/CaseSentry/lib/Perl';

require TKUtils::Utils;

use TKDB::CaseSentry qw{ :get $dbhCaseSentry };

use Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw{ get_support_program_id get_support_program_id_by_contract get_support_contract_id
  create_smart_net_support_program_contract associate_entity_to_contract };

sub get_support_program_id {
    my $support_program = shift;

    my $t
      = $dbhCaseSentry->selectrow_array(qq{SELECT id FROM lu_support_program WHERE support_program='$support_program'})
      or ($DBI::errstr
        ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
        : SG::Logger->debug("[$$][No lu_support_program record found for $support_program]"));

    if ($t) {
        return $t;
    } else {
        return;
    }
}

sub get_support_program_id_by_contract {
    my $contract = shift;

    my $t = $dbhCaseSentry->selectrow_array(
        qq{
            SELECT lsp.id FROM lu_support_program lsp 
            JOIN lu_support_contract lsc ON lsp.id=lsc.support_program_id
            WHERE lsc.contract='$contract'
        }
      )
      or ($DBI::errstr
        ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
        : SG::Logger->debug("[$$][No lu_support_program record found for $contract]"));

    if ($t) {
        return $t;
    } else {
        return;
    }
}

sub get_support_contract_id {
    my $contract = shift;

    my $t = $dbhCaseSentry->selectrow_array(
        qq{
            SELECT id FROM lu_support_contract
            WHERE contract='$contract'
        }
      )
      or ($DBI::errstr
        ? SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr))
        : SG::Logger->debug("[$$][No lu_support_contract record found for $contract]"));

    if ($t) {
        return $t;
    } else {
        return;
    }
}

sub create_smart_net_support_program_contract {
    my $service_level       = shift;
    my $smartnet_contract   = shift;
    my $contract_expiration = shift;

    my $support_program;

    # Build smartnet name
    if ($service_level =~ /^SMARTNet/) {
        $support_program = $service_level;
    } else {
        $support_program = 'SMARTNet - ' . $service_level;
    }

    my $support_program_id;
    my $support_contract_id;

    # check for existing
    if (!get_support_program_id($support_program) && !get_support_program_id_by_contract($smartnet_contract)) {

        # None found
        $support_program_id = insert_smart_net_support_program($support_program);
    }

    # Verify we can get a support_program_id
    $support_program_id = get_support_program_id($support_program) unless $support_program_id;
    $support_program_id = get_support_program_id_by_contract($smartnet_contract) unless $support_program_id;
    return unless $support_program_id;

    # Now see if we can insert the support contract
    if (defined $smartnet_contract) {
        $support_contract_id = insert_support_contract($support_program_id, $smartnet_contract, $contract_expiration);
    }
}

sub insert_smart_net_support_program {
    my $support_program = shift;

    $dbhCaseSentry->do(
        sprintf(
            q{
                    INSERT IGNORE INTO lu_support_program VALUES 
                    (DEFAULT, '%s', '(800) 553 2447', 'http://www.cisco.com/cisco/web/support/index.html', 'N')
                }, $support_program
        )
    );
    if ($DBI::errstr) {
        SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
        return;
    } else {
        my $support_program_id = get_support_program_id($support_program);
        SG::Logger->debug(
            "[$$][Insterted lu_support_program record for $support_program][insert id: $support_program_id]");
        return $support_program_id;
    }
}

sub insert_support_contract {
    my $support_program_id  = shift;
    my $smartnet_contract   = shift;
    my $contract_expiration = shift;

    $contract_expiration =~ s/^\s+|\s+$//g;

    use Time::Piece;

    my $t;

    if ($contract_expiration =~ /\d{4}\-\d{1,2}\-\d{1,2}/) {
        $t = Time::Piece->strptime($contract_expiration, "%Y-%m-%d");
    } elsif ($contract_expiration =~ /\d{1,2}\/\d{1,2}\/\d{4}/) {
        $t = Time::Piece->strptime($contract_expiration, "%m/%d/%Y");
    } elsif ($contract_expiration =~ /^\d+$/) {
        use DateTime::Format::Excel;
        my $datetime = DateTime::Format::Excel->parse_datetime($contract_expiration);
        $t = Time::Piece->strptime($datetime->ymd(), "%Y-%m-%d") if defined $datetime;
    }

    $dbhCaseSentry->do(
        sprintf(
            q{
                INSERT IGNORE INTO lu_support_contract VALUES 
                (DEFAULT, '%s', '%s', '%s', 'N')
            }, $support_program_id, $smartnet_contract, defined $t ? $t->strftime('%Y-%m-%d') : $contract_expiration
        )
    );

    if ($DBI::errstr) {
        SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
        return;
    } else {
        my $id = get_support_contract_id($smartnet_contract);
        SG::Logger->debug(
            "[$$][Insterted lu_support_contract $smartnet_contract record for support program with id: $support_program_id][insert id: $id]"
        );
        return $id;
    }
}

sub associate_entity_to_contract {
    my $entity_id   = shift;
    my $contract_id = shift;

    $dbhCaseSentry->do(
        sprintf(
            q{
                    INSERT IGNORE INTO lu_support_contract_object VALUES 
                    ('', '%s', '%s')
                }, $contract_id, $entity_id
        )
    );
    if ($DBI::errstr) {
        SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
        return;
    } else {
        SG::Logger->debug(
            "[$$][Insterted lu_support_contract_object record for Contract id: $contract_id with Entity with id: $entity_id]"
        );
        return 1;
    }
}
