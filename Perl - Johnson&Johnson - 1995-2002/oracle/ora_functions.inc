
##############################################################################
#
# include script for .sh shells containing oracle functions
#
# tom@020211
#	- changed user 'system' to user 'oracle' - on this server, the 
#	'oracle' user is used for backups and system tasks
#
##############################################################################
# RCS ID: 
# 	$Id: ora_functions.inc,v 1.1 2002/02/12 21:22:56 oracle Exp $
#
# RCS History:
#	$Log: ora_functions.inc,v $
#	Revision 1.1  2002/02/12 21:22:56  oracle
#	Initial revision
#
##############################################################################


ORACLE_OWNER=oracle
ORACLE_DBA=oracle

#######
# Initialize ORACLE environment in Bourne shell
# Param : $1 : ORA_SID
#######
InitOracleEnv()
{
   export ORACLE_BASE=/sw/oracle/app/oracle
   export ORACLE_HOME=${ORACLE_BASE}/product/8.1.7
   export PATH=${ORACLE_HOME}/bin:$PATH
   export ORACLE_SID=$1
   ORAENV_ASK=NO
   . ${LOCAL_BIN}/oraenv
   export SRVMGRDBA=${ORACLE_HOME}/bin/svrmgrl
   return $?
}

#######
# Execute .sql script with an ops$ account
#######
ExecSQL()
{
   if [ $# -lt 1 ] ; then
      echo "*** ExecSQL Error : Incorrect usage : ExecSQL sqlscript"
      return 1
   fi
   if [ ! -s ${1} ] ; then
      echo "*** ExecSQL Error : Sqlscript ${1} doesn't exist or is empty."
      return 2
   fi
   sqlplus -S / @"$@"
   rc=$?
   if [ $rc != 0 ] ; then
      echo "*** ExecSQL Error : Sqlscript ${1} finished with returncode $rc on ${HumanDate}."
      return $rc
   fi
   return 0
}

#######
# Stop an ORACLE instance
# Env : ${TMP_DIR} must be set, should be OK in an SGI environment
#######
OraStop()
{
   if [ $# -ne 1 ]; then
      echo "*** OraStop Error : Incorrect usage: OraStop Instance \n"
      return 1
   else
      Instance=$1
   fi
   PollCount=30
   PollInterval=10
   CheckStop=${TMP_DIR}/ora_stop_${Instance}.txt
   StopLog=${TMP_DIR}/ora_stop_${Instance}.log
   
   echo "*** shutdown immediate for $Instance"
   rm -f $CheckStop
   at now <<endofdata
exec > $StopLog 2>&1
echo 'connect internal \n shutdown immediate' | $SRVMGRDBA
date > $CheckStop
endofdata
   ###
   # Let shutdown take place for a maximum of PollCount * PollInterval seconds
   # by checking the existance of CheckStop file and sleep for PollInterval seconds
   
   while [ ${PollCount} -gt 0 ] ; do
      if [ -f ${CheckStop} ] ; then
         echo "*** shutdown completed for ${Instance}"
         sleep ${PollInterval}
         for Line in `ps -ef | grep -v grep | grep -v oracle | grep ${Instance}` ; do
            Zombie=`echo ${Line} | cut -f7 -d' '`
            if [ -n ${Zombie} ] ; then
              echo "*** immeidate kill zombieproces : ${Zombie}"
              kill -9 ${Zombie}
            fi
         done
         #/sbin/killall -9 oracle
         return 0
      else
         PollCount=`expr ${PollCount} - 1`
         echo "*** PollCount = ${PollCount}"
         sleep ${PollInterval}
      fi
   done
   ###
   # If database is not down, then shutdown abort
   # and kill zombie processes
   
   echo "*** shutdown abort for $Instance"
   echo 'connect internal \n shutdown abort' | $SRVMGRDBA
   sleep ${PollInterval}
   for Line in `ps -ef | grep -v grep | grep -v oracle | grep ${Instance}` ; do
     Zombie=`echo ${Line} | cut -f7 -d' '`
     if [ -n ${Zombie} ] ; then
        echo "*** abort kill zombieproces : ${Zombie}"
        kill -9 ${Zombie}
     fi
     kill -9 ${Zombie}
   done
   #/sbin/killall -9 oracle
   
   ###
   # Restart database in restrict mode
   # followed by a new shutdown immediate.
   # Let's wait for completion
   
   echo "*** startup restrict of $Instance"
   echo 'connect internal \n startup restrict' | $SRVMGRDBA
   echo "*** shutdown immediate for $Instance"
   echo 'connect internal \n shutdown immediate' | $SRVMGRDBA
   return 1
}

#######
# Start an ORACLE instance
# Env : ${TMP_DIR} must be set, should be OK in an SGI environment
#######
OraStart()
{
   if [ $# -ne 1 ]; then
      echo "Usage: OraStart Instance \n"
      return 11
   else
      Instance=$1
   fi
   PollCount=60
   PollInterval=5
   CheckStart=${TMP_DIR}/ora_start_${Instance}.txt
   StartLog=${TMP_DIR}/ora_start_${Instance}.log
   
   ###
   # starting servermanager in forgroud could not start database up properly
   # (refresh utility for snapshots didn't work) !! so,
   # start database with at
   # redirect of output is necessary for making "at" work properly
   # after startup, create CheckStart file
   
   echo "*** Startup database ${Instance}"
   rm -f ${CheckStart}
   at now <<endofdata
exec > ${StartLog} 2>&1
echo 'connect internal \n startup' | $SRVMGRDBA
date > ${CheckStart}
endofdata
   
   while [ $PollCount -gt 0 ] ; do
      if [ -f $CheckStart ] ; then
         echo "*** startup completed for $Instance"
         ## tom@020211: oracle 8i no longer creates a sgadef* files anymore on DB start
	 # if [ ! -f $ORACLE_HOME/dbs/sgadef${Instance}.dbf ]; then
         #   echo "*** Database $Instance is not started on ${HumanDate}."
         #   return 1
         #fi
         return 0
      else
         PollCount=`expr $PollCount - 1`
         echo "*** PollCount = $PollCount"
         sleep ${PollInterval}
      fi
   done
   return 1
}
