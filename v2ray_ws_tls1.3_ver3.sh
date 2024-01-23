#!/bin/bash

baseUrl=https://raw.githubusercontent.com/sakz/install_ss/master/

#判断系统
if [ ! -e '/etc/redhat-release' ]; then
echo "仅支持centos7"
exit
fi
if  [ -n "$(grep ' 6\.' /etc/redhat-release)" ] ;then
echo "仅支持centos7"
exit
fi

function blue(){
    echo -e "\033[34m\033[01m $1 \033[0m"
}
function green(){
    echo -e "\033[32m\033[01m $1 \033[0m"
}
function red(){
    echo -e "\033[31m\033[01m $1 \033[0m"
}
function yellow(){
    echo -e "\033[33m\033[01m $1 \033[0m"
}


#安装nginx
install_nginx(){
    green "====编译安装nginx耗时时间较长，请耐心等待===="
    sleep 1
    systemctl stop firewalld
    systemctl disable firewalld
    CHECK=$(grep SELINUX= /etc/selinux/config | grep -v "#")
    if [ "$CHECK" == "SELINUX=enforcing" ]; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
    if [ "$CHECK" == "SELINUX=permissive" ]; then
         sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
         setenforce 0
    fi
    cd /etc
    wget  ${baseUrl}nginx.zip
    yum install -y unzip
    yum install -y openssl
    unzip nginx.zip
    
    # green "====输入解析到此VPS的域名===="
    # read domain
    if [ -z "$1" ];then
        green "====输入解析到此VPS的域名===="
        read domain
    else
        domain=$1
    fi
    
cat > /etc/nginx/conf/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /etc/nginx/logs/error.log warn;
pid        /etc/nginx/logs/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/conf/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /etc/nginx/logs/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF

    /etc/nginx/sbin/nginx
	
cat > /etc/nginx/conf.d/default.conf<<-EOF
server { 
    listen       80;
    server_name  *.$domain;
    rewrite ^(.*)$  https://\$host\$1 permanent; 
}
server {
    listen 443 ssl http2;
    listen 444 ssl http2;
    server_name $domain;
    root /etc/nginx/html;
    index index.php index.html;
    ssl_certificate /root/.acme.sh/*.${domain}_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/*.${domain}_ecc/*.$domain.key;
    #TLS 版本控制
    ssl_protocols   TLSv1.3;
    ssl_ciphers     TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256;
    ssl_prefer_server_ciphers   on;
    # 开启 1.3 0-RTT
    ssl_early_data  on;
    ssl_stapling on;
    ssl_stapling_verify on;
    #add_header Strict-Transport-Security "max-age=31536000";
    #access_log /var/log/nginx/access.log combined;
    location /mypath {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:11234; 
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    location /user {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:11233; 
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
}
EOF
    #增加自启动脚本
cat > /etc/rc.d/init.d/autov2ray<<-EOF
#!/bin/sh
#chkconfig: 2345 80 90
#description:autov2ray
/etc/nginx/sbin/nginx
supervisord -c /etc/supervisord.conf
EOF

    #设置脚本权限
    chmod +x /etc/rc.d/init.d/autov2ray
    chkconfig --add autov2ray
    chkconfig autov2ray on

    /etc/nginx/sbin/nginx -s stop
    /etc/nginx/sbin/nginx
}
#安装v2ray
install_v2ray(){
    
    yum install -y wget
    bash <(curl -L -s https://install.direct/go.sh)  
    cd /etc/v2ray/
    rm -f config.json
    wget https://raw.githubusercontent.com/atrandys/v2ray-ws-tls/master/config.json
    v2uuid=$(cat /proc/sys/kernel/random/uuid)
    sed -i "s/aaaa/$v2uuid/;" config.json
    # newpath=$(cat /dev/urandom | head -1 | md5sum | head -c 4)
    newpath=game
    sed -i "s/mypath/$newpath/;" config.json
    sed -i "s/mypath/$newpath/;" /etc/nginx/conf.d/default.conf
    # cd /etc/nginx/html
    # rm -rf /etc/nginx/html/*
    # wget https://github.com/atrandys/v2ray-ws-tls/raw/master/web.zip
    # unzip web.zip
    /etc/nginx/sbin/nginx -s stop
    /etc/nginx/sbin/nginx
    systemctl restart v2ray.service
    systemctl enable v2ray.service
    
    #增加自启动脚本
cat > /etc/rc.d/init.d/autov2ray<<-EOF
#!/bin/sh
#chkconfig: 2345 80 90
#description:autov2ray
/etc/nginx/sbin/nginx
EOF

    #设置脚本权限
    chmod +x /etc/rc.d/init.d/autov2ray
    chkconfig --add autov2ray
    chkconfig autov2ray on

cat > /etc/v2ray/myconfig.json<<-EOF
{
===========配置参数=============
地址：${domain}
端口：443
uuid：${v2uuid}
额外id：64
加密方式：aes-128-gcm
传输协议：ws
别名：myws
路径：${newpath}
底层传输：tls
}
EOF

clear
green
green "安装已经完成"
green 
green "===========配置参数============"
green "地址：${domain}"
green "端口：443"
green "uuid：${v2uuid}"
green "额外id：64"
green "加密方式：aes-128-gcm"
green "传输协议：ws"
green "别名：myws"
green "路径：${newpath}"
green "底层传输：tls"
green 
}

remove_v2ray(){

    /etc/nginx/sbin/nginx -s stop
    systemctl stop v2ray.service
    systemctl disable v2ray.service
    
    rm -rf /usr/bin/v2ray /etc/v2ray
    rm -rf /etc/v2ray
    rm -rf /etc/nginx
    
    green "nginx、v2ray已删除"
    
}

start_menu(){
    clear
    echo
    green " 1. 安装v2ray+ws+tls1.3"
    green " 2. 升级v2ray"
    green " 4. hello"
    green " 5. o3o"
    green " 6. o5o"
    red " 3. 卸载v2ray"
    yellow " 0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    install_nginx
    # install_v2ray
    ;;
    4)
    install_nginx "helloking.win"
    ;;
    5)
    install_nginx "o3o3o.top"
    ;;
    6)
    install_nginx "o5o5o.top"
    ;;
    2)
    bash <(curl -L -s https://install.direct/go.sh)  
    ;;
    3)
    remove_v2ray 
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    red "请输入正确数字"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu
