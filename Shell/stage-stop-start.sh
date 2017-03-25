#!/bin/bash
PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin
PRIVATE_KEY=/var/lib/rundeck/scripts/stage/stage_stop_start/zephyr.pem
RIAK_KEY=/var/lib/rundeck/scripts/stage/stage_stop_start/riakbackup.pem
SSH_OPTS="ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
USERNAME=zephyr
RIAK_USERNAME=riakbackup
DATE=`date +%F`
TIME=`date +%H-%M-%S`
EMAIL_FROM=zephyr-alerts@minjar.com
EMAIL_RCPTS=zephyr-alerts@minjar.com
EMAIL_SUBJECT="Stage instance stop and start"
MAILLOG=/tmp/stage/stage_mailog_${DATE}-${TIME}.log


playlist=/tmp/stage/play_instance.txt
playelb="stage-zfjcloud-play-cluster-lb"
#play_tag="Stage-Play"

playapilist=/tmp/stage/playapi_instance.txt
playapielb="stage-zfjcloud-api-cluster-lb"
#playapi_tag="Stage-PlayAPI"

eslist=/tmp/stage/es_instance.txt
es_tag="Stage-ES"

riaklist=/tmp/stage/riak_instance.txt
riakelb="stage-zfjcloud-riak-cluster-lb"
#riak_tag="Stage-Riak"

xraylist=/tmp/stage/xray_instance.txt
xrayelb="stage-zfjcloud-xray-cluster-lb"
#xray_tag="Stage-Xray"

echo "deleting the old instance files" | tee $MAILLOG
rm -f $playlist $playapilist $eslist $riaklist $xraylist
touch $playlist $playapilist $eslist $riaklist $xraylist


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

        --region)
            REGION=$2
            shift
            ;;
        --Action)
            ACTION=$2
            shift
            ;;

       *)
            echo "Unknown argument: $1"
            print_help
            ;;
    esac
    shift
done

play_discover() {
echo "getting the stage play server instance id from $playelb" | tee $MAILLOG
INSTANCES=`aws elb describe-load-balancers --load-balancer-names $playelb --query 'LoadBalancerDescriptions[*].Instances[*].InstanceId' --output text --region $REGION`
echo $INSTANCES | tee $playlist
echo $INSTANCES | tee $MAILLOG
if [ -z $playlist ];then
echo "No servers atatched with $playelb or the access permission issues " | tee $MAILLOG
exit 1
fi
}

play_stop() {
for i in `cat $playlist`;do
IP=`aws ec2 describe-instances --instance-ids  "$i" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION`
echo "stopping the docker connect on instance $i($IP)" | tee $MAILLOG
output=`ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker stop connect"`
echo $output | tee $MAILLOG
echo "stopping the stage play server $i" | tee $MAILLOG
stop=`aws ec2 stop-instances --instance-ids $i --output text --region $REGION`
echo "$stop" | tee $MAILLOG
done
}

play_start() {
echo "starting the stage play servers" | tee $MAILLOG
for i in `cat $playlist`;do
start=`aws ec2 start-instances --instance-ids $i --output text --region $REGION`
echo "stage play instance started $i" | tee $MAILLOG
echo "$start" | tee $MAILLOG
done

for i in `cat $playlist` ; do
echo "checking the stage play instance $i reachability" | tee $MAILLOG
status=`aws ec2 describe-instance-status  --instance-ids $i --output text --region $REGION | grep -i DETAILS | head -1 | awk '{print $3}'`
while [ "passed" != "$status" ] ; do
      echo "stage play instance $i is not reachable and wait for 30sec" | tee $MAILLOG
      sleep 30
      status=`aws ec2 describe-instance-status  --instance-ids $i --output text --region $REGION | grep -i DETAILS | head -1 | awk '{print $3}'`
done
echo "stage play instance $i is reachable and starting the docker" | tee $MAILLOG
IP=`aws ec2 describe-instances --instance-ids  "$i" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION`
output=`ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker start connect"`
echo "$output" | tee $MAILLOG
done
}

