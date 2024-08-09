#!/bin/sh

##############################################################################
#
# What info     :                                                               
# @(#)FILE      : archive_ora_offline.sh "                                      
# @(#)TYPE FILE : Executable shell script"                                      
# @(#)ENVRONMENT:                                                          
# @(#)PARAMS    :                                                         
#       $1: oracle instance                                                      
#       $2: start oracle after backup, value : -s                                
#     or type 'archive_ora_offline.sh' for params                                
# @(#)AUTHOR    : M. Quirijnen                                     DATE: 17/10/96"
# @(#)USAGE     : Make oracle offline backup and archive using ADSM"             
# @(#)RETURN CODES :                                                            
#   0 = normal successfull completion                                           
#   1 = successfull backup after shutdown abort                                 
#   2 = successfull backup with warnings                                        
#   3 = other errors                                                             
#   4 = severe error: database not started                                        
#  if more than one exception occurs, the highest completion code will be used   
#
# runs as a cronjob for user 'oracle'
#
##############################################################################
# RCS ID: 
# 	$Id: archive_ora_offline.sh,v 1.3 2002/03/11 16:41:45 oracle Exp $
#
# RCS History:
#	$Log: archive_ora_offline.sh,v $
#	Revision 1.3  2002/03/11 16:41:45  oracle
#	uncommented TEST=0
#	  the TEST variable needs to be set, we cannot just uncomment it
#	changed AdsmServer="mvs1" to AdsmServer="BMDCS1"
#	  for correct operation on new server
#	added output line for $ArchiveLogMode
#
#	Revision 1.2  2002/03/01 20:45:41  oracle
#	disabled TEST - so the files are sent to the ADSM daemon
#
#	Revision 1.1  2002/02/12 21:32:07  oracle
#	Initial revision
#
##############################################################################


cc_normal=0
cc_aborted=1
cc_warning=2
cc_abend=3
cc_notstarted=4
cc=$cc_normal

TEST=0			## DEBUG FLAG

LOCAL_BIN=/usr/local/bin
TMP_DIR=/usr/tmp
ADSM=/usr/adsm/dsmc
AdsmServer="BMDCS1"

LogDate=`date +%Y%m%d`
HumanDate=`date +%d-%m-%Y`
ManagementClass=MC_ARCH_STATIC
DynManagementClass=MC_ARCH_DYNAMIC
SqlListOraDiag=${LOCAL_BIN}/scripts/oracle/list_ora_diag.sql
SqlCheckOraArchiveMode=${LOCAL_BIN}/scripts/oracle/check_ora_archivemode.sql
SqlSelOraOff=${LOCAL_BIN}/scripts/oracle/sel_ora_off.sql
SqlGetOraArchDir=${LOCAL_BIN}/scripts/oracle/get_ora_arch_dir.sql
SqlGetOraDumpDest=${LOCAL_BIN}/scripts/oracle/get_ora_dump_dest.sql
SqlBackupOraCtrlfile=${LOCAL_BIN}/scripts/oracle/backup_ora_ctrlfile.sql

# Include oracle functions
. ${LOCAL_BIN}/scripts/oracle/ora_functions.inc

##############################################
# Params : None                              #
# Usage  : echo script usage and exits       #
##############################################
EchoUsageAndExit()
{
   echo "Usage is :"
   echo "\t$SCRIPT -i ORA_SID [-s][-T]"
   echo "\t\twhere -s : start after backup"
   echo "\t\t      -T : run in test mode, no backup done"
   exit ${cc_abend}
}

