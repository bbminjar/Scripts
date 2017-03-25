#!/bin/bash
DATE=`date +%F`
TIME=`date +%H-%M-%S`
MAILLOG=/tmp/dd_downtime/stage_mailog_${DATE}-${TIME}.log

playlist=/tmp/dd_downtime/play_instance.txt
playapilist=/tmp/dd_downtime/playapi_instance.txt
eslist=/tmp/dd_downtime/es_instance.txt
riaklist=/tmp/dd_downtime/riak_instance.txt
xraylist=/tmp/dd_downtime/dd_downtime/xray_instance.txt

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


instance_id=`aws ec2 describe-instances   --filters "Name=tag:Ansible,Values=$1" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[InstanceId]' --output text --region $REGION`


api_key{
api_key=*****
app_key=*****
}

downtime{
start=$(date +%s)
end=$(date +%s -d "+$2 hours")
}

schedule{

for i in `cat files.txt`
do
curl -X POST -H "Content-type: application/json" \
-d '{
      "scope": "instance_id:$i",
      "start": '"${start}"',
      "end": '"${end}"'
     }' \
    "https://app.datadoghq.com/api/v1/downtime?api_key=${api_key}&application_key=${app_key}"
done
}

if [ "$ACTION" = "downtime" ];then

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



