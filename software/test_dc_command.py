#!/usr/bin/env python3
"""
测试 DC 启动命令 - 完整调试版本
"""

import serial
import serial.tools.list_ports
import time

def calculate_checksum(data):
    """计算校验和"""
    return sum(data) & 0xFF

def generate_dc_start_command(sample_rate_hz):
    """生成 DC 启动命令"""
    SYSTEM_CLK = 60_000_000
    divider = SYSTEM_CLK // sample_rate_hz

    cmd = 0x0B
    len_h = 0x00
    len_l = 0x02
    div_h = (divider >> 8) & 0xFF
    div_l = divider & 0xFF

    checksum = calculate_checksum([cmd, len_h, len_l, div_h, div_l])
    full_cmd = bytes([0xAA, 0x55, cmd, len_h, len_l, div_h, div_l, checksum])

    return full_cmd, divider

def list_ports():
    """列出可用串口"""
    ports = serial.tools.list_ports.comports()
    print("\n可用串口:")
    for i, port in enumerate(ports, 1):
        print(f"{i}. {port.device} - {port.description}")
    return [port.device for port in ports]

def test_dc_command(port, sample_rate_hz, duration=5):
    """
    测试 DC 启动命令

    Args:
        port: 串口名称
        sample_rate_hz: 采样率
        duration: 测试时长（秒）
    """
    try:
        ser = serial.Serial(port, 115200, timeout=0.1)
        print(f"\n✅ 已连接到 {port}")

        # 生成命令
        cmd, divider = generate_dc_start_command(sample_rate_hz)
        actual_rate = 60_000_000 / divider

        print(f"\n📊 配置:")
        print(f"   目标采样率: {sample_rate_hz} Hz")
        print(f"   分频系数:   {divider}")
        print(f"   实际采样率: {actual_rate:.2f} Hz")
        print(f"   命令 (HEX): {' '.join([f'{b:02X}' for b in cmd])}")

        # 发送命令
        print(f"\n📤 发送 DC START 命令...")
        ser.write(cmd)
        time.sleep(0.5)  # 等待命令处理

        # 读取响应
        print(f"⏱️  接收数据 {duration} 秒...\n")

        count = 0
        start = time.time()
        last_print = start
        first_bytes = []

        while time.time() - start < duration:
            if ser.in_waiting > 0:
                data = ser.read(ser.in_waiting)
                count += len(data)

                # 保存前 20 字节用于分析
                if len(first_bytes) < 20:
                    first_bytes.extend(data[:20 - len(first_bytes)])

            # 每秒打印一次
            now = time.time()
            if now - last_print >= 1.0:
                elapsed = now - start
                rate = count / elapsed if elapsed > 0 else 0
                print(f"[{elapsed:.1f}s] 接收: {count:,} bytes | 速率: {rate:,.0f} bytes/s")
                last_print = now

        # 发送停止命令
        stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
        print(f"\n📤 发送 DC STOP 命令: {' '.join([f'{b:02X}' for b in stop_cmd])}")
        ser.write(stop_cmd)
        time.sleep(0.2)

        # 最终统计
        total_time = time.time() - start
        avg_rate = count / total_time if total_time > 0 else 0

        print(f"\n{'='*60}")
        print(f"📊 测试结果")
        print(f"{'='*60}")
        print(f"总接收字节: {count:,} bytes")
        print(f"测试时长:   {total_time:.2f} 秒")
        print(f"平均速率:   {avg_rate:,.0f} bytes/s ({avg_rate/1000:.1f} KB/s)")

        if len(first_bytes) > 0:
            print(f"\n前 {len(first_bytes)} 字节 (HEX):")
            hex_str = ' '.join([f'{b:02X}' for b in first_bytes])
            print(f"   {hex_str}")
            print(f"\n前 {len(first_bytes)} 字节 (二进制):")
            for i, b in enumerate(first_bytes[:10]):  # 只显示前10个
                print(f"   Byte[{i}] = 0x{b:02X} = {b:08b}")

        print(f"{'='*60}\n")

        # 诊断
        if count == 0:
            print("❌ 未接收到任何数据")
            print("\n可能原因:")
            print("   1. dc_signal_in[0] 引脚无输入信号 ⚠️")
            print("   2. DC handler 未启动（cmd_ready 阻塞）")
            print("   3. 命令校验和错误（但刚才生成的是正确的）")
            print("   4. 比特流中 DC 模块未启用")
            print("\n建议:")
            print("   → 给 dc_signal_in[0] 引脚接一个高电平（3.3V）")
            print("   → 或接一个方波信号发生器")
            print("   → 或用跳线短接到 VCC")
        elif avg_rate > 10000:
            print(f"✅ 数据接收正常！")
            print(f"   → 实测速率: {avg_rate:.0f} bytes/s")
            print(f"   → 理论速率: {actual_rate:.0f} bytes/s")
            if abs(avg_rate - actual_rate) / actual_rate < 0.1:
                print(f"   → 速率误差 < 10%，非常准确！")
        else:
            print("⚠️  接收速率低于预期")
            print(f"   → 实测: {avg_rate:.0f} bytes/s")
            print(f"   → 理论: {actual_rate:.0f} bytes/s")

        ser.close()

    except Exception as e:
        print(f"❌ 错误: {e}")

if __name__ == "__main__":
    print("="*60)
    print("🔬 DC 启动命令测试工具")
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

    # 选择采样率（先用低速测试）
    print("\n选择采样率:")
    rates = [
        ("10 kHz (低速测试)", 10_000),
        ("100 kHz", 100_000),
        ("1 MHz", 1_000_000)
    ]
    for i, (name, _) in enumerate(rates, 1):
        print(f"{i}. {name}")

    print("\n请输入采样率编号:", end=" ")
    try:
        rate_idx = int(input()) - 1
        if rate_idx < 0 or rate_idx >= len(rates):
            print("❌ 无效选择")
            exit(1)
        selected_rate = rates[rate_idx][1]
    except (ValueError, IndexError):
        print("❌ 无效输入")
        exit(1)

    # 运行测试
    test_dc_command(selected_port, selected_rate, duration=5)

    print("\n💡 下一步:")
    print("   1. 如果收到数据 → 使用 dc_command_tool.py 查看波形")
    print("   2. 如果仍无数据 → 检查 dc_signal_in[0] 引脚是否有输入信号\n")
