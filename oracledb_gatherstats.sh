# #################################################################################################################
# V. 2.2
# Backup & Gather Statistics On SCHEMA|TABLE.
# To be run by ORACLE user		
#                                       #   #     #
# Author:       Mahmmoud ADEL         # # # #   ###
# Created:      02-02-2014          #   #   # #   #
# Modified:	02-05-2018 Re-coded the script to run the gather stats commands in the background [nohup mode].
#		14-01-2021 Checking the statistics LOCK status before gathering statistics.
#		31-05-2021 Added the option of gathering STALE statistics only instead of gathering all statistics.
# #################################################################################################################

# ###########
# Description:
# ###########
echo
echo "======================================================="
echo "This script Gather & Backup Statistics on SCHEMA|TABLE."
echo "======================================================="
sleep 1
echo ""
echo "WARNING: GATHERING NEW STATISTICS DOES NOT ALWAYS LEAD TO BETTER PERFORMANCE. BUT DON'T WORRY! THIS SCRIPT BACKS UP THE CURRENT STATISTICS BEFORE DOING ANYTHING, YOU WILL BE PROMPTED THE RESTORE COMMAND IN THE OUTPUT."
echo ""


# #######################################
# Excluded INSTANCES:
# #######################################
# Here you can mention the instances the script will IGNORE and will NOT run against:
# Use pipe "|" as a separator between each instance name.
# e.g. Excluding: -MGMTDB, ASM instances:

EXL_DB="\-MGMTDB|ASM|APX"                           #Excluded INSTANCES [Will not get reported offline].


# ##############################
# SCRIPT ENGINE STARTS FROM HERE ............................................
# ##############################

# ###########################
# Listing Available Databases:
# ###########################

# Count Instance Numbers:
INS_COUNT=$( ps -ef|grep pmon|grep -v grep|egrep -v ${EXL_DB}|wc -l )

# Exit if No DBs are running:
if [ $INS_COUNT -eq 0 ]
 then
   echo "No Database is Running !"
   echo
   return
fi

# If there is ONLY one DB set it as default without prompt for selection:
if [ $INS_COUNT -eq 1 ]
 then
   export ORACLE_SID=$( ps -ef|grep pmon|grep -v grep|egrep -v ${EXL_DB}|awk '{print $NF}'|sed -e 's/ora_pmon_//g'|grep -v sed|grep -v "s///g" )

