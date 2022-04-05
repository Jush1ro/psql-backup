##############################################################################################################

function WRITE_LOG
 {
    case "$2" in
        "0")
            echo `date +"%d-%m-%Y %H:%M:%S"` : "$1" | tee -a $LOG_FILENAME
            ;;
        "1")
            echo -n `date +"%d-%m-%Y %H:%M:%S"` : "$1" | tee -a $LOG_FILENAME
            ;;
        "2")
            echo "$1" | tee -a $LOG_FILENAME
            ;;
        "3")
            echo -n "$1" | tee -a $LOG_FILENAME
            ;;
    esac
 }

##############################################################################################################

function EMAIL_BACKUP_RESULTS
 {
  cat $LOG_FILENAME | mail -s "$1" $MAIL_RECIPIENTS;
  return 0;
 }

##############################################################################################################

function CHECK_IF_BACKUP_PATH_EXISTS
 {
   [ -d $BACKUP_PATH/daily ] || WRITE_LOG "Backup directory tree does not exist! Will be created now." 0; mkdir -p $BACKUP_PATH/{daily,weekly,monthly,logs} >/dev/null 2>&1;
   return 0;
 }

##############################################################################################################

function CHECK_IF_RETRY_TRIGER_FILE_EXISTS
 {
#   if [[ ( ! -e $RETRY_TRIGGER_FILE ) && ( $(date +"%k") -eq 13 ) ]];
   if [[ ( ! -e $RETRY_TRIGGER_FILE ) ]];
   then
     WRITE_LOG "RETRY_TRIGGER_FILE does not exist - all was done on the 1st try! Exit." 0;
     return 1;
   fi
   return 0;
 }

##############################################################################################################

function CHECK_IF_ENOUGH_FREE_SPACE
 {
  [[ -f $LAST_BACKUP_FILENAME ]] || return 0;
#  FREE_SPACE=$(df $(df -P $BACKUP_PATH | tail -n 1 | cut -d' ' -f 1) | tail -n 1 | awk '{printf("%.0f",$4/1024^2)}')
  FREE_SPACE=$(df -P $BACKUP_PATH | tail -n 1| awk '{fs=$4/1024^2; printf("%.0f",fs)}');
#  LAST_BACKUP_FILESIZE=$(ls -l $LAST_BACKUP_FILENAME | awk '{printf("%.0f",$5/1024^3)}');
  LAST_BACKUP_FILESIZE=$(stat -c "%s" $LAST_BACKUP_FILENAME | awk '{lbs=$1/1024^3; printf("%.0f",lbs)}');
#  if [[ $FREE_SPACE -le $(echo "$LAST_BACKUP_FILESIZE*1.01/1" | bc) ]];
  if [[ $FREE_SPACE -le $(echo "$LAST_BACKUP_FILESIZE*1.0/1" | bc) ]];
  then
    WRITE_LOG "There is not enough free space for placing backup files!" 0;
    EMAIL_BACKUP_RESULTS "Failure: Database backup";
    return 1;
  fi
  return 0;
 }

##############################################################################################################

function CKECK_IF_BACKUP_TARGET_ACCESSIBLE
 {
  DB_HOST=$PRIMARY_DB_HOST;
  WRITE_LOG "Trying primary backup target ($DB_HOST)." 0;
  WRITE_LOG "Checking connection to DB server.." 1;
  psql -lqt -h $DB_HOST -U $DB_USER >/dev/null 2>&1
  if [ $? -eq 0 ]
  then
    WRITE_LOG " done." 2;
    return 0;
  else
    WRITE_LOG " failed!" 2;
    DB_HOST=$SECONDARY_DB_HOST;
    WRITE_LOG "Trying secondary backup target ($DB_HOST)." 0;
    WRITE_LOG "Checking connection to DB server.." 1;
    psql -lqt -h $DB_HOST -U $DB_USER >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
      WRITE_LOG " done." 2;
      return 0;
    else
      WRITE_LOG " failed!" 2;
      [ -e $RETRY_TRIGGER_FILE ] && rm -rf $RETRY_TRIGGER_FILE || touch $RETRY_TRIGGER_FILE; WRITE_LOG "RETRY_TRIGGER_FILE created, will retry job at 04:00!" 0;
      EMAIL_BACKUP_RESULTS "Failure: Database backup";
      return 1;
    fi
  fi
 }

