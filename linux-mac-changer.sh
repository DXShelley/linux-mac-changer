#!/bin/bash

#
# Linux MAC Changer - 远程 MAC 地址修改工具
# 修改 MAC 地址后自动获取新 IP 并通知用户
# 版本: 1.0.0
# 许可证: MIT License
# 作者: DXShelley
# 仓库: https://github.com/DXShelley/linux-mac-changer
#
# 支持 Debian/Ubuntu/Kali 等 Linux 发行版
#

# 配置区域
NOTIFY_METHOD="url"  # localfile, url, telegram, all
LOCAL_NOTIFY_FILE="/tmp/new_ip.txt"
REMOTE_NOTIFY_URL="http://192.168.70.241:8089"  # 填入你的通知服务器 URL
TELEGRAM_BOT_TOKEN=""  # Telegram Bot Token
TELEGRAM_CHAT_ID=""    # Telegram Chat ID
NETWORK_INTERFACE="${1:-eth0}"
SCAN_NETWORK="192.168.70.0/24"  # 你的局域网段
SSH_PORT=22

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 系统检测函数
check_system() {
    local errors=0

    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本需要 root 权限${NC}"
        echo "请使用: sudo sh $0"
        exit 1
    fi

    # 检测操作系统
    local supported=false
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="$VERSION_ID"

        # 验证是否在支持的发行版列表中
        case "$ID" in
            debian|ubuntu|kali|raspbian|armbian|linuxmint|pop)
                supported=true
                ;;
            *)
                # 检查是否基于 Debian
                if [ -n "$ID_LIKE" ]; then
                    for like in $ID_LIKE; do
                        if [ "$like" = "debian" ]; then
                            supported=true
                            break
                        fi
                    done
                fi
                ;;
        esac
    else
        OS_NAME="unknown"
        OS_VERSION="unknown"
        echo -e "${YELLOW}警告: 无法检测操作系统类型${NC}"
        echo -e "${YELLOW}此脚本主要支持基于 Debian 的系统${NC}"
    fi

    # 检查内核版本（需要 3.0+ 以支持某些网络功能）
    local kernel_version=$(uname -r | cut -d. -f1)
    if [ "$kernel_version" -lt 3 ] 2>/dev/null; then
        echo -e "${YELLOW}警告: 内核版本过旧 (当前: $(uname -r))${NC}"
        echo -e "${YELLOW}建议使用内核 3.0 或更高版本${NC}"
    fi

    # 检查是否有 systemd（影响某些功能）
    local has_systemd=false
    if command -v systemctl &>/dev/null; then
        has_systemd=true
    fi

    # 检查必需命令
    local required_commands=("ip" "grep" "awk" "sed")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}错误: 缺少必需命令 '$cmd'${NC}"
            errors=$((errors + 1))
        fi
    done

    # 检查 ip 命令版本（某些旧系统有 ip 但功能不全）
    if command -v ip &>/dev/null; then
        if ! ip link show &>/dev/null; then
            echo -e "${RED}错误: ip 命令功能不完整${NC}"
            echo -e "${RED}请确保安装了 iproute2 包${NC}"
            errors=$((errors + 1))
        fi
    fi

    # 检查 DHCP 客户端（必需，否则修改 MAC 后无法获取 IP）
    local has_dhclient=false
    local has_dhcpcd=false
    if command -v dhclient &>/dev/null; then
        has_dhclient=true
    fi
    if command -v dhcpcd &>/dev/null; then
        has_dhcpcd=true
    fi

    if [ "$has_dhclient" = false ] && [ "$has_dhcpcd" = false ]; then
        echo -e "${RED}错误: 缺少 DHCP 客户端（dhclient 或 dhcpcd）${NC}"
        echo -e "${RED}修改 MAC 地址后需要 DHCP 客户端获取 IP，否则网络将断开${NC}"
        errors=$((errors + 1))
    fi

    # 检查 HTTP 客户端（根据 NOTIFY_METHOD 决定）
    local has_curl=false
    local has_wget=false
    if command -v curl &>/dev/null; then
        has_curl=true
    fi
    if command -v wget &>/dev/null; then
        has_wget=true
    fi

    # 如果使用 URL/Telegram 通知，需要 HTTP 客户端（改为警告）
    if [ "$NOTIFY_METHOD" = "url" ] || [ "$NOTIFY_METHOD" = "telegram" ] || [ "$NOTIFY_METHOD" = "all" ]; then
        if [ "$has_curl" = false ] && [ "$has_wget" = false ]; then
            echo -e "${YELLOW}警告: NOTIFY_METHOD='$NOTIFY_METHOD' 需要 curl 或 wget，但未找到${NC}"
            echo -e "${YELLOW}通知功能将不可用，但 MAC 修改功能正常${NC}"
            # 自动回退到 localfile 模式
            NOTIFY_METHOD="localfile"
            echo -e "${CYAN}已自动切换到 localfile 通知模式${NC}"
        fi
    fi

    # 检查可选命令（jq）
    local has_jq=false
    if command -v jq &>/dev/null; then
        has_jq=true
    fi

    # 检查 NetworkManager 相关工具（如果使用 NetworkManager）
    local has_nmcli=false
    local nm_manager_running=false
    if [ "$has_systemd" = true ]; then
        if systemctl is-active --quiet NetworkManager 2>/dev/null; then
            nm_manager_running=true
            if command -v nmcli &>/dev/null; then
                has_nmcli=true
            else
                echo -e "${YELLOW}警告: 检测到 NetworkManager 但未安装 nmcli${NC}"
                echo -e "${YELLOW}永久保存功能可能不可用，请安装: apt install network-manager${NC}"
            fi
        fi
    else
        # 非 systemd 系统，尝试其他方式检测
        if pgrep -x "NetworkManager" &>/dev/null; then
            nm_manager_running=true
            if command -v nmcli &>/dev/null; then
                has_nmcli=true
            fi
        fi
    fi

    # 检查 python3（Netplan 需要）
    local has_python3=false
    if [ -d /etc/netplan ]; then
        if command -v python3 &>/dev/null; then
            # 检查是否有 PyYAML
            if python3 -c "import yaml" 2>/dev/null; then
                has_python3=true
            else
                echo -e "${YELLOW}警告: python3 已安装但缺少 yaml 模块${NC}"
                echo -e "${YELLOW}请安装: apt install python3-yaml${NC}"
            fi
        else
            echo -e "${YELLOW}警告: 检测到 Netplan 但未安装 python3${NC}"
            echo -e "${YELLOW}永久保存功能将需要手动配置 YAML 文件${NC}"
        fi
    fi

    # 输出系统信息
    if [ "$errors" -eq 0 ]; then
        log "系统检测通过: $OS_NAME $OS_VERSION"
        [ "$has_dhclient" = true ] && log "DHCP: dhclient" || log "DHCP: dhcpcd"
        [ "$has_jq" = true ] && log "JSON: jq 已安装" || log "JSON: 使用备用方式"
        if [ "$has_curl" = true ]; then
            log "HTTP: curl 可用"
        elif [ "$has_wget" = true ]; then
            log "HTTP: wget 可用"
        fi

        # 显示额外信息
        if [ "$has_systemd" = false ]; then
            log "提示: 非 systemd 系统，某些功能可能受限"
        fi

        # 检查通知功能是否可用
        local notification_available=false
        local notification_method=""

        if [ "$NOTIFY_METHOD" = "localfile" ]; then
            # localfile 模式始终可用
            notification_available=true
            notification_method="本地文件 ($LOCAL_NOTIFY_FILE)"
        elif [ "$NOTIFY_METHOD" = "url" ] || [ "$NOTIFY_METHOD" = "all" ]; then
            if [ -n "$REMOTE_NOTIFY_URL" ]; then
                if [ "$has_curl" = true ] || [ "$has_wget" = true ]; then
                    notification_available=true
                    notification_method="URL 通知 ($REMOTE_NOTIFY_URL)"
                fi
            fi
        elif [ "$NOTIFY_METHOD" = "telegram" ]; then
            if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
                if [ "$has_curl" = true ]; then
                    notification_available=true
                    notification_method="Telegram 通知"
                fi
            fi
        fi

        # 如果通知功能不可用，询问用户是否继续
        if [ "$notification_available" = false ]; then
            echo ""
            echo -e "${YELLOW}========================================${NC}"
            echo -e "${YELLOW}⚠️  通知功能不可用${NC}"
            echo -e "${YELLOW}========================================${NC}"
            echo ""
            echo -e "${RED}当前配置的通知方式: $NOTIFY_METHOD${NC}"
            echo -e "${RED}问题: ${NC}"
            if [ "$NOTIFY_METHOD" = "url" ] || [ "$NOTIFY_METHOD" = "all" ]; then
                echo "  - 未配置 REMOTE_NOTIFY_URL"
                echo "  - 或缺少 HTTP 客户端 (curl/wget)"
            elif [ "$NOTIFY_METHOD" = "telegram" ]; then
                echo "  - 未配置 TELEGRAM_BOT_TOKEN 或 TELEGRAM_CHAT_ID"
                echo "  - 或缺少 curl"
            else
                echo "  - 未知的配置错误"
            fi
            echo ""
            echo -e "${CYAN}⚠️  注意事项:${NC}"
            echo ""
            echo -e "${YELLOW}  如果您是通过 ${RED}远程 SSH${YELLOW} 连接到此主机:${NC}"
            echo -e "${YELLOW}    - 修改 MAC 后 IP 地址可能会改变${NC}"
            echo -e "${YELLOW}    - 您需要使用其他方式找到主机的 IP 地址${NC}"
            echo -e "${YELLOW}    - 可用方法:${NC}"
            echo -e "${YELLOW}      • 路由器 DHCP 客户端列表${NC}"
            echo -e "${YELLOW}      • 扫描局域网: sudo $0 scan $SCAN_NETWORK${NC}"
            echo -e "${YELLOW}      • 直接连显示器查看 IP${NC}"
            echo ""
            echo -e "${GREEN}  如果您是在 ${GREEN}本地控制${NC} ${GREEN}此主机:${NC}"
            echo -e "${GREEN}    - 无需担心，修改后可直接在终端看到新 IP${NC}"
            echo -e "${GREEN}    - 本地文件通知将保存到: $LOCAL_NOTIFY_FILE${NC}"
            echo ""
            echo -e "${CYAN}💡 建议: 可以使用 'localfile' 模式作为保底方案${NC}"
            echo ""
            echo -e "${YELLOW}========================================${NC}"
            echo ""

            read -p "是否继续？(y/N): " confirm_continue
            if [ "$confirm_continue" != "y" ] && [ "$confirm_continue" != "Y" ]; then
                echo ""
                echo -e "${CYAN}已取消操作${NC}"
                echo -e "${CYAN}如需继续，请配置通知功能后重试:${NC}"
                echo ""
                echo -e "${CYAN}方法1: 使用本地文件通知${NC}"
                echo "  编辑脚本，设置: NOTIFY_METHOD=\"localfile\""
                echo ""
                echo -e "${CYAN}方法2: 配置 URL 通知${NC}"
                echo "  1. 启动通知服务器: python3 notification-server.py"
                echo "  2. 编辑脚本，设置: REMOTE_NOTIFY_URL=\"http://YOUR_IP:8089\""
                echo ""
                exit 0
            else
                echo ""
                echo -e "${GREEN}✓ 继续执行（通知功能已禁用）${NC}"
                echo -e "${YELLOW}  MAC 修改功能将正常工作${NC}"
                # 自动切换到 localfile 模式
                NOTIFY_METHOD="localfile"
                echo -e "${CYAN}  已自动切换到 localfile 通知模式${NC}"
                echo ""
            fi
        else
            log "通知功能: $notification_method"
        fi

        # 支持的发行版提示
        if [ "$supported" = false ] && [ "$OS_NAME" != "unknown" ]; then
            echo -e "${YELLOW}提示: $OS_NAME 可能未在测试列表中${NC}"
            echo -e "${YELLOW}如遇问题请报告: https://github.com/DXShelley/linux-mac-changer/issues${NC}"
        fi
    else
        echo -e "${RED}系统检测失败，请安装缺少的依赖${NC}"
        exit 1
    fi
}

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /tmp/mac_change.log
}

