#!/usr/bin/env bash

set -euo pipefail

V2BX_INSTALL_URL="https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh"
XRAYR_INSTALL_URL="https://raw.githubusercontent.com/leaderen/wyx2685-XrayR-scripts/refs/heads/master/install.sh"

V2BX_CONFIGS=(
  # "配置名称|https://example.com/private-v2bx.zip"
)

XRAYR_CONFIGS=(
  # "配置名称|https://example.com/private-xrayr.zip"
)

if [ -t 1 ]; then
  C_RESET="\033[0m"
  C_RED="\033[31m"
  C_GREEN="\033[32m"
  C_YELLOW="\033[33m"
  C_BLUE="\033[34m"
  C_CYAN="\033[36m"
  C_BOLD="\033[1m"
else
  C_RESET=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
  C_BOLD=""
fi

info() {
  printf "${C_CYAN}==>${C_RESET} %s\n" "$1"
}

ok() {
  printf "${C_GREEN}OK:${C_RESET} %s\n" "$1"
}

warn() {
  printf "${C_YELLOW}WARN:${C_RESET} %s\n" "$1"
}

die() {
  printf "${C_RED}ERROR:${C_RESET} %s\n" "$1" >&2
  exit 1
}

usage() {
  cat <<EOF
${C_BOLD}V2bX / XrayR 管理脚本${C_RESET}

用法:
  bash v2bx_xrayr_manager.sh
  bash v2bx_xrayr_manager.sh v2bx [config_zip_url]
  bash v2bx_xrayr_manager.sh xrayr [config_zip_url]
  bash v2bx_xrayr_manager.sh update-v2bx [config_zip_url]
  bash v2bx_xrayr_manager.sh update-xrayr [config_zip_url]
  bash v2bx_xrayr_manager.sh status [v2bx|xrayr]
  bash v2bx_xrayr_manager.sh help

环境变量:
  V2BX_CONFIG_URL          V2bX 配置 ZIP 链接
  XRAYR_CONFIG_URL         XrayR 配置 ZIP 链接

说明:
  v2bx / xrayr             安装或更新程序，然后覆盖配置目录并重启服务
  update-v2bx/update-xrayr 只覆盖配置目录并重启服务
  status                  默认输出 V2bX 和 XrayR 两个服务状态
EOF
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "请使用 root 用户运行这个操作"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

service_name() {
  case "$1" in
    v2bx) printf "V2bX" ;;
    xrayr) printf "XrayR" ;;
    *) die "未知类型: $1" ;;
  esac
}

config_dir() {
  case "$1" in
    v2bx) printf "/etc/V2bX" ;;
    xrayr) printf "/etc/XrayR" ;;
    *) die "未知类型: $1" ;;
  esac
}

install_url() {
  case "$1" in
    v2bx) printf "%s" "$V2BX_INSTALL_URL" ;;
    xrayr) printf "%s" "$XRAYR_INSTALL_URL" ;;
    *) die "未知类型: $1" ;;
  esac
}

default_config_url() {
  local item env_url

  case "$1" in
    v2bx)
      env_url="${V2BX_CONFIG_URL:-}"
      [ -n "$env_url" ] && printf "%s" "$env_url" && return
      [ "${#V2BX_CONFIGS[@]}" -gt 0 ] || return
      item="${V2BX_CONFIGS[0]}"
      ;;
    xrayr)
      env_url="${XRAYR_CONFIG_URL:-}"
      [ -n "$env_url" ] && printf "%s" "$env_url" && return
      [ "${#XRAYR_CONFIGS[@]}" -gt 0 ] || return
      item="${XRAYR_CONFIGS[0]}"
      ;;
    *) die "未知类型: $1" ;;
  esac

  printf "%s" "${item#*|}"
}

print_title() {
  printf "\n${C_BOLD}${C_BLUE}%s${C_RESET}\n" "$1"
}

config_count() {
  case "$1" in
    v2bx) printf "%s" "${#V2BX_CONFIGS[@]}" ;;
    xrayr) printf "%s" "${#XRAYR_CONFIGS[@]}" ;;
    *) die "未知类型: $1" ;;
  esac
}

config_item() {
  local kind="$1"
  local index="$2"

  case "$kind" in
    v2bx) printf "%s" "${V2BX_CONFIGS[$index]}" ;;
    xrayr) printf "%s" "${XRAYR_CONFIGS[$index]}" ;;
    *) die "未知类型: $kind" ;;
  esac
}

