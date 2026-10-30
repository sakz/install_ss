# install_ss
some shell scripts for personal usage

## pfmgr 本机端口转发

pfmgr v2.2.0 新增本机端口转发。安装或升级管理器后，将本机 IPv4 的 8090 转发到同一地址的 8080（同时支持 TCP 和 UDP）：

```bash
sudo bash pfmgr-v2.2.0.sh install
sudo pfmgr add 8090 local 8080
```

支持外部访问 `服务器IPv4:8090`，也支持本机访问 `127.0.0.1:8090` 或 `本机IPv4:8090`。仅改变目标端口，保留目标 IP 和客户端 IP，不影响访问其他机器的 8090。外部访问时，8080 服务需监听 `0.0.0.0` 或相应本机 IP；仅监听 `127.0.0.1` 的服务可通过本机 loopback 访问。现有防火墙需要在 INPUT 中放行转换后的目标端口（例如 8080），云安全组需要放行入口端口（例如 8090）。

```bash
sudo pfmgr update 8090 local 8081  # 修改本机目标端口
sudo pfmgr list                    # 查看配置
sudo pfmgr stats                   # 查看 TCP/UDP 双向流量
sudo pfmgr delete 8090             # 删除该转发
```

规则继续通过 nftables 和 `pfmgr.service` 在开机时恢复；原有 `pfmgr add 8443 1.2.3.4 443` 远端转发用法保持兼容。本机转发的入口和目标端口必须不同。
