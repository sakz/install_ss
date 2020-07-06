#!/bin/bash

baseUrl=https://raw.githubusercontent.com/sakz/install_ss/master/

wget  ${baseUrl}checkV2ray.sh
wget  ${baseUrl}cleanDockerLog.sh

echo "* * * * * bash /root/checkV2ray.sh" >> /var/spool/cron/root
echo "0 * * * * bash /root/cleanDockerLog.sh" >> /var/spool/cron/root