choose_config_url() {
  local kind="$1"
  local count choice item name url i env_url env_name

  print_title "请选择配置" >&2
  count="$(config_count "$kind")"
  case "$kind" in
    v2bx)
      env_url="${V2BX_CONFIG_URL:-}"
      env_name="V2BX_CONFIG_URL"
      ;;
    xrayr)
      env_url="${XRAYR_CONFIG_URL:-}"
      env_name="XRAYR_CONFIG_URL"
      ;;
    *) die "未知类型: $kind" ;;
  esac

  if [ -n "$env_url" ]; then
    printf "  1) 使用环境变量 %s\n" "$env_name" >&2
    i=0
    while [ "$i" -lt "$count" ]; do
      item="$(config_item "$kind" "$i")"
      name="${item%%|*}"
      printf "  %s) %s\n" "$((i + 2))" "$name" >&2
      i="$((i + 1))"
    done
    printf "  %s) 手动输入配置 ZIP 链接\n" "$((count + 2))" >&2
    printf "\n" >&2

    read -r -p "请输入选项 [默认 1]: " choice
    choice="${choice:-1}"

    if [ "$choice" -eq 1 ] 2>/dev/null; then
      printf "%s" "$env_url"
      return
    fi

    if [ "$choice" -ge 2 ] 2>/dev/null && [ "$choice" -le "$((count + 1))" ]; then
      item="$(config_item "$kind" "$((choice - 2))")"
      url="${item#*|}"
      printf "%s" "$url"
      return
    fi

    if [ "$choice" -eq "$((count + 2))" ] 2>/dev/null; then
      read -r -p "请输入 ${kind} 配置 ZIP 链接: " url
      [ -n "$url" ] || die "配置链接不能为空"
      printf "%s" "$url"
      return
    fi

    die "无效选项: $choice"
  fi

  i=0
  while [ "$i" -lt "$count" ]; do
    item="$(config_item "$kind" "$i")"
    name="${item%%|*}"
    printf "  %s) %s\n" "$((i + 1))" "$name" >&2
    i="$((i + 1))"
  done
  printf "  %s) 手动输入配置 ZIP 链接\n" "$((count + 1))" >&2
  printf "\n" >&2

  read -r -p "请输入选项 [默认 1]: " choice
  choice="${choice:-1}"

  if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$count" ]; then
    item="$(config_item "$kind" "$((choice - 1))")"
    url="${item#*|}"
    printf "%s" "$url"
    return
  fi

  if [ "$choice" -eq "$((count + 1))" ] 2>/dev/null; then
    read -r -p "请输入 ${kind} 配置 ZIP 链接: " url
    [ -n "$url" ] || die "配置链接不能为空"
    printf "%s" "$url"
    return
  fi

  die "无效选项: $choice"
}

resolve_config_url() {
  local kind="$1"
  local given="${2:-}"
  local url

  if [ -n "$given" ]; then
    printf "%s" "$given"
    return
  fi

  url="$(default_config_url "$kind")"
  if [ -n "$url" ]; then
    printf "%s" "$url"
    return
  fi

  if [ -t 0 ]; then
    read -r -p "请输入 ${kind} 配置 ZIP 链接: " url
    [ -n "$url" ] || die "配置链接不能为空"
    printf "%s" "$url"
    return
  fi

  die "未提供配置链接。请传入 URL，或设置 V2BX_CONFIG_URL / XRAYR_CONFIG_URL"
}

safe_remove_config_dir() {
  local dir="$1"

  case "$dir" in
    /etc/V2bX|/etc/XrayR)
      rm -rf "$dir"
      ;;
    *)
      die "拒绝删除非固定配置目录: $dir"
      ;;
  esac
}

download_file() {
  local url="$1"
  local output="$2"

  require_cmd wget
  wget -q --show-progress --no-check-certificate -O "$output" "$url"
}

install_panel_script() {
  local kind="$1"
  local url script_path

  url="$(install_url "$kind")"
  script_path="/tmp/${kind}_install.sh"

  info "下载 $(service_name "$kind") 安装脚本"
  download_file "$url" "$script_path"

  info "运行 $(service_name "$kind") 安装脚本"
  bash "$script_path"
}

