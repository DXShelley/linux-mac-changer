# GitHub Release 自动打包脚本
# 功能：
# 1. 自动递增主版本号
# 2. 创建 zip 压缩包（不含 CLAUDE.md）
# 3. 上传到 GitHub Release
# 4. 自动删除本地 zip 文件

param(
    [string]$Version = ""  # 可选：指定版本号，如 v1.2.3
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
        # 自动递增主版本号
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

# 创建 zip 包名
$zipName = "linux-mac-changer-$newVersion.zip"

# 创建 zip 压缩包（不含 CLAUDE.md）
Write-Host "创建压缩包: $zipName" -ForegroundColor Cyan
if (Test-Path $zipName) {
    Remove-Item $zipName -Force
}
Compress-Archive -Path "README.md", "linux-mac-changer.sh", "notification-server.py" -DestinationPath $zipName -Force

# 创建 Release 说明
$releaseNotes = @"
## Linux MAC Changer $newVersion

### 功能特性
- MAC 地址随机修改
- 保持 IP 不变
- 永久保存 MAC 地址
- 多渠道通知（URL/Telegram/本地文件）

### 使用方法
````bash
# 随机 MAC（推荐）
sudo sh linux-mac-changer.sh random-keepip eth0

# 指定 MAC
sudo sh linux-mac-changer.sh custom-keepip eth0 <MAC地址>

# 测试通知
sudo sh linux-mac-changer.sh notify-test eth0
````

### 文件说明
- `linux-mac-changer.sh` - 主脚本
- `notification-server.py` - 通知服务器
- `README.md` - 使用说明
"@

# 检查是否存在同名 tag，存在则删除
$existingTag = git tag -l $newVersion 2>$null
if ($existingTag) {
    Write-Host "删除旧 tag: $newVersion" -ForegroundColor Yellow
    git tag -d $newVersion
    git push origin :refs/tags/$newVersion 2>$null
}

# 删除旧 Release（如果存在）
$releases = gh release list --limit 100 2>$null
foreach ($line in $releases) {
    if ($line -match "^$newVersion`t") {
        Write-Host "删除旧 Release: $newVersion" -ForegroundColor Yellow
        gh release delete $newVersion --yes 2>$null
        break
    }
}

# 创建 GitHub Release
Write-Host "创建 GitHub Release..." -ForegroundColor Cyan
gh release create $newVersion --title "Release $newVersion" --notes "$releaseNotes" $zipName

# 删除本地 zip 文件
Write-Host "删除本地压缩包..." -ForegroundColor Cyan
Remove-Item $zipName -Force

# 创建新 tag 并推送
Write-Host "创建版本标签..." -ForegroundColor Cyan
git tag -a $newVersion -m "Release $newVersion"
git push origin $newVersion

Write-Host "完成！" -ForegroundColor Green
Write-Host "Release 地址: https://github.com/DXShelley/linux-mac-changer/releases/tag/$newVersion" -ForegroundColor Cyan

# 切回 develop 分支
git checkout develop
