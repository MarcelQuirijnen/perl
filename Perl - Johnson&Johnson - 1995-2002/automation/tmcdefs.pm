##############################################################################
#
# MDC perl module for standard definitions
#
##############################################################################
# RCS ID: 
# 	$Id: TMCDefs.pm,v 1.2 2002/02/25 17:11:43 root Exp $
#
# RCS History:
#	$Log: TMCDefs.pm,v $
#	Revision 1.2  2002/02/25 17:11:43  root
#	added $RNUM2JNJS_CONV_TABLE to definitions
#
#	Revision 1.1  2002/02/12 21:42:03  root
#	Initial revision
#
##############################################################################


package Modules::TMCDefs;

=head1 NAME

Modules::TMCDefs - TMC definitions and constants

=head1 SYNOPSIS

	use Modules::TMCDefs;
        $some_var = $Modules::TMCDefs::RNUM_LEN;

=head1 DESCRIPTION

	follows later

=head1 AUTHOR

Unix Sysmannen (5889)
JRF-IT 1999

=cut

require 5.000;
require Exporter;
@ISA = qw(Exporter);

@EXPORT = qw($RNUM_LEN $DAYLIGHT_ENV $SDF_FILE $TDT_FILE $SQL_FILE $MDL_FILE $QCPE_ENV
             $SMILES_LEN $ERR_SMILESNOTAVAIL $SQL_CTL_FILE $SQL_BAD_FILE $SQL_LOG_FILE
             $COMP_NR_LEN $COMP_TYPE_LEN $DESCR2_LEN $CSRP_LEN $GN_LEN $ERR_SMILESNOTDEFINED
             $ERR_STRUCTURENOTAVAIL $SQL_DISCARD_FILE $SQL_ERRORS $CLOGP_FILE $ERR_CLOGPNOTAVAIL
             $CLUSTERSIZE $ERR_FINGERPRINTNOTAVAIL $PALLAS_ENV $BCI_ENV $ERR_PKAPKBNOTAVAIL
             $CORINA_ENV $ERR_PLOGPNOTAVAIL $ERR_NOTAVAIL $ERR_SDFFILENOTAVAIL $DOCTYPE $ERR_NA
             $PERIODIC_TABLE $MOLCONZ_ENV $ERR_TIMEOUT $RNUM2JNJS_CONV_TABLE
            );

$VERSION = '1.0';
# Record descriptions TB_SMILES@TMC_S2
$rnum_len = 6;
$comp_nr_len = 20;
$comp_type_len = 5;
$descr2_len = 240;
$csrp_len = 20;
$gn_len = 100;
$smiles_len = 700;
$sql_errors = 10000;
$Doctype = '<!DOCTYPE data SYSTEM "/usr/local/bin/scripts/automation/Modules/tmc.dtd">';
*RNUM_LEN = \$rnum_len;
*COMP_NR_LEN = \$comp_nr_len;
*COMP_TYPE_LEN = \$comp_type_len;
*DESCR2_LEN = \$descr2_len;
*CSRP_LEN = \$csrp_len;
*GN_LEN = \$gn_len;
*SMILES_LEN = \$smiles_len;
*SQL_ERRORS = \$sql_errors;
*DOCTYPE = \$Doctype;

$clogp_timeout_err = '-99P';

# Error strings
*ERR_TIMEOUT = \$clogp_timeout_err;
*ERR_SMILESNOTAVAIL = \"SmilesNotAvailable";
*ERR_FINGERPRINTNOTAVAIL = \"FingerprintNotAvailable";
*ERR_PKAPKBNOTAVAIL = \"pKa_pKb_NotAvailable";
*ERR_CLOGPNOTAVAIL = \"ClogPNotAvailable";
*ERR_PLOGPNOTAVAIL = \"PlogPNotAvailable";
*ERR_SDFFILENOTAVAIL = \"null";
*ERR_NA = \'NA';

$clustersize = 2048;
*CLUSTERSIZE = \$clustersize;

