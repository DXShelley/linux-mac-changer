# 永久保存 MAC 地址指南

## 📋 问题说明

使用 `ip link set address` 命令修改 MAC 地址是**临时修改**，重启后会从硬件或配置文件恢复原始 MAC 地址。

## 🔧 为什么会恢复？

Linux 系统在启动时按以下顺序设置 MAC 地址：

1. **硬件默认值** - 网卡的出厂 MAC 地址
2. **配置文件** - 网络配置中的指定值
3. **驱动初始化** - 网卡驱动加载时的设置

临时修改只影响运行时，不会写入配置文件。

## ✅ 永久保存方法

脚本会自动检测并支持以下网络管理方式：

### 1. NetworkManager (最常见)

**检测条件**: `systemctl is-active NetworkManager`

**配置方式**: 使用 `nmcli` 命令

```bash
nmcli connection modify "连接名称" ethernet.cloned-mac-address xx:xx:xx:xx:xx:xx
nmcli connection up "连接名称"
```

**配置文件位置**:
- `/etc/NetworkManager/system-connections/<连接名称>.nmconnection`

**特点**:
- ✅ 立即生效，无需重启
- ✅ 支持多个配置文件
- ✅ NetworkManager 会自动管理

### 2. systemd-networkd

**检测条件**: `systemctl is-active systemd-networkd`

**配置方式**: 创建 `.link` 文件

```bash
cat > /etc/systemd/network/10-persistent-net.link << 'EOF'
[Match]
OriginalName=eth0

[Link]
MACAddress=xx:xx:xx:xx:xx:xx
EOF
```

**需要重启**: `reboot`

**特点**:
- ⚠️ 需要重启才能生效
- ✅ 适用于 systemd 系统
- ✅ 启动时早期应用

### 3. ifupdown (传统 Debian/Ubuntu)

**检测条件**: 文件 `/etc/network/interfaces` 存在

**配置方式**: 编辑 `/etc/network/interfaces`

```bash
# 在接口配置中添加
auto eth0
iface eth0 inet dhcp
    hwaddress ether xx:xx:xx:xx:xx:xx
```

**应用方式**:
```bash
systemctl restart networking
# 或
ifdown eth0 && ifup eth0
```

**特点**:
- ⚠️ 需要重启网络服务
- ✅ 传统方式，兼容性好
- ✅ 简单直接

### 4. Netplan (Ubuntu 18.04+)

**检测条件**: 目录 `/etc/netplan` 存在

**配置方式**: 编辑 `/etc/netplan/*.yaml`

```yaml
network:
  version: 2
  ethernets:
    eth0:
      macaddress: xx:xx:xx:xx:xx:xx
      dhcp4: true
```

**应用方式**:
```bash
netplan apply
```

**特点**:
- ✅ 立即生效
- ✅ YAML 格式，易于阅读
- ⚠️ 需要 root 权限

## 🎯 脚本自动化流程

脚本执行流程：

```
1. 检测网络管理方式
   ↓
2. 根据 NetworkManager/systemd/ifupdown/Netplan 选择方法
   ↓
3. 备份原配置文件
   ↓
4. 修改配置文件
   ↓
5. 应用新配置（如需要）
   ↓
6. 显示成功消息和注意事项
```

## 📊 方法对比

| 方法 | 立即生效 | 需要重启 | 难度 | 兼容性 |
|------|---------|---------|------|--------|
| NetworkManager | ✅ | ❌ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| systemd-networkd | ❌ | ✅ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| ifupdown | 部分 | 部分 | ⭐ | ⭐⭐⭐⭐⭐ |
| Netplan | ✅ | ❌ | ⭐⭐⭐ | ⭐⭐⭐ |

## ⚠️ 注意事项

### 1. 配置文件备份

脚本会自动备份配置文件：
```bash
/etc/network/interfaces.backup.20260326214356
/etc/netplan/01-netcfg.yaml.backup.20260326214356
```

### 2. 恢复原始 MAC

如需恢复原始 MAC，有以下方式：

**方式 1**: 编辑配置文件，删除或修改 `MACAddress`/`hwaddress` 行

**方式 2**: 使用脚本重新设置
```bash
sudo ./linux-mac-changer.sh custom eth0 <原始MAC>
```

**方式 3**: 删除配置文件中的 MAC 设置项，让系统使用硬件默认值

### 3. 验证永久设置

重启后验证 MAC 是否保持：
```bash
ip link show eth0 | grep link/ether
```

### 4. 多网卡环境

如果有多个网卡，需要为每个网卡单独配置：
```bash
# NetworkManager
nmcli connection modify "Wired connection 1" ethernet.cloned-mac-address xx:xx:xx:xx:xx:01
nmcli connection modify "Wired connection 2" ethernet.cloned-mac-address xx:xx:xx:xx:xx:02
```

## 🔍 故障排查

### 问题 1: NetworkManager 找不到连接名称

**检查**:
```bash
nmcli connection show
```

**解决**: 记录准确的连接名称（注意大小写和空格）

### 问题 2: systemd-networkd 配置不生效

**检查**:
```bash
systemctl status systemd-networkd
ls -l /etc/systemd/network/*.link
```

**解决**: 确保文件名按字母顺序在默认规则之前（如 `10-` 前缀）

### 问题 3: ifupdown 修改后网络断开

**检查**:
```bash
cat /etc/network/interfaces
```

**解决**: 确保语法正确，缩进使用空格而非 Tab

### 问题 4: Netplan 应用失败

**检查**:
```bash
netplan try
netplan --debug apply
```

**解决**:
- 检查 YAML 语法（缩进必须使用空格）
- 确保接口名称正确

## 📚 参考资料

- [NetworkManager 配置](https://networkmanager.dev/docs/api/latest/nm-settings-nmcli.html)
- [systemd.link 文档](https://manpages.debian.org/testing/systemd.link/systemd.link.html)
- [Debian 网络配置](https://wiki.debian.org/NetworkConfiguration)
- [Netplan 参考](https://netplan.readthedocs.io/)

---

**文档版本**: v1.0
**更新时间**: 2026-03-26
**作者**: DXShelley
