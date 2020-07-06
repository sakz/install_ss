#!/bin/bash

echo "==================== start clean docker containers logs =========================="

logs=$(find /var/lib/docker/containers/ -name *-json.log)
echo $logs

for log in $logs;

do

echo "clean logs: $log"

cat /dev/null > $log

done

echo "==================== end clean docker containers logs  =========================="