play_elb_reattach() {
for i in `cat $playlist` ; do
echo "Reattach the instance($i) with elb if it's in outofservice" | tee $MAILLOG
status=`aws elb describe-instance-health --load-balancer-name "$playelb"  --region $REGION --instances $i --output text --region $REGION | awk '{print $5}'`
if  [ "InService" != "$status" ] ; then
      echo "detaching the instance from elb $playelb" | tee $MAILLOG
      aws elb deregister-instances-from-load-balancer --load-balancer-name "$playelb" --instances "$i" --output text --region $REGION
      sleep 30
      echo "attaching back the instance to elb $playelb" | tee $MAILLOG
      aws elb register-instances-with-load-balancer --load-balancer-name "$playelb"--instances "$i" --output text --region $REGION     
fi
done
}


play_elb_check() {
for i in `cat $playlist` ; do
status=`aws elb describe-instance-health --load-balancer-name "$playelb"  --region $REGION --instances $i --output text --region $REGION | awk '{print $5}'`
if  [ "InService" != "$status" ] ; then
     echo "Please check!instance $i is in out of service after reattach with ELB as well" | tee $MAILLOG
else 
     echo "instance $i is inservice"  | tee $MAILLOG
fi
done
}


playapi_discover() {
echo "getting the stage playapi server instance id from $playapielb" | tee $MAILLOG
INSTANCES=`aws elb describe-load-balancers --load-balancer-names $playapielb --query 'LoadBalancerDescriptions[*].Instances[*].InstanceId' --output text --region $REGION`
echo $INSTANCES | tee $playapilist
echo $INSTANCES | tee $MAILLOG
if [ -z $playapilist ];then
echo "No servers attached with the $playapielb or the access permission issues" | tee $MAILLOG
exit 1
fi
}

playapi_stop() {
#stopping the play docker 
for i in `cat $playapilist`;do
IP=`aws ec2 describe-instances --instance-ids  "$i" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION`
echo "stopping the docker connect on instance $i($IP)" | tee $MAILLOG
output=`ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker stop connect"`
echo $output | tee $MAILLOG
#stopping the play server
echo "stopping the stage play api server $i" | tee $MAILLOG
stop=`aws ec2 stop-instances --instance-ids $i --output text --region $REGION`
echo "$stop" | tee $MAILLOG
done
}

playapi_start() {
echo "starting the stage play api servers" | tee $MAILLOG
for i in `cat $playapilist`;do
start=`aws ec2 start-instances --instance-ids $i --output text --region $REGION`
echo "stage play api instance started $i" | tee $MAILLOG
echo "$start" | tee $MAILLOG
done

#check instance reachability
for i in `cat $playapilist` ; do
echo "checking the stage play api instance $i reachability" | tee $MAILLOG
status=`aws ec2 describe-instance-status  --instance-ids $i --output text --region $REGION | grep -i DETAILS | head -1 | awk '{print $3}'`
echo "checking the instance ($i) reachability"
while [ "passed" != "$status" ] ; do
      echo "stage play api instance $i is not reachable and waiting for 30sec" | tee $MAILLOG
      sleep 30
      status=`aws ec2 describe-instance-status  --instance-ids $i --output text --region $REGION | grep -i DETAILS | head -1 | awk '{print $3}'`
done
echo "stage play api instance $i is reachable and starting the docker" | tee $MAILLOG
IP=`aws ec2 describe-instances --instance-ids  "$i" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION`
output=`ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker start connect"`
echo "$output" | tee $MAILLOG
done
}

playapi_elb_reattach () {
for i in `cat $playapilist` ; do
echo "Reattach the instance($i) with elb if it's in outofservice" | tee $MAILLOG
status=`aws elb describe-instance-health --load-balancer-name "$playapielb"  --region $REGION --instances $i --output text --region $REGION | awk '{print $5}'`
if  [ "InService" != "$status" ] ; then
      echo "detaching the instance from elb $playelb" | tee $MAILLOG
      aws elb deregister-instances-from-load-balancer --load-balancer-name "$playapielb" --instances "$i" --output text --region $REGION
      sleep 30
      echo "attaching back the instance to elb $playapielb" | tee $MAILLOG
      aws elb register-instances-with-load-balancer --load-balancer-name "$playapielb"--instances "$i" --output text --region $REGION     
fi
done
}


