#!/usr/bin/env bash
#
# 下载 Clash Verge 最新版，或按版本删除客户端。
#
# 默认目录:
#   /home/wwwroot/file.o4o.win/clash/clash-verge
#   ├── macOs     (aarch64.dmg / x64.dmg)
#   └── windows   (*-setup.exe，含 fixed_webview2 版本)
#
# 用法:
#   bash download-clash-verge.sh                  # 使用默认目录
#   bash download-clash-verge.sh /data/clash-verge
#   bash download-clash-verge.sh --force          # 覆盖已存在的最新版文件
#   bash download-clash-verge.sh --dry-run        # 只显示将要下载的文件
#   bash download-clash-verge.sh -r 2.5.6         # 删除 2.5.6 的全部客户端
#   bash download-clash-verge.sh -r 2.5.6 -y      # 删除时跳过确认
#
# 可选环境变量:
#   BASE_DIR       自定义目标根目录
#   GITHUB_TOKEN   GitHub API 限流时使用
#
set -euo pipefail

REPO="clash-verge-rev/clash-verge-rev"
DEFAULT_BASE_DIR="/home/wwwroot/file.o4o.win/clash/clash-verge"
BASE_DIR="${BASE_DIR:-$DEFAULT_BASE_DIR}"
FORCE=0
DRY_RUN=0
DELETE_VERSION=""
ASSUME_YES=0

usage() {
  cat <<'EOF'
用法:
  bash download-clash-verge.sh [选项] [目标根目录]

默认目标根目录:
  /home/wwwroot/file.o4o.win/clash/clash-verge
  ├── macOs     (aarch64.dmg / x64.dmg)
  └── windows   (*-setup.exe，含 fixed_webview2 版本)

选项:
  -d, --dir DIR    指定目标根目录
  -f, --force      覆盖已存在的同版本文件
  -n, --dry-run    只显示将要下载的文件，不实际下载
  -r, --rm VERSION  删除指定版本的全部客户端（先列出并确认；可写 2.5.6 或 v2.5.6）
  -y, --yes        删除时跳过确认
  -h, --help       显示帮助

环境变量:
  BASE_DIR        自定义目标根目录
  GITHUB_TOKEN    GitHub API 限流时使用
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force)
      FORCE=1
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    -r|--rm)
      if [ $# -lt 2 ]; then
        echo "错误: $1 需要一个版本号，例如 2.5.6" >&2
        exit 1
      fi
      DELETE_VERSION="$2"
      shift 2
      ;;
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    -d|--dir)
      if [ $# -lt 2 ]; then
        echo "错误: $1 需要一个目录参数" >&2
        exit 1
      fi
      BASE_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "错误: 未知选项 $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      BASE_DIR="$1"
      shift
      ;;
  esac
done

delete_version_files() {
  local version="$1"
  local file
  local files=()
  local deleted=0
  local failed=0
  local reply

  version="${version#[vV]}"
  case "$version" in
    [0-9]*) ;;
    *)
      echo "错误: 版本号格式不正确: ${version}（例如 2.5.6）" >&2
      return 1
      ;;
  esac
  case "$version" in
    *[!0-9A-Za-z._-]*)
      echo "错误: 版本号只能包含数字、字母、点、下划线和短横线。" >&2
      return 1
      ;;
  esac

  if [ ! -d "$BASE_DIR" ]; then
    echo "错误: 目录不存在: $BASE_DIR" >&2
    return 1
  fi

  shopt -s nullglob
  files=(
    "$BASE_DIR/macOs/Clash.Verge_${version}_"*.dmg
    "$BASE_DIR/windows/Clash.Verge_${version}_"*-setup.exe
  )
  shopt -u nullglob

  if [ "${#files[@]}" -eq 0 ]; then
    echo "未找到 Clash Verge ${version} 的客户端文件。目录: ${BASE_DIR}"
    return 0
  fi

  echo "将删除 Clash Verge ${version} 的客户端文件:"
  for file in "${files[@]}"; do
    printf '  %s (%s)\n' "$file" "$(du -h "$file" | cut -f1)"
  done

  if [ "$ASSUME_YES" -eq 0 ]; then
    if [ ! -t 0 ]; then
      echo "当前不是交互终端，未执行删除；如确认删除请加 -y。" >&2
      return 2
    fi
    printf '确认删除以上 %d 个文件？[y/N] ' "${#files[@]}"
    if ! IFS= read -r reply; then
      echo
      echo "已取消删除。"
      return 0
    fi
    case "$reply" in
      [yY]|[yY][eE][sS]) ;;
      *)
        echo "已取消删除。"
        return 0
        ;;
    esac
  fi

  for file in "${files[@]}"; do
    if rm -f -- "$file"; then
      printf '  已删除: %s\n' "$file"
      deleted=$((deleted + 1))
    else
      printf '  删除失败: %s\n' "$file" >&2
      failed=$((failed + 1))
    fi
  done

  echo "删除完成: 成功 ${deleted} 个，失败 ${failed} 个。"
  [ "$failed" -eq 0 ]
}

if [ -n "$DELETE_VERSION" ]; then
  delete_version_files "$DELETE_VERSION"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "错误: 未找到 curl，请先安装 curl。" >&2
  exit 1