##############################################################################################################

function MAKE_DATABASE_BACKUP
 {
  WRITE_LOG "Making binary dump of DB.." 1;
#  touch $BACKUP_FILENAME;
  pg_basebackup -l "pg_basebackup_$DATE" -h $DB_HOST -U $DB_USER -Ft -Xf -v -P -D - | lbzip2 -n 12 --fast > $BACKUP_FILENAME
#  pg_basebackup -l "pg_basebackup_$DATE" -h $DB_HOST -U $DB_USER -Ft -Xf -v -P -D - | bzip2 --compress --quiet --fast > $BACKUP_FILENAME
#  if [ ${PIPESTATUS[0]} -ne 0 ]
#  then
#    WRITE_LOG " failed!" 2;
#    [ -e $RETRY_TRIGGER_FILE ] && rm -rf $RETRY_TRIGGER_FILE || touch $RETRY_TRIGGER_FILE; WRITE_LOG "RETRY_TRIGGER_FILE created, will retry job at 04:00!" 0;
#    EMAIL_BACKUP_RESULTS "Failure: Database backup";
#    return 1;
#  fi
  WRITE_LOG " done." 2;
  return 0;
 }

##############################################################################################################

function CHECK_BACKUP_FILE_SIZE
 {
  fs=`stat -c '%s' $BACKUP_FILENAME`;
  [[ -f $LAST_BACKUP_FILENAME ]] && lfs=`stat -c '%s' $LAST_BACKUP_FILENAME` || lfs=0;
  [[ $fs -lt $lfs ]] && WRITE_LOG "Warning: Cuurent backup size lower then previous!" 0;
  if [ "$fs" -lt "1048576" ]; then
    fs="$(($fs/1024))KB";
  elif [ "$fs" -lt "1073741824" ]; then
    fs="$((fs/1024/1024))MB";
  else
    fs="$((fs/1024/1024/1024))GB";
  fi
  WRITE_LOG "File size = $fs" 0;
  return 0;
 }

##############################################################################################################

function CREATE_HARD_LINK_TO_LAST_BACKUP
 {
  WRITE_LOG "Creating hard link to 'fresh' backup file.." 1;
  [[ -e $LAST_BACKUP_FILENAME ]] && unlink $LAST_BACKUP_FILENAME
  ln $BACKUP_FILENAME $LAST_BACKUP_FILENAME
  if [ $? -eq 0 ]
  then
    WRITE_LOG " done." 2;
#    return 0;
  else
    WRITE_LOG " failed!" 2;
#    EMAIL_BACKUP_RESULTS "Warning: Database backup";
#    return 1;
  fi
  return 0;
 }

##############################################################################################################

function REMOVE_OLD_BACKUP_FILES
 {
  [[ -z "$1" ]] && days=2 || days=$1;
  WRITE_LOG "Removing old backups.." 1;
  find $BACKUP_PATH/daily -type f -mtime +${days} -delete;
#  find $BACKUP_PATH/daily -type f -mmin +1000 -delete;
  WRITE_LOG " done." 2;
  return 0;
 }
##############################################################################################################

function REMOVE_OLD_LOG_FILES
 {
  [[ -z "$1" ]] && days=30 || days=$1;
  WRITE_LOG "Removing old logs.." 1;
  find $BACKUP_PATH/logs -type f -mtime +${days} -delete;
  WRITE_LOG " done." 2;
  return 0;
 }

##############################################################################################################
