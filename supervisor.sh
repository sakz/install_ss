#!/usr/bin/env bash

baseUrl=https://raw.githubusercontent.com/sakz/install_ss/master/

yum install -y python-setuptools
easy_install -i https://pypi.tuna.tsinghua.edu.cn/simple "meld3==1.0.2"
easy_install -i https://pypi.tuna.tsinghua.edu.cn/simple "supervisor==3.3.5"
wget -P /etc  ${baseUrl}supervisord.conf
unlink /tmp/supervisor.sock
supervisord -c /etc/supervisord.conf
supervisorctl status
echo "0 5 * * * pkill supervisord; sleep 4; /usr/bin/supervisord -c /etc/supervisord.conf" >> /var/spool/cron/root
curl cip.cc