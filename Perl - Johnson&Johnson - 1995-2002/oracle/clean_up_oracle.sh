#!/bin/sh

##############################################################################
#
# Clean up oracle log-, trace, and dumpfiles for $Instance
# Arguments:
#       $1: oracle instance
# Return value:	0 when succesfull
#		16 for invalid arguments or unable to set ORACLE environment
#		or sum of 
# 		1 when an error occurred for the logfiles
# 		2 when an error occurred for the tracefiles
# 		4 when an error occurred for the bdumpfiles
# 		8 when an error occurred for the auditfiles
#
# is run as a cronjob for user 'oracle'
#
##############################################################################
# RCS ID: 
# 	$Id: clean_up_oracle.sh,v 1.1 2002/02/12 21:27:00 oracle Exp $
#
# RCS History:
#	$Log: clean_up_oracle.sh,v $
#	Revision 1.1  2002/02/12 21:27:00  oracle
#	Initial revision
#
##############################################################################


LOCAL_BIN=/usr/local/bin
rc=0
TEST=0
HumanDate=`date +%d-%m-%Y`
TMP_FILE=/usr/tmp/ora_tmp.lst
DUMP_SCRIPT=${LOCAL_BIN}/scripts/oracle/get_ora_dump_dest.sql

trap 'rm -f $TMP_FILE; exit' 0 1 2 15

# Include oracle functions
. ${LOCAL_BIN}/scripts/oracle/ora_functions.inc


##############################################
# Params : None                              #
# Usage  : echo script usage and exits       #
##############################################
EchoUsageAndExit()
{
   echo "Usage is :"
   echo "\t$SCRIPT -i ORA_SID -T"
   echo "\t\twhere -T : run in test mode, no removal is done"
   exit 16
}

##############################################
# Params : None                              #
# Usage  : Clean up of ORACLE log files      #
# Return : 0 = success                       #
#          1 = failure                       #
##############################################
CleanUpLogFiles()
{
   echo "*** Clean up logfiles ***"
   if [ -f ${DUMP_DIR}/log/* ] ; then
      if [ $TEST -eq 1 ] ; then
         echo "find ${DUMP_DIR}/log -type f -mtime +30 -print -exec rm {} \;"
      else
         echo "find ${DUMP_DIR}/log -type f -mtime +30 -print -exec rm {} \;"
         find ${DUMP_DIR}/log -type f -mtime +30 -print -exec rm {} \; || return 1
      fi
   else
      echo "*** warning : no log files found in ${DUMP_DIR}/log"
   fi
   return 0
}

##############################################
# Params : None                              #
# Usage  : Clean up of ORACLE trace files    #
# Return : 0 = success                       #
#          1 = failure                       #
##############################################
CleanUpTraceFiles()
{
   echo "*** Clean up tracefiles ***"
   if [ -f ${DUMP_DIR}/udump/* ] ; then
      if [ $TEST -eq 1 ] ; then
         echo "find ${DUMP_DIR}/udump -type f -mtime +30 -print -exec rm {} \;"
      else
         echo "find ${DUMP_DIR}/udump -type f -mtime +30 -print -exec rm {} \;"
         find ${DUMP_DIR}/udump -type f -mtime +30 -print -exec rm {} \; || return 1
      fi
   else
      echo "*** warning : no log files found in ${DUMP_DIR}/udump"
   fi
}

##############################################
# Params : None                              #
# Usage  : Clean up of ORACLE dump files     #
# Return : 0 = success                       #
#          1 = failure                       #
##############################################
CleanUpDumpFiles()
{
   echo "*** Clean up dumpfiles ***"
   if [ -f ${DUMP_DIR}/bdump/* ] ; then
      if [ $TEST -eq 1 ] ; then
         echo "find ${DUMP_DIR}/bdump -type f -mtime +30 -print -exec rm {} \;"
      else
         echo "find ${DUMP_DIR}/bdump -type f -mtime +30 -print -exec rm {} \;"
         find ${DUMP_DIR}/bdump -type f -mtime +30 -print -exec rm {} \; || return 1
      fi
   else
      echo "*** warning : no log files found in ${DUMP_DIR}/bdump"
   fi
}

##############################################
# Params : None                              #
# Usage  : Get ORACLE dump destination       #
# Return : 0 = success                       #
#          1 = failure                       #
##############################################
GetOracleDumpDest()
{
   ExecSQL ${DUMP_SCRIPT} ${TMP_FILE}
   if [ ! -s ${TMP_FILE} ] ; then
      echo "*** GetOracleDumpDest : Could not select Oracle dump destination."
      return 1
   fi
   UDUMP_DIR=`cat ${TMP_FILE}`
   DUMP_DIR=`dirname ${UDUMP_DIR}`
   echo "*** Oracle dump directory : $DUMP_DIR ***"
   return 0
}


#########################################################
# start of script
#########################################################
SCRIPT=`basename $0`
if [ $# -eq 0 ]; then
   EchoUsageAndExit
else
   while getopts i:T arg ; do
      case $arg in
         i) Instance=$OPTARG ;;
         T) TEST=1 ;;
        \?) EchoUsageAndExit ;;
      esac
   done
fi
## . ${HOME}/.profile		## no longer needed - tom@0202011
InitOracleEnv ${Instance}
if [ $? -ne 0 ] ; then
   echo "*** Severe error in preparing cleanup of ${Instance} on ${HumanDate}."
   echo "*** Could not initialize ORACLE environment ***"
   exit 16
else
   printenv | egrep 'ORACLE|DBA'
fi
GetOracleDumpDest
if [ $? -ne 0 ] ; then
   echo "*** Severe error in preparing cleanup of ${Instance} on ${HumanDate}."
   exit 16
fi
CleanUpLogFiles
cc=$?
rc=`expr $rc + $cc`
CleanUpTraceFiles
cc=$?
rc=`expr $rc + $cc`
CleanUpDumpFiles
cc=$?
rc=`expr $rc + $cc`
if [ $rc -eq 0 ] ; then
   echo " *** ORACLE cleanup OK on ${HumanDate}."
else
   echo " *** ORACLE cleanup NOK on ${HumanDate}."
fi
exit $rc
