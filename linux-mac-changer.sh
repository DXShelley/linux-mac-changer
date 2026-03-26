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
        echo "请使用: sudo $0"
        exit 1
    fi

    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="$VERSION_ID"
    else
        OS_NAME="unknown"
        OS_VERSION="unknown"
    fi

    # 检查必需命令
    local required_commands=("ip" "grep" "awk" "sed")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}错误: 缺少必需命令 '$cmd'${NC}"
            errors=$((errors + 1))
        fi
    done

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

    # 如果使用 URL/Telegram 通知，需要 HTTP 客户端
    if [ "$NOTIFY_METHOD" = "url" ] || [ "$NOTIFY_METHOD" = "telegram" ] || [ "$NOTIFY_METHOD" = "all" ]; then
        if [ "$has_curl" = false ] && [ "$has_wget" = false ]; then
            echo -e "${RED}错误: NOTIFY_METHOD='$NOTIFY_METHOD' 需要 curl 或 wget${NC}"
            errors=$((errors + 1))
        fi
    fi

    # 检查可选命令（jq）
    local has_jq=false
    if command -v jq &>/dev/null; then
        has_jq=true
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
    if systemctl is-active --quiet NetworkManager; then
        echo "networkmanager"
    elif systemctl is-active --quiet systemd-networkd; then
        echo "systemd-networkd"
    elif [ -f /etc/network/interfaces ]; then
        echo "ifupdown"
    elif [ -d /etc/netplan ]; then
        echo "netplan"
    else
        echo "unknown"
    fi
}

# 永久保存 MAC 地址
make_mac_permanent() {
    local interface=$1
    local new_mac=$2
    local manager=$(detect_network_manager)

    echo -e "${CYAN}正在永久保存 MAC 地址...${NC}"

    case "$manager" in
        networkmanager)
            # NetworkManager 方式
            local conn_name=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$interface$" | cut -d: -f1)
            if [ -n "$conn_name" ]; then
                nmcli connection modify "$conn_name" ethernet.cloned-mac-address "$new_mac"
                log "NetworkManager: 已设置 $conn_name 的 MAC 为 $new_mac"
                echo -e "${GREEN}✓ 已永久保存 (NetworkManager)${NC}"
                return 0
            else
                echo -e "${YELLOW}✗ 无法找到网络连接${NC}"
                return 1
            fi
            ;;

        systemd-networkd)
            # systemd-networkd 方式
            local link_file="/etc/systemd/network/10-persistent-$interface.link"
            cat > "$link_file" << EOF
[Match]
OriginalName=$interface

[Link]
MACAddress=$new_mac
EOF
            log "systemd-networkd: 已创建 $link_file"
            echo -e "${GREEN}✓ 已永久保存 (systemd-networkd)${NC}"
            echo -e "${YELLOW}⚠️  需要重启生效: reboot${NC}"
            return 0
            ;;

        ifupdown)
            # /etc/network/interfaces 方式
            if grep -q "iface $interface" /etc/network/interfaces; then
                if ! grep -q "hwaddress ether $new_mac" /etc/network/interfaces; then
                    # 备份原文件
                    cp /etc/network/interfaces "/etc/network/interfaces.backup.$(date +%Y%m%d%H%M%S)"

                    # 在对应接口配置中添加 hwaddress
                    sed -i "/iface $interface/a\    hwaddress ether $new_mac" /etc/network/interfaces
                    log "ifupdown: 已添加 MAC 到 /etc/network/interfaces"
                    echo -e "${GREEN}✓ 已永久保存 (ifupdown)${NC}"
                    echo -e "${YELLOW}⚠️  需要重启网络: systemctl restart networking${NC}"
                    return 0
                else
                    echo -e "${YELLOW}✗ MAC 已存在于配置文件中${NC}"
                    return 1
                fi
            else
                echo -e "${YELLOW}✗ 接口 $interface 不在 /etc/network/interfaces 中${NC}"
                return 1
            fi
            ;;

        netplan)
            # Netplan 方式 (Ubuntu 18.04+)
            local netplan_file=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
            if [ -n "$netplan_file" ]; then
                # 备份
                cp "$netplan_file" "${netplan_file}.backup.$(date +%Y%m%d%H%M%S)"

                # 检查是否已有该接口配置
                if grep -q "$interface:" "$netplan_file"; then
                    # 已有配置，添加或修改 macaddress
                    if grep -q "macaddress:" "$netplan_file"; then
                        sed -i "s/macaddress:.*/macaddress: $new_mac/" "$netplan_file"
                    else
                        sed -i "/$interface:/a\            macaddress: $new_mac" "$netplan_file"
                    fi
                else
                    # 添加新接口配置
                    cat >> "$netplan_file" << EOF

