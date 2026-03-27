# 永久保存MAC地址指南

## 描述

Linux系统使用`ip link set address`命令修改MAC地址是临时修改，重启后会恢复。此指南提供4种永久保存MAC地址的方法，脚本会自动检测并应用最适合的方法。

## 使用场景

当用户需要将修改的MAC地址永久保存，重启后仍然有效时使用。

## 支持的网络管理方式

### 1. NetworkManager (最常见，推荐)

**检测条件**: `systemctl is-active NetworkManager`

**命令示例**:
```bash
nmcli connection modify "连接名称" ethernet.cloned-mac-address xx:xx:xx:xx:xx:xx
nmcli connection up "连接名称"
```

**特点**: 立即生效，无需重启，兼容性最好

### 2. systemd-networkd

**检测条件**: `systemctl is-active systemd-networkd`

**配置文件**: `/etc/systemd/network/10-persistent-net.link`

```bash
[Match]
OriginalName=eth0

[Link]
MACAddress=xx:xx:xx:xx:xx:xx
```

**特点**: 需要重启，适用于systemd系统

### 3. ifupdown (传统方式)

**检测条件**: `/etc/network/interfaces` 存在

**配置示例**:
```bash
auto eth0
iface eth0 inet dhcp
    hwaddress ether xx:xx:xx:xx:xx:xx
```

**应用**: `systemctl restart networking`

**特点**: 兼容性好，简单直接

### 4. Netplan (Ubuntu 18.04+)

**检测条件**: `/etc/netplan` 目录存在

**配置文件**: `/etc/netplan/*.yaml`

```yaml
network:
  version: 2
  ethernets:
    eth0:
      macaddress: xx:xx:xx:xx:xx:xx
      dhcp4: true
```

**应用**: `netplan apply`

**特点**: 立即生效，YAML格式

## 方法对比

| 方法 | 立即生效 | 需要重启 | 难度 | 兼容性 |
|------|---------|---------|------|--------|
| NetworkManager | ✅ | ❌ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| systemd-networkd | ❌ | ✅ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| ifupdown | 部分 | 部分 | ⭐ | ⭐⭐⭐⭐⭐ |
| Netplan | ✅ | ❌ | ⭐⭐⭐ | ⭐⭐⭐ |

## 故障排查

### NetworkManager找不到连接
```bash
nmcli connection show
```

### systemd-networkd配置不生效
```bash
ls -l /etc/systemd/network/*.link
```

### Netplan应用失败
```bash
netplan try
netplan --debug apply
```

## 脚本自动化流程

1. 检测网络管理方式
2. 选择对应的配置方法
3. 备份原配置文件
4. 修改配置文件
5. 应用新配置
6. 验证并显示结果

## 注意事项

- 脚本会自动备份配置文件
- 多网卡需要单独配置
- 重启后验证: `ip link show eth0 | grep link/ether`

## 相关文档

- `network-mac-keep-guide` - IP保持模式详解
- `github-setup-guide` - GitHub仓库设置指南
