#!/usr/bin/env python3
"""
测试 USB CDC 基本连接 - 心跳命令（0xFF）
"""

import serial
import serial.tools.list_ports
import time

def list_ports():
    """列出可用串口"""
    ports = serial.tools.list_ports.comports()
    print("\n可用串口:")
    for i, port in enumerate(ports, 1):
        print(f"{i}. {port.device} - {port.description}")
    return [port.device for port in ports]

def test_heartbeat(port):
    """
    测试心跳命令响应
    """
    try:
        ser = serial.Serial(port, 115200, timeout=1)
        print(f"\n✅ 已连接到 {port}")

        # 心跳命令: AA 55 FF 00 00 FF
        heartbeat_cmd = bytes([0xAA, 0x55, 0xFF, 0x00, 0x00, 0xFF])

        print("\n📤 发送心跳命令: AA 55 FF 00 00 FF")
        ser.write(heartbeat_cmd)

        print("⏱️  等待响应（2秒）...\n")
        time.sleep(2)

        # 读取响应
        response = ser.read(ser.in_waiting)

        if len(response) > 0:
            print(f"✅ 收到响应: {len(response)} 字节")
            print(f"   数据 (HEX): {' '.join([f'{b:02X}' for b in response])}")
            print(f"   数据 (ASCII): {response}")
            print("\n🎉 USB CDC 连接正常！")
            return True
        else:
            print("❌ 无响应")
            print("\n可能原因:")
            print("   1. FPGA 未下载比特流")
            print("   2. USB CDC 未正确枚举")
            print("   3. 选择了错误的串口")
            print("   4. protocol_parser 模块未工作")
            return False

        ser.close()

    except Exception as e:
        print(f"❌ 错误: {e}")
        return False

if __name__ == "__main__":
    print("="*60)
    print("🔬 USB CDC 心跳测试")
    print("="*60)

    # 列出串口
    ports = list_ports()
    if not ports:
        print("❌ 未找到可用串口")
        exit(1)

    # 选择串口
    print("\n请输入串口编号:", end=" ")
    try:
        port_idx = int(input()) - 1
        if port_idx < 0 or port_idx >= len(ports):
            print("❌ 无效选择")
            exit(1)
        selected_port = ports[port_idx]
    except (ValueError, IndexError):
        print("❌ 无效输入")
        exit(1)

    # 运行测试
    if test_heartbeat(selected_port):
        print("\n✅ 下一步: 测试 DC 启动命令")
        print("   运行: python test_dc_command.py")
    else:
        print("\n⚠️  请先解决 USB CDC 连接问题")
        print("   检查项:")
        print("   1. FPGA 是否下载了比特流")
        print("   2. Windows 设备管理器中是否识别到 COM 口")
        print("   3. 比特流是否包含 USB CDC 功能")
