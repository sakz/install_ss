#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检测主要网卡名称（排除 lo 回环接口）
detect_network_interface() {
    # 优先获取有默认路由的接口
    local interface=$(ip route | grep default | awk '{print $5}' | head -n 1)
    
    # 如果没有找到，尝试获取第一个非 lo 的活跃接口
    if [ -z "$interface" ]; then
        interface=$(ip link show | grep -E "^[0-9]+: " | grep -v "lo:" | awk -F': ' '{print $2}' | head -n 1)
    fi
    
    echo "$interface"
}

# 配置 iptables 规则
configure_iptables_rules() {
    echo -e "${GREEN}=== iptables 端口转发配置工具 ===${NC}\n"
    
    # 自动检测网卡
    detected_interface=$(detect_network_interface)
    echo -e "${YELLOW}检测到的网卡名称: ${detected_interface}${NC}"
    read -p "按 Enter 使用检测到的网卡，或手动输入网卡名称: " network_interface
    network_interface=${network_interface:-$detected_interface}
    
    # 验证网卡是否存在
    if ! ip link show "$network_interface" &>/dev/null; then
        echo -e "${RED}错误: 网卡 '$network_interface' 不存在！${NC}"
        exit 1
    fi
    
    # 获取跳转端口
    read -p "输入跳转目标端口 (默认: 10593): " jump_port
    jump_port=${jump_port:-10593}
    
    # 获取源端口范围
    read -p "输入源端口范围 (默认: 10595:11596): " destination_port
    destination_port=${destination_port:-10595:11596}
    
    echo -e "\n${GREEN}配置信息:${NC}"
    echo "  网卡: $network_interface"
    echo "  源端口: $destination_port"
    echo "  目标端口: $jump_port"
    echo ""
    
    # 清除可能存在的旧规则（避免重复）
    iptables -t nat -D PREROUTING -i "$network_interface" -p udp --dport "$destination_port" -j DNAT --to-destination ":$jump_port" 2>/dev/null
    ip6tables -t nat -D PREROUTING -i "$network_interface" -p udp --dport "$destination_port" -j DNAT --to-destination ":$jump_port" 2>/dev/null
    
    # 添加新规则
    echo -e "${YELLOW}正在配置 IPv4 规则...${NC}"
    iptables -t nat -A PREROUTING -i "$network_interface" -p udp --dport "$destination_port" -j DNAT --to-destination ":$jump_port"
    
    echo -e "${YELLOW}正在配置 IPv6 规则...${NC}"
    ip6tables -t nat -A PREROUTING -i "$network_interface" -p udp --dport "$destination_port" -j DNAT --to-destination ":$jump_port"
    
    # 立即保存规则（使其在重启后生效）
    echo -e "${YELLOW}正在保存 iptables 规则...${NC}"
    
    # 检测系统并使用相应的保存命令
    if command -v netfilter-persistent &>/dev/null; then
        # Debian/Ubuntu 系统
        netfilter-persistent save
    elif command -v iptables-save &>/dev/null; then
        # 通用方法
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > /etc/iptables.rules
        ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || ip6tables-save > /etc/ip6tables.rules
    fi
    
    # 创建持久化脚本
    create_persistent_script "$network_interface" "$jump_port" "$destination_port"
    
    echo -e "\n${GREEN}✓ 配置完成！${NC}"
    echo -e "${GREEN}✓ iptables 规则已立即生效${NC}"
    echo -e "${GREEN}✓ 规则已配置为开机自动加载${NC}\n"
    
    # 显示当前规则
    echo -e "${YELLOW}当前 NAT 规则 (IPv4):${NC}"
    iptables -t nat -L PREROUTING -n -v | grep "$jump_port"
    echo -e "\n${YELLOW}当前 NAT 规则 (IPv6):${NC}"
    ip6tables -t nat -L PREROUTING -n -v | grep "$jump_port"
}

# 创建持久化脚本和服务
create_persistent_script() {
    local interface=$1
    local jump=$2
    local dest=$3
    
    # 创建规则应用脚本
    script_file="/usr/local/bin/apply-iptables-rules.sh"
    
    cat > "$script_file" << EOF
#!/bin/bash
# iptables 端口转发规则自动应用脚本

# 等待网络接口就绪
sleep 2

# 清除旧规则
iptables -t nat -D PREROUTING -i "$interface" -p udp --dport "$dest" -j DNAT --to-destination ":$jump" 2>/dev/null
ip6tables -t nat -D PREROUTING -i "$interface" -p udp --dport "$dest" -j DNAT --to-destination ":$jump" 2>/dev/null

# 应用新规则
iptables -t nat -A PREROUTING -i "$interface" -p udp --dport "$dest" -j DNAT --to-destination ":$jump"
ip6tables -t nat -A PREROUTING -i "$interface" -p udp --dport "$dest" -j DNAT --to-destination ":$jump"

echo "iptables 规则已应用"
EOF
    
    chmod +x "$script_file"
    
    # 创建 systemd 服务
    systemd_service="/etc/systemd/system/apply-iptables-rules.service"
    
    cat > "$systemd_service" << EOF
[Unit]
Description=Apply iptables port forwarding rules at startup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$script_file
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载并启用服务
    systemctl daemon-reload
    systemctl enable apply-iptables-rules.service
}

# 安装必要的工具
install_dependencies() {
    if ! command -v iptables &>/dev/null; then
        echo -e "${YELLOW}正在安装 iptables...${NC}"
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y iptables iptables-persistent
        elif command -v yum &>/dev/null; then
            yum install -y iptables-services
        fi
    fi
}

# 主函数
main() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用 root 权限运行此脚本${NC}"
        exit 1
    fi
    
    # 安装依赖
    install_dependencies
    
    # 配置规则
    configure_iptables_rules
    
    echo -e "${GREEN}所有操作已完成，无需重启 VPS！${NC}"
}

# 执行主函数
main