# Git 分支管理规范

## 📋 分支策略

本项目采用 **Git Flow** 工作流的简化版本：

### 分支说明

| 分支 | 用途 | 文件内容 |
|------|------|---------|
| **main** | 生产版本 | 仅包含3个核心文件 |
| **develop** | 开发版本 | 包含所有文件和文档 |

---

## 🗂️ 分支文件管理

### main 分支（生产版本）

**仅保留3个核心文件**：
- `linux-mac-changer.sh` - 主脚本
- `notification-server.py` - 通知服务器
- `README.md` - 项目文档

**特点**：
- ✅ 精简、稳定
- ✅ 随时可用于生产
- ✅ 最小化依赖

### develop 分支（开发版本）

**包含所有文件**：
- 核心文件（与main相同）
- 文档文件
  - `PERMANENT_MAC.md` - 永久保存指南
  - `PERMANENT_MAC_FIXES.md` - 修复报告
  - `FUNCTIONALITY_CHECK.md` - 功能检查报告
  - `SYSTEM_COMPATIBILITY_FIXES.md` - 兼容性修复报告
  - `linux-mac-tools-development.md` - 开发经验文档
- 配置文件
  - `.gitignore`
  - `LICENSE`

**特点**：
- 🔧 完整的开发环境
- 📚 详细的文档记录
- 🛠️ 持续更新的功能

---

## 🔄 工作流程

### 日常开发流程

```bash
# 1. 切换到develop分支
git checkout develop

# 2. 进行开发和修改
# ... 编辑文件 ...

# 3. 提交更改
git add .
git commit -m "feat: 添加新功能"

# 4. 推送到develop
git push origin develop
```

### 发布到生产版本

```bash
# 1. 确保develop分支稳定
# 测试通过后...

# 2. 切换到main分支
git checkout main

# 3. 合并develop的更改
git merge develop

# 4. 推送到main
git push origin main
```

### 只同步核心文件到main

如果develop分支有文档更新，但核心代码未改变：

```bash
# 1. 切换到main
git checkout main

# 2. 只合并核心文件（如果需要）
git checkout develop -- linux-mac-changer.sh notification-server.py README.md
git commit -m "chore: 同步核心文件到最新版本"
git push origin main
```

---

## 📊 分支状态

### 当前分支结构

```
main (生产)
├── linux-mac-changer.sh
├── notification-server.py
└── README.md

develop (开发)
├── linux-mac-changer.sh
├── notification-server.py
├── README.md
├── .gitignore
├── LICENSE
├── PERMANENT_MAC.md
├── PERMANENT_MAC_FIXES.md
├── FUNCTIONALITY_CHECK.md
├── SYSTEM_COMPATIBILITY_FIXES.md
└── linux-mac-tools-development.md
```

### 默认分支

**默认分支**: `develop`

- 新克隆仓库时默认使用develop分支
- Pull Request默认合并到develop分支
- main分支仅用于稳定的生产版本

---

## 🎯 使用指南

### 普通用户

**使用main分支获取稳定版本**：
```bash
git clone https://github.com/DXShelley/linux-mac-changer.git
cd linux-mac-changer
# 默认在develop分支，切换到main
git checkout main
```

### 开发者

**使用develop分支进行开发**：
```bash
git clone https://github.com/DXShelley/linux-mac-changer.git
cd linux-mac-changer
# 默认已在develop分支
# 直接开始开发
```

### 获取完整文档

**从develop分支获取文档**：
```bash
# 切换到develop分支
git checkout develop

# 文档位于：
- PERMANENT_MAC.md - 永久保存指南
- PERMANENT_MAC_FIXES.md - 修复报告
- FUNCTIONALITY_CHECK.md - 功能检查
- SYSTEM_COMPATIBILITY_FIXES.md - 兼容性报告
- linux-mac-tools-development.md - 开发经验
```

---

## 🔧 分支管理命令

### 查看所有分支
```bash
git branch -a
```

### 切换分支
```bash
git checkout <branch-name>
```

### 同步分支
```bash
# 从develop同步到main
git checkout main
git merge develop
git push origin main
```

### 查看分支差异
```bash
# 查看文件差异
git diff main..develop

# 查看提交历史
git log --oneline --graph --all
```

---

## 📝 提交规范

### Commit Message 格式

遵循 [Conventional Commits](https://www.conventionalcommits.org/) 规范：

```
<type>: <description>

[optional body]
```

**类型（type）**：
- `feat`: 新功能
- `fix`: 修复bug
- `docs`: 文档更新
- `chore`: 构建/工具链更新
- `refactor`: 代码重构
- `test`: 测试相关
- `style`: 代码格式调整

**示例**：
```bash
git commit -m "feat: 添加IP保持功能"
git commit -m "fix: 修复JSON转义问题"
git commit -m "docs: 更新README文档"
```

---

## ⚠️ 注意事项

### 1. 核心文件修改

核心文件（3个）的修改需要：
1. 在develop分支开发和测试
2. 测试通过后合并到main分支
3. 不要直接在main分支修改代码

### 2. 文档文件修改

文档文件的修改只在develop分支进行：
- 不影响main分支
- 用户可以从develop分支获取完整文档

### 3. 版本发布

发布新版本时：
1. 确保develop分支稳定
2. 合并develop到main
3. 创建版本标签
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

---

## 🎉 总结

**main分支**: 稳定、精简的生产版本
**develop分支**: 完整、活跃的开发版本

**默认使用**: `develop` 分支

**工作原则**:
- 开发在develop
- 稳定后合并到main
- main保持最小化

---

**文档版本**: v1.0
**更新时间**: 2026-03-27
**维护者**: DXShelley