apply_config() {
  local kind="$1"
  local url="$2"
  local dir tmp_dir zip_path extract_dir source_dir entry_count first_entry

  require_root
  require_cmd unzip

  dir="$(config_dir "$kind")"
  tmp_dir="$(mktemp -d)"
  zip_path="${tmp_dir}/config.zip"
  extract_dir="${tmp_dir}/extracted"

  info "下载 $(service_name "$kind") 配置: $url"
  download_file "$url" "$zip_path"

  info "解压配置到临时目录"
  mkdir -p "$extract_dir"
  unzip -q "$zip_path" -d "$extract_dir"

  entry_count="$(find "$extract_dir" -mindepth 1 -maxdepth 1 ! -name "__MACOSX" | wc -l | tr -d " ")"
  first_entry="$(find "$extract_dir" -mindepth 1 -maxdepth 1 ! -name "__MACOSX" -print -quit)"
  source_dir="$extract_dir"
  if [ "$entry_count" -eq 1 ] && [ -d "$first_entry" ]; then
    source_dir="$first_entry"
  fi

  info "删除旧配置目录: $dir"
  safe_remove_config_dir "$dir"

  info "写入新配置到: $dir"
  mkdir -p "$dir"
  cp -a "${source_dir}/." "$dir/"

  rm -rf "$tmp_dir"
  ok "$(service_name "$kind") 配置已覆盖"
}

restart_service() {
  local kind="$1"
  local service

  service="$(service_name "$kind")"
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "找不到 systemctl，已跳过重启 ${service}"
    return
  fi

  info "重启服务: $service"
  systemctl restart "$service"
  ok "服务已重启: $service"
}

run_install_or_update() {
  local kind="$1"
  local config_url="$2"

  require_root
  install_panel_script "$kind"
  apply_config "$kind" "$config_url"
  restart_service "$kind"
  show_status "$kind"
}

run_config_update() {
  local kind="$1"
  local config_url="$2"

  require_root
  apply_config "$kind" "$config_url"
  restart_service "$kind"
  show_status "$kind"
}

show_one_status() {
  local kind="$1"
  local service

  service="$(service_name "$kind")"
  print_title "[$service]"

  if ! command -v systemctl >/dev/null 2>&1; then
    warn "找不到 systemctl，无法读取服务状态"
    return
  fi

  if systemctl is-active --quiet "$service"; then
    printf "service: %s\nstatus: ${C_GREEN}active/running${C_RESET}\n" "$service"
    return
  fi

  if systemctl list-unit-files "$service.service" >/dev/null 2>&1; then
    printf "service: %s\nstatus: ${C_RED}%s${C_RESET}\n" "$service" "$(systemctl is-active "$service" 2>/dev/null || true)"
    return
  fi

  printf "service: %s\nstatus: ${C_YELLOW}not-found${C_RESET}\n" "$service"
}

show_status() {
  local target="${1:-all}"

  case "$target" in
    all|"")
      show_one_status v2bx
      show_one_status xrayr
      ;;
    v2bx|xrayr)
      show_one_status "$target"
      ;;
    *)
      die "status 只支持: v2bx 或 xrayr"
      ;;
  esac
}

interactive_menu() {
  local choice url

  print_title "V2bX / XrayR 管理脚本"
  printf "  1) 安装/更新 V2bX\n"
  printf "  2) 安装/更新 XrayR\n"
  printf "  3) 只更新 V2bX 配置\n"
  printf "  4) 只更新 XrayR 配置\n"
  printf "  5) 查看服务状态\n"
  printf "\n"

  read -r -p "请输入选项: " choice

  case "$choice" in
    1)
      url="$(choose_config_url v2bx)"
      run_install_or_update v2bx "$url"
      ;;
    2)
      url="$(choose_config_url xrayr)"
      run_install_or_update xrayr "$url"
      ;;
    3)
      url="$(choose_config_url v2bx)"
      run_config_update v2bx "$url"
      ;;
    4)
      url="$(choose_config_url xrayr)"
      run_config_update xrayr "$url"
      ;;
    5)
      show_status all
      ;;
    *)
      die "无效选项: $choice"
      ;;
  esac
}

main() {
  local cmd="${1:-}"
  local url

  case "$cmd" in
    "")
      interactive_menu
      ;;
    help|--help|-h)
      usage
      ;;
    v2bx|xrayr)
      url="$(resolve_config_url "$cmd" "${2:-}")"
      run_install_or_update "$cmd" "$url"
      ;;
    update-v2bx)
      url="$(resolve_config_url v2bx "${2:-}")"
      run_config_update v2bx "$url"
      ;;
    update-xrayr)
      url="$(resolve_config_url xrayr "${2:-}")"
      run_config_update xrayr "$url"
      ;;
    status)
      show_status "${2:-all}"
      ;;
    *)
      usage
      die "未知命令: $cmd"
      ;;
  esac
}

main "$@"