#########################################################
# Archive Oracle Controlfiles
# return : 0 = all OK
#          1 = there was an error
#########################################################
BackupOraCtrlFile()
{
   ExecSQL ${SqlGetOraDumpDest} ${TxtGetOraDumpDest} || return 1
   if [ ! -s ${TxtGetOraDumpDest} ] ; then
      echo "*** BackupOraCtrlFile : Could not select user dump destination."
      return 1
   fi

   DumpDest=`cat ${TxtGetOraDumpDest} | cut -d' ' -f1`
   DumpFile=${DumpDest}/control_file
   touch ${TxtGetOraDumpDest} # save timestamp before executing script
   #sleep 60
   if [ -f ${DumpFile} ] ; then
      rm ${DumpFile}
   fi
   if [ -f ${DumpFile} ] ; then
      echo "*** Coulnd't remove (${DumpFile})."
      return 1
   fi
   # the next statement may take a while
   ExecSQL ${SqlBackupOraCtrlfile} ${DumpFile} || return 1
   # check dumpfile
   #   check if dumpfile is newly created and has a size greater than 0
   FIND=`find ${DumpDest}/ -size +0 -name 'control_file' -print`
   naam=`basename $FIND`
   if [ ! "${naam}" = "control_file" ] ; then
      echo "*** BackupOraCtrlFile : Error"
      echo "*** No dump file created (${DumpFile})."
      return 1
   else
      echo "*** BackupOraCtrlFile : naam = $naam"
   fi
   # archive dumpfile
   if [ $TEST -eq 1 ] ; then
      echo ${ADSM} archive -servername=${AdsmServer} \
                           -archmc=${DynManagementClass} \
                           -description="CTRLF ${Instance}" ${DumpFile}
   else
      ${ADSM} archive -servername=${AdsmServer} \
                      -archmc=${DynManagementClass} \
                      -description="CTRLF ${Instance}" ${DumpFile}
   fi
   rc=$?
   if [ $rc -ne 0 ] ; then
      echo "*** BackupOraCtrlFile : Error"
      echo "*** DSMC Archive dumpfile finished with returncode $rc on ${HumanDate}."
      return 1
   else
      echo "Backup controlfile to dump:\t$DumpFile" >> $OraListLog
   fi

   # Try to locate backup of controlfile to trace
   #  {knowing DumpFile is created before Trace file}
   for TraceFile in `ls -1t ${DumpDest}` ; do
       if [ ${DumpDest}/${TraceFile} = ${DumpFile} ] ; then
          echo "*** BackupOraCtrlFile : Error"
          echo "*** No trace controlfile created."
          return 1
       fi
       grep -qi 'CREATE CONTROLFILE' ${DumpDest}/${TraceFile}
       if [ $? -eq 0 ] ; then
          break
       fi
   done

   # archive tracefile
   if [ $TEST -eq 0 ] ; then
      ${ADSM} archive -servername=${AdsmServer} \
                      -archmc=${DynManagementClass} \
                      -description="CTRLF ${Instance}" ${DumpDest}/${TraceFile}
   else
      echo ${ADSM} archive -servername=${AdsmServer} \
                           -archmc=${DynManagementClass} \
                           -description="CTRLF ${Instance}" ${DumpDest}/${TraceFile}
   fi
   rc=$?
   if [ $rc -ne 0 ] ; then
      echo "*** BackupOraCtrlFile : Error"
      echo "*** DSMC Archive tracefile finished with returncode $rc on ${HumanDate}."
      return 1
   else
      echo "Backup controlfile to trace:\t${DumpDest}/${TraceFile}" >> $OraListLog
   fi
   return 0
}

##################################################################
# archive oracle redologs
##################################################################
ArchiveOraRedo()
{
   #
   # Get the path to the oracle archives
   #
   ExecSQL ${SqlGetOraArchDir} ${TxtGetOraArchDir}
   rc=$?
   if [ $rc != 0 ] ; then
      echo "*** ArchiveOraRedo : Error"
      echo "*** SqlGetArcDir finished with returncode $rc on ${HumanDate} ."
      echo "*** The procedure will try to use the path from last run."
   fi
   ArchDir=`cat ${TxtGetOraArchDir} | cut -d' ' -f1`
   if [ -z "${ArchDir}" ] ; then
      echo "*** ArchiveOraRedo : Error"
      echo "*** File: '${TxtCountRedologGroups}' empty or non-existant."
      echo "*** Please check the diskusage of the archive filesystems !!!"
      echo "*** Please check status of oracle instance ${Instance} !!!"
      return 1
   fi
   echo "*** ${ArchDir} ***"
   if [ -f ${ArchDir}* ] ; then
      if [ $TEST -eq 1 ] ; then
         echo ${ADSM} archive -servername=${AdsmServer} \
                              -archmc=${ManagementClass} \
                              -description="DBREDO ${Instance}" \
                              -deletefiles "${ArchDir}*"
      else
         ${ADSM} archive -servername=${AdsmServer} \
                         -archmc=${ManagementClass} \
                         -description="DBREDO ${Instance}" \
                         -deletefiles "${ArchDir}*"
      fi
      rc=$?
      if [ $rc -ne 0 ]; then
         echo "*** ArchiveOraRedo : Error"
         echo "*** DSMC Archive finished with returncode $rc on ${HumanDate}."
         return 1
      fi
   else
      echo "*** ArchiveOraRedo: no archived redologs matching ${ArchDir}*."
   fi
   echo "*** ArchiveOraRedo: Normal successfull completion."
   return 0
}


