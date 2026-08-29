#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
# Force machine-readable APT/dpkg output regardless of system language.
export LC_ALL=C
export LANG=C


# ============================================================
# Redis one-click installer/configurator for Debian 12/13
# Default target: Redis 8.2 Extended, local-only, AOF everysec,
#                 noeviction, DB 3 validation, low-memory VPS.
#
# Optional environment overrides:
#   REDIS_SERIES=auto       auto prefers 8.2, then 7.4, then newest official series
#   REDIS_PORT=6379         TCP port
#   REDIS_DB=3              DB used for validation
#   REDIS_BIND='127.0.0.1 -::1'
#   MAXMEMORY=auto          e.g. 256mb / 384mb / 512mb / auto
#   DISABLE_RDB=1           1 = disable periodic RDB snapshots
#   ALLOW_DOWNGRADE=0       1 = permit package downgrade to pinned series
#
# If an existing Redis requires authentication, export REDISCLI_AUTH
# before running this script so self-tests can authenticate.
# ============================================================

REDIS_SERIES="${REDIS_SERIES:-auto}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_DB="${REDIS_DB:-3}"
REDIS_BIND="${REDIS_BIND:-127.0.0.1 -::1}"
MAXMEMORY="${MAXMEMORY:-auto}"
DISABLE_RDB="${DISABLE_RDB:-1}"
ALLOW_DOWNGRADE="${ALLOW_DOWNGRADE:-0}"

CONF_MAIN="/etc/redis/redis.conf"
CONF_LOCAL="/etc/redis/redis-local.conf"
APT_KEYRING="/usr/share/keyrings/redis-archive-keyring.gpg"
APT_LIST="/etc/apt/sources.list.d/redis.list"
APT_PIN="/etc/apt/preferences.d/redis"
SYSCTL_FILE="/etc/sysctl.d/99-redis.conf"
THP_SERVICE="/etc/systemd/system/disable-transparent-huge-pages.service"
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET_VERSION=""


if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_RESET=$'\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_RESET=''
fi

log()  { printf '%s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

on_error() {
  local rc=$?
  printf '\n%s[ERROR]%s 脚本在第 %s 行失败，退出码=%s\n' "$C_RED" "$C_RESET" "${BASH_LINENO[0]:-unknown}" "$rc" >&2
  printf '失败命令: %s\n' "${BASH_COMMAND:-unknown}" >&2
  printf '可查看日志: journalctl -u redis-server -n 100 --no-pager\n' >&2
  exit "$rc"
}
trap on_error ERR

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "请使用 root 执行此脚本。"
}

validate_inputs() {
  [[ "$REDIS_SERIES" == "auto" || "$REDIS_SERIES" =~ ^[0-9]+\.[0-9]+$ ]] || die "REDIS_SERIES 格式错误: $REDIS_SERIES（应为 auto 或如 7.4 / 8.2）"
  [[ "$REDIS_PORT" =~ ^[0-9]+$ ]] || die "REDIS_PORT 必须是数字。"
  (( REDIS_PORT >= 1 && REDIS_PORT <= 65535 )) || die "REDIS_PORT 超出范围。"
  [[ "$REDIS_DB" =~ ^[0-9]+$ ]] || die "REDIS_DB 必须是非负整数。"
  [[ "$DISABLE_RDB" == "0" || "$DISABLE_RDB" == "1" ]] || die "DISABLE_RDB 只能为 0 或 1。"
  [[ "$ALLOW_DOWNGRADE" == "0" || "$ALLOW_DOWNGRADE" == "1" ]] || die "ALLOW_DOWNGRADE 只能为 0 或 1。"
  if [[ "$MAXMEMORY" != "auto" ]]; then
    [[ "$MAXMEMORY" =~ ^[1-9][0-9]*(kb|mb|gb)$ ]] || die "MAXMEMORY 示例: 256mb / 384mb / 1gb / auto"
  fi
}

detect_os() {
  [[ -r /etc/os-release ]] || die "找不到 /etc/os-release。"
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "debian" ]] || die "仅支持 Debian 12/13，当前系统: ${PRETTY_NAME:-unknown}"

  case "${VERSION_ID:-}" in
    12*) CODENAME="${VERSION_CODENAME:-bookworm}" ;;
    13*) CODENAME="${VERSION_CODENAME:-trixie}" ;;
    *) die "仅支持 Debian 12/13，当前 VERSION_ID=${VERSION_ID:-unknown}" ;;
  esac

  ARCH="$(dpkg --print-architecture)"
  ok "系统: ${PRETTY_NAME:-Debian} / codename=$CODENAME / arch=$ARCH"
}