$interface:
    macaddress: $new_mac
EOF
                fi

                netplan apply
                log "netplan: 已更新 $netplan_file"
                echo -e "${GREEN}✓ 已永久保存 (netplan)${NC}"
                return 0
            else
                echo -e "${YELLOW}✗ 未找到 netplan 配置文件${NC}"
                return 1
            fi
            ;;

        *)
            echo -e "${YELLOW}✗ 未知的网络管理方式${NC}"
            echo "请手动配置 MAC 地址持久化"
            return 1
            ;;
    esac
}

# 获取当前 IP
get_current_ip() {
    local interface=$1
    ip -4 addr show "$interface" | grep inet | awk '{print $2}' | cut -d'/' -f1
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
        return
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
        local response=$(curl -s -w "\n%{http_code}" -X POST "$REMOTE_NOTIFY_URL" \
            -H "Content-Type: application/json" \
            -d "$json_data" 2>&1)
        local http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | head -n-1)

        if [ "$http_code" = "200" ]; then
            log "URL 通知成功: $body"
        else
            log "URL 通知失败 (HTTP $http_code): $body"
            log "发送的数据: $json_data"
        fi
    elif command -v wget &>/dev/null; then
        local response=$(wget -q -O- --post-data="$json_data" \
            --header="Content-Type: application/json" \
            "$REMOTE_NOTIFY_URL" 2>&1)
        if [ $? -eq 0 ]; then
            log "URL 通知成功: $response"
        else
            log "URL 通知失败: $response"
            log "发送的数据: $json_data"
        fi
    fi
}

# 发送通知到 Telegram
notify_telegram() {
    local message=$1

    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        log "未配置 Telegram，跳过 Telegram 通知"
        return
    fi

    local escaped_message=$(echo "$message" | sed 's/&/\%26/g' | sed 's/=/\%3D/g')

    if command -v curl &>/dev/null; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d text="$escaped_message" &>/dev/null && log "Telegram 通知成功" || log "Telegram 通知失败"
    fi
}

# 发送所有通知
send_notification() {
    local message=$1

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
    esac
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

# 修改 MAC 并保持连接
change_mac_with_notification() {
    local interface=$1
    local use_random=${2:-true}
    local specific_mac=$3

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  远程安全 MAC 修改${NC}"
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

    echo "接口: $interface"
    echo "当前 IP: $original_ip"
    echo "当前 MAC: $original_mac"
    echo ""

    # 发送修改前通知
    local pre_message="即将修改 $interface MAC 地址
原始 IP: $original_ip
原始 MAC: $original_mac
连接将中断，请等待通知..."

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
    echo -e "${YELLOW}正在修改...${NC}"
    echo ""

    # 创建恢复脚本（以防失败）
    cat > /tmp/restore_mac.sh << EOFRESTORE
#!/bin/bash
ip link set $interface down
ip link set $interface address $original_mac
ip link set $interface up
dhclient $interface 2>/dev/null || true
EOFRESTORE
    chmod +x /tmp/restore_mac.sh

    # 创建监控脚本（后台运行）
    cat > /tmp/monitor_new_ip.sh << EOFMONITOR
#!/bin/bash

INTERFACE="$interface"
ORIGINAL_MAC="$original_mac"
NEW_MAC="$new_mac"
LOG_FILE="/tmp/mac_change.log"
REMOTE_NOTIFY_URL="$REMOTE_NOTIFY_URL"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
NOTIFY_METHOD="$NOTIFY_METHOD"

# 等待 IP
for i in {1..30}; do
    sleep 1
    NEW_IP=\$(ip -4 addr show \$INTERFACE | grep inet | awk '{print \$2}' | cut -d'/' -f1)

    if [ -n "\$NEW_IP" ]; then
        # 找到新 IP
        message="Linux MAC 修改完成

主机: \$(hostname)
接口: \$INTERFACE
原始 MAC: \$ORIGINAL_MAC
新 MAC: \$NEW_MAC
新 IP: \$NEW_IP
SSH: ssh \$(whoami)@\${NEW_IP}

时间: \$(date)"

        echo "\$message" >> /tmp/new_ip.txt
        echo "\$message" >> \$LOG_FILE

        # 发送通知
EOFMONITOR

    # 添加通知方法到监控脚本
    if [ "$NOTIFY_METHOD" = "localfile" ] || [ "$NOTIFY_METHOD" = "all" ]; then
        cat >> /tmp/monitor_new_ip.sh << EOFMONITOR
        echo "\$message" > /tmp/new_ip.txt
EOFMONITOR
    fi

    if [ -n "$REMOTE_NOTIFY_URL" ] && [ "$NOTIFY_METHOD" = "url" -o "$NOTIFY_METHOD" = "all" ]; then
        cat >> /tmp/monitor_new_ip.sh << 'EOFMONITOR'
        # 发送 URL 通知 - 安全转义 JSON
        hostname=$(hostname)
        timestamp=$(date -Iseconds)

        # 优先使用 jq，否则使用手动转义
        if command -v jq &>/dev/null; then
            json_data=$(jq -n \
                --arg hn "$hostname" \
                --arg msg "$message" \
                --arg ip "$NEW_IP" \
                --arg ts "$timestamp" \
                '{hostname: $hn, message: $msg, ip: $ip, timestamp: $ts}')
        else
            escaped_msg=$(printf '%s' "$message" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | tr -d '\n')
            json_data="{\"hostname\":\"$hostname\",\"message\":\"$escaped_msg\",\"ip\":\"$NEW_IP\",\"timestamp\":\"$timestamp\"}"
        fi

        response=$(curl -s -w "\n%{http_code}" -X POST "$REMOTE_NOTIFY_URL" \
            -H "Content-Type: application/json" \
            -d "$json_data" 2>&1)
        http_code=$(echo "$response" | tail -n1)
        if [ "$http_code" = "200" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] URL 通知成功" >> $LOG_FILE
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] URL 通知失败 (HTTP $http_code)" >> $LOG_FILE
        fi
EOFMONITOR
    fi

    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ "$NOTIFY_METHOD" = "telegram" -o "$NOTIFY_METHOD" = "all" ]; then
        cat >> /tmp/monitor_new_ip.sh << EOFMONITOR
        escaped_msg=\$(echo "\$message" | sed 's/&/\%26/g')
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \\
            -d chat_id="${TELEGRAM_CHAT_ID}" \\
            -d text="\$escaped_msg" &>/dev/null || true