# If there is more than one DB ASK the user to select:
elif [ $INS_COUNT -gt 1 ]
 then
    echo
    echo "Select the ORACLE_SID:[Enter the number]"
    echo "---------------------"
    select DB_ID in $( ps -ef|grep pmon|grep -v grep|egrep -v ${EXL_DB}|awk '{print $NF}'|sed -e 's/ora_pmon_//g'|grep -v sed|grep -v "s///g" )
     do
                integ='^[0-9]+$'
                if ! [[ ${REPLY} =~ ${integ} ]] || [ ${REPLY} -gt ${INS_COUNT} ] || [ ${REPLY} -eq 0 ]
                        then
                        echo
                        echo "Error: Not a valid number!"
                        echo
                        echo "Enter a valid NUMBER from the displayed list !: i.e. Enter a number from [1 to ${INS_COUNT}]"
                        echo "----------------------------------------------"
                else
                        export ORACLE_SID=$DB_ID
                        echo 
                        printf "`echo "Selected Instance: ["` `echo -e "\033[33;5m${DB_ID}\033[0m"` `echo "]"`\n"
                        echo
                        break
                fi
     done

fi
# Exit if the user selected a Non Listed Number:
        if [ -z "${ORACLE_SID}" ]
         then
          echo "You've Entered An INVALID ORACLE_SID"
          exit
        fi



# #########################
# Getting ORACLE_HOME
# #########################
  ORA_USER=`ps -ef|grep ${ORACLE_SID}|grep pmon|grep -v grep|egrep -v ${EXL_DB}|grep -v "\-MGMTDB"|awk '{print $1}'|tail -1`
  USR_ORA_HOME=`grep ${ORA_USER} /etc/passwd| cut -f6 -d ':'|tail -1`

# SETTING ORATAB:
if [ -f /etc/oratab ]
  then
  ORATAB=/etc/oratab
  export ORATAB
## If OS is Solaris:
elif [ -f /var/opt/oracle/oratab ]
  then
  ORATAB=/var/opt/oracle/oratab
  export ORATAB
fi

# ATTEMPT1: Get ORACLE_HOME using pwdx command:
export PGREP=`which pgrep`
export PWDX=`which pwdx`
if [[ -x ${PGREP} ]] && [[ -x ${PWDX} ]]
then
PMON_PID=`pgrep  -lf _pmon_${ORACLE_SID}|awk '{print $1}'`
export PMON_PID
ORACLE_HOME=`pwdx ${PMON_PID} 2>/dev/null|awk '{print $NF}'|sed -e 's/\/dbs//g'`
export ORACLE_HOME
fi

# ATTEMPT2: If ORACLE_HOME not found get it from oratab file:
if [ ! -f ${ORACLE_HOME}/bin/sqlplus ]
 then
## If OS is Linux:
if [ -f /etc/oratab ]
  then
  ORATAB=/etc/oratab
  ORACLE_HOME=`grep -v '^\#' $ORATAB | grep -v '^$'| grep -i "^${ORACLE_SID}:" | perl -lpe'$_ = reverse' | cut -f3 | perl -lpe'$_ = reverse' |cut -f2 -d':'`
  export ORACLE_HOME

## If OS is Solaris:
elif [ -f /var/opt/oracle/oratab ]
  then
  ORATAB=/var/opt/oracle/oratab
  ORACLE_HOME=`grep -v '^\#' $ORATAB | grep -v '^$'| grep -i "^${ORACLE_SID}:" | perl -lpe'$_ = reverse' | cut -f3 | perl -lpe'$_ = reverse' |cut -f2 -d':'`
  export ORACLE_HOME
fi
#echo "ORACLE_HOME from oratab is ${ORACLE_HOME}"
fi

# ATTEMPT3: If ORACLE_HOME is still not found, search for the environment variable: [Less accurate]
if [ ! -f ${ORACLE_HOME}/bin/sqlplus ]
 then
  ORACLE_HOME=`env|grep -i ORACLE_HOME|sed -e 's/ORACLE_HOME=//g'`
  export ORACLE_HOME
#echo "ORACLE_HOME from environment  is ${ORACLE_HOME}"
fi

# ATTEMPT4: If ORACLE_HOME is not found in the environment search user's profile: [Less accurate]
if [ ! -f ${ORACLE_HOME}/bin/sqlplus ]
 then
  ORACLE_HOME=`grep -h 'ORACLE_HOME=\/' $USR_ORA_HOME/.bash_profile $USR_ORA_HOME/.*profile | perl -lpe'$_ = reverse' |cut -f1 -d'=' | perl -lpe'$_ = reverse'|tail -1`
  export ORACLE_HOME
#echo "ORACLE_HOME from User Profile is ${ORACLE_HOME}"
fi

# ATTEMPT5: If ORACLE_HOME is still not found, search for orapipe: [Least accurate]
if [ ! -f ${ORACLE_HOME}/bin/sqlplus ]
 then
  ORACLE_HOME=`locate -i orapipe|head -1|sed -e 's/\/bin\/orapipe//g'`
  export ORACLE_HOME
#echo "ORACLE_HOME from orapipe search is ${ORACLE_HOME}"
fi

# TERMINATE: If all above attempts failed to get ORACLE_HOME location, EXIT the script:
if [ ! -f ${ORACLE_HOME}/bin/sqlplus ]
 then
  echo "Please export ORACLE_HOME variable in your .bash_profile file under oracle user home directory in order to get this script to run properly"
  echo "e.g."
  echo "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/db_1"
exit
fi

export LD_LIBRARY_PATH=${ORACLE_HOME}/lib

# ########################################
# Exit if the user is not the Oracle Owner:
# ########################################
CURR_USER=`whoami`
	if [ ${ORA_USER} != ${CURR_USER} ]; then
	  echo ""
	  echo "You're Running This Sctipt with User: \"${CURR_USER}\" !!!"
	  echo "Please Run This Script With The Right OS User: \"${ORA_USER}\""
	  echo "Script Terminated!"
	  exit
	fi


# ########################
# Getting ORACLE_BASE:
# ########################
# Get ORACLE_BASE from user's profile if not set:

if [ -z "${ORACLE_BASE}" ]
 then
   ORACLE_BASE=`grep 'ORACLE_BASE=\/' $USR_ORA_HOME/.*profile | perl -lpe'$_ = reverse' |cut -f1 -d'=' | perl -lpe'$_ = reverse'|tail -1`
   export ORACLE_BASE
fi

# #########################
# SQLPLUS Section:
# #########################
# PROMPT FOR VARIABLES:
# ####################

        if [ ! -d ${USR_ORA_HOME} ]
         then
          export USR_ORA_HOME=/tmp
        fi

GATHERSTATSSCRIPT=${USR_ORA_HOME}/gather_stats_script_DBA_BUNDLE.sql
GATHERSTATSSCRIPTRUNNER=${USR_ORA_HOME}/gather_stats_script_DBA_BUNDLE.sh
GATHERSTATSSPOOL=${USR_ORA_HOME}/gather_stats_script_DBA_BUNDLE.log
STATS_TABLE=BACKUP_STATS
STATS_OWNER=SYS
STATS_TBS=SYSTEM

VAL33=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
set pages 0 feedback off;
SELECT STATUS FROM V\$INSTANCE;
EOF
)
VAL44=`echo $VAL33| awk '{print $NF}'`
		case ${VAL44} in
		"OPEN") echo ;;
		*) echo;echo "ERROR: INSTANCE [${ORACLE_SID}] IS IN STATUS: ${VAL44} !"
		   echo; echo "PLEASE OPEN THE INSTANCE [${ORACLE_SID}] AND RE-RUN THIS SCRIPT.";echo; exit ;;
		esac

