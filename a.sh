#!/bin/bash

fnRun(){
  if [ -z "$1" ];then
    read domain
    else
    domain=$1
  fi
  echo $domain
}

fnRun "helloking.win"
# fnRun
