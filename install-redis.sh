#!/bin/bash 
read -p "输入要安装的redis版本如（3.2.13）：" version
wget http://download.redis.io/releases/redis-${version}.tar.gz
tar xvzf redis-${version}.tar.gz
cd redis-${version}
make

cp src/redis-server /usr/local/bin/
cp src/redis-cli /usr/local/bin/

#make install

mkdir /etc/redis
mkdir /var/redis

cp utils/redis_init_script /etc/init.d/redis_6379

cp redis.conf /etc/redis/6379.conf

mkdir /var/redis/6379

echo "按下面提示编辑这个文件 /etc/redis/6379.conf"
echo 'Set daemonize to yes'
echo 'Set the pidfile to /var/run/redis_6379.pid'
echo 'Set the logfile to /var/log/redis_6379.log'
echo 'Set the dir to /var/redis/6379'

echo '配置文件目录：/etc/redis'
echo 'redis文件目录：/var/redis'

echo '修改完就可以用下面命名启动了'
echo 'sudo /etc/init.d/redis_6379 start'

echo 'come from : https://redis.io/topics/quickstart'