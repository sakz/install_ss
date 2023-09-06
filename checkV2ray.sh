#! /bin/bash

num=$(docker-compose ps | grep Up | wc -l)
echo $num
if [ "$num" != "2" ];then
    docker-compose restart
fi