echo "Enter the SCHEMA NAME/TABLE OWNER:"
echo "=================================="
while read SCHEMA_NAME
 do
        if [ -z ${SCHEMA_NAME} ]
         then
	  echo
	  echo "Enter the SCHEMA NAME/TABLE OWNER:"
	  echo "=================================="
         else
VAL11=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
set pages 0 feedback off;
SELECT COUNT(*) FROM DBA_USERS WHERE USERNAME=upper('${SCHEMA_NAME}');
EOF
)
VAL22=`echo ${VAL11}| awk '{print $NF}'`
                if [ ${VAL22} -eq 0 ]
                 then
                  echo
                  echo "ERROR: USER [${SCHEMA_NAME}] IS NOT EXIST ON DATABASE [${ORACLE_SID}] !"
		  echo
		  echo "Enter the SCHEMA NAME:"
		  echo "====================="
                 else
                  break
                fi
        fi
 done

echo 
echo "Enter the TABLE NAME: [BLANK VALUE MEANS GATHER THE WHOLE [${SCHEMA_NAME}] SCHEMA STATISTICS]"
echo "===================="
while read TABLE_NAME
 do
        if [ -z ${TABLE_NAME} ]
         then
          echo
          echo "Confirm GATHERING STATISTICS ON WHOLE [${SCHEMA_NAME}] SCHEMA? [Y|N] [Y]"
	  echo "===================================================="
	  while read ANS
		 do
	         case $ANS in
                 ""|y|Y|yes|YES|Yes) echo "GATHERING STATISTICS ON SCHEMA [${SCHEMA_NAME}] ..."
echo
echo "GATHER HISTOGRAMS ALONG WITH STATISTICS? [Y|N] [N]"
echo "======================================="
while read ANS1
        do
        case $ANS1 in
        y|Y|yes|YES|Yes) HISTO="FOR ALL COLUMNS SIZE SKEWONLY";HISTOMSG="(+HISTOGRAMS)"; break ;;
        ""|n|N|no|NO|No) HISTO="FOR ALL COLUMNS SIZE 1"; break ;;
        *) echo "Please enter a VALID answer [Y|N]" ;;
        esac
        done


