#!/bin/bash
### Check arguments
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
        --operation)
            OPERATION=$2
            shift
            ;;
        --rds-endpoint)
            RDS_ENDPOINT=$2
            shift
            ;;
       *)
            echo "Unknown argument: $1"
            print_help
            ;;
    esac
    shift
done

if [ -d /mnt/pgbackup ]
then
        echo "directory  exists!"
else
 mkdir -p /mnt/pgbackup
fi
rm -f /mnt/pgbackup/db_restore_cmd.txt

USERNAME=postgres
export PGPASSWORD='postgres'
OUTPUT=/mnt/pgbackup/output.txt
DB_NAME=/mnt/pgbackup/db_name.txt


database_name () {
if [[ $RDS_ENDPOINT = "" ]]; then  echo "No RDS  Name provided ..trying locally."
psql -U $USERNAME -t -A -c 'SELECT datname FROM pg_database' > $OUTPUT
cat $OUTPUT | grep -v template0 | grep -v rdsadmin | grep -v template1 |  grep -v postgres > $DB_NAME
else
psql -h $RDS_ENDPOINT -U $USERNAME -t -A -c 'SELECT datname FROM pg_database' > $OUTPUT
cat $OUTPUT | grep -v template0 | grep -v rdsadmin | grep -v template1 |  grep -v postgres > $DB_NAME
fi
}

database_backup () {
if [ -z $DB_NAME ];then
echo "No DB name in the file..check whether entered RDS endpoint or EC2-DB is correct"
exit 1
fi
if [[ $RDS_ENDPOINT = "" ]]; then  echo "No RDS Name provided ..Doing local backup."
for i in `cat $DB_NAME` ; do
pg_dump -U postgres "$i" > "$i"-$(date -I).sql
done
else
echo "Doing RDS backup"
for i in `cat $DB_NAME` ; do
pg_dump -h $RDS_ENDPOINT -U postgres "$i" > "$i"-$(date -I).sql
done
fi
}

database_restore_cmd () {
if [ -z $DB_NAME ];then
echo "No DB name in the file..check whether entered RDS endpoint or EC2-DB is correct"
exit 1
fi
if [[ $RDS_ENDPOINT = "" ]]; then  echo "No RDS Name provided ..preparing command for local restore."
for i in `cat $DB_NAME`;do
 cat << EOF >> /mnt/pgbackup/db_restore_cmd.txt
psql -U postgres -W $i -f /mnt/$i-$(date -I).sql
EOF
done
else
echo "preparing command for RDS restore"
for i in `cat $DB_NAME` ; do
 cat << EOF >> /mnt/pgbackup/db_restore_cmd.txt
psql -U postgres -W $i -h $RDS_ENDPOINT -f /mnt/$i-$(date -I).sql
EOF
done
fi
}


#Calling functions

if [ "$OPERATION" = "backup" ];then
database_name
database_backup
elif [ "$OPERATION" = "restore-cmd" ];then
database_name
database_restore_cmd
else
echo "Unknown Action"
print_help
fi

