#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="${ROOT_DIR}/docker-entrypoint.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_file() {
  [ -f "$1" ] || { printf 'missing expected file: %s\n' "$1" >&2; exit 1; }
}

run_layout_test() {
  local layout="$1"
  local source="${TMP_DIR}/${layout}-source"
  local archive="${TMP_DIR}/${layout}.zip"
  local config="${TMP_DIR}/${layout}-config"
  local defaults="${TMP_DIR}/${layout}-defaults"

  mkdir -p "$source" "$defaults"
  printf 'base-data\n' > "${defaults}/geoip.dat"
  if [ "$layout" = 'wrapped' ]; then
    mkdir -p "${source}/V2bX"
    printf '{}\n' > "${source}/V2bX/config.json"
    printf 'wrapped\n' > "${source}/V2bX/node.txt"
  else
    printf '{}\n' > "${source}/config.json"
    printf 'root\n' > "${source}/node.txt"
  fi
  (cd "$source" && zip -qr "$archive" .)

  V2BX_CONFIG_DIR="$config" V2BX_DEFAULT_CONFIG_DIR="$defaults" \
    bash -c 'source "$1"; prepare_config "$2"' _ "$ENTRYPOINT" "$archive"

  assert_file "${config}/config.json"
  assert_file "${config}/node.txt"
  assert_file "${config}/geoip.dat"
  [ ! -d "${config}/V2bX" ] || { printf 'nested V2bX directory was not flattened\n' >&2; exit 1; }
}

run_layout_test root
run_layout_test wrapped

printf 'not-a-zip\n' > "${TMP_DIR}/invalid.zip"
mkdir -p "${TMP_DIR}/invalid-config"
printf 'keep-me\n' > "${TMP_DIR}/invalid-config/config.json"
if V2BX_CONFIG_DIR="${TMP_DIR}/invalid-config" V2BX_DEFAULT_CONFIG_DIR="${TMP_DIR}/invalid-defaults" \
  bash -c 'source "$1"; prepare_config "$2"' _ "$ENTRYPOINT" "${TMP_DIR}/invalid.zip" >/dev/null 2>&1; then
  printf 'entrypoint accepted an invalid ZIP\n' >&2
  exit 1
fi
[ "$(cat "${TMP_DIR}/invalid-config/config.json")" = 'keep-me' ] \
  || { printf 'invalid ZIP overwrote the existing configuration\n' >&2; exit 1; }

if V2BX_CONFIG_DIR="${TMP_DIR}/missing-url" V2BX_BIN=/bin/true bash "$ENTRYPOINT" >/dev/null 2>&1; then
  printf 'entrypoint accepted missing V2BX_CONFIG_URL\n' >&2
  exit 1
fi

if V2BX_CONFIG_URL='file:///does-not-exist.zip' V2BX_CONFIG_DIR="${TMP_DIR}/bad-url" V2BX_BIN=/bin/true bash "$ENTRYPOINT" >/dev/null 2>&1; then
  printf 'entrypoint accepted a failed config download\n' >&2
  exit 1
fi

printf 'entrypoint tests passed\n'
