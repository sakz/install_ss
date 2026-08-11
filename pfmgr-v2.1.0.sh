#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# pfmgr - nftables TCP/UDP Port Forward Manager
# Debian 12
#
# 默认:
#   TCP + UDP
#   DNAT + MASQUERADE
#
# 支持:
#   install / add / update / delete / list / show / stats
#   apply / clear
#
# 配置数据库:
#   /etc/pfmgr/rules.tsv
#
# 持久化 nftables 配置:
#   /etc/nftables.d/pfmgr.nft
#
# stats:
#   在 FORWARD hook 中统计真实经过的双向数据包，
#   不使用 NAT 链 counter 作为总流量统计。
# ============================================================

APP="pfmgr"
VERSION="2.1.0"

BASE_DIR="/etc/${APP}"
DB="${BASE_DIR}/rules.tsv"
LOCK_FILE="${BASE_DIR}/lock"

NFT_DIR="/etc/nftables.d"
NFT_FILE="${NFT_DIR}/${APP}.nft"
NFT_MAIN="/etc/nftables.conf"

# 沿用上一版 table 名，方便直接升级，不残留旧 NAT 规则。
TABLE="pfmgr_nat"
PRE_CHAIN="prerouting"
POST_CHAIN="postrouting"
STAT_CHAIN="stats_forward"

SYSCTL_FILE="/etc/sysctl.d/99-pfmgr-ip-forward.conf"

# iptables-nft / Docker FORWARD 兼容层
IPT_CHAIN="PFMGR-FORWARD"
INSTALL_PATH="/usr/local/sbin/pfmgr"
SYSTEMD_UNIT="/etc/systemd/system/pfmgr.service"


# ------------------------------------------------------------
# 输出
# ------------------------------------------------------------

red() {
    printf '\033[31m%s\033[0m\n' "$*" >&2
}

green() {
    printf '\033[32m%s\033[0m\n' "$*"
}

yellow() {
    printf '\033[33m%s\033[0m\n' "$*"
}

die() {
    red "错误: $*"
    exit 1
}


# ------------------------------------------------------------
# 帮助
# ------------------------------------------------------------

usage() {
    cat <<EOF
pfmgr v${VERSION} - nftables TCP/UDP 端口转发管理器

用法:

  $0 install

  $0 add <入口端口> <目标IPv4> [目标端口]

  $0 update <入口端口> <目标IPv4> [目标端口]

  $0 delete <入口端口>

  $0 list

  $0 show

  $0 stats

  $0 apply

  $0 firewall-sync

  $0 clear


说明:

  每条规则同时转发 TCP + UDP。

  如果不指定目标端口:
      目标端口 = 入口端口


示例:

  # 安装/初始化
  $0 install

  # TCP+UDP 443 -> 1.2.3.4:443
  $0 add 443 1.2.3.4

  # TCP+UDP 8443 -> 1.2.3.4:443
  $0 add 8443 1.2.3.4 443

  # 把 443 修改到新服务器
  $0 update 443 5.6.7.8

  # 删除 443 转发
  $0 delete 443

  # 查看配置
  $0 list

  # 查看实际 nftables 规则
  $0 show

  # 查看每个端口 TCP/UDP 双向流量
  $0 stats

  # 重新加载配置（nftables + FORWARD 放行）
  $0 apply

  # 只重新同步 FORWARD / Docker 放行链
  $0 firewall-sync

  # 删除全部转发
  $0 clear


stats 说明:

  上行 = 客户端 -> 目标服务器
  下行 = 目标服务器 -> 客户端

  统计从最近一次规则重新加载后开始。
  执行 add/update/delete/apply/clear 或服务器重启后，
  nftables counter 会重新开始计数。

FORWARD / Docker 说明:

  pfmgr 会创建独立的 iptables-nft 链 PFMGR-FORWARD。
  如果检测到 Docker 的 DOCKER-USER，则把 PFMGR-FORWARD
  挂到 DOCKER-USER 最前面；否则挂到 FORWARD 最前面。

  这样即使 Docker 将 FORWARD policy 设置为 DROP，
  pfmgr 管理的转发连接也会被正确放行。
EOF
}


# ------------------------------------------------------------
# 基础检查
# ------------------------------------------------------------

need_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || \
        die "请使用 root 运行，例如: sudo $0"
}