echo
printf "`echo "GATHER STATISTICS FOR"` `echo -e "\033[33;5mSTALE\033[0m"` `echo "STATISTCS ONLY? [Y|N] [N]"`\n"
echo "==========================================="
while read ANS2
        do
        case $ANS2 in
        y|Y|yes|YES|Yes) STALE_OPTION="OPTIONS => 'GATHER STALE',"; export STALE_OPTION; break ;;
        ""|n|N|no|NO|No) STALE_OPTION=""; export STALE_OPTION; break ;;
        *) echo "Please enter a VALID answer [Y|N]" ;;
        esac
        done


# Check The Existence of BACKUP STATS TABLE:
VAL1=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
set pages 0 feedback off;
SELECT COUNT(*) FROM DBA_TABLES WHERE OWNER=upper('${STATS_OWNER}') AND TABLE_NAME=upper('${STATS_TABLE}');
EOF
)
VAL2=`echo $VAL1| awk '{print $NF}'`
                if [ ${VAL2} -gt 0 ]
                 then
                  echo
                  echo "STATISTICS BACKUP TABLE [${STATS_OWNER}.${STATS_TABLE}] IS ALREADY EXISTS."
                 else
echo
${ORACLE_HOME}/bin/sqlplus -S "/ as sysdba" <<EOF
SET LINESIZE 157
SET PAGESIZE 5000
SET HEADING OFF
SET VERIFY OFF
PROMPT CREATING STATS TABLE [Holds a backup of original statistics, if you want to restore later]...
BEGIN
dbms_stats.create_stat_table (
ownname => upper('${STATS_OWNER}'),
tblspace => upper('${STATS_TBS}'),
stattab => upper('${STATS_TABLE}'));
END;
/
PROMPT
EOF
                fi

echo "spool ${GATHERSTATSSPOOL}"						> ${GATHERSTATSSCRIPT}
echo "PROMPT BACKING UP CURRENT STATISTICS OF SCHEMA [${SCHEMA_NAME}] ..."	>>${GATHERSTATSSCRIPT}
echo "BEGIN"									>>${GATHERSTATSSCRIPT}
echo "DBMS_STATS.EXPORT_SCHEMA_STATS ("						>>${GATHERSTATSSCRIPT}
echo "ownname => upper('${SCHEMA_NAME}'),"					>>${GATHERSTATSSCRIPT}
echo "statown => upper('${STATS_OWNER}'),"					>>${GATHERSTATSSCRIPT}
echo "stattab => upper('${STATS_TABLE}'));"					>>${GATHERSTATSSCRIPT}
echo "END;"									>>${GATHERSTATSSCRIPT}
echo "/"									>>${GATHERSTATSSCRIPT}
echo "PROMPT"									>>${GATHERSTATSSCRIPT}
echo "PROMPT GATHERING STATISTICS ${HISTOMSG} ON SCHEMA [${SCHEMA_NAME}] ..."	>>${GATHERSTATSSCRIPT}
echo "PROMPT"                                                                   >>${GATHERSTATSSCRIPT}
echo "PROMPT Feel free to exist this session any time as this script is running in the background :-)"  >>${GATHERSTATSSCRIPT}
echo "PROMPT"                                                                   >>${GATHERSTATSSCRIPT}
echo "PROMPT To check the progress:"                                            >>${GATHERSTATSSCRIPT}
echo "PROMPT tail -f ${GATHERSTATSSPOOL}"                                       >>${GATHERSTATSSCRIPT}
echo "BEGIN"									>>${GATHERSTATSSCRIPT}
echo "DBMS_STATS.GATHER_SCHEMA_STATS ("						>>${GATHERSTATSSCRIPT}
echo "ownname 	=> upper('${SCHEMA_NAME}'),"					>>${GATHERSTATSSCRIPT}
echo "METHOD_OPT => '${HISTO}',"						>>${GATHERSTATSSCRIPT}
echo "DEGREE  	=> DBMS_STATS.AUTO_DEGREE,"					>>${GATHERSTATSSCRIPT}
echo "${STALE_OPTION}"                                                          >>${GATHERSTATSSCRIPT}
echo "estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE);"			>>${GATHERSTATSSCRIPT}
echo "END;"									>>${GATHERSTATSSCRIPT}
echo "/"									>>${GATHERSTATSSCRIPT}
echo "PROMPT"									>>${GATHERSTATSSCRIPT}
echo "PROMPT (IN CASE THE NEW STATISTICS ARE PERFORMING BAD, RESTORE BACK THE ORIGINAL STATISTICS USING THE FOLLOWING SQL COMMAND):"	>>${GATHERSTATSSCRIPT}
echo "PROMPT >>>>"								>>${GATHERSTATSSCRIPT}
echo "PROMPT EXEC DBMS_STATS.IMPORT_SCHEMA_STATS (ownname => upper('${SCHEMA_NAME}'), statown => upper('${STATS_OWNER}'), stattab => upper('${STATS_TABLE}'));;">>${GATHERSTATSSCRIPT}
echo "PROMPT >>>>"								>>${GATHERSTATSSCRIPT}
echo "PROMPT"									>>${GATHERSTATSSCRIPT}
echo "PROMPT SCRIPT COMPLETED!"                                                 >>${GATHERSTATSSCRIPT}
echo "PROMPT"                                                                   >>${GATHERSTATSSCRIPT}
echo "spool off"								>>${GATHERSTATSSCRIPT}
echo "exit"									>>${GATHERSTATSSCRIPT}