# 检测网络管理方式
detect_network_manager() {
    local check_interface="$1"

    # 如果指定了接口，优先检查该接口的实际管理方式
    if [ -n "$check_interface" ]; then
        # 1. 检查接口是否在 Netplan 配置中
        if [ -d /etc/netplan ] && [ -f /etc/netplan/*.yaml ]; then
            # 检查接口是否在 netplan 配置中
            if grep -q "$check_interface:" /etc/netplan/*.yaml 2>/dev/null; then
                # 检查 renderer 设置
                local renderer=$(grep -E "^\s*renderer:" /etc/netplan/*.yaml 2>/dev/null | head -1 | awk '{print $2}')
                if [ "$renderer" = "networkd" ]; then
                    echo "netplan"
                    return 0
                elif [ "$renderer" = "NetworkManager" ]; then
                    # 确认该接口确实被 NM 管理
                    if command -v nmcli &>/dev/null && nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep -q "^${check_interface}:connected"; then
                        echo "networkmanager"
                        return 0
                    else
                        # 在 NM 配置中但实际未被管理，使用 netplan
                        echo "netplan"
                        return 0
                    fi
                else
                    # 默认使用 netplan
                    echo "netplan"
                    return 0
                fi
            fi
        fi

        # 2. 检查接口是否被 NetworkManager 管理
        if command -v nmcli &>/dev/null; then
            local nm_managed=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep "^${check_interface}:" | cut -d: -f2)
            if [ "$nm_managed" = "connected" ] || [ "$nm_managed" = "connecting" ]; then
                echo "networkmanager"
                return 0
            fi
            # 检查是否有 unmanaged 但有连接
            local nm_connection=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":${check_interface}$")
            if [ -n "$nm_connection" ]; then
                echo "networkmanager"
                return 0
            fi
        fi

        # 3. 检查接口是否在 /etc/network/interfaces 中
        if [ -f /etc/network/interfaces ]; then
            if grep -q "^iface $check_interface " /etc/network/interfaces 2>/dev/null; then
                echo "ifupdown"
                return 0
            fi
        fi

        # 4. 检查是否有 systemd-networkd 配置
        if [ -d /etc/systemd/network ] && ls /etc/systemd/network/*.link 2>/dev/null | head -1 | grep -q .; then
            if grep -q "$check_interface" /etc/systemd/network/*.link 2>/dev/null; then
                echo "systemd-networkd"
                return 0
            fi
        fi
    fi

    # 未指定接口时的全局检测（保持向后兼容）
    if command -v systemctl &>/dev/null; then
        # systemd 系统
        if systemctl is-active --quiet NetworkManager 2>/dev/null; then
            echo "networkmanager"
            return 0
        fi
        if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
            echo "systemd-networkd"
            return 0
        fi
    else
        # 非 systemd 系统，尝试其他方式检测
        if pgrep -x "NetworkManager" &>/dev/null || pgrep -x "networkmanager" &>/dev/null; then
            echo "networkmanager"
            return 0
        fi
    fi

    # 检查 Netplan（Ubuntu 18.04+）
    if [ -d /etc/netplan ] && [ -f /etc/netplan/*.yaml ]; then
        echo "netplan"
        return 0
    fi

    # 检查 ifupdown（传统 Debian/Ubuntu）
    if [ -f /etc/network/interfaces ]; then
        # 检查是否有实际的配置（不只是注释）
        if grep -q "^iface" /etc/network/interfaces 2>/dev/null; then
            echo "ifupdown"
            return 0
        fi
    fi

    # 无法确定
    echo "unknown"
    return 1
}

# 永久保存 MAC 地址
make_mac_permanent() {
    local interface=$1
    local new_mac=$2
    local manager=$(detect_network_manager "$interface")

    echo -e "${CYAN}正在永久保存 MAC 地址...${NC}"
    echo -e "${CYAN}检测到网络管理方式: $manager${NC}"

    case "$manager" in
        networkmanager)
            # NetworkManager 方式
            # 获取活跃连接名称（更可靠的方式）
            # nmcli -t 格式: "名称:设备类型:设备"

            # 方法1: 从活跃连接中查找（处理包含冒号的连接名）
            local conn_name=""
            local conn_info=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$interface$")

            if [ -n "$conn_info" ]; then
                # 从右侧开始匹配设备名，然后获取左侧的连接名
                # 这样可以处理连接名中包含冒号的情况
                conn_name="${conn_info%:$interface}"
            fi

            # 方法2: 如果方法1失败，尝试通过设备状态获取
            if [ -z "$conn_name" ]; then
                # nmcli device status 输出格式: "DEVICE TYPE STATE CONNECTION"
                local device_info=$(nmcli device status "$interface" 2>/dev/null | grep -v "DEVICE")
                if [ -n "$device_info" ]; then
                    # 获取最后一列（连接名称）
                    conn_name=$(echo "$device_info" | awk '{print $4}')
                    # 如果显示 "--" 表示没有连接
                    if [ "$conn_name" = "--" ]; then
                        conn_name=""
                    fi
                fi
            fi

            # 方法3: 列出所有连接，找到使用该接口的
            if [ -z "$conn_name" ]; then
                while IFS= read -r line; do
                    local c_name=$(echo "$line" | cut -d: -f1)
                    local c_device=$(nmcli -g connection.device connection show "$c_name" 2>/dev/null)
                    if [ "$c_device" = "$interface" ]; then
                        conn_name="$c_name"
                        break
                    fi
                done < <(nmcli -t -f NAME connection show 2>/dev/null)
            fi

            if [ -n "$conn_name" ] && [ "$conn_name" != "" ]; then
                # 检查是否已设置
                local current_mac=$(nmcli -g connection.ethernet.cloned-mac-address connection show "$conn_name" 2>/dev/null)

                if [ "$current_mac" = "--" ] || [ -z "$current_mac" ] || [ "$current_mac" = "" ]; then
                    # 设置 MAC 地址
                    echo -e "${CYAN}正在为连接 '$conn_name' 设置 MAC...${NC}"
                    if nmcli connection modify "$conn_name" ethernet.cloned-mac-address "$new_mac" 2>/dev/null; then
                        # 验证是否设置成功
                        local verify_mac=$(nmcli -g connection.ethernet.cloned-mac-address connection show "$conn_name" 2>/dev/null)
                        if [ "$verify_mac" = "$new_mac" ]; then
                            log "NetworkManager: 已设置 $conn_name 的 MAC 为 $new_mac"
                            echo -e "${GREEN}✓ 已永久保存 (NetworkManager)${NC}"
                            echo -e "${YELLOW}⚠️  需要重新连接生效: nmcli connection up '$conn_name'${NC}"
                            echo -e "${CYAN}或者重启网络服务: systemctl restart NetworkManager${NC}"
                            return 0
                        else
                            echo -e "${RED}✗ MAC设置验证失败 (期望: $new_mac, 实际: $verify_mac)${NC}"
                            return 1
                        fi
                    else
                        echo -e "${RED}✗ nmcli 命令执行失败${NC}"
                        echo -e "${CYAN}请手动运行: nmcli connection modify '$conn_name' ethernet.cloned-mac-address $new_mac${NC}"
                        return 1
                    fi
                else
                    echo -e "${YELLOW}✗ 该连接已设置 MAC: $current_mac${NC}"
                    echo -e "${CYAN}如需修改，请先删除原设置或重新运行脚本${NC}"
                    echo -e "${CYAN}删除命令: nmcli connection modify '$conn_name' ethernet.cloned-mac-address ''${NC}"
                    return 1
                fi
            else
                echo -e "${YELLOW}✗ 无法找到网络连接${NC}"
                echo ""
                echo -e "${CYAN}问题分析:${NC}"
                echo -e "${YELLOW}  接口 '$interface' 当前未被 NetworkManager 管理${NC}"
                echo -e "${CYAN}可能原因:${NC}"
                echo -e "${YELLOW}  1. 接口是通过其他方式管理 (systemd-networkd, ifupdown 等)${NC}"
                echo -e "${YELLOW}  2. 接口存在但未在 NetworkManager 中激活${NC}"
                echo ""
                echo -e "${CYAN}可用连接列表 (仅显示 wlan0):${NC}"
                nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | while IFS=: read -r name device; do
                    echo "  • $name (设备: $device)"
                done
                echo ""
                echo -e "${CYAN}查看所有连接:${NC}"
                echo "  nmcli connection show"
                echo ""
                echo -e "${CYAN}解决方案:${NC}"
                echo -e "${GREEN}  1. 如果接口通过其他方式管理，请使用相应方法${NC}"
                echo -e "${GREEN}  2. 或者先为接口创建 NetworkManager 连接:${NC}"
                echo -e "${GREEN}     sudo nmcli con add type ethernet ifname '$interface' con-name '$interface-auto'"
                echo -e "${GREEN}     sudo nmcli con up '$interface-auto'"
                echo -e "${GREEN}  3. 重新运行脚本进行永久保存${NC}"
                return 1
            fi
            ;;

        systemd-networkd)
            # systemd-networkd 方式
            # 检查systemd-networkd是否正在运行
            if ! command -v systemctl &>/dev/null || ! systemctl is-active systemd-networkd &>/dev/null; then
                echo -e "${YELLOW}⚠️  systemd-networkd 未运行${NC}"
                echo -e "${CYAN}此方法需要 systemd-networkd 服务${NC}"
                echo -e "${CYAN}请使用其他永久保存方式${NC}"
                return 1
            fi

            local link_file="/etc/systemd/network/10-persistent-$interface.link"

            # 检查文件是否已存在
            if [ -f "$link_file" ]; then
                local existing_mac=$(grep "^MACAddress=" "$link_file" | cut -d= -f2)
                echo -e "${YELLOW}⚠️  配置文件已存在: $link_file${NC}"
                echo -e "${CYAN}现有MAC: ${existing_mac:-未知}${NC}"
                echo -e "${CYAN}新MAC: $new_mac${NC}"
                read -p "是否覆盖？(y/N): " overwrite
                if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
                    echo "已取消"
                    return 1
                fi
                # 备份现有文件
                cp "$link_file" "${link_file}.backup.$(date +%Y%m%d%H%M%S)"
            fi

            # 创建 .link 文件
            echo -e "${CYAN}创建systemd-networkd配置文件...${NC}"
            if cat > "$link_file" << EOF
[Match]
OriginalName=$interface

[Link]
MACAddress=$new_mac
EOF
            then
                # 验证文件内容
                if grep -q "OriginalName=$interface" "$link_file" && \
                   grep -q "MACAddress=$new_mac" "$link_file" && \
                   grep -q "\[Match\]" "$link_file" && \
                   grep -q "\[Link\]" "$link_file"; then
                    # 检查文件权限
                    chmod 644 "$link_file"
                    # 重新加载systemd配置
                    if systemctl daemon-reload &>/dev/null; then
                        log "systemd-networkd: 已创建 $link_file"
                        echo -e "${GREEN}✓ 已永久保存 (systemd-networkd)${NC}"
                        echo ""
                        echo -e "${YELLOW}⚠️  需要重启生效${NC}"
                        echo -e "${CYAN}推荐方式: reboot${NC}"
                        echo -e "${CYAN}或重新启动接口: ip link set $interface down && ip link set $interface up${NC}"
                        echo -e "${CYAN}或重启udev: systemctl restart systemd-udevd${NC}"
                        return 0
                    else
                        echo -e "${YELLOW}⚠️  配置文件已创建，但daemon-reload失败${NC}"
                        echo -e "${GREEN}✓ 配置已保存，重启后生效${NC}"
                        return 0
                    fi
                else
                    echo -e "${RED}✗ 配置文件验证失败${NC}"
                    echo -e "${CYAN}文件内容:${NC}"
                    cat "$link_file"
                    rm -f "$link_file"
                    return 1
                fi
            else
                echo -e "${RED}✗ 无法创建配置文件${NC}"
                echo -e "${CYAN}请检查 /etc/systemd/network 目录权限${NC}"
                return 1
            fi
            ;;

        ifupdown)
            # /etc/network/interfaces 方式
            if [ ! -f /etc/network/interfaces ]; then
                echo -e "${RED}✗ /etc/network/interfaces 文件不存在${NC}"
                return 1
            fi

            # 检查接口是否在配置文件中
            if ! grep -q "^iface $interface " /etc/network/interfaces; then
                echo -e "${YELLOW}✗ 接口 $interface 不在 /etc/network/interfaces 中${NC}"
                echo ""
                echo -e "${CYAN}配置文件中的接口:${NC}"
                grep "^iface " /etc/network/interfaces | awk '{print "  • " $2}'
                echo ""
                echo -e "${CYAN}请先在配置文件中添加该接口的配置${NC}"
                return 1
            fi

            # 检查是否已设置此MAC
            if grep -A 15 "^iface $interface " /etc/network/interfaces | grep -q "hwaddress ether $new_mac"; then
                echo -e "${YELLOW}✗ 该 MAC 已存在于配置文件中${NC}"
                echo -e "${CYAN}如需修改，请手动编辑 /etc/network/interfaces${NC}"
                return 1
            fi

            # 检查是否已有其他MAC设置
            local existing_mac=$(grep -A 15 "^iface $interface " /etc/network/interfaces | grep "hwaddress ether" | awk '{print $3}')
            if [ -n "$existing_mac" ]; then
                echo -e "${YELLOW}⚠️  该接口已设置MAC: $existing_mac${NC}"
                echo -e "${CYAN}将替换为新MAC: $new_mac${NC}"
                # 删除旧的hwaddress行
                read -p "是否继续？(y/N): " confirm
                if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                    echo "已取消"
                    return 1
                fi
            fi

            # 备份原文件
            local backup_file="/etc/network/interfaces.backup.$(date +%Y%m%d%H%M%S)"
            if ! cp /etc/network/interfaces "$backup_file"; then
                echo -e "${RED}✗ 无法备份配置文件${NC}"
                return 1
            fi
            echo -e "${CYAN}备份文件: $backup_file${NC}"

            # 使用awk处理配置文件（更可靠）
            # 1. 删除旧的hwaddress行（如果有）
            # 2. 添加新的hwaddress行
            if awk -v iface="$interface" -v mac="$new_mac" '
                BEGIN { in_iface = 0; found_hwaddress = 0 }
                /^iface / {
                    if ($2 == iface) {
                        in_iface = 1
                    } else {
                        in_iface = 0
                    }
                }
                in_iface && /^    hwaddress/ {
                    found_hwaddress = 1
                    next  # 删除旧行
                }
                in_iface && /^    / && !added && !found_hwaddress {
                    # 在第一个选项行前添加hwaddress
                    print "    hwaddress ether " mac
                    added = 1
                }
                { print }
                END {
                    if (!added && in_iface) {
                        # 如果iface存在但没有添加成功，失败
                        exit 1
                    }
                }
            ' /etc/network/interfaces > /tmp/interfaces.tmp 2>/dev/null; then
                # 验证修改后的文件
                if grep -q "hwaddress ether $new_mac" /tmp/interfaces.tmp && \
                   grep -q "^iface $interface " /tmp/interfaces.tmp; then
                    # 应用修改
                    mv /tmp/interfaces.tmp /etc/network/interfaces
                    log "ifupdown: 已添加 MAC 到 /etc/network/interfaces"
                    echo -e "${GREEN}✓ 已永久保存 (ifupdown)${NC}"

                    # 根据系统类型提供不同的重启命令
                    echo ""
                    echo -e "${CYAN}应用更改需要重启网络:${NC}"
                    if command -v systemctl &>/dev/null && systemctl --version &>/dev/null; then
                        echo -e "${YELLOW}  systemctl restart networking${NC}"
                    elif [ -f /etc/init.d/networking ]; then
                        echo -e "${YELLOW}  service networking restart${NC}"
                    else
                        echo -e "${YELLOW}  ifdown $interface && ifup $interface${NC}"
                    fi
                    echo ""
                    return 0
                else
                    echo -e "${RED}✗ 配置文件验证失败${NC}"
                    rm -f /tmp/interfaces.tmp
                    cp "$backup_file" /etc/network/interfaces
                    echo -e "${CYAN}已恢复原配置${NC}"
                    return 1
                fi
            else
                echo -e "${RED}✗ 无法修改配置文件${NC}"
                rm -f /tmp/interfaces.tmp
                return 1
            fi
            ;;

        netplan)
            # Netplan 方式 (Ubuntu 18.04+)
            # 检查是否有netplan配置目录
            if [ ! -d /etc/netplan ]; then
                echo -e "${YELLOW}✗ Netplan配置目录不存在: /etc/netplan${NC}"
                echo -e "${CYAN}此系统可能不使用Netplan${NC}"
                return 1
            fi

            # 查找netplan配置文件
            local netplan_files=($(ls /etc/netplan/*.yaml 2>/dev/null | sort))
            local netplan_file=""

            if [ ${#netplan_files[@]} -eq 0 ]; then
                echo -e "${YELLOW}✗ 未找到 netplan 配置文件 (/etc/netplan/*.yaml)${NC}"
                echo -e "${CYAN}请先创建netplan配置文件${NC}"
                return 1
            elif [ ${#netplan_files[@]} -eq 1 ]; then
                netplan_file="${netplan_files[0]}"
            else
                # 多个文件，让用户选择
                echo -e "${CYAN}找到多个netplan配置文件:${NC}"
                local i=1
                for file in "${netplan_files[@]}"; do
                    echo "  [$i] $(basename "$file")"
                    i=$((i + 1))
                done
                echo ""
                read -p "请选择文件编号 (1-${#netplan_files[@]}): " choice
                if [ "$choice" -ge 1 ] && [ "$choice" -le ${#netplan_files[@]} ] 2>/dev/null; then
                    netplan_file="${netplan_files[$((choice - 1))]}"
                else
                    echo "选择无效"
                    return 1
                fi
            fi

            echo -e "${CYAN}使用配置文件: $netplan_file${NC}"

            # 备份
            local backup_file="${netplan_file}.backup.$(date +%Y%m%d%H%M%S)"
            if ! cp "$netplan_file" "$backup_file"; then
                echo -e "${RED}✗ 无法备份配置文件${NC}"
                return 1
            fi
            echo -e "${CYAN}备份文件: $backup_file${NC}"

            # 检查是否已有该接口的MAC配置
            if grep -A 5 "$interface:" "$netplan_file" | grep -q "macaddress:"; then
                local existing_mac=$(grep -A 5 "$interface:" "$netplan_file" | grep "macaddress:" | awk '{print $2}')
                echo -e "${YELLOW}⚠️  接口 $interface 已配置MAC: $existing_mac${NC}"
                echo -e "${CYAN}新MAC: $new_mac${NC}"
                read -p "是否覆盖？(y/N): " overwrite
                if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
                    echo "已取消"
                    cp "$backup_file" "$netplan_file"
                    return 1
                fi
            fi

            # 检查python3和yaml模块
            if ! command -v python3 &>/dev/null; then
                echo -e "${YELLOW}✗ python3 未安装${NC}"
                echo -e "${CYAN}请手动编辑: $netplan_file${NC}"
                echo -e "${CYAN}在 $interface: 下添加: macaddress: $new_mac${NC}"
                echo ""
                echo "示例配置:"
                echo "  network:"
                echo "    ethernets:"
                echo "      $interface:"
                echo "        macaddress: $new_mac"
                return 1
            fi

            if ! python3 -c "import yaml" 2>/dev/null; then
                echo -e "${YELLOW}✗ python3 yaml模块未安装${NC}"
                echo -e "${CYAN}请安装: apt install python3-yaml${NC}"
                echo ""
                echo "或手动编辑: $netplan_file"
                echo "在 $interface: 下添加: macaddress: $new_mac"
                return 1
            fi

            # 使用 Python 脚本更安全地修改 YAML
            echo -e "${CYAN}正在修改YAML配置...${NC}"
            local python_result=$(python3 << PYTHON_SCRIPT 2>&1
import yaml
import sys

try:
    with open('$netplan_file', 'r') as f:
        config = yaml.safe_load(f)

    # 确保顶层结构正确
    if 'network' not in config:
        config['network'] = {}

    # 确保有 version
    if 'version' not in config['network']:
        config['network']['version'] = 2

    # 确保有 ethernets 配置
    if 'ethernets' not in config['network']:
        config['network']['ethernets'] = {}

    # 设置接口的 MAC 地址
    if '$interface' not in config['network']['ethernets']:
        config['network']['ethernets']['$interface'] = {}

    config['network']['ethernets']['$interface']['macaddress'] = '$new_mac'

    # 写回文件（保持格式）
    with open('$netplan_file', 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)

    print("SUCCESS", file=sys.stderr)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)

            # 检查Python脚本执行结果
            if echo "$python_result" | grep -q "SUCCESS"; then
                # 验证修改后的文件
                if grep -q "macaddress: $new_mac" "$netplan_file" && \
                   grep -q "$interface:" "$netplan_file"; then
                    # 询问是否立即应用配置
                    echo ""
                    echo -e "${YELLOW}========================================${NC}"
                    echo -e "${RED}⚠️  警告: 应用 netplan 配置将会重启网络！${NC}"
                    echo -e "${YELLOW}========================================${NC}"
                    echo ""
                    echo -e "${YELLOW}这将会导致:${NC}"
                    echo -e "${YELLOW}  • 当前 SSH 连接将会断开${NC}"
                    echo -e "${YELLOW}  • 网络接口将会短暂中断${NC}"
                    echo -e "${YELLOW}  • 所有网络连接需要重新建立${NC}"
                    echo ""
                    echo -e "${CYAN}配置文件: $netplan_file${NC}"
                    echo -e "${CYAN}备份文件: $backup_file${NC}"
                    echo ""
                    echo -e "${GREEN}如果不想立即应用，可以稍后手动运行:${NC}"
                    echo -e "${GREEN}  sudo netplan apply${NC}"
                    echo ""
                    read -p "是否立即应用配置？(y/N): " apply_confirm
                    echo ""

                    if [ "$apply_confirm" = "y" ] || [ "$apply_confirm" = "Y" ]; then
                        # 尝试应用配置
                        echo -e "${CYAN}正在应用netplan配置...${NC}"
                        if netplan apply 2>&1 | tee /tmp/netplan_apply.log; then
                            log "netplan: 已更新 $netplan_file"
                            echo -e "${GREEN}✓ 已永久保存 (netplan)${NC}"
                            echo -e "${GREEN}✓ 配置已应用${NC}"
                            echo -e "${CYAN}备份文件: $backup_file${NC}"
                            return 0
                        else
                            echo -e "${YELLOW}⚠️  配置已保存，但 netplan apply 有警告${NC}"
                            echo -e "${CYAN}请检查: /tmp/netplan_apply.log${NC}"
                            echo -e "${CYAN}或手动运行: sudo netplan apply${NC}"
                            return 0
                        fi
                    else
                        echo -e "${CYAN}配置已保存，但未应用${NC}"
                        echo -e "${YELLOW}⚠️  配置将在下次重启或手动运行 netplan apply 后生效${NC}"
                        echo -e "${CYAN}手动应用命令: sudo netplan apply${NC}"
                        echo -e "${CYAN}备份文件: $backup_file${NC}"
                        return 0
                    fi
                else
                    echo -e "${RED}✗ 配置文件验证失败${NC}"
                    echo -e "${CYAN}修改后的文件内容:${NC}"
                    cat "$netplan_file"
                    cp "$backup_file" "$netplan_file"
                    return 1
                fi
            else
                echo -e "${RED}✗ YAML 修改失败${NC}"
                echo -e "${CYAN}错误信息:${NC}"
                echo "$python_result" | grep "ERROR:" | sed 's/ERROR: //'
                cp "$backup_file" "$netplan_file"
                echo -e "${CYAN}已恢复原配置${NC}"
                return 1
            fi
            ;;

        *)
            echo -e "${YELLOW}✗ 未知的网络管理方式: $manager${NC}"
            echo ""
            echo "请手动配置 MAC 地址持久化："
            echo "  • NetworkManager: nmcli connection modify '<name>' ethernet.cloned-mac-address $new_mac"
            echo "  • systemd-networkd: 创建 /etc/systemd/network/*.link 文件"
            echo "  • ifupdown: 编辑 /etc/network/interfaces，添加 'hwaddress ether $new_mac'"
            echo "  • Netplan: 编辑 /etc/netplan/*.yaml，添加 'macaddress: $new_mac'"
            return 1
            ;;
    esac
}

# 验证永久保存配置
verify_permanent_config() {
    local interface=$1
    local expected_mac=$2
    local manager=$(detect_network_manager "$interface")

    echo -e "${CYAN}正在验证永久保存配置...${NC}"
    echo -e "${CYAN}检测到网络管理方式: $manager${NC}"

    case "$manager" in
        networkmanager)
            # 使用与make_mac_permanent相同的连接名称获取逻辑
            local conn_name=""
            local conn_info=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$interface$")

            if [ -n "$conn_info" ]; then
                conn_name="${conn_info%:$interface}"
            fi

            if [ -z "$conn_name" ]; then
                local device_info=$(nmcli device status "$interface" 2>/dev/null | grep -v "DEVICE")
                if [ -n "$device_info" ]; then
                    conn_name=$(echo "$device_info" | awk '{print $4}')
                    [ "$conn_name" = "--" ] && conn_name=""
                fi
            fi

            if [ -n "$conn_name" ] && [ "$conn_name" != "" ]; then
                local configured_mac=$(nmcli -g connection.ethernet.cloned-mac-address connection show "$conn_name" 2>/dev/null)

                if [ "$configured_mac" = "$expected_mac" ]; then
                    echo -e "${GREEN}✓ NetworkManager 配置正确${NC}"
                    echo "  连接: $conn_name"
                    echo "  MAC: $configured_mac"
                    echo ""
                    echo -e "${CYAN}下次重启或重新连接时将自动应用${NC}"
                    return 0
                elif [ "$configured_mac" = "--" ] || [ -z "$configured_mac" ]; then
                    echo -e "${YELLOW}✗ 未配置永久 MAC${NC}"
                    echo -e "${CYAN}当前连接: $conn_name${NC}"
                    echo -e "${CYAN}期望MAC: $expected_mac${NC}"
                    return 1
                else
                    echo -e "${YELLOW}⚠️  MAC 不匹配${NC}"
                    echo "  配置的MAC: $configured_mac"
                    echo "  期望的MAC: $expected_mac"
                    return 1
                fi
            else
                echo -e "${YELLOW}✗ 无法找到连接${NC}"
                echo -e "${CYAN}可用连接:${NC}"
                nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | while IFS=: read -r name device; do
                    echo "  • $name ($device)"
                done
                return 1
            fi
            ;;

        systemd-networkd)
            local link_file="/etc/systemd/network/10-persistent-$interface.link"
            if [ -f "$link_file" ]; then
                local configured_mac=$(grep "^MACAddress=" "$link_file" | cut -d= -f2)
                if [ "$configured_mac" = "$expected_mac" ]; then
                    echo -e "${GREEN}✓ systemd-networkd 配置正确${NC}"
                    echo "  文件: $link_file"
                    echo "  MAC: $configured_mac"
                    echo ""
                    echo -e "${YELLOW}⚠️  需要重启生效${NC}"
                    echo -e "${CYAN}推荐: reboot${NC}"
                    return 0
                else
                    echo -e "${YELLOW}⚠️  MAC 不匹配${NC}"
                    echo "  配置的MAC: $configured_mac"
                    echo "  期望的MAC: $expected_mac"
                    return 1
                fi
            else
                echo -e "${YELLOW}✗ 配置文件不存在: $link_file${NC}"
                echo -e "${CYAN}请先运行永久保存功能${NC}"
                return 1
            fi
            ;;

        ifupdown)
            if [ ! -f /etc/network/interfaces ]; then
                echo -e "${YELLOW}✗ 配置文件不存在: /etc/network/interfaces${NC}"
                return 1
            fi

            if grep -A 15 "^iface $interface " /etc/network/interfaces 2>/dev/null | grep -q "hwaddress ether $expected_mac"; then
                echo -e "${GREEN}✓ ifupdown 配置正确${NC}"
                echo "  文件: /etc/network/interfaces"
                echo "  接口: $interface"
                echo "  MAC: $expected_mac"
                echo ""
                echo -e "${YELLOW}⚠️  需要重启网络生效${NC}"
                if command -v systemctl &>/dev/null && systemctl --version &>/dev/null; then
                    echo -e "${CYAN}命令: systemctl restart networking${NC}"
                elif [ -f /etc/init.d/networking ]; then
                    echo -e "${CYAN}命令: service networking restart${NC}"
                else
                    echo -e "${CYAN}命令: ifdown $interface && ifup $interface${NC}"
                fi
                return 0
            else
                echo -e "${YELLOW}✗ 未在配置文件中找到 MAC 地址${NC}"
                echo -e "${CYAN}期望MAC: $expected_mac${NC}"
                echo ""
                echo -e "${CYAN}当前接口配置:${NC}"
                grep -A 10 "^iface $interface " /etc/network/interfaces 2>/dev/null || echo "  (未找到配置)"
                return 1
            fi
            ;;

        netplan)
            local netplan_files=($(ls /etc/netplan/*.yaml 2>/dev/null | sort))
            local found=false

            for netplan_file in "${netplan_files[@]}"; do
                if grep -A 10 "$interface:" "$netplan_file" | grep -q "macaddress: $expected_mac"; then
                    echo -e "${GREEN}✓ Netplan 配置正确${NC}"
                    echo "  文件: $netplan_file"
                    echo "  接口: $interface"
                    echo "  MAC: $expected_mac"
                    echo ""
                    echo -e "${CYAN}配置已应用，重启后生效${NC}"
                    found=true
                    break
                fi
            done

            if [ "$found" = false ]; then
                echo -e "${YELLOW}✗ 未在配置文件中找到 MAC 地址${NC}"
                echo -e "${CYAN}期望MAC: $expected_mac${NC}"
                return 1
            fi
            return 0
            ;;

        *)
            echo -e "${YELLOW}✗ 未知的网络管理方式: $manager${NC}"
            echo -e "${CYAN}无法验证配置${NC}"
            echo -e "${CYAN}请手动检查配置文件${NC}"
            return 1
            ;;
    esac
}

# 获取当前 IP（只返回最后一个IPv4地址）
get_current_ip() {
    local interface=$1
    ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d'/' -f1 | tail -n1
}

# 获取当前 MAC
get_current_mac() {
    local interface=$1
    ip link show "$interface" | grep link/ether | awk '{print $2}'
}

# 发送通知到本地文件
notify_localfile() {
    local message=$1
    {
        echo "========================================"
        echo "Linux MAC 修改通知"
        echo "========================================"
        echo "时间: $(date)"
        echo "主机: $(hostname)"
        echo "$message"
        echo "========================================"
    } > "$LOCAL_NOTIFY_FILE"
    log "本地通知已保存: $LOCAL_NOTIFY_FILE"
}

# 发送通知到远程 URL
notify_url() {
    local message=$1

    if [ -z "$REMOTE_NOTIFY_URL" ]; then
        log "未配置 REMOTE_NOTIFY_URL，跳过 URL 通知"
        return 0
    fi

    # 检查是否有可用的 HTTP 客户端
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        log "URL 通知跳过：缺少 curl 或 wget"
        return 0
    fi

    # 构建 JSON 数据
    local hostname=$(hostname)
    local timestamp=$(date -Iseconds)

    # 方法1: 使用 jq（如果可用）
    if command -v jq &>/dev/null; then
        local json_data=$(jq -n \
            --arg hn "$hostname" \
            --arg msg "$message" \
            --arg ts "$timestamp" \
            '{hostname: $hn, message: $msg, timestamp: $ts}')
    else
        # 方法2: 手动转义（兼容性更好）
        # 先读取消息，然后处理转义
        local escaped_message=$(printf '%s' "$message" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | tr -d '\n')
        local json_data="{\"hostname\":\"$hostname\",\"message\":\"$escaped_message\",\"timestamp\":\"$timestamp\"}"
    fi

    # 发送 POST 请求
    if command -v curl &>/dev/null; then
        local response=$(curl -s --connect-timeout 5 --max-time 10 -w "\n%{http_code}" -X POST "$REMOTE_NOTIFY_URL" \
            -H "Content-Type: application/json" \
            -d "$json_data" 2>&1) || true
        local http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | head -n-1)

        if [ "$http_code" = "200" ]; then
            log "URL 通知成功: $body"
        else
            log "URL 通知失败 (HTTP $http_code): $body"
        fi
    elif command -v wget &>/dev/null; then
        local response=$(wget -q -O- --post-data="$json_data" \
            --header="Content-Type: application/json" \
            "$REMOTE_NOTIFY_URL" 2>&1) || true
        if [ $? -eq 0 ]; then
            log "URL 通知成功: $response"
        else
            log "URL 通知失败"
        fi
    fi

    return 0
}

# 发送通知到 Telegram
notify_telegram() {
    local message=$1

    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        log "未配置 Telegram，跳过 Telegram 通知"
        return 0
    fi

    # 检查是否有可用的 HTTP 客户端
    if ! command -v curl &>/dev/null; then
        log "Telegram 通知跳过：缺少 curl"
        return 0
    fi

    local escaped_message=$(echo "$message" | sed 's/&/\%26/g' | sed 's/=/\%3D/g')

    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="$escaped_message" &>/dev/null; then
        log "Telegram 通知成功"
    else
        log "Telegram 通知失败"
    fi

    return 0
}

# 发送所有通知
send_notification() {
    local message=$1

    # 使用子shell确保通知失败不影响主流程
    (
        case "$NOTIFY_METHOD" in
            localfile)
                notify_localfile "$message"
                ;;
            url)
                notify_url "$message"
                ;;
            telegram)
                notify_telegram "$message"
                ;;
            all)
                notify_localfile "$message"
                notify_url "$message"
                notify_telegram "$message"
                ;;
            *)
                # 如果通知方法未设置，默认使用 localfile
                notify_localfile "$message"
                ;;
        esac
    ) || true

    return 0
}

# 等待网络恢复
wait_for_network() {
    local interface=$1
    local max_wait=30
    local count=0

    log "等待网络恢复..."

    while [ $count -lt $max_wait ]; do
        local ip=$(get_current_ip "$interface")
        if [ -n "$ip" ]; then
            log "网络已恢复，IP: $ip"
            echo "$ip"
            return 0
        fi
        sleep 1
        count=$((count + 1))
        echo -n "."
    done

    echo ""
    log "网络恢复超时"
    return 1
}

# 修改 MAC 并保证联网（使用三重策略）
change_mac_with_notification() {
    local interface=$1
    local use_random=${2:-true}
    local specific_mac=$3

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  MAC 修改并保证联网${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 需要 root 权限${NC}"
        exit 1
    fi

    # 检查接口是否存在
    if ! ip link show "$interface" &>/dev/null; then
        echo -e "${RED}错误: 接口 $interface 不存在${NC}"
        exit 1
    fi

    # 获取当前信息
    local original_ip=$(get_current_ip "$interface")
    local original_mac=$(get_current_mac "$interface")
    local original_gateway=$(ip route | grep default | awk '{print $3}')
    local original_netmask=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d'/' -f2)

    echo "接口: $interface"
    echo "当前 IP: $original_ip"
    echo "当前 MAC: $original_mac"
    [ -n "$original_gateway" ] && echo "当前网关: $original_gateway"
    echo ""

    # 如果没有原始IP，先尝试获取一个
    if [ -z "$original_ip" ]; then
        echo -e "${YELLOW}当前无IP地址，先尝试获取...${NC}"
        if command -v dhclient &>/dev/null; then
            dhclient "$interface" &>/dev/null || true
            sleep 3
            original_ip=$(get_current_ip "$interface")
            original_gateway=$(ip route | grep default | awk '{print $3}')
            original_netmask=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d'/' -f2)
        fi

        if [ -z "$original_ip" ]; then
            echo -e "${RED}警告: 无法获取初始IP地址${NC}"
            echo -e "${YELLOW}将尝试修改MAC后获取新IP${NC}"
        else
            echo -e "${GREEN}✓ 获取到IP: $original_ip${NC}"
            echo ""
        fi
    fi

    # 发送修改前通知
    local pre_message="即将修改 $interface MAC 地址
原始 IP: ${original_ip:-无}
原始 MAC: $original_mac"
    [ -n "$original_gateway" ] && pre_message="$pre_message
网关: $original_gateway"

    send_notification "$pre_message"

    # 确认
    echo -e "${YELLOW}警告: SSH 连接将中断！${NC}"
    read -p "是否继续？(y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消"
        exit 0
    fi

    # 准备新 MAC
    local new_mac
    if [ "$use_random" = true ]; then
        # 生成随机 MAC
        local byte4=$(printf "%02X" $((RANDOM % 256)))
        local byte5=$(printf "%02X" $((RANDOM % 256)))
        local byte6=$(printf "%02X" $((RANDOM % 256)))
        new_mac="90:2E:16:${byte4}:${byte5}:${byte6}"
    else
        new_mac="$specific_mac"
    fi

    echo ""
    echo -e "${CYAN}新 MAC: $new_mac${NC}"
    echo -e "${YELLOW}正在修改并保证联网...${NC}"
    echo ""

    # 创建恢复脚本
    cat > /tmp/restore_mac.sh << EOFRESTORE
#!/bin/bash
ip link set $interface down
ip link set $interface address $original_mac
ip link set $interface up
dhclient $interface 2>/dev/null || true
EOFRESTORE
    chmod +x /tmp/restore_mac.sh

    # 修改 MAC 地址
    ip link set "$interface" down
    ip link set "$interface" address "$new_mac"
    ip link set "$interface" up

    local final_ip=""
    local ip_obtained=false

    # 策略 1: 尝试通过 DHCP 获取任意IP（最多10秒）
    echo -e "${CYAN}[1/2] 尝试 DHCP 获取IP...${NC}"
    if command -v dhclient &>/dev/null; then
        # 清理可能残留的 dhclient
        killall dhclient &>/dev/null || true
        sleep 1

        # 使用 DHCP 获取 IP
        dhclient "$interface" &>/dev/null || true

        # 等待 IP 分配（最多 10 秒）
        local wait_count=0
        while [ $wait_count -lt 10 ]; do
            sleep 1
            final_ip=$(get_current_ip "$interface")
            if [ -n "$final_ip" ]; then
                echo -e "${GREEN}✓ 获取到 IP: $final_ip${NC}"
                ip_obtained=true
                break
            fi
            echo -n "."
            wait_count=$((wait_count + 1))
        done

        if [ $wait_count -ge 10 ]; then
            echo ""
            echo -e "${YELLOW}✗ DHCP 超时${NC}"
        fi
    else
        echo -e "${YELLOW}✗ dhclient 不可用${NC}"
    fi

    # 策略 2: 如果DHCP失败，尝试手动配置（仅当有原始IP信息时）
    if [ "$ip_obtained" = false ] && [ -n "$original_ip" ] && [ -n "$original_gateway" ]; then
        echo -e "${CYAN}[2/2] 尝试手动配置IP...${NC}"

        # 检测IP是否被占用
        local ip_in_use=false
        if command -v arping &>/dev/null; then
            if arping -c 1 -w 1 "$original_ip" &>/dev/null; then
                ip_in_use=true
            fi
        fi

        if [ "$ip_in_use" = true ]; then
            echo -e "${YELLOW}✗ 原IP已被占用，无法使用${NC}"
        else
            # 设置静态IP
            ip addr flush dev "$interface"
            local netmask="${original_netmask:-24}"
            ip addr add "${original_ip}/${netmask}" dev "$interface" 2>/dev/null || true
            ip route add default via "$original_gateway" dev "$interface" 2>/dev/null || true

            sleep 2
            final_ip=$(get_current_ip "$interface")

            if [ -n "$final_ip" ]; then
                # 测试网络连通性
                if ping -c 1 -W 2 "$original_gateway" &>/dev/null; then
                    echo -e "${GREEN}✓ 手动配置成功: $final_ip${NC}"
                    ip_obtained=true
                else
                    echo -e "${YELLOW}✗ 配置成功但网络不通${NC}"
                    # 清理静态IP
                    ip addr flush dev "$interface"
                fi
            else
                echo -e "${YELLOW}✗ 手动配置失败${NC}"
            fi
        fi
    fi

    # 最终状态检查
    local final_mac=$(get_current_mac "$interface")

    echo ""
    echo "========================================"
    echo -e "${BLUE}修改完成${NC}"
    echo "========================================"
    echo "原始 MAC: $original_mac"
    echo "新 MAC:   $final_mac"
    echo "原始 IP:  ${original_ip:-无}"
    echo "当前 IP:  ${final_ip:-未获取到}"

    # 构建通知消息
    local notify_message=""
    local status=""

    if [ -z "$final_ip" ]; then
        echo -e "${RED}状态: ✗ 未获取到IP地址${NC}"
        echo ""
        echo -e "${RED}⚠️  网络可能不可用！${NC}"
        echo -e "${YELLOW}请检查：${NC}"
        echo "1. 网络连接是否正常"
        echo "2. 运行: cat /tmp/mac_change.log"
        echo "3. 手动配置: ip addr add <IP>/<mask> dev $interface"
        echo ""
        status="no_ip"
        notify_message="Linux MAC 修改完成（未获取到IP）

主机: $(hostname)
接口: $interface
原始 MAC: $original_mac
新 MAC: $final_mac
⚠️ 警告: 未获取到IP地址

时间: $(date)"
    else
        echo -e "${GREEN}状态: ✓ 已获取IP${NC}"
        echo ""
        echo -e "${GREEN}新 SSH 连接: ssh $(whoami)@$final_ip${NC}"

        if [ "$final_ip" = "$original_ip" ]; then
            status="ip_unchanged"
        else
            status="ip_changed"
        fi

        notify_message="Linux MAC 修改完成

主机: $(hostname)
接口: $interface
原始 MAC: $original_mac
新 MAC: $final_mac
${original_ip:+原始 IP: $original_ip
}新 IP: $final_ip ✓

时间: $(date)"
    fi
    echo "========================================"
    echo ""

    # 询问是否永久保存
    if [ "$final_mac" != "$original_mac" ] && [ -n "$final_ip" ]; then
        echo -e "${CYAN}当前修改为临时生效，重启后恢复${NC}"
        read -p "是否永久保存 MAC 地址？(y/N): " save_permanent
        if [ "$save_permanent" = "y" ] || [ "$save_permanent" = "Y" ]; then
            if make_mac_permanent "$interface" "$final_mac"; then
                echo ""
                echo -e "${CYAN}正在验证配置...${NC}"
                verify_permanent_config "$interface" "$final_mac"
            else
                echo -e "${RED}✗ 永久保存失败${NC}"
                echo -e "${YELLOW}当前 MAC 仅本次生效，重启后恢复${NC}"
            fi
            echo ""
        fi
    fi

    # 发送通知
    log "发送通知..."
    (
        # 方法1: 使用 jq 构建结构化 JSON（推荐）
        if command -v jq &>/dev/null; then
            local json_data=$(jq -n \
                --arg hn "$(hostname)" \
                --arg st "$status" \
                --arg iface "$interface" \
                --arg orig_mac "$original_mac" \
                --arg new_mac "$final_mac" \
                --arg orig_ip "${original_ip:-}" \
                --arg new_ip "${final_ip:-}" \
                --arg ts "$(date -Iseconds)" \
                '{
                    hostname: $hn,
                    status: $st,
                    interface: $iface,
                    mac: {
                        original: $orig_mac,
                        new: $new_mac
                    },
                    ip: {
                        original: ($orig_ip // ""),
                        current: ($new_ip // "")
                    },
                    timestamp: $ts
                }')
        else
            # 方法2: 手动构建 JSON（兼容性）
            local json_data="{\"hostname\":\"$(hostname)\",\"status\":\"$status\",\"interface\":\"$interface\",\"mac\":{\"original\":\"$original_mac\",\"new\":\"$final_mac\"},\"ip\":{\"original\":\"${original_ip:-}\",\"current\":\"${final_ip:-}\"},\"timestamp\":\"$(date -Iseconds)\"}"
        fi

        # 保存到本地文件
        echo "$notify_message" > /tmp/new_ip.txt

        # 发送URL通知
        if [ -n "$REMOTE_NOTIFY_URL" ] && command -v curl &>/dev/null; then
            local response=$(curl -s --connect-timeout 5 --max-time 10 -w "\n%{http_code}" -X POST "$REMOTE_NOTIFY_URL" \
                -H "Content-Type: application/json" \
                -d "$json_data" 2>&1) || true
            local http_code=$(echo "$response" | tail -n1)
            if [ "$http_code" = "200" ]; then
                log "通知发送成功"
            else
                log "通知发送失败 (HTTP $http_code)"
            fi
        fi
    ) || true

    echo "详细日志: /tmp/mac_change.log"
    [ -n "$final_ip" ] && echo "新IP已保存到: /tmp/new_ip.txt"

    # 如果没有获取到IP，返回错误码
    if [ -z "$final_ip" ]; then
        return 1
    fi

    return 0
}

# 修改 MAC 并尝试保持 IP 地址
change_mac_keep_ip() {
    local interface=$1
    local use_random=${2:-true}
    local specific_mac=$3

    # 设置 EXIT trap，确保脚本退出时发送通知
    trap '{
        if [ -f /tmp/mac_notify_data.json ]; then
            curl -s --connect-timeout 5 --max-time 10 -X POST "$REMOTE_NOTIFY_URL" \
                -H "Content-Type: application/json" \
                -d @/tmp/mac_notify_data.json > /tmp/notify_result.txt 2>&1 &
        fi
    }' EXIT

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  MAC 修改（保持 IP）${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 需要 root 权限${NC}"
        exit 1
    fi

    # 检查接口是否存在
    if ! ip link show "$interface" &>/dev/null; then
        echo -e "${RED}错误: 接口 $interface 不存在${NC}"
        exit 1
    fi

    # 获取当前信息
    local original_ip=$(get_current_ip "$interface")
    local original_mac=$(get_current_mac "$interface")
    local original_gateway=$(ip route | grep default | awk '{print $3}')
    local original_netmask=$(ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d'/' -f2)

    echo "接口: $interface"
    echo "当前 IP: $original_ip"
    echo "当前 MAC: $original_mac"
    echo "当前网关: $original_gateway"
    echo ""

    # 检查是否有必要信息
    if [ -z "$original_ip" ] || [ -z "$original_gateway" ]; then
        echo -e "${RED}错误: 无法获取 IP 或网关信息${NC}"
        exit 1
    fi

    # 发送修改前通知
    local pre_message="即将修改 $interface MAC 地址（保持 IP 模式）
原始 IP: $original_ip
原始 MAC: $original_mac
目标: 保持 IP 不变"

    send_notification "$pre_message"

    # 确认
    echo -e "${YELLOW}警告: SSH 连接将短暂中断！${NC}"
    read -p "是否继续？(y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消"
        exit 0
    fi

    # 准备新 MAC
    local new_mac
    if [ "$use_random" = true ]; then
        local byte4=$(printf "%02X" $((RANDOM % 256)))
        local byte5=$(printf "%02X" $((RANDOM % 256)))
        local byte6=$(printf "%02X" $((RANDOM % 256)))
        new_mac="90:2E:16:${byte4}:${byte5}:${byte6}"
    else
        new_mac="$specific_mac"
    fi

    echo ""
    echo -e "${CYAN}新 MAC: $new_mac${NC}"
    echo -e "${YELLOW}正在修改...${NC}"
    echo ""

    # 创建恢复脚本
    cat > /tmp/restore_mac.sh << EOFRESTORE
#!/bin/bash
ip link set $interface down
ip link set $interface address $original_mac
ip link set $interface up
dhclient $interface 2>/dev/null || true
EOFRESTORE
    chmod +x /tmp/restore_mac.sh

    # 注意：不再使用监控脚本，直接在主脚本中发送通知

    # 修改 MAC 地址
    ip link set "$interface" down
    ip link set "$interface" address "$new_mac"
    ip link set "$interface" up

    local ip_kept=false
    local final_ip=""

    # 策略 1: 尝试通过 DHCP 请求原 IP
    echo -e "${CYAN}[1/3] 尝试 DHCP REQUEST 原IP...${NC}"
    if command -v dhclient &>/dev/null; then
        # 释放旧租约
        dhclient -r "$interface" &>/dev/null || true
        sleep 1

        # 尝试重新获取（会优先请求原 IP）
        dhclient "$interface" &>/dev/null &
        local dhclient_pid=$!

        # 等待 5 秒检查是否获得原 IP
        local wait_count=0
        while [ $wait_count -lt 5 ]; do
            sleep 1
            local current_ip=$(get_current_ip "$interface")
            if [ "$current_ip" = "$original_ip" ]; then
                echo -e "${GREEN}✓ DHCP REQUEST 成功！保持 IP: $original_ip${NC}"
                kill $dhclient_pid &>/dev/null || true
                ip_kept=true
                final_ip="$original_ip"
                break
            fi
            wait_count=$((wait_count + 1))
            echo -n "."
        done

        if [ "$wait_count" -ge 5 ]; then
            echo ""
            echo -e "${YELLOW}✗ DHCP REQUEST 超时${NC}"
            # 清理 dhclient 进程
            kill $dhclient_pid &>/dev/null || true
            killall dhclient &>/dev/null || true
        fi
    else
        echo -e "${YELLOW}✗ dhclient 不可用${NC}"
    fi

    # 策略 2: 如果策略1失败，尝试设置静态 IP
    if [ "$ip_kept" = false ]; then
        echo -e "${CYAN}[2/3] 尝试设置静态 IP...${NC}"
        local current_ip=$(get_current_ip "$interface")

        if [ -z "$current_ip" ] || [ "$current_ip" != "$original_ip" ]; then
            # 先测试静态 IP 是否可用（如果 arping 可用）
            echo -n "检测 IP 可用性..."
            local ip_in_use=false

            if command -v arping &>/dev/null; then
                if arping -c 1 -w 1 "$original_ip" &>/dev/null; then
                    ip_in_use=true
                fi
            fi

            if [ "$ip_in_use" = true ]; then
                echo -e " ${YELLOW}IP 已被占用${NC}"
                echo -e "${YELLOW}✗ 跳过静态 IP 设置（避免冲突）${NC}"
            else
                # arping 不可用时跳过检测
                if ! command -v arping &>/dev/null; then
                    echo -e " ${CYAN}(跳过检测，arping 不可用)${NC}"
                else
                    echo -e " ${GREEN}可用${NC}"
                fi

                # 设置静态 IP
                ip addr flush dev "$interface"
                ip addr add "${original_ip}/${original_netmask:-24}" dev "$interface"
                ip route add default via "$original_gateway" dev "$interface"

                sleep 2
                current_ip=$(get_current_ip "$interface")

                # 验证静态 IP
                if [ "$current_ip" = "$original_ip" ]; then
                    # 测试网络连通性
                    if ping -c 1 -W 2 "$original_gateway" &>/dev/null; then
                        echo -e "${GREEN}✓ 静态 IP 设置成功！保持 IP: $original_ip${NC}"
                        ip_kept=true
                        final_ip="$original_ip"
                    else
                        echo -e "${YELLOW}✗ 静态 IP 设置成功但网络不通${NC}"
                        # 清理静态 IP，准备使用 DHCP
                        ip addr flush dev "$interface"
                    fi
                else
                    echo -e "${YELLOW}✗ 静态 IP 设置失败${NC}"
                fi
            fi
        else
            echo -e "${GREEN}✓ IP 已正确: $current_ip${NC}"
            ip_kept=true
            final_ip="$current_ip"
        fi
    fi

    # 策略 3: 如果前两个都失败，使用 DHCP 获取任意 IP
    if [ "$ip_kept" = false ]; then
        echo -e "${CYAN}[3/3] 使用 DHCP 获取新IP...${NC}"

        # 清理可能残留的 dhclient
        killall dhclient &>/dev/null || true
        sleep 1

        # 使用 DHCP 获取 IP
        if command -v dhclient &>/dev/null; then
            dhclient "$interface" &>/dev/null || true
        fi

        # 等待 IP 分配（最多 10 秒）
        local wait_count=0
        while [ $wait_count -lt 10 ]; do
            sleep 1
            final_ip=$(get_current_ip "$interface")
            if [ -n "$final_ip" ]; then
                echo -e "${GREEN}✓ 获取到新 IP: $final_ip${NC}"
                break
            fi
            echo -n "."
            wait_count=$((wait_count + 1))
        done

        if [ -z "$final_ip" ]; then
            echo -e "${RED}✗ 无法获取 IP 地址${NC}"
            echo -e "${RED}请检查网络连接或手动设置 IP${NC}"
            return 1
        fi
    fi

    # 检查最终状态
    local final_mac=$(get_current_mac "$interface")

    echo ""
    echo "========================================"
    echo -e "${BLUE}修改完成${NC}"
    echo "========================================"
    echo "原始 MAC: $original_mac"
    echo "新 MAC:   $final_mac"
    echo "原始 IP:  $original_ip"
    echo "当前 IP:  $final_ip"

    # 构建通知消息
    local notify_message=""
    if [ "$final_ip" = "$original_ip" ]; then
        echo -e "${GREEN}状态: ✓ IP 保持不变${NC}"
        echo ""
        echo -e "${GREEN}SSH 连接保持不变: ssh $(whoami)@$original_ip${NC}"

        notify_message="Linux MAC 修改完成（保持 IP 成功）

主机: $(hostname)
接口: $interface
原始 MAC: $original_mac
新 MAC: $final_mac
IP: $final_ip ✓ 保持不变
网关: $original_gateway
SSH: ssh $(whoami)@${final_ip}

时间: $(date)"
    else
        echo -e "${YELLOW}状态: ⚠️  IP 已改变${NC}"
        echo ""
        echo -e "${YELLOW}新 SSH 连接: ssh $(whoami)@$final_ip${NC}"

        notify_message="Linux MAC 修改完成（IP 已改变）

主机: $(hostname)
接口: $interface
原始 MAC: $original_mac
新 MAC: $final_mac
原始 IP: $original_ip
新 IP: $final_ip ⚠️
网关: $original_gateway
SSH: ssh $(whoami)@${final_ip}

时间: $(date)"
    fi
    echo "========================================"
    echo ""

    # 询问是否永久保存 MAC 地址
    if [ "$final_mac" != "$original_mac" ]; then
        echo -e "${CYAN}当前修改为临时生效，重启后恢复${NC}"
        read -p "是否永久保存 MAC 地址？(y/N): " save_permanent
        if [ "$save_permanent" = "y" ] || [ "$save_permanent" = "Y" ]; then
            if make_mac_permanent "$interface" "$final_mac"; then
                echo ""
                echo -e "${CYAN}正在验证配置...${NC}"
                verify_permanent_config "$interface" "$final_mac"
            else
                echo -e "${RED}✗ 永久保存失败${NC}"
                echo -e "${YELLOW}当前 MAC 仅本次生效，重启后恢复${NC}"
            fi
            echo ""
        fi
    fi

    # 发送通知（使用主脚本的 notify_url 函数）
    log "发送通知到服务器..."
    echo -e "${CYAN}发送通知到服务器...${NC}"
    local hostname=$(hostname)
    local timestamp=$(date -Iseconds)
    local current_user=$(whoami)

    # 确定状态
    local status=""
    if [ "$final_ip" = "$original_ip" ]; then
        status="ip_kept"
    else
        status="ip_changed"
    fi

    # 方法1: 使用 jq 构建结构化 JSON（推荐）
    if command -v jq &>/dev/null; then
        local json_data=$(jq -n \
            --arg hn "$hostname" \
            --arg st "$status" \
            --arg iface "$interface" \
            --arg orig_mac "$original_mac" \
            --arg new_mac "$final_mac" \
            --arg orig_ip "$original_ip" \
            --arg new_ip "$final_ip" \
            --arg gw "$original_gateway" \
            --arg ssh_cmd "ssh $current_user@${final_ip}" \
            --arg ts "$timestamp" \
            '{
                hostname: $hn,
                status: $st,
                interface: $iface,
                mac: {
                    original: $orig_mac,
                    new: $new_mac
                },
                ip: {
                    original: $orig_ip,
                    current: $new_ip
                },
                gateway: $gw,
                ssh: $ssh_cmd,
                timestamp: $ts
            }')
    else
        # 方法2: 手动构建 JSON（兼容性）
        local json_data="{\"hostname\":\"$hostname\",\"status\":\"$status\",\"interface\":\"$interface\",\"mac\":{\"original\":\"$original_mac\",\"new\":\"$final_mac\"},\"ip\":{\"original\":\"$original_ip\",\"current\":\"$final_ip\"},\"gateway\":\"$original_gateway\",\"ssh\":\"ssh $current_user@${final_ip}\",\"timestamp\":\"$timestamp\"}"
    fi

    # 保存格式化消息到本地文件（保持可读性）
    {
        echo "========================================"
        echo "Linux MAC 修改完成"
        if [ "$status" = "ip_kept" ]; then
            echo "状态: IP 保持不变 ✓"
        else
            echo "状态: IP 已改变 ⚠️"
        fi
        echo "========================================"
        echo "主机: $hostname"
        echo "接口: $interface"
        echo "原始 MAC: $original_mac"
        echo "新 MAC: $final_mac"
        if [ "$status" = "ip_changed" ]; then
            echo "原始 IP: $original_ip"
        fi
        echo "当前 IP: $final_ip"
        echo "网关: $original_gateway"
        echo "SSH: ssh $current_user@${final_ip}"
        echo "时间: $(date)"
        echo "========================================"
    } > /tmp/new_ip.txt

    # 保存 json_data 到临时文件，确保 trap 可以访问
    echo "$json_data" > /tmp/mac_notify_data.json

    # 发送通知（使用 send_notification 函数，确保失败不影响主流程）
    if [ -n "$REMOTE_NOTIFY_URL" ] && command -v curl &>/dev/null; then
        (
            local response=$(curl -s --connect-timeout 5 --max-time 10 -w "\n%{http_code}" -X POST "$REMOTE_NOTIFY_URL" \
                -H "Content-Type: application/json" \
                -d "$json_data" 2>&1) || true
            local http_code=$(echo "$response" | tail -n1)
            local body=$(echo "$response" | head -n-1)

            if [ "$http_code" = "200" ]; then
                log "通知发送成功: $body"
                touch /tmp/mac_notify_sent
            else
                log "通知发送失败 (HTTP $http_code): $body"
            fi
        ) || true
    fi

    echo "详细日志: /tmp/mac_change.log"
}

# 扫描网段查找本机
scan_orange_pi() {
    local network=${1:-"192.168.1.0/24"}
    local oui_pattern=${2:-"90:2E:16"}

    echo -e "${CYAN}扫描局域网中的本机...${NC}"
    echo "网段: $network"
    echo "OUI 模式: $oui_pattern"
    echo ""

    # 使用 nmap 快速扫描
    if command -v nmap &>/dev/null; then
        echo "使用 nmap 扫描..."
        sudo nmap -sP "$network" 2>/dev/null | grep -B 2 "$oui_pattern" | grep -E "Nmap scan report for|MAC Address"
    else
        echo "使用 ping + arp 扫描..."
        local network_prefix=$(echo "$network" | sed 's/\.0\/24//')

        # 并行 ping
        for i in {1..254}; do
            ping -c 1 -W 1 "${network_prefix}.$i" &>/dev/null &
        done
        wait

        # 查看 ARP 表
        arp -a 2>/dev/null | grep -i "$oui_pattern"
    fi
}

# 显示帮助
show_help() {
    # 获取脚本名称
    local script_name=$(basename "$0")

    # 使用 printf 输出，确保颜色正确显示
    printf "${BLUE}Linux 远程 MAC 修改工具${NC}\n\n"
    printf "${YELLOW}用法:${NC}\n"
    printf "  sudo sh %s <命令> [参数]\n\n" "$script_name"

    printf "${YELLOW}命令:${NC}\n"
    printf "  random <接口>              使用随机 MAC 并通知（推荐）\n"
    printf "  random-keepip <接口>       使用随机 MAC，尝试保持 IP 不变\n"
    printf "  custom <接口> <MAC>        使用指定 MAC 并通知\n"
    printf "  custom-keepip <接口> <MAC> 使用指定 MAC，尝试保持 IP 不变\n"
    printf "  scan [网段]                扫描局域网查找本机\n"
    printf "  verify-permanent <接口>    验证永久 MAC 配置是否正确\n"
    printf "  notify-test [接口]         测试通知配置（默认 eth0）\n\n"

    printf "${YELLOW}示例:${NC}\n"
    printf "  sudo sh %s random eth0                           # 随机 MAC（IP 可能改变）\n" "$script_name"
    printf "  sudo sh %s random-keepip eth0                    # 随机 MAC（尝试保持 IP）\n" "$script_name"
    printf "  sudo sh %s custom eth0 90:2E:16:AB:CD:EF        # 指定 MAC\n" "$script_name"
    printf "  sudo sh %s custom-keepip eth0 90:2E:16:AB:CD:EF # 指定 MAC（保持 IP）\n" "$script_name"
    printf "  sh %s scan 192.168.70.0/24                      # 扫描查找\n" "$script_name"
    printf "  sudo sh %s verify-permanent eth0                # 验证永久 MAC 配置\n" "$script_name"
    printf "  sudo sh %s notify-test eth0                     # 测试通知\n" "$script_name"
}

# 测试通知
test_notification() {
    echo -e "${CYAN}测试通知配置...${NC}"
    echo ""

    # 获取网络接口信息
    local interface="${2:-eth0}"
    local current_ip=$(get_current_ip "$interface")
    local current_mac=$(get_current_mac "$interface")

    # 模拟新旧数据（测试用）
    local old_ip="${current_ip:-192.168.70.100}"
    local old_mac="${current_mac:-90:2E:16:00:00:00}"
    local new_ip="${current_ip:-192.168.70.115}"
    local new_mac="${current_mac:-90:2E:16:AB:CD:EF}"

    local hostname=$(hostname)
    local timestamp=$(date -Iseconds)
    local current_user=$(whoami)
    local gateway=$(ip route | grep default | awk '{print $3}')

    # 构建结构化 JSON
    echo -e "${CYAN}发送测试通知...${NC}"

    if [ -n "$REMOTE_NOTIFY_URL" ]; then
        local json_data=""
        if command -v jq &>/dev/null; then
            json_data=$(jq -n \
                --arg hn "$hostname" \
                --arg st "test" \
                --arg iface "$interface" \
                --arg orig_mac "$old_mac" \
                --arg new_mac "$new_mac" \
                --arg orig_ip "$old_ip" \
                --arg new_ip "$new_ip" \
                --arg gw "${gateway:-192.168.70.1}" \
                --arg ssh_cmd "ssh $current_user@${new_ip}" \
                --arg ts "$timestamp" \
                '{
                    hostname: $hn,
                    status: $st,
                    interface: $iface,
                    mac: {
                        original: $orig_mac,
                        new: $new_mac
                    },
                    ip: {
                        original: $orig_ip,
                        current: $new_ip
                    },
                    gateway: $gw,
                    ssh: $ssh_cmd,
                    timestamp: $ts
                }')
        else
            json_data="{\"hostname\":\"$hostname\",\"status\":\"test\",\"interface\":\"$interface\",\"mac\":{\"original\":\"$old_mac\",\"new\":\"$new_mac\"},\"ip\":{\"original\":\"$old_ip\",\"current\":\"$new_ip\"},\"gateway\":\"${gateway:-192.168.70.1}\",\"ssh\":\"ssh $current_user@${new_ip}\",\"timestamp\":\"$timestamp\"}"
        fi

        local response=$(curl -s --connect-timeout 5 --max-time 10 -w "\n%{http_code}" -X POST "$REMOTE_NOTIFY_URL" \
            -H "Content-Type: application/json" \
            -d "$json_data" 2>&1)
        local http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | head -n-1)

        if [ "$http_code" = "200" ]; then
            echo -e "${GREEN}✓ 测试通知成功${NC}"
        else
            echo -e "${RED}✗ 测试通知失败 (HTTP $http_code)${NC}"
            echo "$body"
        fi
    else
        echo -e "${YELLOW}⚠️  未配置 REMOTE_NOTIFY_URL${NC}"
    fi

    echo ""
    echo "测试通知已发送"
    echo ""

    # 显示发送的信息摘要
    echo -e "${YELLOW}测试数据摘要:${NC}"
    echo "  主机: $hostname"
    echo "  接口: $interface"
    echo "  原始 MAC: $old_mac"
    echo "  新 MAC: $new_mac"
    echo "  原始 IP: $old_ip"
    echo "  新 IP: $new_ip"
    echo ""

    # 保存可读格式到本地文件
    if [ "$NOTIFY_METHOD" = "localfile" ] || [ "$NOTIFY_METHOD" = "all" ]; then
        {
            echo "========================================"
            echo "Linux MAC 修改测试通知"
            echo "========================================"
            echo "主机: $hostname"
            echo "接口: $interface"
            echo "时间: $(date)"
            echo ""
            echo "【修改前】"
            echo "  IP:  $old_ip"
            echo "  MAC: $old_mac"
            echo ""
            echo "【修改后】"
            echo "  IP:  $new_ip"
            echo "  MAC: $new_mac"
            echo ""
            echo "【连接方式】"
            echo "  SSH: ssh $current_user@$new_ip"
            echo ""
            echo "如果看到此消息，通知配置成功！"
            echo "========================================"
        } > "$LOCAL_NOTIFY_FILE"
        echo "本地文件: $LOCAL_NOTIFY_FILE"
        cat "$LOCAL_NOTIFY_FILE"
    fi
}

# 主函数
main() {
    # 系统检测（除 help 和 scan 外）
    if [ "${1:-help}" != "help" ] && [ "${1}" != "scan" ]; then
        check_system
    fi

    case "${1:-help}" in
        random)
            change_mac_with_notification "${2:-eth0}" true
            ;;
        random-keepip)
            change_mac_keep_ip "${2:-eth0}" true
            ;;
        custom)
            if [ -z "$3" ]; then
                echo "用法: $0 custom <接口> <MAC地址>"
                exit 1
            fi
            change_mac_with_notification "$2" false "$3"
            ;;
        custom-keepip)
            if [ -z "$3" ]; then
                echo "用法: $0 custom-keepip <接口> <MAC地址>"
                exit 1
            fi
            change_mac_keep_ip "$2" false "$3"
            ;;
        scan)
            scan_orange_pi "${2:-192.168.1.0/24}" "${3:-90:2E:16}"
            ;;
        verify-permanent)
            if [ -z "$2" ]; then
                echo "用法: $0 verify-permanent <接口>"
                exit 1
            fi
            local current_mac=$(get_current_mac "$2")
            if [ -z "$current_mac" ]; then
                echo -e "${RED}错误: 无法获取接口 $2 的 MAC 地址${NC}"
                exit 1
            fi
            verify_permanent_config "$2" "$current_mac"
            ;;
        notify-test)
            test_notification "${2:-eth0}"
            ;;
        help|*)
            show_help
            ;;
    esac
}

main "$@"