check_system_resources() {
  local avail_kb
  avail_kb="$(df -Pk / | awk 'NR==2 {print $4}')"
  [[ -n "$avail_kb" ]] || die "无法读取根分区可用空间。"
  (( avail_kb >= 300 * 1024 )) || die "根分区可用空间不足 300MB，请先清理磁盘。"

  MEM_TOTAL_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
  [[ -n "$MEM_TOTAL_KB" ]] || die "无法读取系统内存。"

  if [[ "$MAXMEMORY" == "auto" ]]; then
    local mib=$(( MEM_TOTAL_KB / 1024 ))
    if (( mib < 768 )); then
      MAXMEMORY="128mb"
    elif (( mib < 1536 )); then
      MAXMEMORY="256mb"
    elif (( mib < 3072 )); then
      MAXMEMORY="512mb"
    elif (( mib < 6144 )); then
      MAXMEMORY="1024mb"
    else
      MAXMEMORY="2048mb"
    fi
  fi

  log "物理内存: $(( MEM_TOTAL_KB / 1024 )) MiB；Redis maxmemory=$MAXMEMORY"

  if [[ "$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)" -eq 0 ]]; then
    warn "系统没有 Swap。1GB VPS 建议至少准备 512MB~1GB Swap 作为 OOM 缓冲，但本脚本不会自动创建。"
  fi
}

install_prerequisites() {
  export DEBIAN_FRONTEND=noninteractive
  log "更新 APT 索引并安装基础依赖..."
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gpg lsb-release
}

