#!/bin/sh

##############################################################################
#
# create an oracle dump file, as follows:
#	smiles R999999
# uses
#	make1-100OraDump.sql
#
##############################################################################
# RCS ID: 
# 	$Id: make1-100OraDump.sh,v 1.1 2002/03/06 16:24:37 root Exp $
#
# RCS History:
#	$Log: make1-100OraDump.sh,v $
#	Revision 1.1  2002/03/06 16:24:37  root
#	Initial revision
#
##############################################################################



sqlplus tmc/tmc @make1-100OraDump.sql /tmp/oradump
if [ $? -ne 0 ] ; then
   echo "makeTotaloradump : Error returned by sqlplus."
   exit 1
fi
sed -e 's/ //g' -e '/^$/d' /tmp/oradump.lst >/tmp/oradump2.lst
sed -e '/^$/d' -e 's/,/ /1' /tmp/oradump2.lst >/tmp/oradump.lst
echo "Done .. into /tmp/oradump.lst"
exit 0

