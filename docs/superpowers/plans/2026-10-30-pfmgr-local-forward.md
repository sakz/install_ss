# pfmgr 本机端口转发 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 支持 `pfmgr add 8090 local 8080`，将访问本机 IPv4 8090 的 TCP/UDP 连接转到同一地址的 8080。

**Architecture:** 保留三列 TSV 配置，以 `local` 表示本机目标。在 PREROUTING 和 OUTPUT 中限定目标为本机地址，仅做目标端口 DNAT；本机规则不生成远端 MASQUERADE/FORWARD 放行。分别在 INPUT 原方向和 OUTPUT 回复方向计数，避免 loopback 重复统计。沿用现有事务应用、回滚、持久化和管理命令。

**Tech Stack:** Bash、nftables、iptables-nft、Python unittest、Debian 12 Docker 容器。

---

### Task 1: 编写行为回归测试

**Files:**
- Create: `tests/test_pfmgr_local.py`
- Test: `pfmgr-v2.2.0.sh`

- [x] 编写测试，通过加载脚本函数并重定向配置路径，在临时目录调用真实 `cmd_add`、`cmd_update`、`cmd_delete`、`cmd_clear` 和两个规则渲染函数。

```bash
source "$1"  # 测试副本仅移除最终的 main 调用，保留全部函数
BASE_DIR="$2"
DB="${BASE_DIR}/rules.tsv"
prepare_write() { :; }
apply_rules() { render_runtime_nft "${BASE_DIR}/runtime.nft"; render_persistent_nft "${BASE_DIR}/persistent.nft"; }
cmd_add 8090 local 8080
```

- [x] 验证 add/update/list/delete/clear、非法端口、同端口本机转发、重复入口、远端规则兼容以及本机规则无 MASQUERADE/FORWARD 放行。
- [x] 在现有版本执行 `python3 -m unittest discover -s tests -v`，确认本机目标测试因缺少功能而失败。

### Task 2: 实现本机模式及持久化

**Files:**
- Modify: `pfmgr-v2.2.0.sh`
- Modify: `install.sh`
- Modify: `README.md`

- [x] add/update 接受 `local`，继续校验端口范围，拒绝本机入口与目标端口相同的规则；其他目标继续校验 IPv4。
- [x] 在 schema 和运行时事务中新增 OUTPUT NAT、INPUT/OUTPUT 统计链。本机 NAT 规则采用：

```nft
fib daddr type local tcp dport 8090 dnat to :8080
fib daddr type local udp dport 8090 dnat to :8080
```

- [x] 在持久化文件生成相同规则；本机规则跳过远端 MASQUERADE、FORWARD 统计与 iptables 放行。
- [x] INPUT 仅统计 `ct direction original`，OUTPUT 仅统计 `ct direction reply`，都限定 `ct status dnat`、原始入口端口和实际目标端口。stats 从自有整张表读取计数。
- [x] 更新帮助、安装后的示例和 README，说明本机访问、外部访问及服务监听地址要求。新增功能版本升级为 2.2.0，脚本更名为 `pfmgr-v2.2.0.sh`，同步安装入口和测试引用。
- [x] 执行单元测试、`bash -n pfmgr-v2.2.0.sh install.sh` 和 ShellCheck；只处理本次变更产生的问题。

### Task 3: Linux 网络实测与最终检查

**Files:**
- Create: `tests/integration_pfmgr_local.py`

- [x] 在隔离的 Debian 12 容器中运行真实 nftables、TCP/UDP echo 服务；从 loopback、本机网卡地址及独立客户端网络验证 8090→8080 双向收发。
- [x] 验证本机请求访问其他机器的 8090 不被改写、原有远端转发可用、stats 有双向计数、删除/清空后规则消失、重新加载持久化规则后转发仍可用。
- [x] 检查 `git diff --check` 和实际 diff，保留原有两个无关未跟踪文件。报告验证结果与部署用法，提交并推送本次 pfmgr 变更。
