#!/usr/bin/env python3
"""
安全的DC采集工具 - 自动规避有问题的divider值
"""

import serial
import serial.tools.list_ports
import time

def generate_dc_start_command(sample_rate_hz):
    """生成DC启动命令，自动规避有问题的divider值"""
    SYSTEM_CLK = 60_000_000
    divider = SYSTEM_CLK // sample_rate_hz

    # 检查并修正有问题的divider值
    problematic_dividers = {
        30: (60, "2 MHz → 1 MHz"),      # divider=30有问题，改用60
        300: (600, "200 kHz → 100 kHz"), # divider=300有问题，改用600
        3000: (1200, "20 kHz → 50 kHz"), # divider=3000有问题，改用1200
        6000: (12000, "10 kHz → 5 kHz")  # divider=6000有问题，改用12000
    }

    if divider in problematic_dividers:
        new_divider, reason = problematic_dividers[divider]
        actual_rate = SYSTEM_CLK // new_divider
        print(f"⚠️  警告：采样率 {sample_rate_hz} Hz (divider={divider}) 有已知问题")
        print(f"✅ 自动调整为：{actual_rate} Hz (divider={new_divider})")
        print(f"   原因：{reason}")
        divider = new_divider
        sample_rate_hz = actual_rate

    cmd = 0x0B
    len_h = 0x00
    len_l = 0x02
    div_h = (divider >> 8) & 0xFF
    div_l = divider & 0xFF

    checksum = (cmd + len_h + len_l + div_h + div_l) & 0xFF
    full_cmd = bytes([0xAA, 0x55, cmd, len_h, len_l, div_h, div_l, checksum])

    print(f"采样率: {sample_rate_hz} Hz, 分频系数: {divider}")
    print(f"命令: {' '.join([f'{b:02X}' for b in full_cmd])}")

    return full_cmd

def capture_dc(port, sample_rate, duration=10):
    """安全的DC数据采集"""
    try:
        ser = serial.Serial(port, 115200, timeout=0.1)
        print(f"✅ 已连接到 {port}\n")

        # 发送启动命令（自动规避有问题的divider）
        cmd = generate_dc_start_command(sample_rate)
        ser.write(cmd)
        print("✅ 已发送 START 命令\n")

        time.sleep(0.5)

        # 采集数据
        total = 0
        start_time = time.time()
        data_buffer = bytearray()

        print(f"开始采集 {duration} 秒...")
        print(f"{'时间':<8} {'已接收':<12} {'速率':<15} {'状态':<10}")
        print("-" * 50)

        while time.time() - start_time < duration:
            if ser.in_waiting > 0:
                data = ser.read(ser.in_waiting)
                total += len(data)
                data_buffer.extend(data)

            # 每秒显示进度
            elapsed = time.time() - start_time
            if int(elapsed) != int(elapsed - 0.1):
                rate = total / elapsed if elapsed > 0 else 0
                print(f"{elapsed:7.1f}s {total:10,} B  {rate/1024:>10.1f} KB/s  ✅ 正常")

            time.sleep(0.01)

        # 停止采集
        stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
        ser.write(stop_cmd)

        elapsed = time.time() - start_time
        avg_rate = total / elapsed if elapsed > 0 else 0

        print("\n" + "=" * 50)
        print("采集完成")
        print("=" * 50)
        print(f"总接收: {total:,} bytes ({total/1024:.1f} KB)")
        print(f"时间: {elapsed:.1f} 秒")
        print(f"平均速率: {avg_rate/1024:.1f} KB/s")
        print("=" * 50)

        ser.close()
        return data_buffer

    except Exception as e:
        print(f"❌ 错误: {e}")
        return None

if __name__ == "__main__":
    print("=" * 70)
    print("🔬 安全的DC数据采集工具（自动规避divider bug）")
    print("=" * 70)

    # 列出串口
    ports = serial.tools.list_ports.comports()
    print("\n可用串口:")
    for i, port in enumerate(ports, 1):
        print(f"{i}. {port.device} - {port.description}")

    port_list = [p.device for p in ports]
    if not port_list:
        print("❌ 未找到可用串口")
        exit(1)

    # 选择串口
    print("\n请输入串口编号:", end=" ")
    try:
        port_idx = int(input()) - 1
        selected_port = port_list[port_idx]
    except:
        print("❌ 无效输入")
        exit(1)

    # 选择采样率（包括有问题的速率，工具会自动修正）
    print("\n选择采样率:")
    rates = [
        ("1 kHz", 1000),
        ("2 kHz", 2000),
        ("5 kHz", 5000),
        ("10 kHz ⚠️", 10000),      # 会被自动修正
        ("20 kHz ⚠️", 20000),      # 会被自动修正
        ("50 kHz", 50000),
        ("100 kHz", 100000),
        ("200 kHz ⚠️", 200000),    # 会被自动修正
        ("500 kHz", 500000),
    ]

    for i, (name, _) in enumerate(rates, 1):
        print(f"{i}. {name}")

    print("\n⚠️ 标记的速率会被自动调整为安全值")

    print("\n请输入采样率编号:", end=" ")
    try:
        rate_idx = int(input()) - 1
        selected_rate = rates[rate_idx][1]
    except:
        print("❌ 无效输入")
        exit(1)

    print("\n请输入采集时长（秒）:", end=" ")
    try:
        duration = int(input())
    except:
        print("使用默认10秒")
        duration = 10

    print("\n" + "=" * 70 + "\n")

    # 运行采集
    data = capture_dc(selected_port, selected_rate, duration)

    if data:
        print(f"\n✅ 采集成功！共接收 {len(data)} 字节")

        # 可选：保存到文件
        save = input("\n是否保存到文件？(y/n): ")
        if save.lower() == 'y':
            filename = f"dc_capture_{selected_rate}Hz_{int(time.time())}.bin"
            with open(filename, 'wb') as f:
                f.write(data)
            print(f"✅ 已保存到 {filename}")