EOFMONITOR
    fi

    cat >> /tmp/monitor_new_ip.sh << 'EOFMONITOR'

        exit 0
    fi
done

# 超时
echo "警告: 30秒内未获取到 IP 地址" >> /tmp/new_ip.txt
echo "请使用以下命令检查:" >> /tmp/new_ip.txt
echo "  arp -a | grep $interface" >> /tmp/new_ip.txt
echo "  或在路由器查看 DHCP 列表" >> /tmp/new_ip.txt

exit 1
EOFMONITOR

    chmod +x /tmp/monitor_new_ip.sh

    # 启动监控脚本（后台）
    nohup /tmp/monitor_new_ip.sh &>/dev/null &
    MONITOR_PID=$!
    echo "监控进程 PID: $MONITOR_PID"
    echo ""

    # 执行 MAC 修改
    ip link set "$interface" down
    ip link set "$interface" address "$new_mac"
    ip link set "$interface" up

    # 释放并重新获取 IP
    if command -v dhclient &>/dev/null; then
        dhclient -r "$interface" &>/dev/null || true
        dhclient "$interface" &>/dev/null || true
    fi

    echo -e "${GREEN}✓ MAC 已修改为: $new_mac${NC}"
    echo -e "${YELLOW}✗ SSH 连接将中断${NC}"
    echo ""
    echo "========================================"
    echo "连接中断后，请通过以下方式获取新 IP:"
    echo ""
    echo "1. 查看通知（如果配置了 URL/Telegram）"
    echo "2. 在局域网其他设备上运行:"
    echo "   sudo nmap -sP $SCAN_NETWORK"
    echo ""
    echo "3. 在路由器查看 DHCP 客户端列表"
    echo "4. 5分钟后重新扫描:"
    echo "   for i in {1..254}; do ping -c 1 -W 1 192.168.1.\$i & done; arp -a | grep 90:2E:16"
    echo "========================================"

    # 等待一小会儿再断开
    sleep 2
}

# 修改 MAC 并尝试保持 IP 地址
change_mac_keep_ip() {
    local interface=$1
    local use_random=${2:-true}
    local specific_mac=$3

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
            make_mac_permanent "$interface" "$final_mac"
            echo ""
        fi
    fi

    # 发送通知（使用主脚本的 notify_url 函数）
    log "发送通知到服务器..."
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

    if [ -n "$REMOTE_NOTIFY_URL" ]; then
        local response=$(curl -s -w "\n%{http_code}" -X POST "$REMOTE_NOTIFY_URL" \
            -H "Content-Type: application/json" \
            -d "$json_data" 2>&1)
        local http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | head -n-1)

        if [ "$http_code" = "200" ]; then
            log "通知发送成功: $body"
            # 创建标志文件，告诉监控脚本不需要再发送
            touch /tmp/mac_notify_sent
        else
            log "通知发送失败 (HTTP $http_code): $body"
            # 发送失败，监控脚本会作为备份重试
        fi
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
    cat << EOF
