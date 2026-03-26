#!/usr/bin/env python3
"""
Linux MAC Changer - 通知接收服务器

接收 Linux 设备发送的 MAC/IP 通知并显示
版本: 1.0.0
许可: MIT License
作者: DXShelley
仓库: https://github.com/DXShelley/linux-mac-changer
"""

from flask import Flask, request, jsonify, Response
from datetime import datetime
import json
import os
import sys

app = Flask(__name__)

# 配置 JSON 响应不转义中文字符
app.config['JSON_AS_ASCII'] = False

# 存储通知
notifications = []

# 根据操作系统选择合适的文件路径
if sys.platform == 'win32':
    NOTIFICATIONS_FILE = os.path.join(os.environ.get('TEMP', 'C:\\Temp'), 'linux_mac_notifications.json')
else:
    NOTIFICATIONS_FILE = '/tmp/linux_mac_notifications.json'

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'GET':
        return jsonify({
            'status': 'running',
            'notifications': len(notifications),
            'latest': notifications[-1] if notifications else None
        })

    if request.method == 'POST':
        try:
            data = request.get_json()

            # 添加时间戳
            data['received_at'] = datetime.now().isoformat()

            # 保存通知
            notifications.append(data)

            # 保存到文件（使用 UTF-8 编码，不转义中文）
            try:
                with open(NOTIFICATIONS_FILE, 'w', encoding='utf-8') as f:
                    json.dump(notifications, f, indent=2, ensure_ascii=False)
            except Exception as e:
                print(f"警告: 无法保存到文件 {NOTIFICATIONS_FILE}: {e}")

            # 打印通知（结构化格式）
            print("\n" + "="*50)
            print(f"收到 Linux 通知 [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]")
            print("="*50)

            # 基本信息
            if 'hostname' in data:
                print(f"主机: {data['hostname']}")

            # 状态
            if 'status' in data:
                status_map = {
                    'ip_kept': '✓ IP 保持不变',
                    'ip_changed': '⚠️  IP 已改变',
                    'test': '📝 测试通知'
                }
                status_text = status_map.get(data['status'], data['status'])
                print(f"状态: {status_text}")

            # 接口
            if 'interface' in data:
                print(f"接口: {data['interface']}")

            # MAC 地址
            if 'mac' in data and isinstance(data['mac'], dict):
                mac = data['mac']
                if 'original' in mac:
                    print(f"原始 MAC: {mac['original']}")
                if 'new' in mac:
                    print(f"新 MAC:   {mac['new']}")

            # IP 地址
            if 'ip' in data and isinstance(data['ip'], dict):
                ip_data = data['ip']
                if 'original' in ip_data and ip_data['original'] != ip_data.get('current'):
                    print(f"原始 IP: {ip_data['original']}")
                if 'current' in ip_data:
                    print(f"当前 IP: {ip_data['current']}")

            # 网关
            if 'gateway' in data:
                print(f"网关: {data['gateway']}")

            # SSH 连接
            if 'ssh' in data:
                print(f"SSH: {data['ssh']}")

            # 旧消息格式兼容
            if 'message' in data:
                message = data['message']
                message = message.replace('\\n', '\n')
                print(f"消息:")
                print("-" * 50)
                print(message)
                print("-" * 50)

            # 时间戳
            if 'timestamp' in data:
                print(f"发送时间: {data['timestamp']}")
            print(f"接收时间: {data['received_at']}")
            print("="*50 + "\n")

            return jsonify({'status': 'success', 'message': '通知已接收'})

        except Exception as e:
            return jsonify({'status': 'error', 'message': str(e)}), 400

@app.route('/notifications', methods=['GET'])
def get_notifications():
    """获取所有通知"""
    return jsonify(notifications)

@app.route('/notifications/latest', methods=['GET'])
def get_latest():
    """获取最新通知"""
    if notifications:
        return jsonify(notifications[-1])
    return jsonify({'error': '暂无通知'}), 404

@app.route('/stats', methods=['GET'])
def get_stats():
    """获取统计信息"""
    total = len(notifications)
    hosts = set()
    ips = set()
    for n in notifications:
        if 'hostname' in n:
            hosts.add(n['hostname'])
        if 'ip' in n:
            ips.add(n['ip'])
    return jsonify({
        'total_notifications': total,
        'unique_hosts': len(hosts),
        'unique_ips': len(ips),
        'hosts': list(hosts),
        'ips': list(ips)
    })

@app.route('/clear', methods=['POST'])
def clear_notifications():
    """清除通知"""
    notifications.clear()
    return jsonify({'status': 'cleared'})

if __name__ == '__main__':
    print("="*50)
    print("Linux MAC 通知接收服务器")
    print("="*50)
    print(f"启动时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"监听地址: http://0.0.0.0:8089")
    print(f"通知文件: {NOTIFICATIONS_FILE}")
    print("")
    print("API 端点:")
    print("  POST /                 发送通知")
    print("  GET  /                 查看状态")
    print("  GET  /notifications    查看所有通知")
    print("  GET  /notifications/latest  查看最新通知")
    print("  GET  /stats            查看统计信息")
    print("  POST /clear            清除所有通知")
    print("")
    print("在 Linux 脚本中设置:")
    print(f"  REMOTE_NOTIFY_URL='http://YOUR_IP:8089'")
    print("="*50)
    print("\n服务器运行中...\n")

    app.run(host='0.0.0.0', port=8089, debug=False)
