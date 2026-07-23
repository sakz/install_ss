#!/usr/bin/env bash

set -euo pipefail

CONFIG_DIR="${V2BX_CONFIG_DIR:-/etc/V2bX}"
DEFAULT_CONFIG_DIR="${V2BX_DEFAULT_CONFIG_DIR:-/usr/local/share/V2bX}"
V2BX_BIN="${V2BX_BIN:-/usr/local/V2bX/V2bX}"
TEMP_PATHS=()

cleanup() {
  [ "${#TEMP_PATHS[@]}" -eq 0 ] || rm -rf -- "${TEMP_PATHS[@]}"
}

register_temp() {
  TEMP_PATHS+=("$1")
}

trap cleanup EXIT

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

validate_archive_paths() {
  local archive="$1"
  local entry

  while IFS= read -r entry; do
    case "$entry" in
      /*|../*|*/../*|..)
        return 1
        ;;
    esac
  done < <(unzip -Z1 "$archive")
}

prepare_config() {
  local archive="$1"
  local parent stage extracted source_dir

  parent="$(dirname "$CONFIG_DIR")"
  mkdir -p "$parent"
  stage="$(mktemp -d "${parent}/.V2bX.new.XXXXXX")"
  extracted="$(mktemp -d)"
  register_temp "$stage"
  register_temp "$extracted"

  unzip -tqq "$archive" >/dev/null || die '配置 ZIP 校验失败'
  validate_archive_paths "$archive" || die '配置 ZIP 包含不安全的路径'
  unzip -q "$archive" -d "$extracted"

  source_dir="$extracted"
  if [ -d "$extracted/V2bX" ]; then
    source_dir="$extracted/V2bX"
  fi

  if [ -d "$DEFAULT_CONFIG_DIR" ]; then
    cp -a "$DEFAULT_CONFIG_DIR/." "$stage/"
  fi
  cp -a "$source_dir/." "$stage/"
  [ -f "$stage/config.json" ] || die '配置 ZIP 中缺少 config.json'

  rm -rf "$CONFIG_DIR"
  mv "$stage" "$CONFIG_DIR"
  rm -rf "$extracted"
}

main() {
  local archive

  [ -n "${V2BX_CONFIG_URL:-}" ] || die '必须设置 V2BX_CONFIG_URL'
  [ -x "$V2BX_BIN" ] || die "找不到 V2bX 可执行文件: $V2BX_BIN"

  archive="$(mktemp)"
  register_temp "$archive"
  printf '%s\n' '正在下载并校验 V2bX 配置 ZIP'
  curl --fail --location --retry 3 --silent --show-error "$V2BX_CONFIG_URL" --output "$archive" \
    || die '配置 ZIP 下载失败'
  prepare_config "$archive"
  printf '%s\n' '配置已加载，启动 V2bX'
  exec "$V2BX_BIN" "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
