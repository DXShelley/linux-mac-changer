# Linux MAC Changer - Skills索引

## 描述

此目录包含Linux MAC Changer项目的相关技能文档，按照类别组织。

## 文档分类

### 用户指南 (user-guides/)

面向最终用户的操作指南和配置说明。

1. **permanent-mac-guide** - 永久保存MAC地址指南
   - 4种网络管理方式的配置方法
   - NetworkManager、systemd-networkd、ifupdown、Netplan
   - 故障排查和验证方法

2. **github-setup-guide** - GitHub仓库设置指南
   - 默认分支配置
   - 分支保护规则设置
   - 权限配置和工作流程

### 工作流程 (workflow/)

开发团队的工作流程和协作规范。

1. **branch-workflow** - Git分支工作流程
   - main和develop分支的用途
   - 日常开发流程
   - 发布流程和提交规范

### 审计 (audit/)

代码审计和功能验证文档。

1. **core-function-audit** - 核心功能审计报告
   - MAC修改和IP获取保证
   - 失败场景处理
   - 代码质量指标

2. **notification-warning-demo** - 通知警告演示
   - 通知功能不可用时的警告界面
   - 用户选择处理
   - 自动降级机制

### 开发 (development/)

开发最佳实践和技术方案。

1. **linux-mac-tools-best-practices** - 开发最佳实践
   - 需求分析和技术方案
   - 三重策略模式
   - 代码规范和调试技巧

## 使用方法

### 查找文档

根据需求类别查找相应文档：

- 用户操作 → user-guides/
- 工作流程 → workflow/
- 代码审计 → audit/
- 开发参考 → development/

### 文档格式

每个skill文档包含：
- **描述**: 文档用途和适用场景
- **核心内容**: 详细的技术说明
- **代码示例**: 实用的命令和脚本
- **相关文档**: 交叉引用

## 维护说明

- 定期更新文档以反映最新变化
- 保持文档简洁明了
- 提供实用的代码示例
- 建立文档间的交叉引用

## 相关链接

- 项目主文档: ../../README.md
- 核心脚本: ../../linux-mac-changer.sh
- 通知服务器: ../../notification-server.py
