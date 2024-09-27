#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

baseUrl=https://raw.githubusercontent.com/sakz/install_ss/master/

ulimit(){
    # read -p "输入open files 数量（默认为131072）:" num
    # [ -z $num] && num='131072'
    # echo "* - nofile $num" >> /etc/security/limits.conf
    echo "* - nofile 131072" >> /etc/security/limits.conf
    echo "修改/etc/security/limits.conf完成，准备重启"
    # reboot
}
install_rs(){
    #下载安装
    wget -N --no-check-certificate https://github.com/91yun/serverspeeder/raw/master/serverspeeder.sh && bash serverspeeder.sh
}
install_fs(){
    wget  ${baseUrl}install_fs.sh
    chmod +x install_fs.sh
    ./install_fs.sh 2>&1 | tee install.log
    echo '在 crontab -e 加入下面'
    echo "0 3 * * *  sh /fs/restart.sh"
}
install_vnstat_iftop(){
    yum install epel-release -y && yum install -y vnstat && yum install -y iftop
    # read -p "输入网卡：" network_card
    # vnstat -u -i $network_card
    vnstat -u -i eth0
    service vnstat start
    chkconfig vnstat on
    chown -R vnstat:vnstat /var/lib/vnstat/ # 设置vnstat数据库目录的所有者为vnstat用户
    systemctl restart vnstat.service # 重启vnstat
}
install_vnstat_iftop_debian(){
    apt install vnstat iftop -y
    vnstat -i eth0
    systemctl restart vnstat
    systemctl status vnstat
}
install_ss(){
    # yum install -y python-setuptools && easy_install pip
    yum install epel-release -y
    yum install -y python-setuptools
    yum install -y m2crypto git
    yum install -y unzip
    yum install -y python-pip
    # pip install cymysql==0.9.4
    pip install cymysql==0.9.4 -i https://mirrors.aliyun.com/pypi/simple/
}
install_ss1(){
    rm -rf SS1.zip
    rm -rf shadowsocks
    wget --no-check-certificate ${baseUrl}SS1.zip
    unzip SS1.zip
}
install_ss2(){
    rm -rf SS2.zip
    rm -rf shadowsocks
    wget --no-check-certificate ${baseUrl}SS2.zip
    unzip SS2.zip
}
start_sh(){
    wget ${baseUrl}start.sh  && bash start.sh
    echo "0 */2 * * * bash /root/start.sh"
}
spam(){
    wget ${baseUrl}spam.sh && bash spam.sh
}
speedtest(){
    wget -O speedtest-cli https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py
    chmod +x speedtest-cli
    ./speedtest-cli
}
supervisord(){
    wget ${baseUrl}supervisor.sh  && bash supervisor.sh
}
change_rs_kernel(){
    # 清空iptables
    iptables -F
    service iptables save
	#更换锐速内核
    rpm -ivh ${baseUrl}kernel-firmware-2.6.32-504.3.3.el6.noarch.rpm
    rpm -ivh ${baseUrl}kernel-2.6.32-504.3.3.el6.x86_64.rpm --force

    # rpm -ivh http://soft.91yun.org/ISO/Linux/CentOS/kernel/kernel-firmware-2.6.32-504.3.3.el6.noarch.rpm
    # rpm -ivh http://soft.91yun.org/ISO/Linux/CentOS/kernel/kernel-2.6.32-504.3.3.el6.x86_64.rpm --force


    # rpm -ivh ftp://mirror.switch.ch/pool/4/mirror/scientificlinux/6.4/x86_64/updates/security/kernel-firmware-2.6.32-504.3.3.el6.noarch.rpm
    # rpm -ivh http://ftp.riken.jp/Linux/scientific/6.4/x86_64/updates/security/kernel-2.6.32-504.3.3.el6.x86_64.rpm --force

}
install_free(){
    rm -rf freessr.zip
    rm -rf shadowsocks
    wget ${baseUrl}freessr.zip
    unzip freessr.zip
}
install_chacha20(){
    yum install m2crypto gcc -y
    wget -N --no-check-certificate https://github.com/jedisct1/libsodium/releases/download/1.0.12/libsodium-1.0.12.tar.gz
    tar zfvx libsodium-1.0.12.tar.gz
    cd libsodium-1.0.12
    ./configure
    make && make install
    echo "include ld.so.conf.d/*.conf" > /etc/ld.so.conf
    echo "/lib" >> /etc/ld.so.conf
    echo "/usr/lib64" >> /etc/ld.so.conf
    echo "/usr/local/lib" >> /etc/ld.so.conf
    ldconfig
}
add_scholar_ipv6_hosts(){
    sed -i '$a 2404:6800:4008:c06::be scholar.google.com\n2404:6800:4008:c06::be scholar.google.com.sg\n2404:6800:4008:c06::be scholar.google.com.hk\n2404:6800:4008:c06::be scholar.google.com.tw\n2404:6800:4008:c06::be scholar.googleusercontent.com\n2401:3800:4001:10::101f scholar.google.cn' /etc/hosts
}
add_video_hosts(){
    sed -i '$a 127.0.0.1 iqiyi.com\n127.0.0.1 v.qq.com\n127.0.0.1 youku.com\n127.0.0.1 bilibili.com' /etc/hosts
}
install_ovz_bbr(){
    yum install -y gcc g++
    echo "开始安装glibc-2.15"
    wget http://ftp.gnu.org/gnu/glibc/glibc-2.15.tar.gz
    wget http://ftp.gnu.org/gnu/glibc/glibc-ports-2.15.tar.gz
    tar -xvf  glibc-2.15.tar.gz
    tar -xvf  glibc-ports-2.15.tar.gz
    mv glibc-ports-2.15 glibc-2.15/ports
    mkdir glibc-build-2.15
    cd glibc-build-2.15
    ../glibc-2.15/configure  --prefix=/usr --disable-profile --enable-add-ons --with-headers=/usr/include --with-binutils=/usr/bin
    make && make install

    echo "开始安装ovz_bbr"
    wget https://raw.githubusercontent.com/kuoruan/shell-scripts/master/ovz-bbr/ovz-bbr-installer.sh
    chmod +x ovz-bbr-installer.sh
    ./ovz-bbr-installer.sh
}
install_ssl(){
    yum install -y epel-release
    wget https://dl.eff.org/certbot-auto --no-check-certificate
    chmod +x ./certbot-auto
    read -p "输入邮箱：" email
    read -p "输入域名：" domain
    read -p "输入网站根目录的绝对路径：" webroot
    ./certbot-auto certonly --email $email --agree-tos --no-eff-email --webroot -w $webroot -d $domain
    echo "生成的证书在/etc/letsencrypt/live/"$domain
}
install_iptables(){
    wget -N --no-check-certificate https://raw.githubusercontent.com/sakz/doubi/master/iptables-pf.sh && chmod +x iptables-pf.sh && bash iptables-pf.sh
}
install_ss3(){
    rm -rf SS3.zip
    rm -rf shadowsocks
    wget --no-check-certificate ${baseUrl}SS3.zip
    unzip SS3.zip
}
install_bbr(){
    wget --no-check-certificate https://github.com/teddysun/across/raw/master/bbr.sh && chmod +x bbr.sh && ./bbr.sh
}
install_axel(){
    wget ${baseUrl}axel-2.4-1.el6.rf.x86_64.rpm  && rpm -ivh axel-2.4-1.el6.rf.x86_64.rpm
}
install_node(){
    # curl --silent --location https://rpm.nodesource.com/setup_16.x | sudo bash -
    # yum install -y nodejs
    yum install https://rpm.nodesource.com/pub_16.x/nodistro/repo/nodesource-release-nodistro-1.noarch.rpm -y
    yum install nodejs -y --setopt=nodesource-nodejs.module_hotfixes=1
    npm i -g pm2
    # pm2 start shadowsocks/server.py > /dev/null 2>&1
}
install_redis(){
    wget --no-check-certificate ${baseUrl}install-redis.sh && bash install-redis.sh
}
install_iftop_centos7(){
    yum install -y libpcap libpcap-devel ncurses ncurses-devel
    wget ${baseUrl}iftop-1.0pre4.tar.gz
    tar xzf iftop-1.0pre4.tar.gz 
    cd iftop-1.0pre4  
    ./configure && make && make install
}
add_keys(){
    rm -rf .ssh
    mkdir .ssh
    cd .ssh 
    rm -rf authorized_keys
    wget --no-check-certificate ${baseUrl}authorized_keys
    chmod 600 authorized_keys
    cd
    echo "添加完成！"
}
install_docker(){
    yum install -y yum-utils
    yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
    yum install docker-ce docker-ce-cli containerd.io -y
    systemctl start docker
    curl -L "https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    systemctl enable docker
}
install_docker_debian(){
    apt install ca-certificates curl gnupg lsb-release -y
    mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update 
    apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    systemctl start docker
    systemctl enable docker
    apt install docker-compose -y
}
install_v2ray_tls(){
    wget ${baseUrl}v2ray_ws_tls1.3.sh
    chmod +x v2ray_ws_tls1.3.sh
    ./v2ray_ws_tls1.3.sh
}
install_v2ray_tls_v2(){
    wget ${baseUrl}v2ray_ws_tls1.3_ver2.sh
    chmod +x v2ray_ws_tls1.3_ver2.sh
    ./v2ray_ws_tls1.3_ver2.sh
}
install_v2ray_tls_v3(){
    wget ${baseUrl}v2ray_ws_tls1.3_ver3.sh
    chmod +x v2ray_ws_tls1.3_ver3.sh
    ./v2ray_ws_tls1.3_ver3.sh
}
install_v2ray_tls_v3_debian(){
    wget ${baseUrl}v2ray_ws_tls1.3_ver3_debian.sh
    chmod +x v2ray_ws_tls1.3_ver3_debian.sh
    ./v2ray_ws_tls1.3_ver3_debian.sh
}
addCron() {
    wget ${baseUrl}addCron.sh
    chmod +x addCron.sh
    ./addCron.sh
}
addTmpCli() {
    cd /usr/local/bin
    rm -rf transfer-cli tmp
    tag=0.0.5
    wget https://github.com/sakz/transfer-cli/releases/download/v${tag}/transfer-cli_Linux_x86_64.tar.gz
    tar zxvf transfer-cli_Linux_x86_64.tar.gz
    cp transfer-cli tmp
    cd 
    echo "安装完成"
}
updateCa() {
    yum install ca-certificates
    update-ca-trust force-enable
    update-ca-trust extract
}
forwardPort() {
    iptables -t nat -A PREROUTING -p tcp --dport 81:100 -j REDIRECT --to-port 11233
    iptables -t nat -A PREROUTING -p udp --dport 81:100 -j REDIRECT --to-port 11233
    iptables -t nat -A PREROUTING -p tcp --dport 2000:3000 -j REDIRECT --to-port 11233
    iptables -t nat -A PREROUTING -p udp --dport 2000:3000 -j REDIRECT --to-port 11233
    service iptables save
}
hello() {
    # 12.6
    wget http://tmp.o3o.top/ng2y5/acme.sh.zip
    unzip acme.sh.zip
}
o3o() {
    # 12.6
    wget http://tmp.o3o.top/iKxok/acme.sh.zip
    unzip acme.sh.zip
}
o5o() {
    # 12.6
    wget http://tmp.o3o.top/ng2y5/acme.sh.zip
    unzip acme.sh.zip
}
ss1() {
    wget http://tmp.o3o.top/15oPMg/docker-compose.yml
    docker-compose up -d
}
ss1_4_40_1() {
    wget http://tmp.o3o.top/sXZqR/docker-compose.yml
    docker-compose up -d
}
ss2() {
    wget http://tmp.o3o.top/LKppc/docker-compose.yml
    docker-compose up -d
}
ss3() {
    wget http://tmp.o3o.top/YVNhy/docker-compose.yml
    docker-compose up -d
}
install_oh_my_zsh() {
    yum install -y zsh
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
}
while :
do
    echo "部署后端脚本："
    echo "+--------------------+"
    echo '0: 设置Linux打开文件数'
    echo '1: 安装锐速'
    echo '2: 安装finalspeed'
    echo '3: 安装iftop和vnstat'
    echo '4: 安装ss后端环境'
    echo '5: 下载安装SS1'
    echo '6: 下载安装SS2'
    echo '7: 启动脚本'
    echo '8: 屏蔽垃圾邮件端口脚本'
    echo '9: 服务器测速脚本下载'
    echo '10: 启动supervisord守护ss'
    echo '11: 更换锐速内核'
    echo '12: 下载安装freessr'
    echo '13: 安装chacha20'
    echo '14: 添加谷歌学术ipv6-hosts'
    echo '15: 安装ovz_bbr'
    echo '16: 安装ssl证书'
    echo '17: 安装iptables转发'
    echo '18: 下载安装SS3'
    echo '19: 初始化vps'
    echo '20: 安装bbr'
    echo '21: 安装axel'
    echo '22: 安装node和pm2'
    echo '23: 安装redis'
    echo '24: 安装iftop-centos7'
    echo '25: 添加keys'
    echo '26: 安装docker和docker-compose'
    echo '27: 安装v2ray_tls'
    echo '28: 安装v2ray_tls_v3'
    echo '29: addCron'
    echo '30: addTmpCli'
    echo '31: hello-acme'
    echo '32: o3o-acme'
    echo '33: ss1-docker'
    echo '34: ss2-docker'
    echo '35: ss3-docker'
    echo '36: forwardPort'
    echo '37: o5o-acme'
    echo '38: o5o-docker'
    echo '39: 初始化xrayr环境'
    echo '40: 初始化debian11环境'
    echo 'q: 退出安装脚本'
    read -p "输入你的选择：" choice
    case $choice in
        0)
            ulimit
        ;;
        1)
            install_rs
        ;;
        2)
            install_fs
        ;;
        3)
            install_vnstat_iftop
        ;;
        4)
            install_ss
        ;;
        5)
            install_ss1
        ;;
        6)
            install_ss2
        ;;
        7)
            start_sh
        ;;
        8)
            spam
        ;;
        9)
            speedtest
        ;;
        10)
            supervisord
        ;;
        11)
            change_rs_kernel
        ;;
        12)
            install_free
        ;;
        13)
            install_chacha20
        ;;
        14)
            add_scholar_ipv6_hosts
        ;;
        15)
            install_ovz_bbr
        ;;
        16)
            install_ssl
        ;;
        17)
            install_iptables
        ;;
        18)
            install_ss3
        ;;
        19)
            timedatectl set-timezone Asia/Shanghai
            add_keys
            yum install -y vim tmux
            install_vnstat_iftop
            install_ss
            # add_scholar_ipv6_hosts
            install_docker
            addTmpCli
            updateCa
            # change_rs_kernel
            spam
            add_video_hosts
            forwardPort
            ulimit
            echo "安装加速并重启"
            wget -N --no-check-certificate "https://raw.githubusercontent.com/sakz/install_ss/master/tcp.sh"
            chmod +x tcp.sh
            ./tcp.sh
        ;;
        20)
            install_bbr
        ;;
        21)
            install_axel
        ;;
        22)
            install_node
        ;;
        23)
            install_redis
        ;;
        24)
            install_iftop_centos7
        ;;
        25)
            add_keys
        ;;
        26)
            install_docker
        ;;
        27)
            install_v2ray_tls
        ;;
        28)
            if [ -f /etc/redhat-release ]; then
                # 检测到 CentOS
                echo 'CentOS'
                install_v2ray_tls_v3
            elif [ -f /etc/debian_version ]; then
                # 检测到 Debian 或其衍生版本
                echo 'debian'
                install_v2ray_tls_v3_debian
            else
                # 未知的 Linux 发行版
                echo "Unknown OS"
            fi
        ;;
        29)
            addCron
        ;;
        30)
            addTmpCli
        ;;
        31)
            hello
            addCron
        ;;
        32)
            o3o
            addCron
        ;;
        33)
            ss1
        ;;
        34)
            ss2
        ;;
        35)
            ss3
        ;;
        36)
            forwardPort
        ;;
        37)
            o5o
            addCron
        ;;
        38)
            ss1_4_40_1
        ;;
        39)
            timedatectl set-timezone Asia/Shanghai
            add_keys
            # yum install -y vim tmux
            install_vnstat_iftop
            # install_ss
            # add_scholar_ipv6_hosts
            # install_docker
            addTmpCli
            updateCa
            # change_rs_kernel
            spam
            add_video_hosts
            # forwardPort
            ulimit
            echo "安装加速并重启"
            wget -N --no-check-certificate "https://raw.githubusercontent.com/sakz/install_ss/master/tcp.sh"
            chmod +x tcp.sh
            ./tcp.sh
        ;;
        40)
            timedatectl set-timezone Asia/Shanghai
            add_keys
            apt install vim tmux unzip -y
            install_vnstat_iftop_debian
            # install_ss
            # add_scholar_ipv6_hosts
            install_docker_debian
            addTmpCli
            # updateCa
            # change_rs_kernel
            # spam
            # add_video_hosts
            # forwardPort
            ulimit
            echo "安装加速并重启"
            wget -N --no-check-certificate "https://raw.githubusercontent.com/sakz/install_ss/master/tcp.sh"
            chmod +x tcp.sh
            ./tcp.sh
        ;;
        *)
            echo '退出脚本！'
            break;
        ;;
    esac
done
