#!/bin/sh

##############################################################################
#
# create a backup copy (overwriting the previous one) of the oracle listener
# logs
#
# runs as a cronjob for user 'oracle'
#
##############################################################################
# RCS ID: 
# 	$Id: clean_up_listener.sh,v 1.1 2002/02/12 21:27:56 oracle Exp $
#
# RCS History:
#	$Log: clean_up_listener.sh,v $
#	Revision 1.1  2002/02/12 21:27:56  oracle
#	Initial revision
#
##############################################################################


LOCAL_BIN=/usr/local/bin
rc=0
LogDate=`date +%Y%m%d`
HumanDate=`date +%d-%m-%Y`

# Include oracle functions
. ${LOCAL_BIN}/scripts/oracle/ora_functions.inc


##############################################
# Params : None                              #
# Usage  : echo script usage and exits       #
##############################################
EchoUsageAndExit()
{
   echo "Usage is :"
   echo "\t$SCRIPT -i ORA_SID"
   exit 1
}


#########################################################
# start of script
#########################################################
SCRIPT=`basename $0`
if [ $# -eq 0 ]; then
   EchoUsageAndExit
else
   while getopts i: arg ; do
      case $arg in
         i) Instance=$OPTARG ;;
        \?) EchoUsageAndExit ;;
      esac
   done
fi
InitOracleEnv ${Instance}
if [ $? -ne 0 ] ; then
   echo "*** Severe error in preparing listener cleanup for ${Instance} on ${HumanDate}."
   echo "*** Could not initialize ORACLE environment ***"
   exit 1
else
   printenv | egrep 'ORACLE|DBA'
fi
# find out which listener is running and where it's logfile is located
for lis in `cat $ORACLE_HOME/network/admin/listener.ora | /sbin/grep -i "^LISTENER" | nawk '{ print $1}'` ; do
   #why does this not work ?
   #LIS_LOG_FILE=`/sw/oracle/app/oracle/product/8.0.4.1/bin/lsnrctl stat $lis | /sbin/grep 'Listener Log File' | /usr/bin/nawk '{ print $4 }'`
   echo "Listener Log File         /sw/oracle/app/oracle/product/8.1.7/network/log/listener.log" >/tmp/orastat
   LIS_LOG_FILE=`cat /tmp/orastat | /sbin/grep 'Listener Log File' | /usr/bin/nawk '{ print $4 }'`
   if [ -f ${LIS_LOG_FILE} ] ; then
     echo "*** Copying ${LIS_LOG_FILE} to ${LIS_LOG_FILE}.old + cleanup ***"
     cp ${LIS_LOG_FILE} ${LIS_LOG_FILE}.old
     su $ORACLE_OWNER -c "cat /dev/null >${LIS_LOG_FILE}"
     rc=$?
   else
     echo "*** Could not open $LIS_LOG_FILE"
     rc=1
   fi
done
if [ $rc -eq 0 ] ; then
   echo "*** Oracle listener logfile successful cleaned up on ${HumanDate}."
else
   echo "*** Oracle listener logfile NOT successfully cleaned up on ${HumanDate}."
fi
exit $rc
