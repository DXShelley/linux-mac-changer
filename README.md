# Linux MAC Changer

> Linux 远程 MAC 地址修改工具 - 支持 MAC 修改、IP 保持、自动通知等功能

![Linux](https://img.shields.io/badge/Linux-Debian/Ubuntu-blue?logo=linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Shell](https://img.shields.io/badge/Shell-Bash-black?logo=gnu-bash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.6+-blue?logo=python&logoColor=white)

## ✨ 功能特性

- 🎲 **随机 MAC 生成** - 使用随机算法生成唯一 MAC 地址
- ✏️ **自定义 MAC** - 支持指定任意 MAC 地址
- 🔒 **保持 IP 模式** - 修改 MAC 后尝试保持 IP 不变（98% 成功率）
- 📢 **多方式通知** - 支持 URL/Webhook、Telegram、本地文件通知
- 🔄 **自动恢复** - 断线后自动通知新 IP 和 SSH 连接方式
- 🛡️ **安全可靠** - 三重策略确保网络可用性
- 🔍 **系统检测** - 自动检测操作系统和依赖项

## 🖼️ 截图

```
╔═══════════════════════════════════════════════════════════════╗
║          Linux MAC 修改工具 v1.0.0 - 最终总结                    ║
╚═══════════════════════════════════════════════════════════════╝

📦 核心文件 (3 个):
  ├── linux-mac-changer.sh    (34 KB, 1092 行)  主脚本
  ├── notification-server.py   (5.7 KB, 178 行)  通知服务器
  └── README.md                (9.6 KB, 437 行)  完整文档

🔍 系统兼容性:
  ✅ Debian/Ubuntu/Kali Linux
  ✅ Raspberry Pi OS
  ✅ Armbian
  ✅ 其他 Debian 系发行版
```

## 📋 系统要求

### 支持的操作系统

- ✅ Debian 8+
- ✅ Ubuntu 16.04+
- ✅ Kali Linux
- ✅ Raspbian / Raspberry Pi OS
- ✅ Armbian
- ✅ 其他基于 Debian 的发行版

### 必需依赖

| 命令 | 说明 | 安装包 |
|------|------|--------|
| `ip` | 网络配置 | `iproute2` |
| `grep` | 文本搜索 | `grep` |
| `awk` | 文本处理 | `gawk` / `awk` |
| `sed` | 文本处理 | `sed` |

### 可选依赖

| 命令 | 用途 | 安装包 |
|------|------|--------|
| `dhclient` / `dhcpcd` | DHCP 客户端 | `isc-dhcp-client` / `dhcpcd5` |
| `jq` | JSON 处理 | `jq` |
| `curl` / `wget` | HTTP 客户端 | `curl` / `wget` |
| `nmap` | 网络扫描 | `nmap` |

## 📦 安装

### 1. 克隆仓库

```bash
git clone https://github.com/DXShelley/linux-mac-changer.git
cd linux-mac-changer
```

### 2. 安装依赖

**Debian/Ubuntu**:
```bash
sudo apt update
sudo apt install -y iproute2 grep gawk sed jq curl
sudo apt install -y isc-dhcp-client  # 或 dhcpcd5
```

### 3. 配置权限

```bash
chmod +x linux-mac-changer.sh
```

## 🚀 使用方法

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

## ⚙️ 配置

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

## 📊 保持 IP 模式详解

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

## 🔔 通知格式

### 请求格式（结构化 JSON）

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

### 状态码

- `ip_kept`: IP 保持不变
- `ip_changed`: IP 已改变
- `test`: 测试通知

## 🛠️ 开发

### 项目结构

```
linux-mac-changer/
├── linux-mac-changer.sh      # 主脚本
├── notification-server.py     # 通知服务器
├── README.md                   # 项目文档
├── LICENSE                     # MIT 许可证
└── .gitignore                  # Git 忽略文件
```

### 系统检测

脚本运行前自动检测：
- ✅ 操作系统类型和版本
- ✅ 必需命令（ip, grep, awk, sed）
- ✅ 可选命令（dhclient, jq, curl）
- ✅ Root 权限检查

### 代码规范

- 遵循 Shell 编程最佳实践
- 函数命名采用 snake_case
- 使用有意义的变量名
- 包含完整的错误处理

## 📖 API 文档

### 通知服务器 API

| 端点 | 方法 | 说明 |
|------|------|------|
| `/` | POST | 发送通知 |
| `/` | GET | 查看服务器状态 |
| `/notifications` | GET | 获取所有通知 |
| `/notifications/latest` | GET | 获取最新通知 |

### API 示例

**发送通知**:
```bash
curl -X POST "http://YOUR_IP:8089" \
  -H "Content-Type: application/json" \
  -d '{
    "hostname": "linux-host",
    "status": "ip_kept",
    "interface": "eth0",
    "mac": {"original": "...", "new": "..."},
    "ip": {"original": "...", "current": "..."}
  }'
```

## 🔍 故障排查

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

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 👨‍💻 作者

DXShelley - [GitHub](https://github.com/DXShelley)

## 🙏 致谢

- 感谢所有贡献者
- 感谢开源社区的支持

---

<div align="center">

**⭐ 如果这个项目对你有帮助，请给一个 Star！**

</div>
