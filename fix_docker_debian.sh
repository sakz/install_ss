#!/bin/bash
# 修复 Debian/Ubuntu 上损坏的 Docker apt 源和 GPG key，并重新安装 Docker
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 运行"
    exit 1
fi

. /etc/os-release
os_id="$ID"
os_codename="$VERSION_CODENAME"
case "$os_id" in
    debian|ubuntu)
    ;;
    *)
        echo "不支持的系统：${os_id:-unknown}"
        exit 1
    ;;
esac
if [ -z "$os_codename" ]; then
    echo "无法从 /etc/os-release 获取 VERSION_CODENAME"
    exit 1
fi

backup_dir=$(mktemp -d /root/docker-apt-backup-XXXXXX)
echo "备份目录：$backup_dir"
shopt -s nullglob
for f in /etc/apt/sources.list.d/*docker*; do
    mv "$f" "$backup_dir/"
done
for f in /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc; do
    if [ -e "$f" ]; then
        mv "$f" "$backup_dir/"
    fi
done

apt update
apt install -y ca-certificates curl gnupg

install -d -m 0755 /etc/apt/keyrings
tmp_key=$(mktemp)
trap 'rm -f "$tmp_key"' EXIT
repo_url=""
# 优先官方源，官方不可达时再回退腾讯云镜像
for candidate in \
    "https://download.docker.com/linux/${os_id}" \
    "https://mirrors.tencentyun.com/docker-ce/linux/${os_id}" \
    "https://mirrors.cloud.tencent.com/docker-ce/linux/${os_id}"; do
    if curl -fsS --connect-timeout 5 --max-time 10 -o /dev/null "${candidate}/dists/${os_codename}/InRelease" 2>/dev/null \
       && : > "$tmp_key" \
       && curl -fsSL --connect-timeout 5 --max-time 30 "${candidate}/gpg" -o "$tmp_key" 2>/dev/null \
       && [ -s "$tmp_key" ] \
       && gpg --show-keys "$tmp_key" >/dev/null 2>&1; then
        repo_url="$candidate"
        break
    fi
done
if [ -z "$repo_url" ]; then
    echo "找不到可用的 Docker 软件源或 GPG key"
    exit 1
fi
echo "使用 Docker 源：$repo_url"
if ! install -m 0644 "$tmp_key" /etc/apt/keyrings/docker.asc; then
    echo "Docker GPG key 安装失败"
    exit 1
fi
rm -f "$tmp_key"

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] ${repo_url} ${os_codename} stable" > /etc/apt/sources.list.d/docker.list

if ! apt update; then
    echo "apt update 失败"
    exit 1
fi
if [ -z "$(apt-cache madison docker-ce 2>/dev/null || true)" ]; then
    echo "docker-ce 没有可安装候选"
    apt-cache policy docker-ce || true
    exit 1
fi
if ! apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    echo "Docker 软件包安装失败"
    exit 1
fi

if ! systemctl enable --now docker; then
    echo "Docker 服务启动失败"
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon 未正常运行"
    systemctl status docker --no-pager || true
    exit 1
fi
docker compose version

if [ -x /usr/libexec/docker/cli-plugins/docker-compose ]; then
    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
fi

echo "Docker 安装完成；旧配置已备份到 $backup_dir"
