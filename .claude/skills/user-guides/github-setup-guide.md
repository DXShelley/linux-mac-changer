# GitHub仓库设置指南

## 描述

设置GitHub仓库的默认分支、分支保护和权限配置，确保代码质量和团队协作规范。

## 使用场景

初始化新的GitHub项目或配置现有仓库的分支保护规则。

## 默认分支设置

### 设置main为默认分支

```bash
gh repo edit REPO --default-branch main
```

### 验证默认分支

```bash
gh repo view REPO --json defaultBranchRef
```

## 分支保护配置

### main分支保护规则

**必须通过网页设置** (Settings → Branches → Branch protection rules)

**配置项**:
- ✅ Protect this branch (保护此分支)
- ✅ Require a pull request before merging (合并前需要PR)
  - Approvals required: 1
- ✅ Require status checks to pass before merging
  - Require branches to be up to date before merging: 是
- ✅ Require conversation resolution before merging
- ❌ Do not allow force pushes (禁止强制推送)
- ❌ Allow deletions (禁止删除)

### develop分支保护规则

**建议配置**:
- ✅ 需要PR审查
- ✅ 禁止强制推送
- ✅ 需要1个审查批准

## 分支权限矩阵

| 分支 | 默认分支 | 保护 | 强制推送 | 删除 | 合并方式 |
|------|---------|------|---------|------|---------|
| main | ✅ | ✅ | ❌ | ❌ | PR only |
| develop | ❌ | ✅ | ❌ | ❌ | PR recommended |

## 分支管理规范

### 分支用途

- **main**: 生产版本，稳定代码
- **develop**: 开发版本，集成最新功能

### 工作流程

```
develop (开发) → 测试验证 → main (生产)
```

### 权限说明

**main分支**:
- 需要PR审查
- 需要1个批准
- 管理员可绕过

**develop分支**:
- 开发者可直接推送
- 建议通过PR合并
- 保持代码审查

## 验证命令

### 检查默认分支

```bash
gh repo view REPO --json defaultBranchRef
```

### 检查分支保护

```bash
# main分支
gh api repos/OWNER/REPO/branches/main/protection

# develop分支
gh api repos/OWNER/REPO/branches/develop/protection
```

## 替代方案

如无法设置分支保护，通过团队规范管理:

```
✅ main分支只通过PR合并
✅ PR需要审查批准
✅ 禁止强制推送
✅ 删除前需要确认
```

## 相关文档

- `branch-workflow` - Git分支工作流程
- `permanent-mac-guide` - 永久MAC保存指南

## 外部参考

- [GitHub Branch Protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)
- [GitHub Branches API](https://docs.github.com/rest/branches/branch-protection/)
