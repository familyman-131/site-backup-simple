#!/bin/bash
DATE=`date +%d-%m-%Y`
#/root/debian.cnf is an a symlink to /etc/mysql/debian.cnf
DB_USR=`grep -m 1 user /root/debian.cnf | awk '{ print $3}'`
DB_PASS=`grep -m 1 password /root/debian.cnf | awk '{ print $3}'`
SOURCE_DIR=/var/www/
DUMP_NAME=sql-${DATE}.sql.gz
MIN_DUMP_SIZE=2
ARCH_NAME=name.zip
BACKUP_NAME=NAME_OF_BACKUP_TASK
EMAIL=email_address
TEMP_LOG=/var/log/backup-webserv-${DATE}.log
NC_EXT=.jpg:.jpeg:.png:.tiff:.gif:.zip:.mp3:.gz
#/root/ftp.cnf is an file with FTP username, passwd, host like 
#host = xxx.xxx.xxx.xxx
#user = xxxx
#password = xxxxxxx
FTP_USR=`grep -m 1 user /root/ftp.cnf | awk '{ print $3}'`
FTP_PASS=`grep -m 1 password /root/ftp.cnf | awk '{ print $3}'`
FTP_HOST=`grep -m 1 host /root/ftp.cnf | awk '{ print $3}'`
################################################
##functions
#stdout, stderr to log
res2log () {
if [ "$?" -eq 0 ]
then
    echo "`date` Success" >> ${TEMP_LOG}
else
    echo "`date` Error" >> ${TEMP_LOG}
fi
}
#logfile dellimiter
breakline () {
echo "------------------------------" >> ${TEMP_LOG}
}
################################################
#dumping database
breakline
echo "`date` mysqldump all bases" >> ${TEMP_LOG}
cd ${SOURCE_DIR}
/usr/bin/mysqldump -u${DB_USR} -p${DB_PASS} --all-databases  --add-drop-database --events | gzip > ${DUMP_NAME}  2>> ${TEMP_LOG}
res2log
#checking database dump size
DUMP_SIZE_CNTRL=$(echo "`du -m ${SOURCE_DIR}${DUMP_NAME} | awk '{ print $1}'`")
if [ ${DUMP_SIZE_CNTRL} -le ${MIN_DUMP_SIZE} ]
then
    echo "ERROR - dump size is ${DUMP_SIZE_CNTRL}Mb, it's too low!" >> ${TEMP_LOG}
else
    echo "dump is ${DUMP_SIZE_CNTRL}Mb"  >> ${TEMP_LOG}
fi
breakline
###
#compressing /var/www
echo "`date` compress  ${SOURCE_DIR}" >> ${TEMP_LOG}
cd ${SOURCE_DIR}
zip -r -n ${NC_EXT} ${ARCH_NAME} .  2>> ${TEMP_LOG}
res2log
echo "${ARCH_NAME} size is `du -h ${SOURCE_DIR}${ARCH_NAME} | awk '{ print $1}'`" >> ${TEMP_LOG}
breakline
###
#move backup to old filename
echo "`date` rename archive to filename.old" >> ${TEMP_LOG}
/usr/bin/lftp -u ${FTP_USR},${FTP_PASS} -e "rm old.zip; mv ${ARCH_NAME} old.zip; quit" ${FTP_HOST}/  2>> ${TEMP_LOG}
res2log
breakline
###
#uploading compressed files to ftp
echo "`date` send daily archive to ${FTP_HOST}" >> ${TEMP_LOG}
cd ${SOURCE_DIR}
/usr/bin/wput -nv -a ${TEMP_LOG}  -u  ${ARCH_NAME}  ftp://${FTP_USR}:${FTP_PASS}@${FTP_HOST}  2>> ${TEMP_LOG}
res2log
breakline
###
#checking uploaded and local sizes of backup
echo "`date` check filesize on ftp and local storage" >> ${TEMP_LOG}
cd ${SOURCE_DIR}
FTP_SIZE_CNTRL=$(/usr/bin/lftp -u ${FTP_USR},${FTP_PASS} -e "ls; quit" ${FTP_HOST}/ 2> /dev/null | grep ${ARCH_NAME} | awk '{ print $5}')
LOCAL_SIZE_CNTRL=$(echo "`du -b  ${TARGET_DIR}${ARCH_NAME} | awk '{ print $1}'`")
if [ ${FTP_SIZE_CNTRL} -eq ${LOCAL_SIZE_CNTRL} ]
    then
        echo "SUCCESS - filesize on ftp ${FTP_SIZE_CNTRL} and local filesize ${LOCAL_SIZE_CNTRL} are THE SAME" >>  ${TEMP_LOG}
        rm ${SOURCE_DIR}${ARCH_NAME} 2>> ${TEMP_LOG}
        rm ${SOURCE_DIR}${DUMP_NAME} 2>> ${TEMP_LOG}
    else
        echo "ERROR - filesize on ftp ${FTP_SIZE_CNTRL} and local filesize ${LOCAL_SIZE_CNTRL} are DIFFERENT" >>  ${TEMP_LOG}
fi
breakline
#check log to add backup status to mail title
#FTP size checking result
cat ${TEMP_LOG}  | grep -q DIFFERENT
FTP_REP=$(echo "$?")
if [ ${FTP_REP} = 1  ]
    then FTP_REP="filesize OK" #echo 0
    else FTP_REP="filesize DIFFERENT" #echo 1
fi
#DUMP size checking result
cat ${TEMP_LOG}  | grep -q low
DUMP_REP=$(echo "$?")
if [ ${DUMP_REP} = 1  ]
    then DUMP_REP="dump size OK" #echo 0
    else DUMP_REP="dump size LOW" #echo 1
fi
#reporting
echo "`date` send log to email" >> ${TEMP_LOG}
cat ${TEMP_LOG} | mail -s "${BACKUP_NAME} backup report ${DATE} ${FTP_REP} ${DUMP_REP}" ${EMAIL}
rm ${TEMP_LOG}
###
