# -*- perl -*-
#
# Install package : Perl Makefile.PL
#                   make
#                   make install
#
# Use : perl Makefile.PL
#       Will install 'c3_health' script in /usr/local/bin
#
# This package will be installed in the site specific tree
#   find `perl -Te 'print "@INC"'` -name '*.pm' -print
# to check this

use ExtUtils::MakeMaker;
use ExtUtils::Command;

@programs_to_install = ( 'c3_health' );

# PREFIX defaults to '/usr/bin' .. see perl '-V:install.*'
$INSTALLSCRIPT='/usr/local/bin';

WriteMakefile(
   INSTALLSCRIPT => $INSTALLSCRIPT,
   NAME	     => 'System::Unix',
   DISTNAME  => 'UnixSysAdmin-modules',
   PREREQ_PM => { Sys::Hostname => '1.1' },
   EXE_FILES => [ map {"$_"} @programs_to_install ],
   dist      => { SUFFIX   => '.gz', 
                  DIST_DEFAULT => 'all tardist',
                  COMPRESS => 'gzip -9f' 
                },
   VERSION_FROM => 'lib/System/Unix.pm',
   MAN3PODS => { },     # suppress creation on man pages for now
   LIBS      => [''],
   DEFINE    => '',
   INC       => '',
   AUTHOR    => 'Marcel Quirijnen, marcel.j.quirijnen@exxonmobil.com',
   ABSTRACT  => 'Installs basic unix/linux test scripts/packages'
);
