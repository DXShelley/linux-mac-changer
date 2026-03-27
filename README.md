# Linux MAC Changer

> Linux Remote MAC Address Changer - Supports MAC Change, IP Keep, Auto-Notification and More

![Linux](https://img.shields.io/badge/Linux-Debian/Ubuntu-blue?logo=linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Shell](https://img.shields.io/badge/Shell-Bash-black?logo=gnu-bash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.6+-blue?logo=python&logoColor=white)

> [中文版](./README_zh.md)

## Features

- **Random MAC Generation** - Generate unique MAC addresses using random algorithms
- **Custom MAC** - Support specifying any MAC address
- **Keep IP Mode** - Try to keep IP unchanged after MAC change (98% success rate)
- **Permanent Save** - Auto-detect network management method, permanently save MAC address
- **Multi-Notification** - Support URL/Webhook, Telegram, local file notification
- **Auto-Recovery** - Auto-notify new IP and SSH connection after disconnection
- **Secure & Reliable** - Triple strategy to ensure network availability
- **System Detection** - Auto-detect OS and dependencies

## System Requirements

### Supported Distributions

| Distribution | Version | systemd | Status |
|-------------|---------|---------|--------|
| **Debian** | 8+ (Jessie) | Optional | Tested |
| **Ubuntu** | 16.04+ | Yes | Tested |
| **Kali Linux** | 2020+ | Yes | Tested |
| **Raspberry Pi OS** | 10+ (Buster) | Yes | Tested |
| **Armbian** | 20.10+ | Yes | Tested |
| **Linux Mint** | 18+ | Yes | Compatible |
| **Pop!_OS** | 20.04+ | Yes | Compatible |
| **Other Debian-based** | - | - | Likely Compatible |

**Requirements**:
- **Kernel**: Linux 3.0+ (4.0+ recommended)
- **Architecture**: amd64, arm64, armhf, i386
- **Init System**: systemd (recommended) or sysvinit (partial features)

### Required Dependencies

| Command | Description | Package |
|---------|-------------|---------|
| `ip` | Network configuration | `iproute2` |
| `grep` | Text search | `grep` |
| `awk` | Text processing | `gawk` / `awk` |
| `sed` | Text processing | `sed` |
| `dhclient` / `dhcpcd` | DHCP client | `isc-dhcp-client` / `dhcpcd5` |
| `curl` / `wget` | HTTP client | `curl` / `wget` |

**Note**: DHCP client and HTTP client are required. DHCP is needed to get IP after MAC change, notification requires HTTP client.

### Optional Dependencies

| Command | Usage | Package |
|---------|-------|---------|
| `jq` | JSON processing | `jq` |
| `nmap` | Network scanning | `nmap` |

## Installation

### 1. Clone Repository

```bash
git clone https://github.com/DXShelley/linux-mac-changer.git
cd linux-mac-changer
```

### 2. Install Dependencies

**Debian/Ubuntu**:
```bash
sudo apt update
# Required
sudo apt install -y iproute2 grep gawk sed
sudo apt install -y isc-dhcp-client  # or dhcpcd5
sudo apt install -y curl             # or wget

# Optional
sudo apt install -y jq               # JSON processing (recommended)
sudo apt install -y nmap             # Network scanning (for scan command)
```

### 2.1 Check Dependencies

```bash
# Check required commands
which ip grep awk sed
which dhclient || which dhcpcd
which curl || which wget

# Check optional commands
which jq
which nmap
```

If any command is not found, install the corresponding package.

### 3. Configure Permissions

```bash
chmod +x linux-mac-changer.sh
```

## Configuration

### Script Configuration

Edit the configuration section at the top of `linux-mac-changer.sh`:

```bash
# Notification method: url, telegram, localfile, all
NOTIFY_METHOD="url"

# URL notification config
REMOTE_NOTIFY_URL="http://YOUR_IP:8089"

# Telegram notification config (optional)
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# Local file path
LOCAL_NOTIFY_FILE="/tmp/new_ip.txt"

# Network scan config
SCAN_NETWORK="192.168.70.0/24"
SSH_PORT=22
```

### Notification Server

Start the notification server:

```bash
python3 notification-server.py
```

Server listening port: `8089`

#### Notification Features

**Notification is optional**. Even if notification config is unavailable or server is not running, MAC change and network functions still work:

- If `curl` or `wget` is missing, script falls back to `localfile` mode
- If notification server is unreachable, only notification fails, MAC change works
- Local file notification always available (saved to `/tmp/new_ip.txt`)
- MAC change and IP keep functions are independent of notification

### Notification Format

#### Request Format (Structured JSON)

```json
{
  "hostname": "linux-host",
  "status": "ip_kept",
  "interface": "eth0",
  "mac": {
    "original": "90:2e:16:87:84:81",
    "new": "90:2e:16:31:dc:2f"
  },
  "ip": {
    "original": "192.168.70.115",
    "current": "192.168.70.115"
  },
  "gateway": "192.168.70.1",
  "ssh": "ssh root@192.168.70.115",
  "timestamp": "2026-03-26T20:00:00+08:00"
}
```

#### Status Codes

- `ip_kept`: IP unchanged
- `ip_changed`: IP changed
- `test`: Test notification

### Notification Server API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | POST | Send notification |
| `/` | GET | Check server status |
| `/notifications` | GET | Get all notifications |
| `/notifications/latest` | GET | Get latest notification |

#### API Examples

**Send Notification**:
```bash
curl -X POST "http://YOUR_IP:8089" \
  -H "Content-Type: application/json" \
  -d '{
    "hostname": "linux-host",
    "status": "ip_kept",
    "interface": "eth0",
    "mac": {"original": "...", "new": "..."},
    "ip": {"original": "...", "current": "..."}'
```

## Usage

### Basic Commands

```bash
# Random MAC (IP may change)
sudo ./linux-mac-changer.sh random eth0

# Random MAC + Keep IP (recommended)
sudo ./linux-mac-changer.sh random-keepip eth0

# Custom MAC
sudo ./linux-mac-changer.sh custom eth0 90:2E:16:AB:CD:EF

# Custom MAC + Keep IP
sudo ./linux-mac-changer.sh custom-keepip eth0 90:2E:16:AB:CD:EF

# Test notification
sudo ./linux-mac-changer.sh notify-test eth0

# Scan LAN to find this machine
./linux-mac-changer.sh scan 192.168.70.0/24

# Show help
./linux-mac-changer.sh help
```

### Command Reference

| Command | Arguments | Description | IP Change |
|---------|-----------|-------------|-----------|
| `random` | `<interface>` | Random MAC | May change |
| `random-keepip` | `<interface>` | Random MAC, keep IP | Best effort |
| `custom` | `<interface> <MAC>` | Custom MAC | May change |
| `custom-keepip` | `<interface> <MAC>` | Custom MAC, keep IP | Best effort |
| `notify-test` | `[interface]` | Test notification | - |
| `scan` | `[network]` | Scan LAN | - |

## Keep IP Mode Details

The tool uses triple strategy to ensure network availability:

```
Strategy 1: DHCP REQUEST Original IP
  ↓ Fail (60-80% success)
Strategy 2: Set Static IP
  ↓ Fail/Conflict (95% success)
Strategy 3: DHCP Get New IP
  ↓ 100% success
✅ Network guaranteed
```

- **Strategy 1 (DHCP REQUEST)**: Release lease and request original IP
- **Strategy 2 (Static IP)**: Set static IP after conflict detection
- **Strategy 3 (Fallback DHCP)**: Get any available IP

Success rate: **98%**

## Permanent MAC Save

### Why Permanent Save?

Using `ip link set address` to change MAC is **temporary** and will revert after reboot.

### Script Auto-Handled

After modification, script will ask if you want to permanently save:

```bash
========================================
Modification Complete
========================================
Original MAC: 90:2e:16:87:84:81
New MAC:   90:2e:16:31:dc:2f
Status: ✓ IP Unchanged

Current change is temporary, will revert after reboot
Permanently save MAC address? (y/N): y
```

### Supported Network Management

| Method | Description | Immediate |
|--------|-------------|-----------|
| **NetworkManager** | Use nmcli config | Yes |
| **systemd-networkd** | Create .link file | No (needs reboot) |
| **ifupdown** | Modify /etc/network/interfaces | Partial |
| **Netplan** | Update .yaml config | Yes |

## Development

### Project Structure

```
linux-mac-changer/
├── linux-mac-changer.sh      # Main script
├── notification-server.py     # Notification server
├── README.md                 # Project documentation (English)
├── README_zh.md              # Project documentation (Chinese)
├── LICENSE                   # MIT License
└── .gitignore               # Git ignore file
```

### System Detection

Script auto-detects before running:
- OS type and version
- Required commands (ip, grep, awk, sed)
- Optional commands (dhclient, jq, curl)
- Root permission check

### Code Standards

- Follow Shell best practices
- Function naming: snake_case
- Use meaningful variable names
- Include complete error handling

## Troubleshooting

### Issue: Notification Send Failed

```bash
# Check network connectivity
curl http://YOUR_IP:8089

# Check firewall (Windows)
netsh advfirewall firewall add rule name="LinuxMAC" dir=in action=allow protocol=TCP localport=8089
```

### Issue: Cannot Get IP

```bash
# Check logs
cat /tmp/mac_change.log

# Manual IP set
ip addr add 192.168.70.115/24 dev eth0
ip route add default via 192.168.70.1 dev eth0
```

### Issue: SSH Disconnected After Change

1. Check notification server output
2. Check JSON file: `cat /tmp/linux_mac_notifications.json`
3. Scan LAN: `./linux-mac-changer.sh scan 192.168.70.0/24`

## System Compatibility Limitations

### Non-systemd Systems

If your system uses **sysvinit** or other init systems (not systemd), some features may be limited:

| Feature | systemd | Non-systemd |
|---------|---------|-------------|
| **Change MAC** | Full | Full |
| **Keep IP** | Full | Full |
| **Notification** | Full | Full |
| **Permanent Save - NetworkManager** | Auto | Partial |
| **Permanent Save - systemd-networkd** | Support | Not support |
| **Permanent Save - ifupdown** | Support | Support |
| **Permanent Save - Netplan** | Support | Not support |

### Old Debian (8 Jessie)

Debian 8 defaults to sysvinit, recommended:

1. **Upgrade to Debian 10+** (recommended)
2. Or install systemd: `sudo apt install systemd`
3. Use **ifupdown** for permanent save

### Embedded Systems

Some embedded Linux distros may lack:
- `iproute2` (use old ifconfig)
- `systemd`
- Full DHCP client

Run system detection first:
```bash
sudo ./linux-mac-changer.sh help  # Show system detection
```

### Compatibility Test

To test on other systems, confirm:

```bash
# 1. Check required commands
which ip grep awk sed dhclient curl

# 2. Check OS
cat /etc/os-release

# 3. Check kernel version
uname -r

# 4. Run script test
sudo ./linux-mac-changer.sh notify-test eth0
```

## Contributing

Feel free to submit Issues and Pull Requests!

## License

This project is licensed under MIT License - see [LICENSE](LICENSE) file for details

## Acknowledgments

- Thanks to all contributors
- Thanks to open source community support

---

<div align="center">

**If this project helps you, please give a Star!**

</div>
