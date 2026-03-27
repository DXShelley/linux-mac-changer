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

# 2. 创建 release.ps1 脚本（临时文件）
# 将以下内容保存为 release.ps1：
---

# 脚本内容见下方 "release.ps1 模板"

# 3. 运行打包脚本
powershell -File release.ps1

# 脚本自动完成：
# - 读取当前版本号
# - 主版本号 +1 (v1.0.0 -> v2.0.0)
# - 创建 zip 压缩包（含 README.md、README_ZH.md）
# - 上传到 GitHub Release
# - 自动删除本地临时文件（包括 release.ps1 本身）
# - 创建并推送版本标签
# - 自动切换回 develop 分支
```

### release.ps1 模板

```powershell
# GitHub Release 自动打包脚本

param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

# 切换到 main 分支
Write-Host "切换到 main 分支..." -ForegroundColor Cyan
git checkout main
git pull origin main

# 获取当前版本号
$tags = git tag --list "v*" --sort=-v:refname 2>$null
if ($tags) {
    $currentVersion = $tags[0]
    Write-Host "当前版本: $currentVersion" -ForegroundColor Yellow
    if ($Version -eq "") {
        $versionParts = $currentVersion -replace "v", "" -split "\."
        $major = [int]$versionParts[0] + 1
        $newVersion = "v$major.0.0"
    } else {
        $newVersion = $Version
    }
} else {
    $newVersion = if ($Version -ne "") { $Version } else { "v1.0.0" }
    Write-Host "未找到现有版本，从 $newVersion 开始" -ForegroundColor Yellow
}

Write-Host "新版本: $newVersion" -ForegroundColor Green

$zipName = "linux-mac-changer-$newVersion.zip"

# 创建 zip 压缩包
Write-Host "创建压缩包: $zipName" -ForegroundColor Cyan
if (Test-Path $zipName) { Remove-Item $zipName -Force }
Compress-Archive -Path "README.md", "README_ZH.md", "linux-mac-changer.sh", "notification-server.py" -DestinationPath $zipName -Force

# 创建 Release 说明
$releaseNotes = @"
## Linux MAC Changer $newVersion
### 功能特性
- MAC 地址随机修改
- 保持 IP 不变
- 永久保存 MAC 地址
- 多渠道通知
### 文件说明
- linux-mac-changer.sh - 主脚本
- notification-server.py - 通知服务器
- README.md - 使用说明（英文）
- README_ZH.md - 使用说明（中文）
"@

# 检查并删除旧 tag
$existingTag = git tag -l $newVersion
if ($existingTag) {
    Write-Host "删除旧 tag: $newVersion" -ForegroundColor Yellow
    git tag -d $newVersion
    git push origin :refs/tags/$newVersion 2>$null
}

# 删除旧 Release
$releases = gh release list --limit 100
foreach ($line in $releases) {
    if ($line -match "^$newVersion") {
        Write-Host "删除旧 Release: $newVersion" -ForegroundColor Yellow
        gh release delete $newVersion --yes 2>$null
        break
    }
}

# 创建 GitHub Release
Write-Host "创建 GitHub Release..." -ForegroundColor Cyan
gh release create $newVersion --title "Release $newVersion" --notes "$releaseNotes" $zipName

# 创建并推送 tag
Write-Host "创建版本标签..." -ForegroundColor Cyan
git tag -a $newVersion -m "Release $newVersion"
git push origin $newVersion

Write-Host "清理临时文件..." -ForegroundColor Cyan
Remove-Item $zipName -Force
Remove-Item $MyInvocation.MyCommand.Path -Force

Write-Host "完成！" -ForegroundColor Green
Write-Host "Release 地址: https://github.com/DXShelley/linux-mac-changer/releases/tag/$newVersion" -ForegroundColor Cyan

# 切回 develop 分支
git checkout develop
```

### Release 发版后清理

release.ps1 脚本执行完成后会自动清理以下临时文件：

- **zip 压缩包**：如 `linux-mac-changer-v1.0.0.zip`
- **release.ps1 脚本本身**

清理完成后脚本会自动切换回 develop 分支。

### 版本号规则

- 使用语义化版本（SemVer）：vMAJOR.MINOR.PATCH
- 默认递增 MAJOR 版本号
- 手动指定版本：运行脚本时输入具体版本号

### main 分支文件规范

main 分支只包含发布所需文件，共 7 个：

```
LICENSE
README.md
README_ZH.md
linux-mac-changer.sh
notification-server.py
mac修改端执行过程.txt
通知服务器打印及输出.txt
```

**禁止添加其他文件**，如需更新请在 develop 分支操作后手动合并。

合并到 main 时操作步骤：
```bash
# 1. 切换到 main
git checkout main

# 2. 只合并需要的文件
git checkout develop -- LICENSE README.md README_ZH.md linux-mac-changer.sh notification-server.py "mac修改端执行过程.txt" "通知服务器打印及输出.txt"

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
