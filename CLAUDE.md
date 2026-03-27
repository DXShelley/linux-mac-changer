# 项目注意事项

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