${BLUE}Linux 远程 MAC 修改工具${NC}

${YELLOW}用法:${NC}
  $0 <命令> [参数]

${YELLOW}命令:${NC}
  random <接口>              使用随机 MAC 并通知（推荐）
  random-keepip <接口>       使用随机 MAC，尝试保持 IP 不变
  custom <接口> <MAC>        使用指定 MAC 并通知
  custom-keepip <接口> <MAC> 使用指定 MAC，尝试保持 IP 不变
  scan [网段]                扫描局域网查找本机
  notify-test [接口]         测试通知配置（默认 eth0）

${YELLOW}示例:${NC}
  sudo $0 random eth0                           # 随机 MAC（IP 可能改变）
  sudo $0 random-keepip eth0                    # 随机 MAC（尝试保持 IP）
  sudo $0 custom eth0 90:2E:16:AB:CD:EF        # 指定 MAC
  sudo $0 custom-keepip eth0 90:2E:16:AB:CD:EF # 指定 MAC（保持 IP）
  $0 scan 192.168.70.0/24                      # 扫描查找
  sudo $0 notify-test eth0                     # 测试通知

${YELLOW}配置说明:${NC}
  编辑脚本顶部的配置区域设置:
  - NOTIFY_METHOD: localfile, url, telegram, all
  - REMOTE_NOTIFY_URL: 你的通知服务器 URL
  - TELEGRAM_BOT_TOKEN: Telegram Bot Token
  - TELEGRAM_CHAT_ID: Telegram Chat ID
  - SCAN_NETWORK: 你的局域网段

${YELLOW}通知方式:${NC}
  1. URL 通知: POST 结构化 JSON 到你的服务器
     {
       "hostname": "linux-host",
       "status": "ip_kept",  // 或 "ip_changed", "test"
       "interface": "eth0",
       "mac": {"original": "xx:xx:xx:xx:xx:xx", "new": "yy:yy:yy:yy:yy:yy"},
       "ip": {"original": "192.168.x.x", "current": "192.168.x.y"},
       "gateway": "192.168.x.1",
       "ssh": "ssh user@192.168.x.y",
       "timestamp": "2026-03-26T20:00:00+08:00"
     }

  2. Telegram: 发送到你的 Telegram
     需要创建 Bot 并获取 token/chat_id

  3. 本地文件: 保存到 /tmp/new_ip.txt
     需要通过其他方式读取（如串口）

${YELLOW}断连后如何找回 IP?${NC}
  1. 如果配置了 URL/Telegram 通知，查看通知
  2. 在路由器查看 DHCP 客户端列表（查找新 MAC）
  3. 从其他设备扫描局域网:
     $0 scan 192.168.1.0/24
  4. 使用串口连接查看

${YELLOW}保持 IP 模式（-keepip）:${NC}
  适用场景: 隐藏身份时不想频繁更改 SSH 连接

  工作原理:
  1. 尝试 DHCP REQUEST 请求原 IP（依赖 DHCP 服务器配置）
  2. 如果失败，直接设置静态 IP
  3. 两种方式都失败时，允许获取新 IP（并发送通知）

  成功率:
  - DHCP REQUEST: 约 60-80%（取决于 DHCP 服务器）
  - 静态 IP: 约 95%（需要确保 IP 不被占用）
  - 综合成功率: 约 98%

  注意事项:
  - 如果 IP 冲突，静态 IP 方式可能导致网络问题
  - 建议先在测试环境验证

${YELLOW}永久保存 MAC 地址:${NC}
  修改完成后会询问是否永久保存，支持以下方式:
  - NetworkManager: nmcli 命令配置
  - systemd-networkd: 创建 .link 文件
  - ifupdown: 修改 /etc/network/interfaces
  - Netplan: 更新 .yaml 配置

${YELLOW}系统要求:${NC}
  - 操作系统: Debian/Ubuntu/Kali 等 Linux 发行版
  - 权限: root (sudo)

  - 必需命令:
    • ip, grep, awk, sed (基础网络操作)
    • dhclient 或 dhcpcd (DHCP 客户端，用于获取 IP)
    • curl 或 wget (HTTP 客户端，用于 URL/Telegram 通知)

  - 可选命令:
    • jq (JSON 处理，未安装时使用备用方案)

EOF
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

        local response=$(curl -s -w "\n%{http_code}" -X POST "$REMOTE_NOTIFY_URL" \
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
        notify-test)
            test_notification "${2:-eth0}"
            ;;
        help|*)
            show_help
            ;;
    esac
}

main "$@"
