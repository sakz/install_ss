#!/bin/bash

baseUrl=https://raw.githubusercontent.com/sakz/install_ss/master/

wget  ${baseUrl}checkV2ray.sh
wget  ${baseUrl}cleanDockerLog.sh

chmod +x checkV2ray.sh
chmod +x cleanDockerLog.sh


(
    crontab -l 2>/dev/null
    echo "* * * * * bash /root/checkV2ray.sh"
    echo "0 0 * * * bash /root/cleanDockerLog.sh"
    echo "33 0 * * * /root/.acme.sh/acme.sh --cron --home /root/.acme.sh > /dev/null"
    echo "35 4 * * * /etc/nginx/sbin/nginx -s reload"
    echo "0 */2 * * * rm -rf /etc/nginx/logs/*.log"
) | crontab -


# echo "* * * * * bash /root/checkV2ray.sh" >> /var/spool/cron/root
# echo "0 0 * * * bash /root/cleanDockerLog.sh" >> /var/spool/cron/root
# echo "33 0 * * * /root/.acme.sh/acme.sh --cron --home /root/.acme.sh > /dev/null" >> /var/spool/cron/root
# echo "35 4 * * * /etc/nginx/sbin/nginx -s reload" >> /var/spool/cron/root
# echo "0 */2 * * * rm -rf /etc/nginx/logs/*.log" >> /var/spool/cron/root