configure_redis_repo() {
  log "配置 Redis 官方 APT 仓库..."
  install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d

  local tmp_key
  tmp_key="$(mktemp)"
  trap 'rm -f "$tmp_key"' RETURN
  curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
    https://packages.redis.io/gpg -o "$tmp_key"
  gpg --batch --yes --dearmor -o "$APT_KEYRING" "$tmp_key"
  chmod 0644 "$APT_KEYRING"
  rm -f "$tmp_key"
  trap - RETURN

  cat > "$APT_LIST" <<EOF
deb [signed-by=$APT_KEYRING] https://packages.redis.io/deb $CODENAME main
EOF

  # Remove any preference left by an older run before discovering versions.
  rm -f "$APT_PIN"
  apt-get update

  local -a official_versions=()
  mapfile -t official_versions < <(
    apt-cache madison redis-server 2>/dev/null \
      | awk '/packages\.redis\.io/ {print $3}' \
      | sed '/^[[:space:]]*$/d' \
      | sort -u
  )

  if (( ${#official_versions[@]} == 0 )); then
    warn "未发现来自 packages.redis.io 的 redis-server 包。"
    apt-cache policy redis-server >&2 || true
    die "Redis 官方 APT 仓库没有为 Debian $CODENAME / $ARCH 返回 redis-server；不会回退到 Debian 自带版本。"
  fi

  newest_for_series() {
    local wanted="$1" v best=''
    for v in "${official_versions[@]}"; do
      if [[ "${v#*:}" == "${wanted}."* ]]; then
        if [[ -z "$best" ]] || dpkg --compare-versions "$v" gt "$best"; then
          best="$v"
        fi
      fi
    done
    printf '%s' "$best"
  }

  local selected_series='' v core

  if [[ "$REDIS_SERIES" == "auto" ]]; then
    for selected_series in 8.2 7.4; do
      TARGET_VERSION="$(newest_for_series "$selected_series")"
      [[ -n "$TARGET_VERSION" ]] && break
    done

    if [[ -z "$TARGET_VERSION" ]]; then
      for v in "${official_versions[@]}"; do
        if [[ -z "$TARGET_VERSION" ]] || dpkg --compare-versions "$v" gt "$TARGET_VERSION"; then
          TARGET_VERSION="$v"
        fi
      done
      core="${TARGET_VERSION#*:}"
      selected_series="$(sed -E 's/^([0-9]+\.[0-9]+).*/\1/' <<<"$core")"
      warn "官方 APT 未提供首选 8.2/7.4；改用官方仓库最新系列 $selected_series ($TARGET_VERSION)。"
    elif [[ "$selected_series" != "8.2" ]]; then
      warn "官方 APT 未提供 Redis 8.2.x；改用 $selected_series ($TARGET_VERSION)。"
    fi
    REDIS_SERIES="$selected_series"
  else
    TARGET_VERSION="$(newest_for_series "$REDIS_SERIES")"
    if [[ -z "$TARGET_VERSION" ]]; then
      printf '%s\n' "Redis 官方仓库当前可见版本（最多 20 个）:" >&2
      printf '  %s\n' "${official_versions[@]}" | head -n 20 >&2
      die "指定 Redis ${REDIS_SERIES}.x 在官方 APT 仓库中不可用。"
    fi
  fi

  # redis-server has an exact dependency on redis-tools. Verify the same exact
  # version is published by the official repository before touching packages.
  if ! apt-cache madison redis-tools 2>/dev/null \
      | awk '/packages\.redis\.io/ {print $3}' \
      | grep -Fxq -- "$TARGET_VERSION"; then
    die "官方仓库有 redis-server=$TARGET_VERSION，但没有同版本 redis-tools；为避免依赖错配已停止。"
  fi

  local pin_version
  if [[ "$TARGET_VERSION" == *:* ]]; then
    pin_version="${TARGET_VERSION%%:*}:${REDIS_SERIES}.*"
  else
    pin_version="${REDIS_SERIES}.*"
  fi

  cat > "$APT_PIN" <<EOF
Package: redis redis-server redis-sentinel redis-tools
Pin: version ${pin_version}
Pin-Priority: 1001
EOF

  # Do not parse "Candidate:" here: apt-cache policy localizes this word.
  # Instead, verify the exact target remains visible in the official feed.
  if ! apt-cache madison redis-server 2>/dev/null \
      | awk '/packages\.redis\.io/ {print $3}' \
      | grep -Fxq -- "$TARGET_VERSION"; then
    die "写入 APT pin 后目标版本 $TARGET_VERSION 不再可见。"
  fi

  ok "Redis 官方仓库可用：系列=${REDIS_SERIES}.x，精确目标版本=$TARGET_VERSION"
}

install_redis() {
  [[ -n "$TARGET_VERSION" ]] || die "内部错误：TARGET_VERSION 为空。"

  local installed=''
  installed="$(dpkg-query -W -f='${Version}' redis-server 2>/dev/null || true)"

  if [[ -n "$installed" ]]; then
    log "检测到已安装 redis-server: $installed"
    if dpkg --compare-versions "$installed" gt "$TARGET_VERSION" && [[ "$ALLOW_DOWNGRADE" != "1" ]]; then
      die "当前 Redis ($installed) 比目标版本 ($TARGET_VERSION) 更新。为避免自动降级，已停止。若明确需要降级，请设置 ALLOW_DOWNGRADE=1。"
    fi
  fi

  local -a specs=(
    "redis-server=$TARGET_VERSION"
    "redis-tools=$TARGET_VERSION"
  )

  # If meta/sentinel packages already exist, keep the whole installed Redis
  # package family on one exact version. Do not install sentinel on a fresh VPS.
  local pkg
  for pkg in redis redis-sentinel; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'; then
      if apt-cache madison "$pkg" 2>/dev/null \
          | awk '/packages\.redis\.io/ {print $3}' \
          | grep -Fxq -- "$TARGET_VERSION"; then
        specs+=("$pkg=$TARGET_VERSION")
      else
        die "检测到已安装 $pkg，但官方仓库没有其目标版本 $TARGET_VERSION；为避免包依赖不一致已停止。"
      fi
    fi
  done

  local -a apt_opts=(-y --no-install-recommends -o Dpkg::Options::=--force-confold)
  if [[ "$ALLOW_DOWNGRADE" == "1" ]]; then
    apt_opts+=(--allow-downgrades)
  fi

  # A held Redis package would otherwise make a noninteractive exact-version
  # install fail. Explicitly permit changing only packages named in this install.
  if apt-mark showhold 2>/dev/null | grep -Eq '^(redis|redis-server|redis-tools|redis-sentinel)$'; then
    warn "检测到 Redis 相关 APT hold；本次精确版本安装将允许变更 held package，但不会取消 hold 状态。"
    apt_opts+=(--allow-change-held-packages)
  fi

  log "安装前 APT dry-run：${specs[*]}"
  if ! apt-get -s "${apt_opts[@]}" install "${specs[@]}" >/tmp/redis-install-dry-run.log 2>&1; then
    cat /tmp/redis-install-dry-run.log >&2 || true
    die "APT 模拟安装失败，系统尚未进行 Redis 包变更。"
  fi
  ok "APT dry-run 通过，依赖关系可解"

  log "开始安装精确版本 Redis: $TARGET_VERSION"
  apt-get "${apt_opts[@]}" install "${specs[@]}"

  command -v redis-server >/dev/null || die "redis-server 安装后仍不存在。"
  command -v redis-cli >/dev/null || die "redis-cli 安装后仍不存在。"

  local actual_server actual_tools
  actual_server="$(dpkg-query -W -f='${Version}' redis-server 2>/dev/null || true)"
  actual_tools="$(dpkg-query -W -f='${Version}' redis-tools 2>/dev/null || true)"
  [[ "$actual_server" == "$TARGET_VERSION" ]] || die "redis-server 实际包版本=$actual_server，期望=$TARGET_VERSION"
  [[ "$actual_tools" == "$TARGET_VERSION" ]] || die "redis-tools 实际包版本=$actual_tools，期望=$TARGET_VERSION"

  ok "Redis 包安装完成：redis-server=$actual_server；redis-tools=$actual_tools"
}

backup_config_if_present() {
  if [[ -f "$CONF_MAIN" && ! -e "${CONF_MAIN}.bak.${STAMP}" ]]; then
    cp -a "$CONF_MAIN" "${CONF_MAIN}.bak.${STAMP}"
    log "已备份主配置: ${CONF_MAIN}.bak.${STAMP}"
  fi

  if [[ -e "$CONF_LOCAL" && ! -e "${CONF_LOCAL}.bak.${STAMP}" ]]; then
    cp -a "$CONF_LOCAL" "${CONF_LOCAL}.bak.${STAMP}"
    log "已备份本地覆盖配置: ${CONF_LOCAL}.bak.${STAMP}"
  fi
}

write_redis_config() {
  log "写入 Redis 生产配置覆盖文件..."

  cat > "$CONF_LOCAL" <<EOF
# Managed by install_redis_debian.sh
# Generated: $(date -Is)

# 仅监听本机，避免 Redis 暴露到公网。
bind $REDIS_BIND
protected-mode yes
port $REDIS_PORT

# DB 3 需要存在；保留默认 16 个逻辑 DB。
databases 16

# 1C/1G 等小内存 VPS 的安全上限；达到上限后拒绝写入，不淘汰已有 key。
maxmemory $MAXMEMORY
maxmemory-policy noeviction

# AOF 持久化：业务硬性要求。
appendonly yes
appendfsync everysec

# rewrite 期间仍维持 everysec fsync，优先保证持久化语义。
no-appendfsync-on-rewrite no

# Redis 7/8 的 AOF 默认使用 RDB preamble，可加快加载。
aof-use-rdb-preamble yes

# 保持连接存活检测。
tcp-keepalive 300
EOF

  if [[ "$DISABLE_RDB" == "1" ]]; then
    cat >> "$CONF_LOCAL" <<'EOF'

# 已启用 AOF；小内存单核 VPS 默认关闭周期 RDB，减少额外 fork / I/O。
save ""
EOF
  fi

  chmod 0640 "$CONF_LOCAL"
  chown root:redis "$CONF_LOCAL" 2>/dev/null || chown root:root "$CONF_LOCAL"

  # Remove previous occurrences of our exact include, then append it last so overrides win.
  sed -i '\|^[[:space:]]*include[[:space:]]\+/etc/redis/redis-local\.conf[[:space:]]*$|d' "$CONF_MAIN"
  printf '\n# Local production overrides managed by install_redis_debian.sh\ninclude %s\n' "$CONF_LOCAL" >> "$CONF_MAIN"
}

configure_kernel() {
  log "应用 Redis 建议的 Linux 内核设置..."
  cat > "$SYSCTL_FILE" <<'EOF'
# Redis: allow background fork operations under memory pressure.
vm.overcommit_memory = 1
EOF

  # Some Virtuozzo/OpenVZ/LXC VPS hosts restrict guest sysctl writes.
  # This is an optimization/reliability recommendation, not a reason to abort
  # a correct Redis installation when the hypervisor refuses the setting.
  if sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1; then
    ok "vm.overcommit_memory=1 已生效"
  else
    warn "宿主机/容器不允许设置 vm.overcommit_memory；已写入 $SYSCTL_FILE，但本次无法强制生效。Redis 安装继续。"
  fi

  cat > "$THP_SERVICE" <<'EOF'
[Unit]
Description=Disable Transparent Huge Pages for Redis
DefaultDependencies=no
After=local-fs.target
Before=redis-server.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for f in /sys/kernel/mm/transparent_hugepage/enabled /sys/kernel/mm/transparent_hugepage/defrag; do if [ -w "$f" ]; then echo never > "$f"; fi; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  if systemctl enable --now disable-transparent-huge-pages.service >/dev/null 2>&1; then
    local thp_state='unavailable'
    thp_state="$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true)"
    if [[ "$thp_state" == *'[never]'* || "$thp_state" == 'unavailable' || -z "$thp_state" ]]; then
      ok "THP 禁用服务已启用"
    else
      warn "THP 服务已执行，但宿主机未允许切换为 never；当前: $thp_state"
    fi
  else
    warn "无法启用 THP systemd 设置（可能受 VPS 宿主机限制）；Redis 安装继续。"
  fi
}

restart_with_rollback() {
  log "重启 Redis 并验证服务..."
  systemctl enable redis-server >/dev/null

  if systemctl restart redis-server; then
    return 0
  fi

  warn "新配置导致 Redis 启动失败，执行配置回滚。"
  cp -a "${CONF_MAIN}.bak.${STAMP}" "$CONF_MAIN"
  if [[ -f "${CONF_LOCAL}.bak.${STAMP}" ]]; then
    cp -a "${CONF_LOCAL}.bak.${STAMP}" "$CONF_LOCAL"
  else
    rm -f "$CONF_LOCAL"
  fi
  systemctl daemon-reload
  systemctl restart redis-server || true
  journalctl -u redis-server -n 80 --no-pager >&2 || true
  die "Redis 新配置启动失败，已尝试恢复原配置。"
}

redis_value() {
  # CONFIG GET returns key/value on separate lines in default raw mode; tail returns value.
  redis-cli -h 127.0.0.1 -p "$REDIS_PORT" --raw CONFIG GET "$1" | tail -n1 | tr -d '\r'
}

self_test() {
  log "执行 Redis 自检（包括实际 DB $REDIS_DB 读写）..."

  systemctl is-active --quiet redis-server || die "redis-server 服务未处于 active 状态。"

  local pong
  pong="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" --raw PING)"
  [[ "$pong" == "PONG" ]] || die "PING 失败，返回: $pong"

  local appendonly appendfsync policy maxmemory
  appendonly="$(redis_value appendonly)"
  appendfsync="$(redis_value appendfsync)"
  policy="$(redis_value maxmemory-policy)"
  maxmemory="$(redis_value maxmemory)"

  [[ "$appendonly" == "yes" ]] || die "appendonly 实际值=$appendonly，期望 yes"
  [[ "$appendfsync" == "everysec" ]] || die "appendfsync 实际值=$appendfsync，期望 everysec"
  [[ "$policy" == "noeviction" ]] || die "maxmemory-policy 实际值=$policy，期望 noeviction"
  [[ "$maxmemory" =~ ^[1-9][0-9]*$ ]] || die "maxmemory 实际值异常: $maxmemory"

  local test_key="__redis_install_check_${RANDOM}_$$"
  local set_ret get_ret
  set_ret="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" -n "$REDIS_DB" --raw SET "$test_key" ok EX 60)"
  [[ "$set_ret" == "OK" ]] || die "DB $REDIS_DB SET 自检失败: $set_ret"
  get_ret="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" -n "$REDIS_DB" --raw GET "$test_key")"
  redis-cli -h 127.0.0.1 -p "$REDIS_PORT" -n "$REDIS_DB" --raw DEL "$test_key" >/dev/null
  [[ "$get_ret" == "ok" ]] || die "DB $REDIS_DB GET 自检失败: $get_ret"

  local aof_enabled aof_status
  aof_enabled="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" --raw INFO persistence | awk -F: '$1=="aof_enabled" {gsub("\\r", "", $2); print $2}')"
  aof_status="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" --raw INFO persistence | awk -F: '$1=="aof_last_write_status" {gsub("\\r", "", $2); print $2}')"
  [[ "$aof_enabled" == "1" ]] || die "INFO persistence 显示 aof_enabled=$aof_enabled"
  [[ -z "$aof_status" || "$aof_status" == "ok" ]] || die "AOF 最近写入状态异常: $aof_status"

  ok "Redis 核心配置与 DB $REDIS_DB 实际读写全部通过"
}

