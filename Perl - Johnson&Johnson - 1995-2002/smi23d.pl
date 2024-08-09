#!/usr/local/bin/perl

##############################################################################
#
# description
#
##############################################################################
# RCS ID: 
# 	$Id: smi23d.pl,v 1.2 2002/03/07 17:29:46 tmcwebadm Exp $
#
# RCS History:
#	$Log: smi23d.pl,v $
#	Revision 1.2  2002/03/07 17:29:46  tmcwebadm
#	corrected path to smi2mol executable (differs from old server) and
#	  added '-add_2d FALSE' to the params
#
#	Revision 1.1  2002/03/04 20:23:24  root
#	Initial revision
#
##############################################################################


use CGI qw(:standard);
# ENVIRONMENT VARIABLES
$ENV{'DY_HOME'} = "/sw/daylight";
$ENV{'DY_ROOT'} = $ENV{'DY_HOME'} . "/v473";
$ENV{'DY_LICENSEDATA'} = $ENV{'DY_HOME'} . "/local/dy_license.dat";
$ENV{'DY_PASSWORDS'} = $ENV{'DY_ROOT'} . "/etc/dy_passwords.dat";
$ENV{'DY_SYSPROFILE'} = $ENV{'DY_HOME'} . "/local/dy_sysprofile.opt";
$ENV{'LD_LIBRARY_PATH'} = $ENV{'DY_ROOT'} . "/lib:". $ENV{'DY_ROOT'} . "/libo32";
$ENV{'LD_LIBRARYN32_PATH'} = $ENV{'DY_ROOT'} . "/lib";

$CORINA = "/sw/corina/corina";
open(STDERR, ">/dev/null");

#
# RETRIEVE THE SMILES STRING FROM THE CGI PARAMETERS
#

$name = param('rnr');
$smiles = param('smi');
chomp($smiles);
$smiles =~ s/x/\+/g;
$smiles =~ s/y/\#/g;
chomp($name);

#
# WRITE THE SMILES STRING TO A TEMPORARY FILE
#

$TEMP = "../dat/" . time;
$tdt_file = $TEMP . ".tdt";
open (FILE, ">$tdt_file");
print FILE "\$SMI<" . $smiles . ">\n\$NAM<", $name, ">\n\|";
close FILE;

#
# RUN CORINA AND STORE OUTPUT INTERNALLY
#

@corina_out = `$ENV{'DY_ROOT'}/contrib/src/convert/mdl/smi2mol -input_format TDT -add_2d FALSE < $tdt_file | \
               sed 's/\$NAM/COMPID/' | \
	       /sw/corina/corina -i sdfi2n=COMP_ID -o t=sdf -t n -d wh,rs,flapn,de=0`;
	       
#print "$ENV{'DY_ROOT'}/contrib/src/applics/convert/molfiles/smi2mol -input_format TDT  -add_2d FALSE < $tdt_file | \
#               sed 's/\$NAM/COMPID/' | \
#	       /sw/corina/corina -i sdfi2n=COMP_ID -o t=sdf -t n -d wh,rs,flapn,de=0";

#
# OUTPUT SECTION
#

print "Content-type: application\/x-msiviewer-wvs\n\n";
print @corina_out;

#
# CLOSE SECTION
#

#unlink ($tdt_file);
