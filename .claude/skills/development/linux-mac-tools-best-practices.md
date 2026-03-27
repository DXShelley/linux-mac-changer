# Linux MAC工具开发最佳实践

## 描述

基于Linux MAC Changer项目的开发经验总结，包括需求分析、技术方案、实现技巧和代码规范。

## 核心原则

### 1. 功能优先级

**P0** - 必须保证:
- 网络一定可用（即使IP改变）
- 一定能获取到IP

**P1** - 尽力做到:
- 保持IP不变（98%成功率）

**P2** - 可选功能:
- 通知功能（多种方式）

### 2. 三重策略模式

**最优方案 → 降级方案 → 保底方案**

```bash
# 策略1: DHCP REQUEST原IP (60-80%)
dhclient -r eth0 && dhclient eth0

# 策略2: 设置静态IP (95%)
arping -c 1 IP && ip addr add IP/24 dev eth0

# 策略3: DHCP获取新IP (100%)
dhclient eth0  # 保底方案
```

**实施要点**:
- 每个策略独立验证
- 失败后立即切换
- 最终验证网络连通性

### 3. 渐进式降级设计

```bash
# 优先级1: 使用jq（复杂JSON）
if command -v jq &>/dev/null; then
    json_data=$(jq -n '{...}')
# 优先级2: 手动转义（兼容性）
else
    json_data="{\"message\":\"...\"}"
fi
```

## 技术方案

### DHCP工作原理

```
客户端发送MAC → 服务器查看数据库 → 分配IP
```

**关键认知**:
- MAC改变 = 新设备 = 可能分配新IP
- 保持IP需要"欺骗"DHCP服务器
- 需要保底方案

### 状态跟踪机制

```bash
ip_kept=false  # 状态变量
final_ip=""    # 最终IP

# 每个策略更新状态
if [ "$ip_kept" = false ]; then
    # 尝试下一策略
fi
```

### 错误处理模式

```bash
# 所有可能失败的操作都要处理
command || true  # 不阻断
$(command 2>/dev/null)  # 忽略错误
if command; then ... fi  # 条件执行
```

## 代码规范

### 函数设计

```bash
function_name() {
    local param1=$1
    local param2=${2:-default}  # 默认值

    # 函数体

    return 0  # 成功返回0
}
```

### 变量命名

- 全局变量：UPPER_CASE
- 局部变量：lower_case
- 常量：UPPER_CASE

### 错误处理

```bash
# 检查命令可用性
if ! command -v cmd &>/dev/null; then
    echo "错误: 缺少cmd"
    return 1
fi

# 使用子shell隔离错误
( risky_command ) || true
```

### 日志记录

```bash
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /tmp/logfile
}
```

## 调试技巧

### 1. 语法检查

```bash
bash -n script.sh  # 语法检查
bash -x script.sh  # 调试模式
```

### 2. 日志文件

```bash
/tmp/mac_change.log   # 主日志
/tmp/new_ip.txt       # IP记录
```

### 3. 恢复脚本

```bash
/tmp/restore_mac.sh   # 紧急恢复
```

## 安全考虑

### 1. 权限检查

```bash
if [ "$EUID" -ne 0 ]; then
    echo "需要root权限"
    exit 1
fi
```

### 2. 输入验证

```bash
# 验证接口存在
if ! ip link show "$interface" &>/dev/null; then
    echo "接口不存在"
    exit 1
fi
```

### 3. 配置备份

```bash
# 修改前备份
cp "$config_file" "${config_file}.backup.$(date +%s)"
```

## Git工作流

### 分支策略

- main: 生产版本
- develop: 开发版本

### 提交规范

```
feat: 新功能
fix: 修复bug
docs: 文档更新
refactor: 重构
chore: 构建/工具
```

## 项目规范

### 文件组织

```
project/
├── linux-mac-changer.sh    # 主脚本
├── notification-server.py   # 通知服务器
├── README.md                # 文档
└── LICENSE                  # 许可证
```

### 测试检查

- [x] 语法检查通过
- [x] 核心功能可用
- [x] 错误处理完善
- [x] 文档完整

## 相关文档

- `core-function-audit` - 核心功能审计
- `branch-workflow` - 分支工作流程
