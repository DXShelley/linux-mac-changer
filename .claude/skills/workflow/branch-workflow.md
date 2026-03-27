# Git分支工作流程

## 描述

简化的Git Flow工作流程，main分支保留生产代码，develop分支用于开发。

## 分支策略

| 分支 | 用途 | 文件内容 |
|------|------|---------|
| main | 生产版本 | 仅3个核心文件 |
| develop | 开发版本 | 所有文件和文档 |

## main分支（生产版本）

**核心文件**:
- `linux-mac-changer.sh` - 主脚本
- `notification-server.py` - 通知服务器
- `README.md` - 项目文档

**特点**: 精简、稳定、随时可用

## develop分支（开发版本）

**包含文件**:
- 核心文件（与main相同）
- 所有文档和配置文件

**特点**: 完整开发环境、详细文档

## 日常开发流程

```bash
# 1. 切换到develop
git checkout develop

# 2. 开发和修改
# ... 编辑文件 ...

# 3. 提交更改
git add .
git commit -m "feat: 添加新功能"

# 4. 推送develop
git push origin develop
```

## 发布到生产

```bash
# 1. 确保develop稳定
# 测试通过后...

# 2. 切换到main
git checkout main

# 3. 合并develop
git merge develop

# 4. 推送main
git push origin main
```

## 同步核心文件

如果develop只有文档更新，核心代码未改变：

```bash
git checkout main
git checkout develop -- linux-mac-changer.sh notification-server.py README.md
git commit -m "chore: 同步核心文件"
git push origin main
```

## 提交规范

使用conventional commits:

```
feat: 新功能
fix: 修复bug
docs: 文档更新
refactor: 重构代码
chore: 构建/工具变动
test: 测试相关
```

## 分支保护

- main分支需要PR审查
- 禁止直接推送
- 禁止强制推送

## 合并策略

```
develop → 测试验证 → main (生产)
```

## 相关文档

- `github-setup-guide` - GitHub仓库设置指南