echo "#!/bin/bash" 												> ${GATHERSTATSSCRIPTRUNNER}
echo "nohup ${ORACLE_HOME}/bin/sqlplus \"/ as sysdba\" @${GATHERSTATSSCRIPT} | tee ${GATHERSTATSSPOOL} 2>&1 &" 	>>${GATHERSTATSSCRIPTRUNNER}
chmod 740 ${GATHERSTATSSCRIPTRUNNER}
echo ""
source ${GATHERSTATSSCRIPTRUNNER}

		 exit 1 ;;
		 n|N|no|NO|No) echo; echo "Enter the TABLE NAME:";echo "====================";break ;;
	         *) echo "Please enter a VALID answer [Y|N]" ;;
		esac
		done
         else
# Check The Existence of ENTERED TABLE:
VAL1=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
set pages 0 feedback off;
SELECT COUNT(*) FROM DBA_TABLES WHERE OWNER=upper('${SCHEMA_NAME}') AND TABLE_NAME=upper('${TABLE_NAME}');
EOF
)
VAL2=`echo $VAL1| awk '{print $NF}'`
                if [ ${VAL2} -eq 0 ]
                 then
                  echo
                  echo "ERROR: TABLE [${SCHEMA_NAME}.${TABLE_NAME}] IS NOT EXIST !"
		  echo;echo "Enter the TABLE NAME: [BLANK VALUE MEANS GATHER THE WHOLE SCHEMA [${SCHEMA_NAME}] STATISTICS]"
		  echo "===================="
		 else
${ORACLE_HOME}/bin/sqlplus -S "/ as sysdba" <<EOF
SET LINESIZE 157
SET PAGESIZE 5000
col TABLE_NAME for a70
SELECT TABLE_NAME,to_char(LAST_ANALYZED, 'DD-MON-YYYY HH24:MI:SS')LAST_STATISTICS_DATE FROM DBA_TABLES WHERE OWNER=upper('${SCHEMA_NAME}') AND TABLE_NAME=upper('${TABLE_NAME}');
EOF
		  break
		fi
        fi
 done

