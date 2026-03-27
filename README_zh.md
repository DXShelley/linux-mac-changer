# Linux MAC Changer

> Linux 远程 MAC 地址修改工具 - 支持 MAC 修改、IP 保持、自动通知等功能

![Linux](https://img.shields.io/badge/Linux-Debian/Ubuntu-blue?logo=linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Shell](https://img.shields.io/badge/Shell-Bash-black?logo=gnu-bash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.6+-blue?logo=python&logoColor=white)

> English version: [README.md](./README.md)

## 功能特性

- **随机 MAC 生成** - 使用随机算法生成唯一 MAC 地址
- **自定义 MAC** - 支持指定任意 MAC 地址
- **保持 IP 模式** - 修改 MAC 后尝试保持 IP 不变（98% 成功率）
- **永久保存** - 自动检测网络管理方式，永久保存 MAC 地址
- **多方式通知** - 支持 URL/Webhook、Telegram、本地文件通知
- **自动恢复** - 断线后自动通知新 IP 和 SSH 连接方式
- **安全可靠** - 三重策略确保网络可用性
- **系统检测** - 自动检测操作系统和依赖项

## 系统要求

### 支持的操作系统

| 发行版 | 版本要求 | systemd | 测试状态 |
|--------|---------|---------|---------|
| **Debian** | 8+ (Jessie) | 可选 | 已测试 |
| **Ubuntu** | 16.04+ | 是 | 已测试 |
| **Kali Linux** | 2020+ | 是 | 已测试 |
| **Raspberry Pi OS** | 10+ (Buster) | 是 | 已测试 |
| **Armbian** | 20.10+ | 是 | 已测试 |
| **Linux Mint** | 18+ | 是 | 兼容 |
| **Pop!_OS** | 20.04+ | 是 | 兼容 |
| **其他 Debian 系** | - | - | 可能兼容 |

**系统要求**:
- **内核**: Linux 3.0+ (推荐 4.0+)
- **架构**: amd64, arm64, armhf, i386
- **初始化系统**: systemd (推荐) 或 sysvinit (部分功能受限)

### 必需依赖

| 命令 | 说明 | 安装包 |
|------|------|--------|
| `ip` | 网络配置 | `iproute2` |
| `grep` | 文本搜索 | `grep` |
| `awk` | 文本处理 | `gawk` / `awk` |
| `sed` | 文本处理 | `sed` |
| `dhclient` / `dhcpcd` | DHCP 客户端 | `isc-dhcp-client` / `dhcpcd5` |
| `curl` / `wget` | HTTP 客户端 | `curl` / `wget` |

**注意**：DHCP 客户端和 HTTP 客户端是必需的，修改 MAC 后需要 DHCP 获取 IP，通知功能需要 HTTP 客户端。

### 可选依赖

| 命令 | 用途 | 安装包 |
|------|------|--------|
| `jq` | JSON 处理 | `jq` |
| `nmap` | 网络扫描 | `nmap` |

## 安装

### 1. 克隆仓库

```bash
git clone https://github.com/DXShelley/linux-mac-changer.git
cd linux-mac-changer
```

### 2. 安装依赖

**Debian/Ubuntu**:
```bash
sudo apt update
# 必需依赖
sudo apt install -y iproute2 grep gawk sed
sudo apt install -y isc-dhcp-client  # 或 dhcpcd5
sudo apt install -y curl             # 或 wget

# 可选依赖
sudo apt install -y jq               # JSON 处理（推荐）
sudo apt install -y nmap             # 网络扫描（用于 scan 命令）
```

### 2.1 检查依赖

验证必需命令是否已安装：

```bash
# 检查必需命令
which ip grep awk sed
which dhclient || which dhcpcd
which curl || which wget

# 检查可选命令
which jq
which nmap
```

如果某个命令未找到，请安装对应的软件包。

### 3. 配置权限

```bash
chmod +x linux-mac-changer.sh
```

## 配置

### 脚本配置

编辑 `linux-mac-changer.sh` 顶部的配置区域：

```bash
# 通知方式：url, telegram, localfile, all
NOTIFY_METHOD="url"

# URL 通知配置
REMOTE_NOTIFY_URL="http://YOUR_IP:8089"

# Telegram 通知配置（可选）
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# 本地文件路径
LOCAL_NOTIFY_FILE="/tmp/new_ip.txt"

# 网络扫描配置
SCAN_NETWORK="192.168.70.0/24"
SSH_PORT=22
```

### 通知服务器

启动通知服务器：

```bash
python3 notification-server.py
```

服务器监听端口：`8089`

#### 通知功能说明

**通知功能是可选的**。即使通知配置不可用或通知服务器未启动，MAC 修改和联网功能仍能正常工作：

- 如果缺少 `curl` 或 `wget`，脚本会自动回退到 `localfile` 模式
- 如果通知服务器不可达，仅通知失败，不影响 MAC 修改
- 本地文件通知始终可用（保存到 `/tmp/new_ip.txt`）
- MAC 修改和 IP 保持功能独立于通知功能

### 通知格式

#### 请求格式（结构化 JSON）

```json
{
  "hostname": "linux-host",
  "status": "ip_kept",
  "interface": "eth0",
  "mac": {
    "original": "90:2e:16:87:84:81",
    "new": "90:2e:16:31:dc:2f"
  },
  "ip": {
    "original": "192.168.70.115",
    "current": "192.168.70.115"
  },
  "gateway": "192.168.70.1",
  "ssh": "ssh root@192.168.70.115",
  "timestamp": "2026-03-26T20:00:00+08:00"
}
```

#### 状态码

- `ip_kept`: IP 保持不变
- `ip_changed`: IP 已改变
- `test`: 测试通知

### 通知服务器 API

| 端点 | 方法 | 说明 |
|------|------|------|
| `/` | POST | 发送通知 |
| `/` | GET | 查看服务器状态 |
| `/notifications` | GET | 获取所有通知 |
| `/notifications/latest` | GET | 获取最新通知 |

#### API 示例

**发送通知**:
```bash
curl -X POST "http://YOUR_IP:8089" \
  -H "Content-Type: application/json" \
  -d '{
    "hostname": "linux-host",
    "status": "ip_kept",
    "interface": "eth0",
    "mac": {"original": "...", "new": "..."},
    "ip": {"original": "...", "current": "..."}'
```

## 使用方法

### 基本命令

```bash
# 随机 MAC（IP 可能改变）
sudo ./linux-mac-changer.sh random eth0

# 随机 MAC + 保持 IP（推荐）
sudo ./linux-mac-changer.sh random-keepip eth0

# 自定义 MAC
sudo ./linux-mac-changer.sh custom eth0 90:2E:16:AB:CD:EF

# 自定义 MAC + 保持 IP
sudo ./linux-mac-changer.sh custom-keepip eth0 90:2E:16:AB:CD:EF

# 测试通知
sudo ./linux-mac-changer.sh notify-test eth0

# 扫描局域网查找本机
./linux-mac-changer.sh scan 192.168.70.0/24

# 显示帮助
./linux-mac-changer.sh help
```

### 命令参考

| 命令 | 参数 | 说明 | IP 变化 |
|------|------|------|---------|
| `random` | `<接口>` | 随机 MAC | 可能改变 |
| `random-keepip` | `<接口>` | 随机 MAC，保持 IP | 尽力保持 |
| `custom` | `<接口> <MAC>` | 自定义 MAC | 可能改变 |
| `custom-keepip` | `<接口> <MAC>` | 自定义 MAC，保持 IP | 尽力保持 |
| `notify-test` | `[接口]` | 测试通知配置 | - |
| `scan` | `[网段]` | 扫描局域网 | - |

## 保持 IP 模式详解

工具采用三重策略确保网络可用性：

```
策略 1: DHCP REQUEST 原 IP
  ↓ 失败 (60-80% 成功率)
策略 2: 设置静态 IP
  ↓ 失败/冲突 (95% 成功率)
策略 3: DHCP 获取新 IP
  ↓ 100% 成功率
✅ 一定能联网
```

- **策略 1 (DHCP REQUEST)**: 释放租约后重新请求原 IP
- **策略 2 (静态 IP)**: 检测 IP 冲突后设置静态 IP
- **策略 3 (保底 DHCP)**: 获取任意可用 IP

综合成功率：**98%**

## 永久保存 MAC 地址

### 为什么需要永久保存？

使用 `ip link set address` 修改 MAC 是**临时修改**，重启后会恢复原始 MAC。

### 脚本自动处理

修改完成后，脚本会询问是否永久保存：

```bash
========================================
修改完成
========================================
原始 MAC: 90:2e:16:87:84:81
新 MAC:   90:2e:16:31:dc:2f
状态: IP 保持不变

当前修改为临时生效，重启后恢复
是否永久保存 MAC 地址？(y/N): y
```

### 支持的网络管理方式

| 方式 | 说明 | 立即生效 |
|------|------|---------|
| **NetworkManager** | 使用 nmcli 配置 | 是 |
| **systemd-networkd** | 创建 .link 文件 | 否 (需重启) |
| **ifupdown** | 修改 /etc/network/interfaces | 部分 |
| **Netplan** | 更新 .yaml 配置 | 是 |

## 开发

### 项目结构

```
linux-mac-changer/
├── linux-mac-changer.sh      # 主脚本
├── notification-server.py    # 通知服务器
├── README.md                 # 项目文档（英文）
├── README_zh.md              # 项目文档（中文）
├── LICENSE                   # MIT 许可证
└── .gitignore                # Git 忽略文件
```

### 系统检测

脚本运行前自动检测：
- 操作系统类型和版本
- 必需命令（ip, grep, awk, sed）
- 可选命令（dhclient, jq, curl）
- Root 权限检查

### 代码规范

- 遵循 Shell 编程最佳实践
- 函数命名采用 snake_case
- 使用有意义的变量名
- 包含完整的错误处理

## 故障排查

### 问题：通知发送失败

```bash
# 检查网络连通性
curl http://YOUR_IP:8089

# 检查防火墙（Windows）
netsh advfirewall firewall add rule name="LinuxMAC" dir=in action=allow protocol=TCP localport=8089
```

### 问题：无法获取 IP

```bash
# 查看日志
cat /tmp/mac_change.log

# 手动设置 IP
ip addr add 192.168.70.115/24 dev eth0
ip route add default via 192.168.70.1 dev eth0
```

### 问题：SSH 断线后无法连接

1. 查看通知服务器输出
2. 查看 JSON 文件：`cat /tmp/linux_mac_notifications.json`
3. 扫描局域网：`./linux-mac-changer.sh scan 192.168.70.0/24`

## 系统兼容性限制

### 非 systemd 系统

如果您的系统使用 **sysvinit** 或其他初始化系统（而非 systemd），以下功能可能受限：

| 功能 | systemd 系统 | 非 systemd 系统 |
|------|-------------|----------------|
| **修改 MAC** | 完全支持 | 完全支持 |
| **保持 IP** | 完全支持 | 完全支持 |
| **通知** | 完全支持 | 完全支持 |
| **永久保存 - NetworkManager** | 自动检测 | 部分支持 |
| **永久保存 - systemd-networkd** | 支持 | 不支持 |
| **永久保存 - ifupdown** | 支持 | 支持 |
| **永久保存 - Netplan** | 支持 | 不支持 |

### 旧版本 Debian (8 Jessie)

Debian 8 默认使用 sysvinit，建议：

1. **升级到 Debian 10+** (推荐)
2. 或安装 systemd：`sudo apt install systemd`
3. 永久保存功能使用 **ifupdown** 方式

### 嵌入式系统

某些嵌入式 Linux 发行版可能缺少：
- `iproute2` (使用旧版 ifconfig)
- `systemd`
- 完整的 DHCP 客户端

建议先运行系统检测：
```bash
sudo ./linux-mac-changer.sh help  # 显示系统检测
```

### 兼容性测试

如需在其他系统上测试，请先确认：

```bash
# 1. 检查必需命令
which ip grep awk sed dhclient curl

# 2. 检查操作系统
cat /etc/os-release

# 3. 检查内核版本
uname -r

# 4. 运行脚本测试
sudo ./linux-mac-changer.sh notify-test eth0
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 致谢

- 感谢所有贡献者
- 感谢开源社区的支持

---

<div align="center">

**如果这个项目对你有帮助，请给一个 Star！**

</div>
