#!/bin/bash

set -e

MAIL_PORTS="25,465,587,2525"

echo "========================================"
echo "Installing mail abuse blocking rules..."
echo "Blocked TCP ports: $MAIL_PORTS"
echo "========================================"

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Please run this script as root."
    exit 1
fi

# =========================
# 安装 iptables-persistent
# =========================

if ! command -v netfilter-persistent >/dev/null 2>&1; then
    echo "[INFO] netfilter-persistent is not installed."

    if command -v apt >/dev/null 2>&1; then
        echo "[INFO] Installing iptables-persistent..."

        export DEBIAN_FRONTEND=noninteractive

        apt update
        apt install -y iptables-persistent

        echo "[OK] iptables-persistent installed."
    else
        echo "[WARNING] apt not found."
        echo "[WARNING] Firewall rules will be applied, but may not survive reboot."
    fi
else
    echo "[OK] netfilter-persistent is already installed."
fi


# =========================
# IPv4 OUTPUT
# =========================

if ! iptables -C OUTPUT \
    -p tcp \
    -m multiport \
    --dports "$MAIL_PORTS" \
    -j REJECT \
    --reject-with tcp-reset 2>/dev/null; then

    iptables -I OUTPUT 1 \
        -p tcp \
        -m multiport \
        --dports "$MAIL_PORTS" \
        -j REJECT \
        --reject-with tcp-reset

    echo "[OK] IPv4 OUTPUT rule added."
else
    echo "[SKIP] IPv4 OUTPUT rule already exists."
fi


# =========================
# IPv4 FORWARD
# =========================

if ! iptables -C FORWARD \
    -p tcp \
    -m multiport \
    --dports "$MAIL_PORTS" \
    -j REJECT \
    --reject-with tcp-reset 2>/dev/null; then

    iptables -I FORWARD 1 \
        -p tcp \
        -m multiport \
        --dports "$MAIL_PORTS" \
        -j REJECT \
        --reject-with tcp-reset

    echo "[OK] IPv4 FORWARD rule added."
else
    echo "[SKIP] IPv4 FORWARD rule already exists."
fi


# =========================
# IPv4 DOCKER-USER
# =========================

if iptables -L DOCKER-USER -n >/dev/null 2>&1; then

    if ! iptables -C DOCKER-USER \
        -p tcp \
        -m multiport \
        --dports "$MAIL_PORTS" \
        -j REJECT \
        --reject-with tcp-reset 2>/dev/null; then

        iptables -I DOCKER-USER 1 \
            -p tcp \
            -m multiport \
            --dports "$MAIL_PORTS" \
            -j REJECT \
            --reject-with tcp-reset

        echo "[OK] IPv4 DOCKER-USER rule added."
    else
        echo "[SKIP] IPv4 DOCKER-USER rule already exists."
    fi

else
    echo "[SKIP] DOCKER-USER chain not found. Docker may not be installed."
fi


# =========================
# IPv6
# =========================

if command -v ip6tables >/dev/null 2>&1; then

    # IPv6 OUTPUT
    if ! ip6tables -C OUTPUT \
        -p tcp \
        -m multiport \
        --dports "$MAIL_PORTS" \
        -j REJECT \
        --reject-with tcp-reset 2>/dev/null; then

        ip6tables -I OUTPUT 1 \
            -p tcp \
            -m multiport \
            --dports "$MAIL_PORTS" \
            -j REJECT \
            --reject-with tcp-reset

        echo "[OK] IPv6 OUTPUT rule added."
    else
        echo "[SKIP] IPv6 OUTPUT rule already exists."
    fi


    # IPv6 FORWARD
    if ! ip6tables -C FORWARD \
        -p tcp \
        -m multiport \
        --dports "$MAIL_PORTS" \
        -j REJECT \
        --reject-with tcp-reset 2>/dev/null; then

        ip6tables -I FORWARD 1 \
            -p tcp \
            -m multiport \
            --dports "$MAIL_PORTS" \
            -j REJECT \
            --reject-with tcp-reset

        echo "[OK] IPv6 FORWARD rule added."
    else
        echo "[SKIP] IPv6 FORWARD rule already exists."
    fi


    # IPv6 DOCKER-USER
    if ip6tables -L DOCKER-USER -n >/dev/null 2>&1; then

        if ! ip6tables -C DOCKER-USER \
            -p tcp \
            -m multiport \
            --dports "$MAIL_PORTS" \
            -j REJECT \
            --reject-with tcp-reset 2>/dev/null; then

            ip6tables -I DOCKER-USER 1 \
                -p tcp \
                -m multiport \
                --dports "$MAIL_PORTS" \
                -j REJECT \
                --reject-with tcp-reset

            echo "[OK] IPv6 DOCKER-USER rule added."
        else
            echo "[SKIP] IPv6 DOCKER-USER rule already exists."
        fi

    else
        echo "[SKIP] IPv6 DOCKER-USER chain not found."
    fi

else
    echo "[SKIP] ip6tables not found."
fi


# =========================
# 保存规则
# =========================

echo
echo "Saving firewall rules..."

if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
    echo "[OK] Rules saved with netfilter-persistent."
else
    # 兜底保存
    mkdir -p /etc/iptables

    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/iptables/rules.v4
        echo "[OK] IPv4 rules saved to /etc/iptables/rules.v4"
    fi

    if command -v ip6tables-save >/dev/null 2>&1; then
        ip6tables-save > /etc/iptables/rules.v6
        echo "[OK] IPv6 rules saved to /etc/iptables/rules.v6"
    fi
fi


# =========================
# 显示最终规则
# =========================

echo
echo "========================================"
echo "IPv4 mail blocking rules:"
echo "========================================"

iptables -L OUTPUT -n --line-numbers | grep -E '25|465|587|2525' || true
iptables -L FORWARD -n --line-numbers | grep -E '25|465|587|2525' || true

if iptables -L DOCKER-USER -n >/dev/null 2>&1; then
    iptables -L DOCKER-USER -n --line-numbers | grep -E '25|465|587|2525' || true
fi

echo
echo "========================================"
echo "Mail abuse blocking rules installed."
echo "Blocked TCP ports: $MAIL_PORTS"
echo "========================================"
