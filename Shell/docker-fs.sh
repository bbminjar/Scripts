#!/bin/bash
PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin
PRIVATE_KEY=/var/lib/rundeck/scripts/fscheck.pem
SSH_OPTS="ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
USERNAME=zephyr
DATE=`date +%F`
TIME=`date +%H-%M-%S`
SERVER_LIST=/tmp/server_ips.txt
EMAIL_FROM=****
EMAIL_RCPTS=****
EMAIL_SUBJECT="Docker File System Monitoring"
FS_CHECK=/tmp/fscheck.txt
#REMOTE_CMD="docker exec connect df -H | grep -vE '^Filesystem|tmpfs' | awk '{ print $5 " " $1 }'"
rm -f /tmp/server_ips.txt
touch /tmp/server_ips.txt

print_help () {
echo "Help"
}
while test -n "$1"; do
   case "$1" in
       --help)
           print_help
           ;;
       -h)
           print_help
           ;;
        --tag)
            TAG=$2
            shift
            ;;
        --docker-name)
            DOCKER_NAME=$2
            shift
            ;;
        --remote-cmd)
            REMOTE_CMD=$2
            shift
            ;;
        --region)
            AWS_DEFAULT_REGION=$2
            REGION=$2
            shift
            ;;
       *)
            echo "Unknown argument: $1"
            print_help
            ;;
    esac
    shift
done


get_public_ip() {
aws ec2 describe-instances --filters Name=tag:Ansible,Values=$TAG  "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION
}

fs_check() {
get_public_ip | tee $SERVER_LIST
if [ -z $SERVER_LIST ];then
echo "No servers with the $TAG tagging or the access permission issues"
exit 1
fi
for IP in `cat $SERVER_LIST`
do
echo "Checking file system on $IP"
echo "---------START--------------"
ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker exec connect df -H | grep -vE '^Filesystem|tmpfs' | awk '{ print $5 " " $1 }'" | tee -a $FS_CHECK
echo "---------END--------------"
while read line ; do
usep=`echo  $line | awk '{print $1}'`
partition=`echo  $line | awk '{print $5}' | sed 's/%/ /'`
if [ $partition -ge 60 ]; then
echo "Running out of space \"$partition ($usep%)\" on $(IP) as on $(date)" | mail -s "\"$EMAIL_SUBJECT [ISSUE - LOW SPACE]\"" -r "$EMAIL_FROM" "$EMAIL_RCPTS"
fi
done  < $FS_CHECK
done
rm -f $FS_CHECK
}

get_public_ip
fs_check