playapi_elb_check () {
for i in `cat $playapilist` ; do
status=`aws elb describe-instance-health --load-balancer-name "$playapielb"  --region $REGION --instances $i --output text --region $REGION | awk '{print $5}'`
if  [ "InService" != "$status" ] ; then
     echo "Please check!instance $i is in out of service after reattach with ELB as well" | tee $MAILLOG
else 
     echo "instance $i is inservice"  | tee $MAILLOG
fi
done
}


es_discover() {
echo "fetch the stage es servers instance id using $es_tag tagging in AWS" | tee $MAILLOG
INSTANCES=`aws ec2 describe-instances --filters Name=tag:Ansible,Values=$es_tag --output text --region $REGION | grep -i INSTANCES | awk '{print $8}'`
echo $INSTANCES | tee $MAILLOG
echo $INSTANCES | tee $eslist
if [ -z $eslist ];then
echo "No servers with the $es_tag tagging or the access permission issues"
exit 1
fi
}

es_stop() {
#stopping the es docker 
for i in `cat $eslist`;do
IP=`aws ec2 describe-instances --instance-ids  "$i" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION`
echo "stopping the docker elasticsearch on instance $i and IP $IP" | tee $MAILLOG
output=`ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker stop elasticsearch"`
echo $output | tee $MAILLOG
echo "stopping the stage es server $i" | tee $MAILLOG
stop=`aws ec2 stop-instances --instance-ids $i --output text --region $REGION`
echo $stop | tee $MAILLOG
done
}

es_start() {
echo "starting the stage es servers" | tee $MAILLOG
for i in `cat $eslist`;do
start=`aws ec2 start-instances --instance-ids $i --output text --region $REGION`
echo "stage es instance started $i" | tee $MAILLOG
echo "$start" | tee $MAILLOG
done
#check instance reachability
for i in `cat $eslist` ; do
echo "checking the stage es instance $i reachability" | tee $MAILLOG
status=`aws ec2 describe-instance-status  --instance-ids $i --output text --region $REGION | grep -i DETAILS | head -1 | awk '{print $3}'`
echo "checking the instance ($i) reachability"
while [ "passed" != "$status" ] ; do
      echo "stage es instance $i is not reachable and wait for 30sec" | tee $MAILLOG
      sleep 30
      status=`aws ec2 describe-instance-status  --instance-ids $i --output text --region $REGION | grep -i DETAILS | head -1 | awk '{print $3}'`
done
echo "stage es instance $i is reachable and starting the docker" | tee $MAILLOG
IP=`aws ec2 describe-instances --instance-ids  "$i" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION`
output=`ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker start elasticsearch"`
echo "$output" | tee $MAILLOG
done
}

riak_discover() {
echo "getting the stage riak server instance id from $riakelb" | tee $MAILLOG
INSTANCES=`aws elb describe-load-balancers --load-balancer-names $riakelb --query 'LoadBalancerDescriptions[*].Instances[*].InstanceId' --output text --region $REGION`
echo $INSTANCES | tee $riaklist
echo $INSTANCES | tee $MAILLOG
if [ -z $riaklist ];then
echo "No servers attached with $riakelb or the access permission issues" | tee $MAILLOG
exit 1
fi
}

riak_stop() {
for i in `cat $riaklist`;do
IP=`aws ec2 describe-instances --instance-ids  "$i" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION`
echo "stopping the Riak on instance $i ($IP)" | tee $MAILLOG
output=`ssh -q -i $RIAK_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $RIAK_USERNAME@$IP "sudo riak stop"`
echo $output | tee $MAILLOG
echo "stopping the stage riak server $i" | tee $MAILLOG
stop=`aws ec2 stop-instances --instance-ids $i --output text --region $REGION`
echo "$stop" | tee $MAILLOG
done
}