###########################################################
# OraOfflinePre:
#  completion codes:
#    =  0 --> successfull completion
#    =  1 --> warning: offline backup may take place
#    >  1 --> error: script will abort
###########################################################
OraOfflinePre()
{
   warnings=0

   # Remove listfile from previous backup
   rm -f ${OraFileList}
   echo "Table of contents - offline backup for ${Instance} on ${HumanDate}.\n" > $OraListLog
   echo "*** make oradiag"
   ExecSQL ${SqlListOraDiag} ${LogOraDiag}
   rc=$?
   if [ $rc -ne 0 ] ; then
      echo "*** OraOfflinePre : Warning ***"
      echo "*** ExecSQL warning : rc = $rc ***"
      warnings=`expr $warnings + 1`
   else
      if [ -s ${LogOraDiag} ] ; then
         if [ $TEST -eq 0 ] ; then
            ${ADSM} archive -servername=${AdsmServer} \
                            -archmc=${ManagementClass} \
                            -description="DBOFF ${Instance}" "${LogOraDiag}"
         else
            echo ${ADSM} archive -servername=${AdsmServer} \
                                 -archmc=${ManagementClass} \
                                 -description="DBOFF ${Instance}" "${LogOraDiag}"
         fi
         rc=$?
         if [ $rc -ne 0 ] ; then
            echo "*** OraOfflinePre : Warning ***"
            echo "*** DSMC Archive file with OraDiagnostics finished with returncode $rc on ${HumanDate}."
            warnings=`expr $warnings + 1`
            break
         else
            echo "Diagnostics in:\t${LogOraDiag}" >> $OraListLog
         fi
      else
         echo "*** OraOfflinePre : Warning ***"
         echo "*** Warning: File with OraDiagnostic (${LogOraDiag}) empty or not existant."
         warnings=`expr $warnings + 1`
      fi
   fi
  
   echo "*** backup control files"
   BackupOraCtrlFile ${Instance} ${OraListLog}
   rc=$?
   if [ $rc -ne 0 ] ; then
      echo "*** OraOfflinePre : Warning ***"
      echo "*** Backup control files failed on ${HumanDate}."
      warnings=`expr $warnings + 1`
   fi
   #
   # If Instance is in archivelogmode then cleanup archived redologs
   #
   echo "*** check archive logmode"
   ArchiveLogMode=`ExecSQL ${SqlCheckOraArchiveMode}`
   echo "    archive logmode = [$ArchiveLogMode] using ${SqlCheckOraArchiveMode}"
   rc=$?
   if [ $rc -ne 0 ]; then
      echo "*** OraOfflinePre : Warning ***"
      echo "*** Check Oracle Archivelog mode failed with returncode $rc on ${HumanDate}."
      warnings=`expr $warnings + 1`
   else
      if [ "$ArchiveLogMode" = 'NOARCHIVELOG' ] ; then
         echo "*** Oracle $Instance is running in NoArchivelog mode on ${HumanDate}."
      else
         echo "*** archive/delete archived redologs"
         ArchiveOraRedo ${Instance}
         rc=$?
         if [ $rc -ne 0 ] ; then
            echo "*** OraOfflinePre : Warning ***"
            echo "*** Archive Oracle Redologs failed with returncode $rc on ${HumanDate}."
            warnings=`expr $warnings + 1`
         else
            echo "All redologs were archived on ${HumanDate}." >> $OraListLog
         fi
      fi
   fi
   echo "*** select files for offline backup of $Instance."
   ExecSQL ${SqlSelOraOff} ${OraFileList}
   # if outputfile does not exist -> there was an error, no need to test on return code
   if [ ! -s ${OraFileList} ]; then
      echo "*** No files selected from database $Instance on ${HumanDate}."
      echo "*** ExecSQL warning : rc = $rc ***"
      return $rc
   fi
   if [ ${warnings} -gt 0 ] ; then
      echo "*** Successfull completion of OraOfflinePre with $warning warnings on ${HumanDate}."
      return 1
   fi
   echo "*** Successfull completion of OraOfflinePre with no warnings on ${HumanDate}."
   return 0
}


#########################################################
# start of script
#########################################################
SCRIPT=`basename $0`
Start_ora='nostart'
if [ $# -eq 0 ] ; then
   EchoUsageAndExit
else
   while getopts i:sT arg ; do
      case $arg in
         i) Instance=$OPTARG ;;
         s) Start_ora="start" ;;
         T) TEST=1 ;;
        \?) EchoUsageAndExit ;;
      esac
   done
fi
#
# set these filenames when instance variable is filled in
#
#. ${HOME}/.profile		## not needed anymore - tom@0202011
OraFileList=${TMP_DIR}/ora_off_files_${Instance}.txt
OraListLog=${TMP_DIR}/offline_${Instance}.txt
LogOraDiag=${TMP_DIR}/oradiag_${Instance}.log
TxtGetOraArchDir=${TMP_DIR}/get_ora_arch_dir_${Instance}.txt
TxtGetOraDumpDest=${TMP_DIR}/get_ora_dump_dest_${Instance}.txt

#
# setup oracle environment
#
InitOracleEnv ${Instance}
if [ $? -ne 0 ] ; then
   echo "*** Severe error in preparing offline backup for ${Instance} on ${HumanDate}."
   echo "*** Could not initialize ORACLE environment ***"
   exit ${cc_abend}