validate_port() {
    local p="${1:-}"

    [[ "$p" =~ ^[0-9]+$ ]] || \
        die "端口必须是数字: $p"

    (( p >= 1 && p <= 65535 )) || \
        die "端口范围必须是 1-65535: $p"
}

validate_ipv4() {
    local ip="${1:-}"
    local a b c d oct

    # 必须恰好 4 段。
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || \
        die "IPv4 地址格式错误: $ip"

    IFS=. read -r a b c d <<< "$ip"

    for oct in "$a" "$b" "$c" "$d"; do
        (( 10#$oct >= 0 && 10#$oct <= 255 )) || \
            die "IPv4 地址格式错误: $ip"
    done
}

ensure_dirs() {
    install -d -m 700 "$BASE_DIR"
    install -d -m 755 "$NFT_DIR"

    touch "$DB"
    chmod 600 "$DB"

    touch "$LOCK_FILE"
    chmod 600 "$LOCK_FILE"
}

lock_db() {
    exec 9>"$LOCK_FILE"
    flock -x 9
}

ensure_nft() {
    command -v nft >/dev/null 2>&1 || \
        die "未安装 nftables，请先运行: $0 install"
}

ensure_iptables() {
    command -v iptables >/dev/null 2>&1 || \
        die "未安装 iptables（iptables-nft），请先运行: $0 install"
}


# ------------------------------------------------------------
# IPv4 Forward
# ------------------------------------------------------------

enable_ip_forward() {
    cat > "$SYSCTL_FILE" <<'EOF'
# Managed by pfmgr
net.ipv4.ip_forward=1
EOF

    sysctl -w net.ipv4.ip_forward=1 >/dev/null
}


# ------------------------------------------------------------
# nftables 持久化
# ------------------------------------------------------------

ensure_persistence() {
    local backup

    if [[ ! -f "$NFT_MAIN" ]]; then
        cat > "$NFT_MAIN" <<'EOF'
#!/usr/sbin/nft -f

include "/etc/nftables.d/*.nft"
EOF
        chmod 755 "$NFT_MAIN"

    elif ! grep -Eq \
        '/etc/nftables\.d/(\*\.nft|pfmgr\.nft)' \
        "$NFT_MAIN"
    then
        backup="${NFT_MAIN}.bak.$(date +%Y%m%d-%H%M%S)"
        cp -a "$NFT_MAIN" "$backup"

        cat >> "$NFT_MAIN" <<'EOF'

# pfmgr managed rules
include "/etc/nftables.d/pfmgr.nft"
EOF

        yellow "已备份原 nftables.conf:"
        yellow "$backup"
    fi

    # 不主动 restart/reload 整套 nftables，
    # 避免影响服务器已有防火墙规则。
    systemctl enable nftables >/dev/null 2>&1 || true
}


# ------------------------------------------------------------
# 运行时 schema
#
# apply 时只 flush/rebuild 我们自己的 chain。
# 这样三条 chain 的更新可以放进同一个 nft transaction。
# ------------------------------------------------------------

ensure_schema() {
    ensure_nft

    if ! nft list table ip "$TABLE" >/dev/null 2>&1; then
        nft add table ip "$TABLE"
    fi

    if ! nft list chain ip "$TABLE" "$PRE_CHAIN" >/dev/null 2>&1; then
        nft "add chain ip ${TABLE} ${PRE_CHAIN} { type nat hook prerouting priority -100; policy accept; }"
    fi

    if ! nft list chain ip "$TABLE" "$POST_CHAIN" >/dev/null 2>&1; then
        nft "add chain ip ${TABLE} ${POST_CHAIN} { type nat hook postrouting priority 100; policy accept; }"
    fi

    if ! nft list chain ip "$TABLE" "$STAT_CHAIN" >/dev/null 2>&1; then
        # 较晚的 FORWARD priority，尽量统计已经通过常规 filter 的流量。
        # 本链没有 drop/reject，不负责改变用户现有防火墙策略。
        nft "add chain ip ${TABLE} ${STAT_CHAIN} { type filter hook forward priority 300; policy accept; }"
    fi
}


# ------------------------------------------------------------
# FORWARD / Docker 兼容层
#
# Docker 常见配置会把 FORWARD policy 改为 DROP：
#
#   FORWARD -> DOCKER-USER -> ... -> policy DROP
#
# 因此仅仅在另一个 nft base chain 里 accept 并不足以绕过
# Docker 的 DROP。这里使用 iptables-nft 创建我们自己的普通链，
# 并把它插入 DOCKER-USER（优先）或 FORWARD 的最前面。
#
# 所有 pfmgr 规则只存在于 PFMGR-FORWARD，更新时仅 flush
# 我们自己的链，不会清理 Docker 或用户的其他规则。
# ------------------------------------------------------------

iptables_chain_exists() {
    local chain="$1"
    iptables -w 5 -nL "$chain" >/dev/null 2>&1
}

remove_jump_if_present() {
    local parent="$1"

    iptables_chain_exists "$parent" || return 0

    while iptables -w 5 -C "$parent" -j "$IPT_CHAIN" >/dev/null 2>&1; do
        iptables -w 5 -D "$parent" -j "$IPT_CHAIN" || return 1
    done
}

sync_forward_rules() {
    local parent
    local listen_port
    local target_ip
    local target_port

    ensure_iptables

    # 创建自己的普通链；已存在则忽略。
    if ! iptables_chain_exists "$IPT_CHAIN"; then
        iptables -w 5 -N "$IPT_CHAIN"
    fi

    # 清理可能存在的旧挂载，防止重复 jump。
    remove_jump_if_present "DOCKER-USER"
    remove_jump_if_present "FORWARD"

    # Docker 存在时官方预留的用户链优先；否则直接挂 FORWARD。
    if iptables_chain_exists "DOCKER-USER"; then
        parent="DOCKER-USER"
    else
        parent="FORWARD"
    fi

    iptables_chain_exists "$parent" || \
        die "找不到 iptables ${parent} 链，无法配置 FORWARD 放行。"

    # 放到最前面，确保先于 Docker 后续 DROP 规则执行。
    iptables -w 5 -I "$parent" 1 -j "$IPT_CHAIN"

    # 只重建我们自己的链。
    iptables -w 5 -F "$IPT_CHAIN"

    while IFS=$'\t' read -r \
        listen_port \
        target_ip \
        target_port
    do
        [[ -n "${listen_port:-}" ]] || continue

        # TCP 上行：DNAT 后的目标地址/端口。
        iptables -w 5 -A "$IPT_CHAIN" \
            -p tcp \
            -d "$target_ip" \
            --dport "$target_port" \
            -m conntrack \
            --ctstate NEW,ESTABLISHED,RELATED \
            -m comment \
            --comment "pfmgr tcp ${listen_port} up" \
            -j ACCEPT

        # TCP 下行。
        iptables -w 5 -A "$IPT_CHAIN" \
            -p tcp \
            -s "$target_ip" \
            --sport "$target_port" \
            -m conntrack \
            --ctstate ESTABLISHED,RELATED \
            -m comment \
            --comment "pfmgr tcp ${listen_port} down" \
            -j ACCEPT

        # UDP 上行。
        iptables -w 5 -A "$IPT_CHAIN" \
            -p udp \
            -d "$target_ip" \
            --dport "$target_port" \
            -m conntrack \
            --ctstate NEW,ESTABLISHED,RELATED \
            -m comment \
            --comment "pfmgr udp ${listen_port} up" \
            -j ACCEPT

        # UDP 下行。
        iptables -w 5 -A "$IPT_CHAIN" \
            -p udp \
            -s "$target_ip" \
            --sport "$target_port" \
            -m conntrack \
            --ctstate ESTABLISHED,RELATED \
            -m comment \
            --comment "pfmgr udp ${listen_port} down" \
            -j ACCEPT

    done < "$DB"
}

install_systemd_service() {
    cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=pfmgr port-forward rules
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${INSTALL_PATH} apply
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable pfmgr.service >/dev/null 2>&1 || true
}

install_self() {
    local self
    self="$(readlink -f "$0")"

    if [[ "$self" != "$INSTALL_PATH" ]]; then
        install -m 755 "$self" "$INSTALL_PATH"
    else
        chmod 755 "$INSTALL_PATH"
    fi
}


# ------------------------------------------------------------
# 生成运行时 transaction
# ------------------------------------------------------------

render_runtime_nft() {
    local out="$1"

    local listen_port
    local target_ip
    local target_port

    {
        echo "# Generated by pfmgr"
        echo "# Runtime transaction"
        echo

        echo "flush chain ip ${TABLE} ${PRE_CHAIN}"
        echo "flush chain ip ${TABLE} ${POST_CHAIN}"
        echo "flush chain ip ${TABLE} ${STAT_CHAIN}"
        echo

        while IFS=$'\t' read -r \
            listen_port \
            target_ip \
            target_port
        do
            [[ -n "${listen_port:-}" ]] || continue

            # ------------------------------
            # DNAT
            # ------------------------------
            printf \
                'add rule ip %s %s tcp dport %s dnat to %s:%s comment "pfmgr tcp %s -> %s:%s"\n' \
                "$TABLE" "$PRE_CHAIN" \
                "$listen_port" "$target_ip" "$target_port" \
                "$listen_port" "$target_ip" "$target_port"

            printf \
                'add rule ip %s %s udp dport %s dnat to %s:%s comment "pfmgr udp %s -> %s:%s"\n' \
                "$TABLE" "$PRE_CHAIN" \
                "$listen_port" "$target_ip" "$target_port" \
                "$listen_port" "$target_ip" "$target_port"

            # ------------------------------
            # MASQUERADE
            #
            # ct original proto-dst 用来限定：
            # 只处理由本条入口端口建立的连接。
            # ------------------------------
            printf \
                'add rule ip %s %s meta l4proto tcp ct original proto-dst %s ip daddr %s tcp dport %s masquerade comment "pfmgr tcp masq %s"\n' \
                "$TABLE" "$POST_CHAIN" \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

            printf \
                'add rule ip %s %s meta l4proto udp ct original proto-dst %s ip daddr %s udp dport %s masquerade comment "pfmgr udp masq %s"\n' \
                "$TABLE" "$POST_CHAIN" \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

            # ------------------------------
            # STATS - TCP
            #
            # 上行:
            #   client -> target
            #
            # 下行:
            #   target -> client
            #
            # 这里处于 filter/FORWARD 链，
            # counter 会统计连接中的实际数据包，
            # 而不是 NAT 链只看到的首包。
            # ------------------------------
            printf \
                'add rule ip %s %s meta l4proto tcp ct original proto-dst %s ip daddr %s tcp dport %s counter comment "pfmgr-stat up tcp %s"\n' \
                "$TABLE" "$STAT_CHAIN" \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

            printf \
                'add rule ip %s %s meta l4proto tcp ct original proto-dst %s ip saddr %s tcp sport %s counter comment "pfmgr-stat down tcp %s"\n' \
                "$TABLE" "$STAT_CHAIN" \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

            # ------------------------------
            # STATS - UDP
            # ------------------------------
            printf \
                'add rule ip %s %s meta l4proto udp ct original proto-dst %s ip daddr %s udp dport %s counter comment "pfmgr-stat up udp %s"\n' \
                "$TABLE" "$STAT_CHAIN" \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

            printf \
                'add rule ip %s %s meta l4proto udp ct original proto-dst %s ip saddr %s udp sport %s counter comment "pfmgr-stat down udp %s"\n' \
                "$TABLE" "$STAT_CHAIN" \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

            echo
        done < "$DB"

    } > "$out"
}


# ------------------------------------------------------------
# 生成开机持久化配置
# ------------------------------------------------------------

render_persistent_nft() {
    local out="$1"

    local listen_port
    local target_ip
    local target_port

    {
        echo "#!/usr/sbin/nft -f"
        echo "#"
        echo "# Generated by pfmgr"
        echo "# Do NOT edit manually."
        echo

        echo "table ip ${TABLE} {"

        echo "    chain ${PRE_CHAIN} {"
        echo "        type nat hook prerouting priority -100; policy accept;"

        while IFS=$'\t' read -r listen_port target_ip target_port; do
            [[ -n "${listen_port:-}" ]] || continue

            printf \
                '        tcp dport %s dnat to %s:%s comment "pfmgr tcp %s -> %s:%s"\n' \
                "$listen_port" "$target_ip" "$target_port" \
                "$listen_port" "$target_ip" "$target_port"

            printf \
                '        udp dport %s dnat to %s:%s comment "pfmgr udp %s -> %s:%s"\n' \
                "$listen_port" "$target_ip" "$target_port" \
                "$listen_port" "$target_ip" "$target_port"

        done < "$DB"

        echo "    }"
        echo

        echo "    chain ${POST_CHAIN} {"
        echo "        type nat hook postrouting priority 100; policy accept;"

        while IFS=$'\t' read -r listen_port target_ip target_port; do
            [[ -n "${listen_port:-}" ]] || continue

            printf \
                '        meta l4proto tcp ct original proto-dst %s ip daddr %s tcp dport %s masquerade comment "pfmgr tcp masq %s"\n' \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

            printf \
                '        meta l4proto udp ct original proto-dst %s ip daddr %s udp dport %s masquerade comment "pfmgr udp masq %s"\n' \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

        done < "$DB"

        echo "    }"
        echo

        echo "    chain ${STAT_CHAIN} {"
        echo "        type filter hook forward priority 300; policy accept;"

        while IFS=$'\t' read -r listen_port target_ip target_port; do
            [[ -n "${listen_port:-}" ]] || continue

            printf \
                '        meta l4proto tcp ct original proto-dst %s ip daddr %s tcp dport %s counter comment "pfmgr-stat up tcp %s"\n' \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

            printf \
                '        meta l4proto tcp ct original proto-dst %s ip saddr %s tcp sport %s counter comment "pfmgr-stat down tcp %s"\n' \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

            printf \
                '        meta l4proto udp ct original proto-dst %s ip daddr %s udp dport %s counter comment "pfmgr-stat up udp %s"\n' \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

            printf \
                '        meta l4proto udp ct original proto-dst %s ip saddr %s udp sport %s counter comment "pfmgr-stat down udp %s"\n' \
                "$listen_port" "$target_ip" "$target_port" "$listen_port"

        done < "$DB"

        echo "    }"
        echo "}"

    } > "$out"
}


# ------------------------------------------------------------
# 应用 nftables
# ------------------------------------------------------------

apply_rules() {
    local runtime_tmp
    local persist_tmp

    ensure_nft
    ensure_schema

    runtime_tmp="$(mktemp "${BASE_DIR}/pfmgr-runtime.XXXXXX.nft")"
    persist_tmp="$(mktemp "${BASE_DIR}/pfmgr-persist.XXXXXX.nft")"

    render_runtime_nft "$runtime_tmp"
    render_persistent_nft "$persist_tmp"

    # 第一步：只检查 transaction，不真正应用。
    if ! nft -c -f "$runtime_tmp"; then
        red "nftables 配置检查失败。"
        rm -f "$runtime_tmp" "$persist_tmp"
        return 1
    fi

    # 第二步：同一 transaction 中 flush + rebuild 三条 chain。
    if ! nft -f "$runtime_tmp"; then
        red "nftables 规则应用失败。"
        rm -f "$runtime_tmp" "$persist_tmp"
        return 1
    fi

    # 第三步：保存开机配置。
    if ! install -m 600 "$persist_tmp" "$NFT_FILE"; then
        red "无法写入持久化配置: $NFT_FILE"
        rm -f "$runtime_tmp" "$persist_tmp"
        return 1
    fi

    rm -f "$runtime_tmp" "$persist_tmp"

    # 第四步：同步 FORWARD / Docker 放行规则。
    if ! sync_forward_rules; then
        red "FORWARD / Docker 放行规则应用失败。"
        return 1
    fi

    return 0
}


# ------------------------------------------------------------
# 数据库
# ------------------------------------------------------------

rule_exists() {
    local port="$1"

    awk \
        -F '\t' \
        -v p="$port" \
        '$1 == p { found=1 }
         END { exit(found ? 0 : 1) }' \
        "$DB"
}

commit_new_db() {
    local new_db="$1"
    local backup

    backup="$(mktemp "${BASE_DIR}/rules.XXXXXX.bak")"
    cp -a "$DB" "$backup"

    install -m 600 "$new_db" "$DB"

    if apply_rules; then
        rm -f "$backup" "$new_db"
        return 0
    fi

    red "规则应用失败，正在回滚。"

    install -m 600 "$backup" "$DB"

    if ! apply_rules >/dev/null 2>&1; then
        red "警告：自动恢复旧 nftables 配置失败，请立即检查 nftables。"
    fi

    rm -f "$backup" "$new_db"
    return 1
}

prepare_write() {
    ensure_dirs
    lock_db
    ensure_nft
    enable_ip_forward
    ensure_persistence
}


# ------------------------------------------------------------
# install
# ------------------------------------------------------------

cmd_install() {
    need_root

    if ! command -v nft >/dev/null 2>&1 || ! command -v iptables >/dev/null 2>&1; then
        yellow "正在安装 nftables / iptables..."

        apt-get update

        DEBIAN_FRONTEND=noninteractive \
            apt-get install -y nftables iptables
    fi

    command -v flock >/dev/null 2>&1 || \
        die "缺少 flock（通常由 util-linux 提供）"

    ensure_dirs
    lock_db

    # 固定安装到 /usr/local/sbin/pfmgr，供 systemd 开机恢复使用。
    install_self

    enable_ip_forward
    ensure_persistence
    install_systemd_service

    if ! apply_rules; then
        die "初始化 nftables 失败"
    fi

    green "安装完成。"

    echo
    echo "IPv4 Forward : 已开启"
    echo "nftables     : 已启用"
    echo "FORWARD 链   : $IPT_CHAIN"
    echo "开机恢复     : pfmgr.service"
    echo "配置数据库   : $DB"
    echo "nft 配置     : $NFT_FILE"

    echo
    echo "示例:"
    echo
    echo "  $0 add 443 1.2.3.4"
    echo "  $0 stats"
}


# ------------------------------------------------------------
# add
# ------------------------------------------------------------

cmd_add() {
    local listen_port="${1:-}"
    local target_ip="${2:-}"
    local target_port="${3:-}"

    local new_db

    [[ -n "$listen_port" &&
       -n "$target_ip" ]] || {
        usage
        exit 1
    }

    target_port="${target_port:-$listen_port}"

    validate_port "$listen_port"
    validate_port "$target_port"
    validate_ipv4 "$target_ip"

    prepare_write

    if rule_exists "$listen_port"; then
        die "入口端口 $listen_port 已存在，请使用 update 修改。"
    fi

    new_db="$(mktemp "${BASE_DIR}/rules.XXXXXX.new")"
    cat "$DB" > "$new_db"

    printf \
        '%s\t%s\t%s\n' \
        "$listen_port" \
        "$target_ip" \
        "$target_port" \
        >> "$new_db"

    commit_new_db "$new_db"

    green \
        "已添加: TCP+UDP ${listen_port} -> ${target_ip}:${target_port}"
}


# ------------------------------------------------------------
# update
# ------------------------------------------------------------

cmd_update() {
    local listen_port="${1:-}"
    local target_ip="${2:-}"
    local target_port="${3:-}"

    local new_db

    [[ -n "$listen_port" &&
       -n "$target_ip" ]] || {
        usage
        exit 1
    }

    target_port="${target_port:-$listen_port}"

    validate_port "$listen_port"
    validate_port "$target_port"
    validate_ipv4 "$target_ip"

    prepare_write

    rule_exists "$listen_port" || \
        die "入口端口 $listen_port 不存在。"

    new_db="$(mktemp "${BASE_DIR}/rules.XXXXXX.new")"

    awk \
        -F '\t' \
        -v OFS='\t' \
        -v p="$listen_port" \
        -v ip="$target_ip" \
        -v tp="$target_port" \
        '
        {
            if ($1 == p) {
                print p, ip, tp
            } else {
                print $1, $2, $3
            }
        }
        ' \
        "$DB" > "$new_db"

    commit_new_db "$new_db"

    green \
        "已修改: TCP+UDP ${listen_port} -> ${target_ip}:${target_port}"

    yellow \
        "注意：已有连接可能暂时继续使用旧 conntrack 映射；新连接立即使用新地址。"
}


# ------------------------------------------------------------
# delete
# ------------------------------------------------------------

cmd_delete() {
    local listen_port="${1:-}"
    local new_db

    [[ -n "$listen_port" ]] || {
        usage
        exit 1
    }

    validate_port "$listen_port"

    prepare_write

    rule_exists "$listen_port" || \
        die "入口端口 $listen_port 不存在。"

    new_db="$(mktemp "${BASE_DIR}/rules.XXXXXX.new")"

    awk \
        -F '\t' \
        -v p="$listen_port" \
        '$1 != p' \
        "$DB" > "$new_db"

    commit_new_db "$new_db"

    green "已删除入口端口: $listen_port"
}


# ------------------------------------------------------------
# list
# ------------------------------------------------------------

cmd_list() {
    local listen_port
    local target_ip
    local target_port

    local count=0

    ensure_dirs

    printf \
        '%-12s %-10s %-18s %-12s\n' \
        "入口端口" \
        "协议" \
        "目标IP" \
        "目标端口"

    printf \
        '%-12s %-10s %-18s %-12s\n' \
        "------------" \
        "----------" \
        "------------------" \
        "------------"

    while IFS=$'\t' read -r \
        listen_port \
        target_ip \
        target_port
    do
        [[ -n "${listen_port:-}" ]] || continue

        printf \
            '%-12s %-10s %-18s %-12s\n' \
            "$listen_port" \
            "TCP+UDP" \
            "$target_ip" \
            "$target_port"

        ((count+=1))

    done < "$DB"

    if (( count == 0 )); then
        echo "(暂无转发规则)"
    fi
}


# ------------------------------------------------------------
# show
# ------------------------------------------------------------

cmd_show() {
    ensure_nft

    if nft -n list table ip "$TABLE" 2>/dev/null; then
        :
    else
        yellow "当前内核不存在 ${TABLE}。"
        echo
        echo "可以执行:"
        echo "  $0 apply"
    fi

    if command -v iptables >/dev/null 2>&1; then
        echo
        echo "===== FORWARD compatibility ====="

        if iptables_chain_exists "DOCKER-USER"; then
            iptables -S DOCKER-USER 2>/dev/null | grep -E "${IPT_CHAIN}|^-N DOCKER-USER" || true
        else
            iptables -S FORWARD 2>/dev/null | grep -E "${IPT_CHAIN}|^-P FORWARD" || true
        fi

        iptables -vnL "$IPT_CHAIN" --line-numbers 2>/dev/null || \
            yellow "当前不存在 ${IPT_CHAIN}，请执行: $0 apply"
    fi
}


# ------------------------------------------------------------
# stats
# ------------------------------------------------------------

human_bytes() {
    local bytes="${1:-0}"

    awk -v b="$bytes" '
    BEGIN {
        split("B KiB MiB GiB TiB PiB EiB", unit, " ")
        i = 1

        while (b >= 1024 && i < 7) {
            b /= 1024
            i++
        }

        if (i == 1) {
            printf "%.0f %s", b, unit[i]
        } else if (b >= 100) {
            printf "%.0f %s", b, unit[i]
        } else if (b >= 10) {
            printf "%.1f %s", b, unit[i]
        } else {
            printf "%.2f %s", b, unit[i]
        }
    }'
}

human_packets() {
    local n="${1:-0}"

    awk -v n="$n" '
    BEGIN {
        if (n >= 1000000000) {
            printf "%.2fG", n / 1000000000
        } else if (n >= 1000000) {
            printf "%.2fM", n / 1000000
        } else if (n >= 1000) {
            printf "%.2fK", n / 1000
        } else {
            printf "%.0f", n
        }
    }'
}

cmd_stats() {
    local nft_output
    local line

    local direction
    local proto
    local port
    local packets
    local bytes

    local listen_port
    local target_ip
    local target_port

    local key
    local up_bytes down_bytes total_bytes
    local up_packets down_packets total_packets

    local grand_up_bytes=0
    local grand_down_bytes=0
    local grand_packets=0
    local row_count=0

    declare -A STAT_BYTES=()
    declare -A STAT_PACKETS=()

    ensure_dirs
    ensure_nft

    if ! nft list chain ip "$TABLE" "$STAT_CHAIN" >/dev/null 2>&1; then
        yellow "当前没有统计链，请先执行:"
        echo "  $0 apply"
        return 1
    fi

    nft_output="$(nft -n list chain ip "$TABLE" "$STAT_CHAIN")"

    # 从我们自己生成的 comment 精确定位统计规则。
    while IFS= read -r line; do

        if [[ "$line" =~ comment[[:space:]]+\"pfmgr-stat[[:space:]]+(up|down)[[:space:]]+(tcp|udp)[[:space:]]+([0-9]+)\" ]]; then
            direction="${BASH_REMATCH[1]}"
            proto="${BASH_REMATCH[2]}"
            port="${BASH_REMATCH[3]}"
        else
            continue
        fi

        if [[ "$line" =~ counter[[:space:]]+packets[[:space:]]+([0-9]+)[[:space:]]+bytes[[:space:]]+([0-9]+) ]]; then
            packets="${BASH_REMATCH[1]}"
            bytes="${BASH_REMATCH[2]}"
        else
            packets=0
            bytes=0
        fi

        key="${port}:${proto}:${direction}"

        STAT_PACKETS["$key"]="$packets"
        STAT_BYTES["$key"]="$bytes"

    done <<< "$nft_output"

    echo "统计说明：上行=客户端→目标服务器，下行=目标服务器→客户端"
    echo "计数周期：自最近一次规则重新加载后开始；add/update/delete/apply/clear 或重启会重新计数。"
    echo

    printf \
        '%-8s %-5s %-22s %12s %12s %12s %10s\n' \
        "入口" \
        "协议" \
        "目标" \
        "上行" \
        "下行" \
        "总流量" \
        "数据包"

    printf \
        '%-8s %-5s %-22s %12s %12s %12s %10s\n' \
        "--------" \
        "-----" \
        "----------------------" \
        "------------" \
        "------------" \
        "------------" \
        "----------"

    while IFS=$'\t' read -r \
        listen_port \
        target_ip \
        target_port
    do
        [[ -n "${listen_port:-}" ]] || continue

        for proto in tcp udp; do

            up_bytes="${STAT_BYTES["${listen_port}:${proto}:up"]:-0}"
            down_bytes="${STAT_BYTES["${listen_port}:${proto}:down"]:-0}"

            up_packets="${STAT_PACKETS["${listen_port}:${proto}:up"]:-0}"
            down_packets="${STAT_PACKETS["${listen_port}:${proto}:down"]:-0}"

            total_bytes=$((up_bytes + down_bytes))
            total_packets=$((up_packets + down_packets))

            printf \
                '%-8s %-5s %-22s %12s %12s %12s %10s\n' \
                "$listen_port" \
                "${proto^^}" \
                "${target_ip}:${target_port}" \
                "$(human_bytes "$up_bytes")" \
                "$(human_bytes "$down_bytes")" \
                "$(human_bytes "$total_bytes")" \
                "$(human_packets "$total_packets")"

            grand_up_bytes=$((grand_up_bytes + up_bytes))
            grand_down_bytes=$((grand_down_bytes + down_bytes))
            grand_packets=$((grand_packets + total_packets))

            ((row_count+=1))
        done

    done < "$DB"

    if (( row_count == 0 )); then
        echo "(暂无转发规则)"
        return 0
    fi

    echo
    printf \
        '合计: 上行 %s | 下行 %s | 总流量 %s | 数据包 %s\n' \
        "$(human_bytes "$grand_up_bytes")" \
        "$(human_bytes "$grand_down_bytes")" \
        "$(human_bytes "$((grand_up_bytes + grand_down_bytes))")" \
        "$(human_packets "$grand_packets")"
}


# ------------------------------------------------------------
# firewall-sync
# ------------------------------------------------------------

cmd_firewall_sync() {
    prepare_write
    ensure_iptables

    if ! sync_forward_rules; then
        die "FORWARD / Docker 放行规则同步失败"
    fi

    green "已同步 FORWARD / Docker 放行规则。"
}


# ------------------------------------------------------------
# apply
# ------------------------------------------------------------

cmd_apply() {
    prepare_write

    if ! apply_rules; then
        die "重新加载失败"
    fi

    green "已重新应用全部规则。"
    yellow "stats 计数已从 0 重新开始。"
}


# ------------------------------------------------------------
# clear
# ------------------------------------------------------------

cmd_clear() {
    local new_db

    prepare_write

    new_db="$(mktemp "${BASE_DIR}/rules.XXXXXX.new")"
    : > "$new_db"

    commit_new_db "$new_db"

    green "已清空全部端口转发规则。"
}


# ------------------------------------------------------------
# main
# ------------------------------------------------------------

main() {
    need_root

    local cmd="${1:-}"

    shift || true

    case "$cmd" in

        install)
            cmd_install "$@"
            ;;

        add)
            cmd_add "$@"
            ;;

        update|modify|set)
            cmd_update "$@"
            ;;

        delete|del|rm)
            cmd_delete "$@"
            ;;

        list|ls)
            cmd_list "$@"
            ;;

        show)
            cmd_show "$@"
            ;;

        stats|stat)
            cmd_stats "$@"
            ;;

        apply)
            cmd_apply "$@"
            ;;

        firewall-sync|fw-sync)
            cmd_firewall_sync "$@"
            ;;

        clear)
            cmd_clear "$@"
            ;;

        version|-v|--version)
            echo "pfmgr v${VERSION}"
            ;;

        -h|--help|help|"")
            usage
            ;;

        *)
            die "未知命令: $cmd"
            ;;
    esac
}

main "$@"