riak_start() {
echo "starting the stage riak servers" | tee $MAILLOG
for i in `cat $riaklist`;do
start=`aws ec2 start-instances --instance-ids $i --output text --region $REGION`
echo "stage riak instance started $i" | tee $MAILLOG
echo "$start" | tee $MAILLOG
done
#check instance reachability
for i in `cat $riaklist` ; do
echo "checking the stage riak instance $i reachability" | tee $MAILLOG
status=`aws ec2 describe-instance-status  --instance-ids $i --output text --region $REGION | grep -i DETAILS | head -1 | awk '{print $3}'`
while [ "passed" != "$status" ] ; do
      echo "stage riak instance $i is not reachable and wait for 30sec" | tee $MAILLOG
      sleep 30
      status=`aws ec2 describe-instance-status  --instance-ids $i --output text --region $REGION | grep -i DETAILS | head -1 | awk '{print $3}'`
done
echo "stage riak instance $i is reachable and starting the riak" | tee $MAILLOG
IP=`aws ec2 describe-instances --instance-ids  "$i" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION`
ssh -q -i $RIAK_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $RIAK_USERNAME@$IP "sudo echo deadline > /sys/block/xvda/queue/scheduler"
ssh -q -i $RIAK_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $RIAK_USERNAME@$IP "sudo echo 1024 > /sys/block/xvda/queue/nr_requests"
output=`ssh -q -i $RIAK_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $RIAK_USERNAME@$IP "sudo riak start"`
echo "$output" | tee $MAILLOG
done
}

riak_status_check() {
for i in `cat $riaklist` ; do
status=ssh -q -i $RIAK_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $RIAK_USERNAME@$IP "sudo riak ping"
echo "checking the riak status $i"  | tee $MAILLOG
if  [ "pong" != "$status" ] ; then
  echo "Riak not started on $i and starting it again"  | tee $MAILLOG
  output=`ssh -q -i $RIAK_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $RIAK_USERNAME@$IP "sudo riak start"`
  echo "$output"  | tee $MAILLOG
else
  echo "Riak already running on the instance $i" | tee $MAILLOG
fi
done
}

riak_elb_reattach() {
for i in `cat $riaklist` ; do
status=`aws elb describe-instance-health --load-balancer-name "$riakelb"  --region $REGION --instances $i --output text --region $REGION | awk '{print $5}'`
echo "Reattach the instance($i) with elb if it's in outofservice" | tee $MAILLOG
if  [ "InService" != "$status" ] ; then
      echo "detaching the instance from elb $riakelb" | tee $MAILLOG
      aws elb deregister-instances-from-load-balancer --load-balancer-name "$riakelb" --instances "$i" --output text --region $REGION
      sleep 30
      echo "attaching back the instance to elb $riakelb" | tee $MAILLOG
      aws elb register-instances-with-load-balancer --load-balancer-name "$riakelb"--instances "$i" --output text --region $REGION     
fi
done
}
riak_elb_check() {
for i in `cat $riaklist` ; do
status=`aws elb describe-instance-health --load-balancer-name "$riakelb"  --region $REGION --instances $i --output text --region $REGION | awk '{print $5}'`
if  [ "InService" != "$status" ] ; then
     echo "Please check!instance $i is in out of service after reattach with ELB as well" | tee $MAILLOG
else 
     echo "instance $i is inservice"  | tee $MAILLOG
fi
done
}

xray_discover() {
echo "getting the stage xray server instance id from $xrayelb" | tee $MAILLOG
INSTANCES=`aws elb describe-load-balancers --load-balancer-names $xrayelb --query 'LoadBalancerDescriptions[*].Instances[*].InstanceId' --output text --region $REGION`
echo $INSTANCES | tee $xraylist
echo $INSTANCES | tee $MAILLOG
if [ -z $xraylist ];then
echo "No servers atatched with $xrayelb 
or the access permission issues"
exit 1
fi
}

xray_stop() {
#stopping the play docker 
for i in `cat $xraylist`;do
IP=`aws ec2 describe-instances --instance-ids  "$i" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION`
echo "stopping the docker xray,elasticsearch,influx on instance $i($IP)" | tee $MAILLOG
output=`ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker stop xray elasticsearch influx"`
echo $output | tee $MAILLOG
echo "stopping the stage xray server" | tee $MAILLOG
stop=`aws ec2 stop-instances --instance-ids $i --output text --region $REGION`
echo $stop | tee $MAILLOG
done
}