else
   printenv | egrep 'ORACLE|DBA'
fi

OraOfflinePre
rc=$?
if [ $rc -gt 1 ] ; then
   echo "*** Severe error in preparing offline backup for ${Instance} on ${HumanDate}."
   echo "*** error: cc was ${rc}."
   exit ${cc_abend}
else
   if [ $rc -gt 0 ] ; then
      echo "*** Problems recorded in preparing for offline backup."
      echo "*** error: rc was ${rc}.  Processing will continue."
      if [ $cc -lt $cc_abend ] ; then 
         cc=$cc_abend
      fi
   fi
fi
####
# Shutdown database
#  completion codes:
#    = 0 --> successfull completion
#    = 1 --> database down after abort
#  other --> program error: script will abort

OraStop ${Instance}
rc=$?
if [ $rc -eq 1 ] ; then
   echo "*** Database was shutdown with ABORT or"
   echo "*** Daemons could not be stopped propperly.  Instance: ${Instance} Date: ${HumanDate}."
   echo "*** error: cc was ${rc}."
   if [ $cc -lt $cc_aborted ] ; then 
      cc=$cc_aborted
   fi
else
   if [ $rc -ne 0 ] ; then
      echo "*** Program error in ora_stop.  Instance: ${Instance} Date: ${HumanDate}."
      echo "*** error: cc was ${rc}."
      return ${cc_abend}
   fi
fi

####
# Archive databasefiles
# When successfully, add filename to logfile
# else exit with warning

echo "*** Archive files from database $Instance for offline backup"
FILELIST=`cat ${OraFileList}`
for Line in $FILELIST ; do
   if [ ! -f $Line ] ; then
      echo "*** File $Line does not exist on ${HumanDate}."
      if [ $cc -lt $cc_abend ] ; then 
         cc=$cc_abend
      fi
      continue
   else
      if [ $TEST -eq 1 ] ; then
         echo "${ADSM} archive -servername=$AdsmServer \
                               -archmc=$ManagementClass \
                               -description='DBOFF $Instance' $Line"
      else
         ${ADSM} archive -servername=$AdsmServer \
                         -archmc=$ManagementClass \
                         -description="DBOFF $Instance" $Line
      fi
      rc=$?
      if [ $rc -ne 0 ]; then
         echo "*** DSMC Archive finished with returncode $rc on ${HumanDate}."
         if [ $cc -lt $cc_abend ] ; then 
            cc=$cc_abend
         fi
         continue
      else
         echo "Databasefile :\t$Line" >> $OraListLog
      fi
   fi
done

####
# Startup database
#  completion codes:
#    = 0 --> successfull completion
#    = 1 --> database instance is not started !
#  other --> program error: script will abort

if [ $Start_ora = "start" ] ; then
   OraStart ${Instance}
   rc=$?
   if [ $rc -eq 1 ] ; then
      echo "*** Error in startup database $Instance on ${HumanDate}."
      echo "*** error: cc was ${rc}."
      if [ $cc -lt $cc_notstarted ] ; then
         cc=$cc_notstarted
      fi
   else
      if [ $rc -ne 0 ] ; then
         echo "*** Program error ora_start script.  Instance: ${Instance} Date: ${HumanDate}."
         echo "*** error: cc was ${rc}."
         return ${cc_abend}
      else
         echo "*** Oracle started OK on ${HumanDate}. ***"
      fi
   fi
fi

####
# archive listlog file
echo "*** Then archive listlog file for $Instance"
if [ ! -s ${OraListLog} ]; then
   echo "*** Warning : Listlog file (${OraListLog}) not found for $Instance on ${HumanDate}."
   if [ $cc -lt $cc_warning ] ; then
      cc=$cc_warning
   fi
else
   if [ $TEST -eq 0 ] ; then
      ${ADSM} archive -servername=${AdsmServer} \
                      -archmc=${ManagementClass} \
                      -description="DBOFF listlog ${Instance}" "${OraListLog}"
   else
      echo ${ADSM} archive -servername=${AdsmServer} \
                           -archmc=${ManagementClass} \
                           -description="DBOFF listlog ${Instance}" "${OraListLog}"
   fi
   rc=$?
   if [ $rc -ne 0 ] ; then
      echo "*** Warning : DSMC Archive oralistlog file finished with returncode $rc on ${HumanDate}."
      if [ $cc -lt $cc_warning ] ; then
         cc=$cc_warning
      fi
   fi
fi
if [ $cc -eq 0 ] ; then
   echo "*** $SCRIPT terminated OK on ${HumanDate}. ***" 
else
   echo "*** $SCRIPT terminated OK on ${HumanDate} BUT with errorcode/warningvalue = $cc. ***" 
fi
exit $cc
