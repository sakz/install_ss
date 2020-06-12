#! /bin/bash

num=$(docker ps | wc -l)
echo $num
if [ "$num" == "2" ];then
    docker-compose restart
fi