# Check Lock status on Statistics:
LOCK_STATS_RAW=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
set pages 0 feedback off;
SELECT COUNT(*) FROM DBA_TAB_STATISTICS WHERE OWNER=upper('${SCHEMA_NAME}') AND TABLE_NAME=upper('${TABLE_NAME}') and STATTYPE_LOCKED='ALL';
EOF
)
LOCK_STATS=`echo ${LOCK_STATS_RAW} | perl -lpe'$_ = reverse' |awk '{print $1}'|perl -lpe'$_ = reverse'`

		if [ "${LOCK_STATS}" -eq 1 ]
                 then
                  echo
		  printf "`echo "Statistics are "` `echo -e "\033[33;5mLOCKED\033[0m"` `echo " on TABLE [${SCHEMA_NAME}.${TABLE_NAME}]"`\n"
		  echo
		  echo "NOTE: Statistics will be UNLOCKED temporarily during the statistics gather and will be LOCKED after."
		  export UNLOCK_STATS_MSG="PROMPT UNLOCKING STATISTICS ON TABLE [${SCHEMA_NAME}.${TABLE_NAME}]"
		  export UNLOCK_STATS_SQL="exec dbms_stats.unlock_table_stats('${SCHEMA_NAME}','${TABLE_NAME}');"
		  export LOCK_STATS_MSG="PROMPT LOCKING BACK STATISTICS ON TABLE [${SCHEMA_NAME}.${TABLE_NAME}]"
		  export LOCK_STATS_SQL="exec dbms_stats.lock_table_stats('${SCHEMA_NAME}','${TABLE_NAME}');"
		  break
		fi
echo
echo "GATHER HISTOGRAMS ALONG WITH STATISTICS? [Y|N] [N]"
echo "======================================="
while read ANS1
 	do
        case $ANS1 in
        y|Y|yes|YES|Yes) HISTO="FOR ALL COLUMNS SIZE SKEWONLY"; HISTOMSG="(+HISTOGRAMS)";break ;;
        ""|n|N|no|NO|No) HISTO="FOR ALL COLUMNS SIZE 1"; break ;;
        *) echo "Please enter a VALID answer [Y|N]" ;;
        esac
        done


echo
echo "GATHER STATISTICS ON ALL TABLE's INDEXES? [Y|N] [Y]"
echo "========================================="
while read ANS2
        do
        case $ANS2 in
        ""|y|Y|yes|YES|Yes) CASCD="TRUE";CASCMSG="AND ITS INDEXES"; break ;;
        n|N|no|NO|No) CASCD="FALSE"; break ;;
        *) echo "Please enter a VALID answer [Y|N]" ;;
        esac
        done

# Execution of SQL Statement:
# ##########################

VAL1=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
set pages 0 feedback off;
SELECT COUNT(*) FROM DBA_TABLES WHERE OWNER=upper('${STATS_OWNER}') AND TABLE_NAME=upper('${STATS_TABLE}');
EOF
)
VAL2=`echo $VAL1| awk '{print $NF}'`
                if [ ${VAL2} -gt 0 ]
                 then
                  echo
                  echo "BACKUP STATS TABLE [${STATS_OWNER}.${STATS_TABLE}] IS ALREADY EXISTS."
                 else
${ORACLE_HOME}/bin/sqlplus -S "/ as sysdba" <<EOF
SET LINESIZE 157
SET PAGESIZE 5000
SET HEADING OFF
SET VERIFY OFF
PROMPT CREATING BACKUP STATS TABLE ...
BEGIN
dbms_stats.create_stat_table (
ownname => upper('${STATS_OWNER}'),
tblspace => upper('${STATS_TBS}'),
stattab => upper('${STATS_TABLE}'));
END;
/
PROMPT
EOF
                fi