xray_start() {
echo "starting the stage xray servers" | tee $MAILLOG
for i in `cat $xraylist`;do
start=`aws ec2 start-instances --instance-ids $i --output text --region $REGION`
echo "stage play instance started $i" | tee $MAILLOG
echo "$start" | tee $MAILLOG
done
#check instance reachability
for i in `cat $xraylist` ; do
echo "checking the stage xray instance $i reachability" | tee $MAILLOG
status=`aws ec2 describe-instance-status  --instance-ids $i --output text --region $REGION | grep -i DETAILS | head -1 | awk '{print $3}'`
while [ "passed" != "$status" ] ; do
    echo "stage xray instance $i is not reachable and wait for 30sec" | tee $MAILLOG
      sleep 30

      status=`aws ec2 describe-instance-status  --instance-ids $i --output text --region $REGION | grep -i DETAILS | head -1 | awk '{print $3}'`
done
echo "stage xray instance $i is reachable and starting the docker" | tee $MAILLOG
IP=`aws ec2 describe-instances --instance-ids  "$i" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text --region $REGION`
output1=`ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker start influx"`
output2=`ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker start elasticsearch"`
output3=`ssh -q -i $PRIVATE_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $USERNAME@$IP "docker start xray"`

echo $output1 | tee $MAILLOG
echo $output2 | tee $MAILLOG
echo $output3 | tee $MAILLOG
done
}

xray_elb_reattach() {
for i in `cat $xraylist` ; do
echo "Reattach the instance($i) with elb if it's in outofservice" | tee $MAILLOG
status=`aws elb describe-instance-health --load-balancer-name "$xrayelb"  --region $REGION --instances $i --output text --region $REGION | awk '{print $5}'`
if  [ "InService" != "$status" ] ; then
       echo "detaching the instance from elb $xrayelb" | tee $MAILLOG
      aws elb deregister-instances-from-load-balancer --load-balancer-name "$xrayelb" --instances "$i" --output text --region $REGION
      sleep 10
      echo "attaching back the instance to elb $xrayelb" | tee $MAILLOG
      aws elb register-instances-with-load-balancer --load-balancer-name "$xrayelb"--instances "$i" --output text --region $REGION     
fi
done
}


xray_elb_check() {
for i in `cat $xraylist` ; do

status=`aws elb describe-instance-health --load-balancer-name "$xrayelb"  --region $REGION --instances $i --output text --region $REGION | awk '{print $5}'`
if  [ "InService" != "$status" ] ; then
     echo "Please check!instance $i is in out of service after reattach with ELB as well" | tee $MAILLOG
else 
     echo "instance $i is inservice"  | tee $MAILLOG
fi
done
}


if [ "$ACTION" = "stage_bring_down" ];then
echo "Stopping the play servers"
play_discover
play_stop
echo "Stopping the playapi servers"
playapi_discover
playapi_stop
echo "stopping the Elasticsearch server"
es_discover
es_stop
echo "stopping the xray servers"
xray_discover
xray_stop
echo "stopping the riak server"
riak_discover
riak_stop
elif ["$ACTION" = "stage_bring_up"]
echo "starting the riak server"
riak_discover
riak_start
riak_status_check
riak_elb_reattach
sleep 30
riak_elb_check
echo "starting the es server"
es_discover
es_start
echo "starting the xray server"
xray_discover
xray_start
xray_elb_reattach
sleep 30
xray_elb_check
echo "starting the playapi server"
playapi_discover
playapi_start
playapi_elb_reattach
sleep 30
playapi_elb_check
echo "starting the play server"
play_discover
play_start
play_elb_reattach
sleep 30
play_elb_check

else
echo "Unknown Action"
print_help
fi
cat $MAILLOG | mail -s "\"$EMAIL_SUBJECT\"" -r "$EMAIL_FROM" "$EMAIL_RCPTS"