$SDF_FILE = \"/usr/people/clogp/daylight/rnum/rnum.sdf" if -e "/usr/people/clogp/daylight/rnum/rnum.sdf" && -R _ && -T _ && -s _;
$TDT_FILE = \"/usr/people/clogp/daylight/rnum/rnum.tdt" if -e "/usr/people/clogp/daylight/rnum/rnum.tdt" && -R _ && -T _ && -s _;
$CLOGP_FILE = \"/usr/people/clogp/daylight/rnum/clogp.tdt" if -e "/usr/people/clogp/daylight/rnum/clogp.tdt" && -R _ && -T _ && -s _;
$SQL_FILE = "/usr/tmp/sqlload.sql";
$MDL_FILE = \"/usr/tmp/mdl.key";
$SQL_CTL_FILE = "/usr/tmp/sqlload.ctl";
$SQL_DISCARD_FILE = "/usr/tmp/sqlload.dis";
$SQL_BAD_FILE = "/usr/tmp/sqlload.bad";
$SQL_LOG_FILE = "/usr/tmp/sqlload.log";
*DAYLIGHT_ENV = \"/sw/daylight/cshrc" if -e "/sw/daylight/cshrc" && -R _ && -T _ && -s _;
*BCI_ENV = \"/sw/bci/cshrc" if -e "/sw/bci/cshrc" && -R _ && -T _ && -s _;
*PALLAS_ENV = \"/sw/pallas/cshrc" if -e "/sw/pallas/cshrc" && -R _ && -T _ && -s _;
*CORINA_ENV = \"/sw/corina/cshrc" if -e "/sw/corina/cshrc" && -R _ && -T _ && -s _;
*QCPE_ENV = \"/sw/qcpe/cshrc_ms" if -e "/sw/qcpe/cshrc_ms" && -R _ && -T _ && -s _;
*MOLCONZ_ENV = \"/sw/molconn-z/cshrc" if -e "/sw/molconn-z/cshrc" && -R _ && -T _ && -s _;

$RNUM2JNJS_CONV_TABLE="/usr/local/bin/scripts/automation/Modules/r_to_jnjs.lst";

