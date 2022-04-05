#!/bin/bash

#set -x

##############################################################################################################

PRIMARY_DB_HOST=IP____ADDRESS
SECONDARY_DB_HOST=IP____ADDRESS
DB_USER=postgres
DB_PASSWORD=

DATE=`date +"%d-%m-%Y-%H%M"`

BACKUP_PATH=/backup
BACKUP_FILENAME=$BACKUP_PATH/daily/$DATE.tar.bz2
LAST_BACKUP_FILENAME=$BACKUP_PATH/fresh-backup.tar.bz2
LOG_FILENAME=$BACKUP_PATH/logs/$DATE.log

MAIL_RECIPIENTS=mail@youremail.test

RETRY_TRIGGER_FILE=$BACKUP_PATH/retry-trigger-file

##############################################################################################################

source .backup-functions.sh

##############################################################################################################

 WRITE_LOG "Starting backup process." 0;
 CHECK_IF_BACKUP_PATH_EXISTS;
# CHECK_IF_RETRY_TRIGER_FILE_EXISTS || exit;
# !!!
REMOVE_OLD_BACKUP_FILES 22;
# rm -rf $BACKUP_PATH/daily/$(date -d yesterday +"%d-%m-%Y")-*.tar.bz2
# rm -rf $LAST_BACKUP_FILENAME
# !!!
 CHECK_IF_ENOUGH_FREE_SPACE || exit;
 CKECK_IF_BACKUP_TARGET_ACCESSIBLE || exit;
 MAKE_DATABASE_BACKUP || exit;
 CHECK_BACKUP_FILE_SIZE;
# CREATE_HARD_LINK_TO_LAST_BACKUP || exit;
 REMOVE_OLD_BACKUP_FILES 2;
# rm -rf $BACKUP_PATH/daily/$(date -d yesterday +"%d-%m-%Y")-*.tar.bz2
 REMOVE_OLD_LOG_FILES 30;
 WRITE_LOG "Backup succesfully completed!" 0;
 EMAIL_BACKUP_RESULTS "Success: Backup database"

##############################################################################################################
