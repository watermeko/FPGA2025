#!/usr/bin/env python3
"""
简单的接收测试脚本 - 只计数不显示，避免GUI开销
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

def test_receive(port, duration=10):
    """
    测试接收数据

    Args:
        port: 串口名称
        duration: 测试时长（秒）
    """
    try:
        ser = serial.Serial(port, 115200, timeout=0.1)
        print(f"\n✅ 已连接到 {port}")
        print(f"⏱️  开始接收，持续 {duration} 秒...\n")

        count = 0
        start = time.time()
        last_print = start

        while time.time() - start < duration:
            # 读取所有可用数据
            if ser.in_waiting > 0:
                data = ser.read(ser.in_waiting)
                count += len(data)

            # 每秒打印一次统计
            now = time.time()
            if now - last_print >= 1.0:
                elapsed = now - start
                rate = count / elapsed if elapsed > 0 else 0
                print(f"[{elapsed:.1f}s] 接收: {count:,} bytes | 速率: {rate:,.0f} bytes/s ({rate/1000:.1f} KB/s)")
                last_print = now

        # 最终统计
        total_time = time.time() - start
        avg_rate = count / total_time if total_time > 0 else 0

        print(f"\n{'='*60}")
        print(f"📊 测试完成")
        print(f"{'='*60}")
        print(f"总接收字节: {count:,} bytes")
        print(f"测试时长:   {total_time:.2f} 秒")
        print(f"平均速率:   {avg_rate:,.0f} bytes/s ({avg_rate/1000:.1f} KB/s)")
        print(f"{'='*60}\n")

        if count == 0:
            print("❌ 未接收到任何数据")
            print("   可能原因:")
            print("   1. FPGA 未下载比特流")
            print("   2. 未发送启动命令（0x0B）")
            print("   3. dc_signal_in[0] 无输入信号")
        elif avg_rate > 100000:
            print("✅ 接收速率正常！（> 100 KB/s）")
            print("   → 数据确实在传输")
            print("   → 串口调试助手可能无法显示高速数据")
        elif avg_rate > 1000:
            print("⚠️  接收速率较低")
            print(f"   → 可能采样率设置较低，或间歇传输")
        else:
            print("⚠️  接收速率很低")
            print("   → 检查是否持续发送数据")

        ser.close()

    except Exception as e:
        print(f"❌ 错误: {e}")

if __name__ == "__main__":
    print("="*60)
    print("🔬 DC 模块接收测试工具")
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
    test_receive(selected_port, duration=10)

    print("\n💡 提示:")
    print("   - 如果接收速率 > 100 KB/s，说明数据正在传输")
    print("   - 串口调试助手可能无法显示如此高速的数据")
    print("   - 建议使用 dc_command_tool.py 查看实时波形\n")
