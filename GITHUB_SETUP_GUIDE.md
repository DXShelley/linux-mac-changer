# GitHub 仓库设置指南

## ✅ 已完成的设置

### 1. 默认分支设置

**状态**: ✅ 已完成

```bash
# 已执行命令
gh repo edit DXShelley/linux-mac-changer --default-branch main
```

**验证**:
```bash
gh repo view DXShelley/linux-mac-changer --json defaultBranchRef
# 输出: main ✓
```

**当前默认分支**: `main`

---

## 🔒 分支保护设置

由于环境限制无法通过 API 设置，请按照以下步骤在 GitHub 网页上设置：

### 方法 1: 通过 GitHub 网页设置（推荐）

#### 设置 main 分支保护

1. 访问仓库页面
   ```
   https://github.com/DXShelley/linux-mac-changer
   ```

2. 点击 **Settings** (设置)

3. 点击左侧菜单的 **Branches** (分支)

4. 找到 **main** 分支，点击分支名称

5. 点击 **Branch protection rule** (分支保护规则)
   - 或者点击 **Edit** 图标

6. 配置以下选项：

   **Branch protection rules** (分支保护规则)

   ✅ **Protect this branch** (保护此分支)

   **Branch name pattern** (分支名称模式)
   ```
   main
   ```

   **Rule settings** (规则设置)

   - ✅ **Require a pull request before merging** (合并前需要 PR)
     - Approvals required (需要的审批数): **1**

   - ✅ **Require status checks to pass before merging** (合并前需要状态检查通过)
     - Require branches to be up to date before merging (合并前分支必须是最新的): ✅

   - ✅ **Require conversation resolution before merging** (合并前需要解决对话)

   - ❌ **Do not allow bypassing the above settings** (不允许绕过上述设置)

   - ✅ **Allow force pushes** (允许强制推送): ❌ **Do not allow force pushes** (不允许强制推送)

7. 点击 **Create** (创建) 或 **Changes** (保存)

---

### 方法 2: 使用 GitHub CLI (如果环境支持)

由于当前环境 SSL 证书问题，如果您的环境支持，可以使用以下命令：

```bash
# 使用 gh cli 设置分支保护
gh api \
  -X PUT \
  repos/DXShelley/linux-mac-changer/branches/main/protection \
  -f branch-protection.json
```

其中 `branch-protection.json` 内容：

```json
{
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1
  },
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_status_checks": {
    "strict": false
  }
}
```

---

## 📋 分支权限配置总结

### main 分支（生产版本）

| 设置项 | 状态 | 说明 |
|--------|------|------|
| **默认分支** | ✅ main | 已设置 |
| **分支保护** | ⚠️ 需手动设置 | 需要 PR 审查才能合并 |
| **强制推送** | ❌ 禁止 | 保护生产代码 |
| **删除保护** | ❌ 禁止 | 防止误删除 |
| **管理员绕过** | ✅ 允许 | 管理员可绕过检查 |

### develop 分支（开发版本）

| 设置项 | 状态 | 建议 |
|--------|------|------|
| **分支保护** | ⚠️ 可选 | 建议：需要 PR 审查 |
| **强制推送** | ⚠️ 可选 | 建议：禁止强制推送 |
| **合并要求** | ⚠️ 可选 | 建议：需要 1 个审查 |

---

## 🎯 分支管理规范

### 分支用途

| 分支 | 用途 | 合并策略 |
|------|------|---------|
| **main** | 生产版本 | 仅从 develop 合并稳定版本 |
| **develop** | 开发版本 | 合并新功能和修复 |

### 工作流程

```
develop (开发)
    ↓ 测试稳定
main (生产)
```

### 权限说明

**main 分支**:
- 需要创建 Pull Request
- 需要 1 个审查批准
- 管理员可绕过检查（谨慎使用）

**develop 分支**:
- 开发者可直接推送
- 建议通过 PR 合并
- 保持代码审查

---

## 📝 验证设置

### 检查默认分支

```bash
gh repo view DXShelley/linux-mac-changer --json defaultBranchRef
# 应输出: main
```

### 检查分支保护

```bash
# 检查 main 分支
gh api repos/DXShelley/linux-mac-changer/branches/main/protection

# 检查 develop 分支
gh api repos/DXelley/linux-mac-changer/branches/develop/protection
```

---

## 🔧 如果无法设置分支保护

### 替代方案

如果无法设置分支保护，可以通过以下方式保护 main 分支：

#### 1. 使用 GitHub Settings

在仓库设置中限制：
- Who can push (谁可以推送)
- Branches (分支权限)
- Include file patterns (包含文件模式)

#### 2. 团队协作规范

建立团队规范：
```
✅ main 分支只通过 PR 合并
✅ PR 需要审查批准
✅ 禁止强制推送
✅ 删除前需要确认
```

---

## ✅ 当前状态

| 设置 | 状态 |
|------|------|
| **默认分支** | ✅ main (已设置) |
| **main 分支保护** | ⚠️ 需手动设置 |
| **develop 分支保护** | ⚠️ 可选设置 |
| **远程仓库** | ✅ 已更新 |

---

## 📚 相关文档

- [GitHub Branch Protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)
- [GitHub Branches API](https://docs.github.com/rest/branches/branch-protection/)
- [Git Branch Workflow](BRANCH_WORKFLOW.md)

---

**创建时间**: 2026-03-27
**仓库**: DXShelley/linux-mac-changer
**状态**: 默认分支已设置为 main ✅
