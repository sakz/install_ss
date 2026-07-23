# Debian 12 Docker V2bX

此目录把 V2bX 放进 Debian 12 容器运行，供 CentOS 7 等 Linux Docker 宿主机使用。容器不依赖 systemd；V2bX 以 PID 1 运行。首版只发布 `linux/amd64` 镜像，构建主机须为 amd64，或使用已启用 buildx 的跨架构构建器。

## 本地构建与启动

```bash
cd docker-v2bx-debian12
cp .env.example .env
```

编辑 `.env`：

- `V2BX_VERSION`：V2bX 上游 GitHub Release 的精确 tag。
- `V2BX_CONFIG_URL`：你的私有 `v.zip` 下载链接。
- `V2BX_IMAGE`：本地保持默认即可。

然后执行：

```bash
docker compose build
docker compose up -d
docker compose logs -f v2bx
```

每次容器启动都会重新下载 ZIP，校验后将配置写入 `/etc/V2bX`。ZIP 可直接包含配置文件，或包含一层 `V2bX/` 目录；两种布局都会写入该目录根部。ZIP 必须包含 `config.json`。

`docker-compose.yml` 使用 `network_mode: host`，所以 ZIP 中配置的监听端口直接暴露在宿主机上。请在宿主机防火墙和云安全组中开放所需端口。host 网络只适用于 Linux Docker 宿主机。

不要提交 `.env`，其中的私有链接可能包含访问令牌。启动日志不会输出该链接。

## 更新

修改 `.env` 的 `V2BX_VERSION` 后重新构建并启动：

```bash
docker compose build --pull
docker compose up -d
```

仅更新 ZIP 配置时，更新链接指向的文件后重启容器：

```bash
docker compose restart v2bx
```

## GHCR 私有镜像

工作流 `.github/workflows/publish-ghcr.yml` 支持手动触发，或推送形如 `v2bx-v0.4.0` 的 Git tag。它会推送到：

```text
ghcr.io/<GitHub-owner>/v2bx-debian12:<image-tag>
```

发布前应确认仓库 Actions 有 `packages: write` 权限，并在 GHCR 包设置中保持私有。运行服务器需要使用具有 `read:packages` 权限的 GitHub PAT 登录：

```bash
echo '<PAT>' | docker login ghcr.io -u '<GitHub-user>' --password-stdin
```

然后将 `.env` 的 `V2BX_IMAGE` 改成已发布镜像地址，执行：

```bash
docker compose pull
docker compose up -d
```

## 验证

```bash
bash -n docker-entrypoint.sh
bash tests/test-entrypoint.sh
docker compose build
```