print_summary() {
  local redis_ver used_human rss_human max_human keys_db aof_size dir appenddirname thp swap_total
  redis_ver="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" --raw INFO server | awk -F: '$1=="redis_version" {gsub("\\r", "", $2); print $2}')"
  used_human="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" --raw INFO memory | awk -F: '$1=="used_memory_human" {gsub("\\r", "", $2); print $2}')"
  rss_human="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" --raw INFO memory | awk -F: '$1=="used_memory_rss_human" {gsub("\\r", "", $2); print $2}')"
  max_human="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" --raw INFO memory | awk -F: '$1=="maxmemory_human" {gsub("\\r", "", $2); print $2}')"
  keys_db="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" -n "$REDIS_DB" --raw DBSIZE)"
  aof_size="$(redis-cli -h 127.0.0.1 -p "$REDIS_PORT" --raw INFO persistence | awk -F: '$1=="aof_current_size" {gsub("\\r", "", $2); print $2}')"
  dir="$(redis_value dir)"
  appenddirname="$(redis_value appenddirname)"
  thp="$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo unavailable)"
  swap_total="$(awk '/^SwapTotal:/ {printf "%.0f MiB", $2/1024}' /proc/meminfo)"

  printf '\n============================================================\n'
  printf '%sRedis 安装/配置完成%s\n' "$C_GREEN" "$C_RESET"
  printf '============================================================\n'
  printf 'OS                  : Debian %s (%s) / %s\n' "${VERSION_ID}" "$CODENAME" "$ARCH"
  printf 'Redis version       : %s\n' "${redis_ver:-unknown}"
  printf 'Service             : %s\n' "$(systemctl is-active redis-server)"
  printf 'Listen              : %s:%s\n' "$REDIS_BIND" "$REDIS_PORT"
  printf 'Target DB           : %s (keys=%s)\n' "$REDIS_DB" "$keys_db"
  printf 'appendonly          : %s  [PASS]\n' "$(redis_value appendonly)"
  printf 'appendfsync         : %s  [PASS]\n' "$(redis_value appendfsync)"
  printf 'maxmemory-policy    : %s  [PASS]\n' "$(redis_value maxmemory-policy)"
  printf 'maxmemory           : %s\n' "${max_human:-$MAXMEMORY}"
  printf 'used_memory         : %s\n' "${used_human:-unknown}"
  printf 'used_memory_rss     : %s\n' "${rss_human:-unknown}"
  printf 'AOF current size    : %s bytes\n' "${aof_size:-unknown}"
  printf 'AOF directory       : %s/%s\n' "${dir:-?}" "${appenddirname:-?}"
  printf 'RDB periodic save   : %s\n' "$([[ "$DISABLE_RDB" == "1" ]] && echo disabled || echo vendor-default)"
  printf 'overcommit_memory   : %s\n' "$(sysctl -n vm.overcommit_memory 2>/dev/null || echo unknown)"
  printf 'THP                 : %s\n' "$thp"
  printf 'Swap                : %s\n' "$swap_total"
  printf 'Config              : %s\n' "$CONF_MAIN"
  printf 'Managed overrides   : %s\n' "$CONF_LOCAL"
  printf 'Config backup       : %s.bak.%s\n' "$CONF_MAIN" "$STAMP"
  printf '============================================================\n'
  printf '最终检查命令：\n'
  printf '  redis-cli -n %s CONFIG GET appendonly appendfsync maxmemory maxmemory-policy\n' "$REDIS_DB"
  printf '  redis-cli -n %s INFO persistence\n' "$REDIS_DB"
  printf '  redis-cli -n %s INFO memory\n' "$REDIS_DB"
  printf '============================================================\n'
}

main() {
  require_root
  validate_inputs
  detect_os
  check_system_resources
  install_prerequisites
  configure_redis_repo
  backup_config_if_present
  install_redis
  [[ -f "$CONF_MAIN" ]] || die "安装后未找到 $CONF_MAIN"
  backup_config_if_present
  write_redis_config
  configure_kernel
  restart_with_rollback
  self_test
  print_summary
}

main "$@"
