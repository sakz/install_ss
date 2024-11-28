#!/bin/bash

baseUrl=https://raw.githubusercontent.com/sakz/install_ss/master/

# 检查系统
if [ ! -f /etc/debian_version ]; then
    echo "仅支持Debian"
    exit
fi
# if [ "$(cat /etc/debian_version | cut -d'.' -f1)" -ne "11" ]; then
#     echo "仅支持Debian 11"
#     exit
# fi

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

# 安装nginx
install_nginx(){
    green "====编译安装nginx耗时时间较长，请耐心等待===="
    sleep 1

    # 停止并禁用防火墙 (Debian 使用 ufw 而不是 firewalld)
    systemctl stop ufw
    systemctl disable ufw

    # 检查并禁用 SELinux (Debian 通常没有启用 SELinux, 可以跳过这部分)
    CHECK=$(grep SELINUX= /etc/selinux/config 2>/dev/null | grep -v "#")
    if [ "$CHECK" == "SELINUX=enforcing" ]; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
    if [ "$CHECK" == "SELINUX=permissive" ]; then
        sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi

    cd /etc
    wget ${baseUrl}nginx.zip

    # 使用 apt 代替 yum 安装依赖
    apt update
    apt install -y unzip openssl
    apt install libpcre3 libpcre3-dev -y
    ln -s /usr/lib/x86_64-linux-gnu/libpcre.so.3 /usr/lib/x86_64-linux-gnu/libpcre.so.1

    unzip nginx.zip
    
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
    keepalive_timeout  120;
    client_max_body_size 20m;
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
    ssl_protocols   TLSv1.3;
    ssl_ciphers     TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256;
    ssl_prefer_server_ciphers   on;
    ssl_early_data  on;
    ssl_stapling on;
    ssl_stapling_verify on;
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

    # 增加自启动脚本
cat > /etc/init.d/autov2ray<<-EOF
#!/bin/sh
#chkconfig: 2345 80 90
#description: autov2ray
/etc/nginx/sbin/nginx
supervisord -c /etc/supervisord.conf
EOF

    # 设置脚本权限并启用服务
    chmod +x /etc/init.d/autov2ray
    update-rc.d autov2ray defaults

    /etc/nginx/sbin/nginx -s stop
    /etc/nginx/sbin/nginx
}

remove_v2ray(){
    systemctl stop nginx
    systemctl stop v2ray
    systemctl disable v2ray
    
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/remove-v2ray.sh)
    apt remove -y nginx
    apt autoremove -y
    
    rm -rf /etc/nginx
    rm -rf /usr/local/etc/v2ray
    
    green "nginx、v2ray已删除"
}

start_menu(){
    clear
    echo
    green " 1. 安装v2ray+ws+tls1.3"
    green " 2. 升级v2ray"
    green " 4. 安装v2ray+ws+tls1.3 (域名: helloking.win)"
    green " 5. 安装v2ray+ws+tls1.3 (域名: o3o3o.top)"
    green " 6. 安装v2ray+ws+tls1.3 (域名: o5o5o.top)"
    red " 3. 卸载v2ray"
    yellow " 0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    install_nginx
    install_v2ray
    ;;
    2)
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
    ;;
    3)
    remove_v2ray 
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