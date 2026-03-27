# 项目注意事项

## 开发流程

### 分支管理规则

1. **每次修改前默认切换到 develop 分支**
2. **提交并推送到 develop 远程分支**
3. **由用户确认是否合并到 main 分支**

### 操作步骤

```bash
# 1. 切换到 develop 分支
git checkout develop

# 2. 进行代码修改...

# 3. 提交修改
git add <修改的文件>
git commit -m "描述"

# 4. 推送到 develop
git push origin develop

# 5. 用户确认后，切换到 main 并合并所需文件
git checkout main
git checkout develop -- <文件路径>
git commit -m "merge: ..."
git push
```

### 版本发布流程

```bash
# 1. 确保在 main 分支且已合并最新代码
git checkout main
git pull origin main

# 2. 运行打包脚本（自动递增主版本号）
# Windows
powershell -File release.ps1

# Linux/macOS
bash release.sh

# 脚本自动完成：
# - 读取当前版本号
# - 主版本号 +1 (v1.0.0 -> v2.0.0)
# - 创建 zip 压缩包（不含 CLAUDE.md）
# - 上传到 GitHub Release
# - 自动删除本地 zip 文件
```

### 版本号规则

- 使用语义化版本（SemVer）：vMAJOR.MINOR.PATCH
- 默认递增 MAJOR 版本号
- 手动指定版本：运行脚本时输入具体版本号

## 跨平台开发注意事项

### 换行符问题

Windows 使用 CRLF (`\r\n`)，Linux/macOS 使用 LF (`\n`)。Windows 编辑的 Shell 脚本在 Linux 上无法执行。

**修复方法：**
```bash
# 方法1: 使用 sed
sed -i 's/\r$//' script.sh

# 方法2: 使用 dos2unix
dos2unix script.sh

# 方法3: 使用 tr
tr -d '\r' < script.sh > script_new.sh
```

**预防措施：**
- 在 Windows 上使用 VS Code 时，将文件设置为 LF 换行符
- 或在 .gitattributes 文件中添加：
  ```
  *.sh text eol=lf
  ```
- 使用 Git 的 `core.autocrlf` 配置自动转换

### Git 换行符配置建议

```bash
# Windows (全局)
git config --global core.autocrlf true

# Linux/macOS (全局)
git config --global core.autocrlf input

# 或在项目中创建 .gitattributes
* text=auto
*.sh text eol=lf
```
