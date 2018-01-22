#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
ulimit(){
    # read -p "输入open files 数量（默认为131072）:" num
    # [ -z $num] && num='131072'
    # echo "* - nofile $num" >> /etc/security/limits.conf
    echo "* - nofile 131072" >> /etc/security/limits.conf
    echo "修改/etc/security/limits.conf完成，准备重启"
    reboot
}
install_rs(){
    #下载安装
    wget -N --no-check-certificate https://github.com/91yun/serverspeeder/raw/master/serverspeeder.sh && bash serverspeeder.sh
}
install_fs(){
    wget  http://7xpt4s.com1.z0.glb.clouddn.com/install_fs.sh
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
}
install_ss(){
    # yum install -y python-setuptools && easy_install pip
    yum install -y python-setuptools
    yum install -y m2crypto git
    yum install -y unzip
    yum install -y python-pip
    pip install cymysql
}
install_ss1(){
    rm -rf shadowsocks.zip
    rm -rf shadowsocks
    wget http://7xpt4s.com1.z0.glb.clouddn.com/shadowsocks.zip
    unzip shadowsocks.zip
}
install_ss2(){
    rm -rf SS2.zip
    rm -rf shadowsocks
    wget http://7xpt4s.com1.z0.glb.clouddn.com/SS2.zip
    unzip SS2.zip
}
start_sh(){
    wget http://7xpt4s.com1.z0.glb.clouddn.com/start.sh  && bash start.sh
    echo "0 */2 * * * bash /root/start.sh"
}
spam(){
    wget http://7xpt4s.com1.z0.glb.clouddn.com/spam.sh && bash spam.sh
}
speedtest(){
    wget -O speedtest-cli https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py
    chmod +x speedtest-cli
    ./speedtest-cli
}
supervisord(){
    wget http://7xpt4s.com1.z0.glb.clouddn.com/supervisor.sh  && bash supervisor.sh
}
change_rs_kernel(){
	#更换锐速内核
    # rpm -ivh http://soft.91yun.org/ISO/Linux/CentOS/kernel/kernel-firmware-2.6.32-504.3.3.el6.noarch.rpm
    # rpm -ivh http://soft.91yun.org/ISO/Linux/CentOS/kernel/kernel-2.6.32-504.3.3.el6.x86_64.rpm --force
    rpm -ivh ftp://mirror.switch.ch/pool/4/mirror/scientificlinux/6.4/x86_64/updates/security/kernel-firmware-2.6.32-504.3.3.el6.noarch.rpm
    rpm -ivh http://ftp.riken.jp/Linux/scientific/6.4/x86_64/updates/security/kernel-2.6.32-504.3.3.el6.x86_64.rpm --force

}
install_ss3(){
    rm -rf freessr.zip
    rm -rf shadowsocks
    wget http://7xpt4s.com1.z0.glb.clouddn.com/freessr.zip
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
    wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/iptables-pf.sh && chmod +x iptables-pf.sh && bash iptables-pf.sh
}
install_ss3(){
    rm -rf SS3.zip
    rm -rf shadowsocks
    wget http://7xpt4s.com1.z0.glb.clouddn.com/SS3.zip
    unzip SS3.zip
}
while :
do
    echo "部署后端ss脚本："
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
            install_ss3
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
            install_vnstat_iftop
            install_ss
            add_scholar_ipv6_hosts
            change_rs_kernel
            ulimit
        ;;
        *)  
            echo '退出脚本！'
            break;
        ;;
    esac
done