fi

if [ ! -d "$BASE_DIR" ]; then
  if ! mkdir -p "$BASE_DIR"; then
    echo "错误: 无法创建目录 $BASE_DIR" >&2
    exit 1
  fi
fi
if ! mkdir -p "$BASE_DIR/macOs" "$BASE_DIR/windows"; then
  echo "错误: 无法创建子目录，请检查 $BASE_DIR 的写权限。" >&2
  exit 1
fi

API_URL="https://api.github.com/repos/${REPO}/releases/latest"
CURL_HEADERS=(
  -H "Accept: application/vnd.github+json"
  -H "User-Agent: clash-verge-downloader"
)
if [ -n "${GITHUB_TOKEN:-}" ]; then
  CURL_HEADERS+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

echo "正在获取最新版本信息: ${REPO}"
if ! RELEASE_JSON="$(curl -fsSL --retry 3 --connect-timeout 15 "${CURL_HEADERS[@]}" "$API_URL")"; then
  echo "错误: 获取 GitHub Release 失败。" >&2
  echo "提示: 如果遇到 API 限流，可设置 GITHUB_TOKEN 后重试。" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  TAG="$(printf '%s' "$RELEASE_JSON" | jq -r '.tag_name // empty')"
  ASSET_NAMES="$(printf '%s' "$RELEASE_JSON" | jq -r '.assets[]?.name // empty')"
else
  TAG="$(printf '%s\n' "$RELEASE_JSON" \
    | grep -m 1 '"tag_name"' \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
  ASSET_NAMES="$(printf '%s\n' "$RELEASE_JSON" \
    | grep -oE '"name": *"[^"]+\.(dmg|exe)"' \
    | sed -E 's/.*"name": *"([^"]+)"/\1/')"
fi

if [ -z "$TAG" ]; then
  echo "错误: 无法解析最新版本号。" >&2
  exit 1
fi
VERSION="${TAG#v}"

DMG_NAMES=()
EXE_NAMES=()
while IFS= read -r name; do
  [ -n "$name" ] || continue
  case "$name" in
    *.dmg) DMG_NAMES+=("$name") ;;
    *-setup.exe) EXE_NAMES+=("$name") ;;
  esac
done <<EOF
$ASSET_NAMES
EOF

echo "最新版本: ${VERSION} (${TAG})"
echo "目标目录: ${BASE_DIR}"
if [ "${#DMG_NAMES[@]}" -eq 0 ] && [ "${#EXE_NAMES[@]}" -eq 0 ]; then
  echo "错误: 最新 Release 中没有找到 .dmg 或 -setup.exe 文件。" >&2
  exit 1
fi

DOWNLOADED=0
SKIPPED=0
FAILED=0
PLANNED=0

download_one() {
  local name="$1"
  local dest_dir="$2"
  local dest="${dest_dir}/${name}"
  local url="https://github.com/${REPO}/releases/download/${TAG}/${name}"
  local tmp

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [预览] %s\n' "$dest"
    PLANNED=$((PLANNED + 1))
    return 0
  fi

  if [ -s "$dest" ] && [ "$FORCE" -eq 0 ]; then
    printf '  已存在，跳过: %s\n' "$name"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  if ! tmp="$(mktemp "${dest}.part.XXXXXX")"; then
    printf '  错误: 无法创建临时文件: %s\n' "$dest" >&2
    return 1
  fi

  printf '  正在下载: %s\n' "$name"
  if curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 \
      --silent --show-error -o "$tmp" "$url"; then
    if ! mv -f "$tmp" "$dest"; then
      rm -f "$tmp"
      printf '  错误: 无法写入 %s\n' "$dest" >&2
      return 1
    fi
    # mktemp 创建的临时文件是 600 权限，mv 会保留；nginx 需要可读，统一改为 644
    chmod 644 "$dest"
    printf '  完成: %s (%s)\n' "$name" "$(du -h "$dest" | cut -f1)"
    DOWNLOADED=$((DOWNLOADED + 1))
    return 0
  else
    rm -f "$tmp"
    printf '  下载失败: %s\n' "$url" >&2
    return 1
  fi
}

download_list() {
  local dest_dir="$1"
  shift
  local name
  for name in "$@"; do
    if ! download_one "$name" "$dest_dir"; then
      FAILED=$((FAILED + 1))
    fi
  done
}

if [ "${#DMG_NAMES[@]}" -gt 0 ]; then
  echo
  echo "==> macOS (${BASE_DIR}/macOs)"
  download_list "$BASE_DIR/macOs" "${DMG_NAMES[@]}"
fi

if [ "${#EXE_NAMES[@]}" -gt 0 ]; then
  echo
  echo "==> Windows (${BASE_DIR}/windows)"
  download_list "$BASE_DIR/windows" "${EXE_NAMES[@]}"
fi

echo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "预览完成: 共 ${PLANNED} 个文件，未实际下载。"
else
  echo "处理完成: 新下载 ${DOWNLOADED} 个，跳过 ${SKIPPED} 个，失败 ${FAILED} 个。"
fi

[ "$FAILED" -eq 0 ] || exit 1