$PERIODIC_TABLE = {
   'H' => { 'atom_no' => 1, 'atom_weight' => 1.008, 'group' => 1, 'period' => 1 },
   'He' => { 'atom_no' => 2, 'atom_weight' => 4.003, 'group' => 18, 'period' => 1 },
   'Li' => { 'atom_no' => 3, 'atom_weight' => 6.941, 'group' => 1, 'period' => 2 },
   'Be' => { 'atom_no' => 4, 'atom_weight' => 9.012, 'group' => 2, 'period' => 2 },
   'B' => { 'atom_no' => 5, 'atom_weight' => 10.81, 'group' => 13, 'period' => 2 }, 
   'C' => { 'atom_no' => 6, 'atom_weight' => 12.01, 'group' => 14, 'period' => 2 },
   'N' => { 'atom_no' => 7, 'atom_weight' => 14.01, 'group' => 15, 'period' => 2 },
   'O' => { 'atom_no' => 8, 'atom_weight' => 16.00, 'group' => 16, 'period' => 2 },
   'F' => { 'atom_no' => 9, 'atom_weight' => 19.00, 'group' => 17, 'period' => 2 },
   'Ne' => { 'atom_no' => 10, 'atom_weight' => 20.18, 'group' => 18, 'period' => 2 },
   'Na' => { 'atom_no' => 11, 'atom_weight' => 22.99, 'group' => 1, 'period' => 3 },
   'Mg' => { 'atom_no' => 12, 'atom_weight' => 24.31, 'group' => 2, 'period' => 3 },
   'Al' => { 'atom_no' => 13, 'atom_weight' => 26.98, 'group' => 13, 'period' => 3 },
   'Si' => { 'atom_no' => 14, 'atom_weight' => 28.09, 'group' => 14, 'period' => 3 },
   'P' => { 'atom_no' => 15, 'atom_weight' => 30.97, 'group' => 15, 'period' => 3 },
   'S' => { 'atom_no' => 16, 'atom_weight' => 32.06, 'group' => 16, 'period' => 3 },
   'Cl' => { 'atom_no' => 17, 'atom_weight' => 35.45, 'group' => 17, 'period' => 3 },
   'Ar' => { 'atom_no' => 18, 'atom_weight' => 39.95, 'group' => 18, 'period' => 3 },
   'K' => { 'atom_no' => 19, 'atom_weight' => 39.10, 'group' => 1, 'period' => 4 },
   'Ca' => { 'atom_no' => 20, 'atom_weight' => 40.08, 'group' => 2, 'period' => 4 },
   'Sc' => { 'atom_no' => 21, 'atom_weight' => 44.96, 'group' => 3, 'period' => 4 },
   'Ti' => { 'atom_no' => 22, 'atom_weight' => 47.90, 'group' => 4, 'period' => 4 },
   'V' => { 'atom_no' => 23, 'atom_weight' => 50.94, 'group' => 5, 'period' => 4 },
   'Cr' => { 'atom_no' => 24, 'atom_weight' => 52.00, 'group' => 6, 'period' => 4 },
   'Mn' => { 'atom_no' => 25, 'atom_weight' => 54.94, 'group' => 7, 'period' => 4 },
   'Fe' => { 'atom_no' => 26, 'atom_weight' => 55.85, 'group' => 8, 'period' => 4 },
   'Co' => { 'atom_no' => 27, 'atom_weight' => 58.93, 'group' => 9, 'period' => 4 },
   'Ni' => { 'atom_no' => 28, 'atom_weight' => 58.71, 'group' => 10, 'period' => 4 },
   'Cu' => { 'atom_no' => 29, 'atom_weight' => 63.54, 'group' => 11, 'period' => 4 },
   'Zn' => { 'atom_no' => 30, 'atom_weight' => 65.37, 'group' => 12, 'period' => 4 },
   'Ga' => { 'atom_no' => 31, 'atom_weight' => 69.72, 'group' => 13, 'period' => 4 },
   'Ge' => { 'atom_no' => 32, 'atom_weight' => 72.59, 'group' => 14, 'period' => 4 },
   'As' => { 'atom_no' => 33, 'atom_weight' => 74.92, 'group' => 15, 'period' => 4 },
   'Se' => { 'atom_no' => 34, 'atom_weight' => 78.96, 'group' => 16, 'period' => 4 },
   'Br' => { 'atom_no' => 35, 'atom_weight' => 79.91, 'group' => 17, 'period' => 4 },
   'Kr' => { 'atom_no' => 36, 'atom_weight' => 83.80, 'group' => 18, 'period' => 4 },
   'Rb' => { 'atom_no' => 37, 'atom_weight' => 85.47, 'group' => 1, 'period' => 5 },
   'Sr' => { 'atom_no' => 38, 'atom_weight' => 87.62, 'group' => 2, 'period' => 5 },
   'Y' => { 'atom_no' => 39, 'atom_weight' => 88.91, 'group' => 3, 'period' => 5 },
   'Zr' => { 'atom_no' => 40, 'atom_weight' => 91.22, 'group' => 4, 'period' => 5 },
   'Nb' => { 'atom_no' => 41, 'atom_weight' => 92.91, 'group' => 5, 'period' => 5 },
   'Mo' => { 'atom_no' => 42, 'atom_weight' => 95.94, 'group' => 6, 'period' => 5 },
   'Tc' => { 'atom_no' => 43, 'atom_weight' => 98.91, 'group' => 7, 'period' => 5 },
   'Ru' => { 'atom_no' => 44, 'atom_weight' => 101.07, 'group' => 8, 'period' => 5 },
   'Rh' => { 'atom_no' => 45, 'atom_weight' => 102.91, 'group' => 9, 'period' => 5 },
   'Pd' => { 'atom_no' => 46, 'atom_weight' => 106.40, 'group' => 10, 'period' => 5 },
   'Ag' => { 'atom_no' => 47, 'atom_weight' => 107.87, 'group' => 11, 'period' => 5 },
   'Cd' => { 'atom_no' => 48, 'atom_weight' => 112.40, 'group' => 12, 'period' => 5 },
   'In' => { 'atom_no' => 49, 'atom_weight' => 114.82, 'group' => 13, 'period' => 5 },
   'Sn' => { 'atom_no' => 50, 'atom_weight' => 118.69, 'group' => 14, 'period' => 5 },
   'Sb' => { 'atom_no' => 51, 'atom_weight' => 121.75, 'group' => 15, 'period' => 5 },
   'Te' => { 'atom_no' => 52, 'atom_weight' => 127.60, 'group' => 16, 'period' => 5 },
   'I' => { 'atom_no' => 53, 'atom_weight' => 126.90, 'group' => 17, 'period' => 5 },
   'Xe' => { 'atom_no' => 54, 'atom_weight' => 131.30, 'group' => 18, 'period' => 5 },
   'Cs' => { 'atom_no' => 55, 'atom_weight' => 132.91, 'group' => 1, 'period' => 6 },
   'Ba' => { 'atom_no' => 56, 'atom_weight' => 137.34, 'group' => 2, 'period' => 6 },
   'La' => { 'atom_no' => 57, 'atom_weight' => 138.91, 'group' => 3, 'period' => 6 },
   'Ce' => { 'atom_no' => 58, 'atom_weight' => 140.12, 'group' => 3, 'period' => 6 },
   'Pr' => { 'atom_no' => 59, 'atom_weight' => 140.91, 'group' => 3, 'period' => 6 },
   'Nd' => { 'atom_no' => 60, 'atom_weight' => 144.24, 'group' => 3, 'period' => 6 },
   'Pm' => { 'atom_no' => 61, 'atom_weight' => 146.92, 'group' => 3, 'period' => 6 },
   'Sm' => { 'atom_no' => 62, 'atom_weight' => 150.35, 'group' => 3, 'period' => 6 },
   'Eu' => { 'atom_no' => 63, 'atom_weight' => 151.96, 'group' => 3, 'period' => 6 },
   'Gd' => { 'atom_no' => 64, 'atom_weight' => 157.25, 'group' => 3, 'period' => 6 },
   'Tb' => { 'atom_no' => 65, 'atom_weight' => 158.92, 'group' => 3, 'period' => 6 },
   'Dy' => { 'atom_no' => 66, 'atom_weight' => 162.50, 'group' => 3, 'period' => 6 },
   'Ho' => { 'atom_no' => 67, 'atom_weight' => 164.93, 'group' => 3, 'period' => 6 },
   'Er' => { 'atom_no' => 68, 'atom_weight' => 167.26, 'group' => 3, 'period' => 6 },
   'Tm' => { 'atom_no' => 69, 'atom_weight' => 168.93, 'group' => 3, 'period' => 6 },
   'Yb' => { 'atom_no' => 70, 'atom_weight' => 173.04, 'group' => 3, 'period' => 6 },
   'Lu' => { 'atom_no' => 71, 'atom_weight' => 174.97, 'group' => 3, 'period' => 6 },
   'Hf' => { 'atom_no' => 72, 'atom_weight' => 178.49, 'group' => 4, 'period' => 6 },
   'Ta' => { 'atom_no' => 73, 'atom_weight' => 180.95, 'group' => 5, 'period' => 6 },
   'W' => { 'atom_no' => 74, 'atom_weight' => 183.85, 'group' => 6, 'period' => 6 },
   'Re' => { 'atom_no' => 75, 'atom_weight' => 186.20, 'group' => 7, 'period' => 6 },
   'Os' => { 'atom_no' => 76, 'atom_weight' => 190.20, 'group' => 8, 'period' => 6 },
   'Ir' => { 'atom_no' => 77, 'atom_weight' => 192.20, 'group' => 9, 'period' => 6 },
   'Pt' => { 'atom_no' => 78, 'atom_weight' => 195.09, 'group' => 10, 'period' => 6 },
   'Au' => { 'atom_no' => 79, 'atom_weight' => 197.97, 'group' => 11, 'period' => 6 },
   'Hg' => { 'atom_no' => 80, 'atom_weight' => 200.59, 'group' => 12, 'period' => 6 },
   'Tl' => { 'atom_no' => 81, 'atom_weight' => 204.37, 'group' => 13, 'period' => 6 },
   'Pb' => { 'atom_no' => 82, 'atom_weight' => 207.19, 'group' => 14, 'period' => 6 },
   'Bi' => { 'atom_no' => 83, 'atom_weight' => 208.98, 'group' => 15, 'period' => 6 },
   'Po' => { 'atom_no' => 84, 'atom_weight' => 210.00, 'group' => 16, 'period' => 6 },
   'At' => { 'atom_no' => 85, 'atom_weight' => 210.00, 'group' => 17, 'period' => 6 },
   'Rn' => { 'atom_no' => 86, 'atom_weight' => 222.00, 'group' => 18, 'period' => 6 },
   'Fr' => { 'atom_no' => 87, 'atom_weight' => 223.00, 'group' => 1, 'period' => 7 },
   'Ra' => { 'atom_no' => 88, 'atom_weight' => 226.03, 'group' => 2, 'period' => 7 },
   'Ac' => { 'atom_no' => 89, 'atom_weight' => 227.03, 'group' => 3, 'period' => 7 },
   'Th' => { 'atom_no' => 90, 'atom_weight' => 232.03, 'group' => 3, 'period' => 7 },
   'Pa' => { 'atom_no' => 91, 'atom_weight' => 231.03, 'group' => 3, 'period' => 7 },
   'U' => { 'atom_no' => 92, 'atom_weight' => 238.02, 'group' => 3, 'period' => 7 },
   'Np' => { 'atom_no' => 93, 'atom_weight' => 237, 'group' => 3, 'period' => 7 },
   'Pu' => { 'atom_no' => 94, 'atom_weight' => 244, 'group' => 3, 'period' => 7 },
   'Am' => { 'atom_no' => 95, 'atom_weight' => 243, 'group' => 3, 'period' => 7 },
   'Cm' => { 'atom_no' => 96, 'atom_weight' => 247, 'group' => 3, 'period' => 7 },
   'Bk' => { 'atom_no' => 97, 'atom_weight' => 247, 'group' => 3, 'period' => 7 },
   'Cf' => { 'atom_no' => 98, 'atom_weight' => 251, 'group' => 3, 'period' => 7 },
   'Es' => { 'atom_no' => 99, 'atom_weight' => 252, 'group' => 3, 'period' => 7 },
   'Fm' => { 'atom_no' => 100, 'atom_weight' => 257, 'group' => 3, 'period' => 7 },
   'Md' => { 'atom_no' => 101, 'atom_weight' => 258, 'group' => 3, 'period' => 7 },
   'No' => { 'atom_no' => 102, 'atom_weight' => 252, 'group' => 3, 'period' => 7 },
   'Lr' => { 'atom_no' => 103, 'atom_weight' => 262, 'group' => 3, 'period' => 7 },
   'Rf' => { 'atom_no' => 104, 'atom_weight' => 261, 'group' => 4, 'period' => 7 },
   'Db' => { 'atom_no' => 105, 'atom_weight' => 262, 'group' => 5, 'period' => 7 },
   'Sg' => { 'atom_no' => 106, 'atom_weight' => 266, 'group' => 6, 'period' => 7 },
   'Bh' => { 'atom_no' => 107, 'atom_weight' => 264, 'group' => 7, 'period' => 7 },
   'Hs' => { 'atom_no' => 108, 'atom_weight' => 269, 'group' => 8, 'period' => 7 },
   'Mt' => { 'atom_no' => 109, 'atom_weight' => 268, 'group' => 9, 'period' => 7 },
   'Uun' => { 'atom_no' => 110, 'atom_weight' => '', 'group' => 10, 'period' => 7 },
   'Uuu' => { 'atom_no' => 111, 'atom_weight' => '', 'group' => 11, 'period' => 7 },
   'Uub' => { 'atom_no' => 112, 'atom_weight' => '', 'group' => 12, 'period' => 7 },
   'Uut' => { 'atom_no' => 113, 'atom_weight' => '', 'group' => 13, 'period' => 7 },
   'Uuq' => { 'atom_no' => 114, 'atom_weight' => '', 'group' => 14, 'period' => 7 },
   'Uup' => { 'atom_no' => 115, 'atom_weight' => '', 'group' => 15, 'period' => 7 },
   'Uuh' => { 'atom_no' => 116, 'atom_weight' => '', 'group' => 16, 'period' => 7 },
   'Uus' => { 'atom_no' => 117, 'atom_weight' => '', 'group' => 17, 'period' => 7 },
   'Uuo' => { 'atom_no' => 118, 'atom_weight' => '', 'group' => 18, 'period' => 7 },
};

$| = 1;

1;
