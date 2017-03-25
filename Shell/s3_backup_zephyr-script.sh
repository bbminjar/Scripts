#!/bin/bash
S3BUCKET_SRC_NAME=zfjcloud-prod-us
S3BUCKET_DESC_NAME=zfjcloud-dr-us
SCRIPT_DIR=/var/lib/rundeck/scripts/s3bucket_sync_script
DATE=`date +%F` 
TIME=`date +%H-%M`
DATA_SYNC_LOG="$SCRIPT_DIR/log/Data_Sync_log-$DATE-$TIME.log" 
MAIL_LOG="$SCRIPT_DIR/log/mail_log-$DATE-$TIME.log"
EMAIL_FROM=***
EMAIL_RCPTS=***
EMAIL_SUBJECT="Zfjcloud Bucket Data Sync"

send_success_email() {
/bin/mail -s "\"$EMAIL_SUBJECT[SUCCES]\"" -r "$EMAIL_FROM"  $EMAIL_RCPTS < $MAIL_LOG
}

send_failure_email() {
/bin/mail -s "\"$EMAIL_SUBJECT[FAILURE]\"" -r "$EMAIL_FROM"  $EMAIL_RCPTS < $MAIL_LOG
}

/usr/bin/aws s3 sync s3://$S3BUCKET_SRC_NAME/ s3://$S3BUCKET_DESC_NAME/ --acl bucket-owner-full-control --only-show-errors >> $DATA_SYNC_LOG
head -n 10 $DATA_SYNC_LOG >> $MAIL_LOG
tail -n 10 $DATA_SYNC_LOG >> $MAIL_LOG

if [ $? -eq 0 ]; then
send_success_email
find $SCRIPT_DIR/log/ -name *.log -mtime +3 -exec rm -rf {} \;
else
send_failure_email
fi
