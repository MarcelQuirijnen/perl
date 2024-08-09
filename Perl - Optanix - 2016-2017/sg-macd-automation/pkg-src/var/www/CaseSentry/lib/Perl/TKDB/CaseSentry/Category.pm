# Category.pm
#
# @version $Id: Category.pm 2015-04-03 14:21:18Z homans $
# @copyright 1999,2015, ShoreGroup, Inc.
package TKDB::CaseSentry::Category;
require 5.14.0;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use lib '/var/www/CaseSentry/lib/Perl';

require TKUtils::Utils;

use TKDB::CaseSentry qw{ :get $dbhCaseSentry };

use Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw{ validate_device_category get_all_categories get_device_categories
  insert_object_def_category create_basic_category };

my $CSVersion = TKDB::CaseSentry::get_cs_version();

sub validate_device_category {
    my $device_name = shift;
    my $category    = shift;
    my $sql;

    if ($CSVersion >= 5) {
        $sql = sprintf(
            q{
                SELECT count(*) 
                FROM object_def o
                JOIN object_def_category odc ON odc.object_def_id = o.id
                JOIN Case_Management.category cmc ON cmc.id = odc.category_id
                WHERE o.name = '%s' AND cmc.name = '%s'
            }, $device_name, $category
        );
    } elsif ($CSVersion >= 4 && $CSVersion < 5) {
        $sql = sprintf(
            q{
                SELECT count(*) 
                FROM object_def o
                JOIN object_def_category odc ON odc.object_def_id = o.id
                JOIN lu_case_category lcc ON lcc.id = odc.category_id
                WHERE o.name = '%s' AND lcc.case_category = '%s'
            }, $device_name, $category
        );
    }

    my $count = $dbhCaseSentry->selectrow_array($sql);
    SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr)) if $DBI::errstr;
    return $count;
}

sub get_all_categories {
    my $categories;

    if ($CSVersion >= 5) {
        $categories = get_all_hashref('SELECT * FROM Case_Management.category', ['name']);
    } elsif ($CSVersion >= 4 && $CSVersion < 5) {
        my $temp_hash = get_all_hashref('SELECT * FROM lu_case_category', ['case_category']);
        foreach my $cat (keys $temp_hash) {
            $categories->{$cat} = translate_4_to_5($cat, $temp_hash->{$cat});
        }
    }

    return $categories;
}

sub get_device_categories {
    my $device_name = shift;
    my $sql;

    if ($CSVersion >= 5) {
        $sql = sprintf(
            q{
                SELECT o.name, cmc.name as case_category 
                FROM object_def o
                JOIN object_def_category odc ON odc.object_def_id = o.id
                JOIN Case_Management.category cmc ON cmc.id = odc.category_id
                WHERE o.name = '%s' GROUP BY 1, 2
            }, $device_name
        );
    } elsif ($CSVersion >= 4 && $CSVersion < 5) {
        $sql = sprintf(
            q{
                SELECT o.name, lcc.case_category 
                FROM object_def o
                JOIN object_def_category odc ON odc.object_def_id = o.id
                JOIN lu_case_category lcc ON lcc.id = odc.category_id
                WHERE o.name = '%s' GROUP BY 1, 2
            }, $device_name
        );
    }

    my $hash = &get_all_hashref($sql, ['name', 'case_category']);
    return 0 if !defined $hash || !defined $hash->{$device_name};
    my @categories = keys $hash->{$device_name};
    return @categories;
}

sub insert_object_def_category {
    my $object_def_id = shift;
    my $cat_id        = shift;
    $dbhCaseSentry->do(sprintf(q{INSERT IGNORE object_def_category VALUES ('',%d,%d,0)}, $object_def_id, $cat_id))
      or SG::Logger->err(sprintf(q{[%d][%s]}, $$, $DBI::errstr));
    return 0 if ($DBI::errstr);
    return 1;
}

sub create_basic_category {
    my $category = shift;
    my $sql;

    my $cat_id;
    if ($CSVersion >= 5) {
        $dbhCaseSentry->do(
            sprintf(
                q{
                    INSERT IGNORE INTO Case_Management.category SET name='%s', description='';
                }, $category
            )
        );

        $cat_id = $dbhCaseSentry->selectrow_array(
            sprintf(
                qq{
                    SELECT id FROM Case_Management.category WHERE name='%s';
                }, $category
            )
        );
    } elsif ($CSVersion >= 4 && $CSVersion < 5) {
        $dbhCaseSentry->do(
            sprintf(
                q{
                    INSERT IGNORE INTO lu_case_category SET case_category='%s', description='';
                }, $category
            )
        );

        $cat_id = $dbhCaseSentry->selectrow_array(
            sprintf(
                qq{
                    SELECT id FROM lu_case_category WHERE case_category='%s';
                }, $category
            )
        );
    }

    return $cat_id;
}

sub translate_4_to_5 {
    my $cat_name = shift;
    my $hash     = shift;

    return {
        id                        => $hash->{$cat_name}->{id},
        name                      => $cat_name,
        description               => $hash->{$cat_name}->{description},
        auto_close_time           => $hash->{$cat_name}->{auto_close_time},
        auto_close_warning        => $hash->{$cat_name}->{auto_close_warning},
        is_sticky                 => $hash->{$cat_name}->{sticky},
        is_p1_auto_close_override => ($hash->{$cat_name}->{p1_auto_close_override} eq 'Y') ? 1 : 0,
        is_p2_auto_close_override => ($hash->{$cat_name}->{p2_auto_close_override} eq 'Y') ? 1 : 0,
    };
}

1;
