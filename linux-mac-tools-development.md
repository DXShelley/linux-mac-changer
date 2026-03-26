# Linux MAC 工具开发最佳实践

> 基于 Linux MAC Changer 项目的开发经验总结
> 仓库：https://github.com/DXShelley/linux-mac-changer
> 版本：v1.0.0

## 目录

1. [需求分析](#1-需求分析)
2. [技术方案设计](#2-技术方案设计)
3. [实现技巧](#3-实现技巧)
4. [常见陷阱](#4-常见陷阱)
5. [代码规范](#5-代码规范)
6. [Git 工作流](#6-git-工作流)
7. [项目规范](#7-项目规范)
8. [调试技巧](#8-调试技巧)
9. [安全考虑](#9-安全考虑)

---

## 1. 需求分析

### 1.1 明确核心需求

**原始需求**：
- 修改 MAC 地址（隐藏身份）
- 尽量保持 IP 不变（保持 SSH 连接）
- 自动通知新 IP 和 SSH 连接方式

**需求优先级**：
- P0：网络一定可用（即使 IP 改变）
- P1：尽力保持 IP 不变（98% 成功率即可）
- P2：通知功能（多种方式）

### 1.2 技术约束分析

**DHCP 工作原理**：
```
客户端发送 MAC → 服务器查看数据库 → 分配 IP（基于 MAC）
```

**关键认知**：
- MAC 改变 = 新设备 = 可能分配新 IP
- 保持 IP 需要"欺骗" DHCP 服务器或使用静态 IP
- 需要保底方案（接受新 IP）

### 1.3 功能边界确定

**明确不保证**：
- ❌ 不保证 100% 保持 IP（技术上不可行）
- ❌ 不支持所有 DHCP 服务器（取决于配置）

**明确保证**：
- ✅ 网络一定可用（三重策略）
- ✅ 一定能获取到 IP（保底 DHCP）
- ✅ 通知一定能发送（或记录到本地）

---

## 2. 技术方案设计

### 2.1 三重策略模式

**设计思想**：最优方案 → 降级方案 → 保底方案

```bash
# 策略 1: DHCP REQUEST 原 IP (60-80%)
# 依赖：DHCP 服务器保留原 MAC 的租约
dhclient -r eth0
dhclient eth0  # 会优先请求原 IP

# 策略 2: 设置静态 IP (95%)
# 依赖：IP 未被占用
arping -c 1 IP  # 检测冲突
ip addr add IP/24 dev eth0
ip route add default via GW dev eth0

# 策略 3: DHCP 获取新 IP (100%)
# 保底方案，确保一定能联网
dhclient eth0
```

**实施要点**：
- 每个策略独立验证
- 失败后立即切换下一策略
- 最终状态必须验证网络连通性

### 2.2 渐进式降级设计

```bash
# 优先级 1：jq 构建复杂 JSON
if command -v jq &>/dev/null; then
    json_data=$(jq -n '{...}')
# 优先级 2：手动转义（兼容性）
else
    escaped_msg=$(printf '%s' "$msg" | sed -e 's/\\/\\\\/g')
    json_data="{\"message\":\"$escaped_msg\"}"
```

### 2.3 状态跟踪机制

```bash
# 使用标志变量而非 goto（Bash 不支持 goto）
ip_kept=false
final_ip=""

# 策略 1 成功
ip_kept=true
final_ip="$original_ip"

# 根据状态发送不同通知
if [ "$ip_kept" = true ]; then
    status="ip_kept"
else
    status="ip_changed"
fi
```

---

## 3. 实现技巧

### 3.1 JSON 处理

**❌ 错误示例 1：tr 误用**
```bash
# 问题：tr 替换为反斜杠，不是 \n
escaped_msg=$(echo "$msg" | tr '\n' '\\n')
echo "$escaped_msg"  # 输出：text\text（错误）

# 正确方式 1：jq
json_data=$(jq -n --arg msg "$msg" '{message: $msg}')

# 正确方式 2：sed + awk
escaped=$(printf '%s' "$msg" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | tr -d '\n')
```

**❌ 错误示例 2：变量展开时机**
```bash
# 问题：过早展开，检测到旧 IP
monitor_script &
ip link set eth0 down  # IP 丢失
# monitor_script 检测到旧 IP ❌

# 正确：主脚本完成后直接发送
ip link set eth0 down
# ... 获取新 IP
send_notification "$final_ip"  ✅
```

### 3.2 系统兼容性检测

```bash
check_system() {
    # 检测 OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$ID"
    fi

    # 检查必需命令
    for cmd in ip grep awk sed; do
        command -v "$cmd" &>/dev/null || { echo "缺少 $cmd"; exit 1; }
    done

    # 检查可选命令
    [ -n "$(command -v jq)" ] && echo "✓ jq 可用" || echo "⚠ jq 未安装"
}
```

### 3.3 错误处理模式

```bash
# 每个策略独立 try-catch
if try_strategy_1; then
    success
elif try_strategy_2; then
    success
else
    fallback_strategy_3  # 保底，100% 可用
fi

# 详细日志记录
log "策略 1 失败: $reason"
log "尝试策略 2..."
log "策略 2 失败: $reason"
log "使用保底策略"
```

### 3.4 通知发送时机

```bash
# ❌ 错误：监控脚本在修改前启动
monitor_script &
sleep 1
change_mac  # 监控脚本可能检测到旧 IP

# ✅ 正确：主脚本完成后直接发送
change_mac
wait_for_ip
final_ip=$(get_current_ip)
send_notification "$final_ip"  # 直接发送，准确可靠
```

---

## 4. 常见陷阱

### 4.1 Bash 不支持 goto

```bash
# ❌ 错误
goto success  # Bash 不支持

# ✅ 正确
success=true
if [ "$success" = true ]; then
    echo "成功"
fi
```

### 4.2 heredoc 引号选择

```bash
# 单引号：变量不展开（字面值）
cat << 'EOF' >> script.sh
echo "$VAR"  # 输出: $VAR（字面）
EOF

# 无引号：变量展开（执行时）
cat >> script.sh << EOF
echo "$VAR"  # 输出: 实际值
EOF

# 混合使用策略
# 配置部分（需要展开）：无引号
# 代码逻辑（需要保持）：单引号
```

### 4.3 JSON 转义陷阱

```bash
# ❌ 错误：tr 不能替换为字符串
tr '\n' '\\n'  # 替换为单个反斜杠

# ✅ 正确：使用 jq 或 sed+awk
jq -n --arg msg "$text" '{message: $msg}'
# 或
printf '%s' "$text" | awk '{printf "%s\\n", $0}'
```

### 4.4 浮点数比较

```bash
# ❌ 错误
if [ $1 -eq 0 ]; then  # 可能为空字符串

# ✅ 正确
if [ "$1" = "0" ]; then
```

---

## 5. 代码规范

### 5.1 命名规范

```bash
# 函数：动词+名词，小写下划线
get_current_ip()
get_current_mac()
notify_url()
change_mac_with_notification()

# 变量：小写下划线
local current_ip
local final_ip
local json_data

# 常量：大写下划线
REMOTE_NOTIFY_URL=""
LOG_FILE="/tmp/mac_change.log"

# 标志：描述性小写
ip_kept=false
is_connected=true
```

### 5.2 注释规范

```bash
# 函数注释：简要说明功能
# 发送通知到远程 URL
notify_url() {
    local message=$1
    # ...
}

# 复杂逻辑：分步注释
# 1. 生成 JSON 数据
# 2. 发送 POST 请求
# 3. 检查响应码
```

### 5.3 错误输出

```bash
# 使用颜色区分不同级别
echo -e "${GREEN}✓ 成功${NC}"
echo -e "${YELLOW}⚠ 警告${NC}"
echo -e "${RED}✗ 错误${NC}"
```

---

## 6. Git 工作流

### 6.1 Conventional Commits

```bash
# 功能
git commit -m "feat: 添加 IP 保持功能"

# 重构
git commit -m "refactor: 优化 JSON 构建逻辑"

# 修复
git commit -m "fix: 修复 JSON 转义问题"

# 文档
git commit -m "docs: 更新 README 安装说明"
```

### 6.2 文件命名

```
# 脚本：kebab-case
linux-mac-changer.sh
notification-server.py

# 文档：README.md, CONTRIBUTING.md
```

### 6.3 .gitignore

```gitignore
# 临时文件
*.tmp
*.bak
*.log

# IDE
.vscode/
.idea/

# 依赖
__pycache__/
venv/
```

---

## 7. 项目规范

### 7.1 目录结构

```
project-name/
├── main-script.sh          # 主脚本
├── server.py               # 服务器
├── README.md               # 项目文档
├── LICENSE                 # 许可证
└── .gitignore              # Git 忽略
```

### 7.2 README.md 标准

```markdown
# 项目标题
> 简短描述

[徽章]

## 功能特性
- 特性 1
- 特性 2

## 系统要求
- OS 版本
- 依赖

## 安装
```bash
# 安装步骤
```

## 使用
```bash
# 使用示例
```

## 贡献
欢迎提交 PR

## 许可证
MIT License
```

---

## 8. 调试技巧

### 8.1 详细日志

```bash
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /tmp/mac_change.log
}

# 使用
log "开始 MAC 修改"
log "策略 1 失败: $error"
log "最终 IP: $final_ip"
```

### 8.2 HTTP 调试

```bash
# 查看响应头和状态码
curl -s -w "\n%{http_code}" -X POST "$URL" -d "$data"

# 输出示例
200
{"status":"success"}
```

### 8.3 分阶段测试

```bash
# 阶段 1：测试通知
./script.sh notify-test

# 阶段 2：测试基础功能
./script.sh random eth0  # IP 可能改变

# 阶段 3：测试高级功能
./script.sh random-keepip eth0  # 尝试保持 IP
```

---

## 9. 安全考虑

### 9.1 使用场景警告

```bash
# 脚本顶部添加警告
echo "⚠️  警告：修改 MAC 地址可能违反某些网络的使用条款"
echo "⚠️  请在合法授权的环境下使用"
```

### 9.2 敏感信息

```bash
# 不记录敏感信息
# 日志中不包含密码、Token
# JSON 中不包含私钥

# 脱敏日志
log "IP: $ip"  # OK
log "Password: ***"  # OK
```

---

## 10. 性能优化

### 10.1 延迟启动

```bash
# 避免 MAC 修改和监控脚本的竞态条件
sleep 2  # 等待接口稳定
monitor_script &
```

### 10.2 并行扫描

```bash
# 并行 ping 扫描
for i in {1..254}; do
    ping -c 1 -W 1 "$prefix.$i" &
done
wait
```

---

## 11. 关键代码模板

### 11.1 三重策略模板

```bash
execute_with_fallback() {
    local strategy="primary"

    # 策略 1
    if ! try_primary; then
        log "策略 1 失败"
        strategy="secondary"
    fi

    # 策略 2
    if [ "$strategy" = "secondary" ] && ! try_secondary; then
        log "策略 2 失败"
        strategy="fallback"
    fi

    # 策略 3（保底）
    if [ "$strategy" = "fallback" ]; then
        try_fallback
    fi
}
```

### 11.2 JSON 构建模板

```bash
build_json() {
    local hostname=$1
    local message=$2

    if command -v jq &>/dev/null; then
        jq -n \
            --arg hn "$hostname" \
            --arg msg "$message" \
            '{hostname: $hn, message: $msg}'
    else
        local escaped=$(printf '%s' "$message" | \
            sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | \
            awk '{printf "%s\\n", $0}' | tr -d '\n')
        echo "{\"hostname\":\"$hostname\",\"message\":\"$escaped\"}"
    fi
}
```

### 11.3 系统检测模板

```bash
check_requirements() {
    # 检测 OS
    [ -f /etc/os-release ] && . /etc/os-release

    # 检查命令
    local required=("ip" "grep")
    for cmd in "${required[@]}"; do
        command -v "$cmd" &>/dev/null || { echo "❌ 缺少 $cmd"; exit 1; }
    done

    # 检查可选命令
    command -v jq &>/dev/null && echo "✓ jq" || echo "⚠️ jq 未安装"

    # 检查权限
    [ "$EUID" -eq 0 ] || { echo "❌ 需要 root 权限"; exit 1; }
}
```

---

## 12. 工具推荐

| 工具 | 用途 | 安装 |
|------|------|------|
| jq | JSON 处理 | `apt install jq` |
| shellcheck | Bash 语法检查 | `apt install shellcheck` |
| arping | IP 冲突检测 | `apt install arping` |
| nmap | 网络扫描 | `apt install nmap` |
| gh | GitHub CLI | `apt install gh` |

---

## 13. 适用场景

本经验适用于以下类型工具的开发：

- ✅ 硬件标识修改工具
- ✅ 网络配置变更工具
- ✅ 远程通知系统
- ✅ 需要多级容错的工具
- ✅ 跨平台脚本工具

---

## 14. 项目检查清单

### 开发阶段

- [ ] 需求明确（功能边界）
- [ ] 技术方案设计（保底机制）
- [ ] 错误处理完善
- [ ] 日志记录详细
- [ ] 文档完整

### 测试阶段

- [ ] 功能测试（核心功能）
- [ ] 容错测试（降级方案）
- [ ] 边界测试（无依赖场景）
- [ ] 集成测试（完整流程）

### 发布阶段

- [ ] 代码规范化
- [ ] README 完整
- [ ] LICENSE 添加
- [ ] .gitignore 配置
- [ ] Git 推送
- [ ] 版本标签

---

## 15. 快速参考

### 15.1 MAC 修改

```bash
ip link set eth0 down
ip link set eth0 address XX:XX:XX:XX:XX
ip link set eth0 up
```

### 15.2 IP 获取

```bash
# DHCP
dhclient eth0
dhcpcd eth0

# 静态
ip addr add IP/24 dev eth0
ip route add default via GW dev eth0
```

### 15.3 网络检测

```bash
# 查看 IP
ip addr show eth0 | grep inet

# 测试连通
ping -c 1 192.168.70.1

# 检测 IP 冲突
arping -c 1 192.168.70.115
```

---

## 16. 参考资源

- Bash 编程：[GNU Bash Manual](https://www.gnu.org/software/bash/manual/)
- DHCP 协议：[RFC 2131](https://tools.ietf.org/html/rfc2131)
- Flask API：[Flask Documentation](https://flask.palletsprojects.com/)
- Git 工作流：[Pro Git Book](https://git-scm.com/book/en/v2)

---

**版本**: v1.0
**最后更新**: 2026-03-26
**维护者**: DXShelley
**许可证**: MIT