echo "SET LINESIZE 157"										> ${GATHERSTATSSCRIPT}
echo "SET PAGESIZE 5000"									>>${GATHERSTATSSCRIPT}
echo "SET HEADING OFF"										>>${GATHERSTATSSCRIPT}
echo "spool ${GATHERSTATSSPOOL}"                                                		>>${GATHERSTATSSCRIPT}
echo "${UNLOCK_STATS_MSG}"									>>${GATHERSTATSSCRIPT}
echo "${UNLOCK_STATS_SQL}"                                                                      	>>${GATHERSTATSSCRIPT}
echo "PROMPT BACKING UP CURRENT STATISTICS OF TABLE [${SCHEMA_NAME}.${TABLE_NAME}]  ..."	>>${GATHERSTATSSCRIPT}
echo "BEGIN"											>>${GATHERSTATSSCRIPT}	
echo "DBMS_STATS.EXPORT_TABLE_STATS ("								>>${GATHERSTATSSCRIPT}
echo "ownname => upper('${SCHEMA_NAME}'),"							>>${GATHERSTATSSCRIPT}
echo "tabname => upper('${TABLE_NAME}'),"							>>${GATHERSTATSSCRIPT}
echo "statown => upper('${STATS_OWNER}'),"							>>${GATHERSTATSSCRIPT}
echo "stattab => upper('${STATS_TABLE}'));"							>>${GATHERSTATSSCRIPT}
echo "END;"											>>${GATHERSTATSSCRIPT}
echo "/"											>>${GATHERSTATSSCRIPT}
echo "PROMPT"                                                                                   >>${GATHERSTATSSCRIPT}
echo "PROMPT => In case you want to RESTORE the OLD Statistics, Use this Command:"  		>>${GATHERSTATSSCRIPT}
echo "PROMPT EXEC DBMS_STATS.IMPORT_TABLE_STATS (ownname => upper('${SCHEMA_NAME}'), tabname => upper('${TABLE_NAME}'), statown => upper('${STATS_OWNER}'), stattab => upper('${STATS_TABLE}'));;"                                                                      >>${GATHERSTATSSCRIPT}
echo "PROMPT"											>>${GATHERSTATSSCRIPT}
echo "PROMPT GATHERING STATISTICS ${HISTOMSG} ON TABLE [${SCHEMA_NAME}.${TABLE_NAME}] ${CASCMSG} ..."	>>${GATHERSTATSSCRIPT}
echo "PROMPT"                                                                                   >>${GATHERSTATSSCRIPT}
echo "PROMPT Feel free to exist this session any time as this script is running in the background :-)"	>>${GATHERSTATSSCRIPT}
echo "PROMPT"                                                                                   >>${GATHERSTATSSCRIPT}
echo "PROMPT To check the progress:"								>>${GATHERSTATSSCRIPT}
echo "PROMPT tail -f ${GATHERSTATSSPOOL}"							>>${GATHERSTATSSCRIPT}
echo "BEGIN"											>>${GATHERSTATSSCRIPT}
echo "DBMS_STATS.GATHER_TABLE_STATS ("								>>${GATHERSTATSSCRIPT}
echo "ownname 	=> upper('${SCHEMA_NAME}'),"							>>${GATHERSTATSSCRIPT}
echo "tabname 	=> upper('${TABLE_NAME}'),"							>>${GATHERSTATSSCRIPT}
echo "cascade 	=> ${CASCD},"									>>${GATHERSTATSSCRIPT}
echo "METHOD_OPT 	=> '${HISTO}',"								>>${GATHERSTATSSCRIPT}
echo "DEGREE  	=> DBMS_STATS.AUTO_DEGREE,"							>>${GATHERSTATSSCRIPT}
echo "estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE);"					>>${GATHERSTATSSCRIPT}
echo "END;"											>>${GATHERSTATSSCRIPT}
echo "/"											>>${GATHERSTATSSCRIPT}
echo "PROMPT"											>>${GATHERSTATSSCRIPT}
echo "${LOCK_STATS_MSG}"                                                                        >>${GATHERSTATSSCRIPT}
echo "${LOCK_STATS_SQL}"                                                                      	>>${GATHERSTATSSCRIPT}
echo "PROMPT"                                                                                   >>${GATHERSTATSSCRIPT}
echo "PROMPT SCRIPT COMPLETED!"									>>${GATHERSTATSSCRIPT}
echo "PROMPT"                                                                   		>>${GATHERSTATSSCRIPT}
echo "spool off"                                                                		>>${GATHERSTATSSCRIPT}
echo "exit"	                                                                		>>${GATHERSTATSSCRIPT}

echo "#!/bin/bash"                                                                                                > ${GATHERSTATSSCRIPTRUNNER}
echo "nohup ${ORACLE_HOME}/bin/sqlplus \"/ as sysdba\" @${GATHERSTATSSCRIPT} | tee ${GATHERSTATSSPOOL} 2>&1 &"    >>${GATHERSTATSSCRIPTRUNNER}
chmod 740 ${GATHERSTATSSCRIPTRUNNER}
echo ""
source ${GATHERSTATSSCRIPTRUNNER}

# #############
# END OF SCRIPT
# #############
# REPORT BUGS to: mahmmoudadel@hotmail.com
# DOWNLOAD THE LATEST VERSION OF DATABASE ADMINISTRATION BUNDLE FROM: http://dba-tips.blogspot.com/2014/02/oracle-database-administration-scripts.html
# DISCLAIMER: THIS SCRIPT IS DISTRIBUTED IN THE HOPE THAT IT WILL BE USEFUL, BUT WITHOUT ANY WARRANTY. IT IS PROVIDED "AS IS".
