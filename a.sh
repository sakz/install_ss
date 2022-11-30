#!/bin/bash

fnRun(){
  echo $1
  if [ -z "$1" ];then
    read domain
    else
    domain=$1
    exit
  fi
  echo $domain
}

fnRun "helloking.win"
# fnRun
