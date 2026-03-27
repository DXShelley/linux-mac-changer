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
# - 自动删除本地临时文件（zip 压缩包等）
# - 创建并推送版本标签
```

### Release 发版后清理

release.ps1 脚本执行完成后会自动清理以下临时文件：

- **zip 压缩包**：如 `linux-mac-changer-v1.0.0.zip`

清理完成后脚本会自动切换回 develop 分支。

### 版本号规则

- 使用语义化版本（SemVer）：vMAJOR.MINOR.PATCH
- 默认递增 MAJOR 版本号
- 手动指定版本：运行脚本时输入具体版本号

### main 分支文件规范

main 分支只包含发布所需文件，共 5 个：

```
LICENSE
README.md
README_zh.md
linux-mac-changer.sh
notification-server.py
```

**禁止添加其他文件**，如需更新请在 develop 分支操作后手动合并。

合并到 main 时操作步骤：
```bash
# 1. 切换到 main
git checkout main

# 2. 只合并需要的文件
git checkout develop -- LICENSE README.md README_zh.md linux-mac-changer.sh notification-server.py

# 3. 提交并推送
git add .
git commit -m "release: 更新文件"
git push
```

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
