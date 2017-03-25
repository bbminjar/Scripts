#!/bin/bash
S3BUCKET_SRC_NAME=zfjcloud-prod-us
S3BUCKET_DESC_NAME=zfjcloud-dr-us
SCRIPT_DIR=/var/lib/rundeck/scripts/es_s3_script
DATE=`date +%F` 
TIME=`date +%H-%M`
ES_SYNC_LOG="$SCRIPT_DIR/log/ES_Sync_log-$DATE-$TIME.log" 
MAIL_LOG="$SCRIPT_DIR/log/mail_log-$DATE-$TIME.log"

/usr/bin/aws s3 sync s3://$S3BUCKET_SRC_NAME/ s3://$S3BUCKET_DESC_NAME/  > $ES_SYNC_LOG
cat $SCRIPT_DIR/mail > $MAIL_LOG
head -n 10 $ES_SYNC_LOG >> $MAIL_LOG
tail -n 10 $ES_SYNC_LOG >> $MAIL_LOG

if [ $? -eq 0 ]; then
/usr/lib/sendmail -t -oi < $MAIL_LOG
find $SCRIPT_DIR/log/ -name *.log -mtime +3 -exec rm -rf {} \;
else
/usr/lib/sendmail -t -oi < $SCRIPT_DIR/mail_failure
fi
