#!/usr/bin/env python3
"""
采样率验证工具 - 验证实际采样率是否与设置一致
通过分析数据变化频率来反推实际采样率
"""

import serial
import serial.tools.list_ports
import time
import numpy as np

def generate_dc_start_command(sample_rate_hz):
    """生成 DC 启动命令"""
    SYSTEM_CLK = 60_000_000
    divider = SYSTEM_CLK // sample_rate_hz

    cmd = 0x0B
    len_h = 0x00
    len_l = 0x02
    div_h = (divider >> 8) & 0xFF
    div_l = divider & 0xFF

    checksum = (cmd + len_h + len_l + div_h + div_l) & 0xFF
    full_cmd = bytes([0xAA, 0x55, cmd, len_h, len_l, div_h, div_l, checksum])

    print(f"采样率设置: {sample_rate_hz} Hz ({sample_rate_hz/1000:.0f} kHz)")
    print(f"分频系数: {divider} (0x{divider:04X})")
    print(f"命令: {' '.join([f'{b:02X}' for b in full_cmd])}")

    return full_cmd

def analyze_sample_rate(port, sample_rate, duration=10):
    """分析实际采样率"""
    try:
        ser = serial.Serial(port, 115200, timeout=0.1)
        print(f"✅ 已连接到 {port}\n")

        # 发送STOP清理状态
        stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
        ser.write(stop_cmd)
        time.sleep(0.1)
        ser.reset_input_buffer()

        # 发送START命令
        cmd = generate_dc_start_command(sample_rate)
        ser.write(cmd)
        print("✅ 已发送 START 命令\n")

        # 等待初始化
        if sample_rate > 200_000:
            time.sleep(1.5)
        else:
            time.sleep(max(0.5, 10.0 / sample_rate))

        # 丢弃初始化数据
        if ser.in_waiting > 0:
            ser.read(ser.in_waiting)

        print(f"开始采集 {duration} 秒数据...\n")

        # 精确计时采集
        start_time = time.perf_counter()
        total_bytes = 0
        data_buffer = []

        while (time.perf_counter() - start_time) < duration:
            if ser.in_waiting > 0:
                chunk = ser.read(ser.in_waiting)
                total_bytes += len(chunk)
                data_buffer.extend(chunk)
            time.sleep(0.001)  # 1ms轮询

        end_time = time.perf_counter()
        actual_duration = end_time - start_time

        # 发送STOP
        ser.write(stop_cmd)
        ser.close()

        # 分析结果
        print("="*70)
        print("📊 采集结果")
        print("="*70)
        print(f"采集时长:     {actual_duration:.3f} 秒")
        print(f"总字节数:     {total_bytes:,} bytes ({total_bytes/1024:.2f} KB)")
        print(f"平均速率:     {total_bytes/actual_duration:.0f} B/s ({total_bytes/actual_duration/1024:.1f} KB/s)")

        # 计算理论值
        expected_bytes = int(sample_rate * actual_duration)
        expected_rate = total_bytes / actual_duration

        print(f"\n预期字节数:   {expected_bytes:,} bytes")
        print(f"预期速率:     {sample_rate:.0f} B/s ({sample_rate/1024:.1f} KB/s)")

        # 计算偏差
        byte_ratio = total_bytes / expected_bytes if expected_bytes > 0 else 0
        rate_ratio = expected_rate / sample_rate if sample_rate > 0 else 0

        print(f"\n实际/预期比:  {byte_ratio:.3f}x")

        if byte_ratio > 1.5:
            print(f"⚠️  警告: 实际数据量远超预期 ({byte_ratio:.1f}倍)！")
            print(f"   可能原因: FPGA采样率设置错误或divider计算错误")
        elif byte_ratio < 0.5:
            print(f"⚠️  警告: 实际数据量远低于预期 ({byte_ratio:.2f}倍)！")
            print(f"   可能原因: USB带宽限制或FIFO满导致丢失")
        elif byte_ratio < 0.9:
            loss_rate = (1 - byte_ratio) * 100
            print(f"⚠️  数据丢失: 约 {loss_rate:.1f}%")
            print(f"   可能原因: USB带宽不足 (极限~1.2MB/s)")
        else:
            print(f"✅ 数据完整，无明显丢失")

        # USB带宽分析
        print(f"\n{'='*70}")
        print("🔌 USB带宽分析")
        print("="*70)

        usb_utilization = (expected_rate / 1.2e6) * 100 if expected_rate > 0 else 0
        actual_utilization = (total_bytes/actual_duration / 1.2e6) * 100

        print(f"USB理论利用率: {usb_utilization:.1f}% (基于预期速率)")
        print(f"USB实际利用率: {actual_utilization:.1f}% (基于测量速率)")
        print(f"USB Full-Speed极限: 1.2 MB/s (1,200 KB/s)")

        if expected_rate > 1.2e6:
            print(f"\n⚠️  预期速率 ({expected_rate/1024:.0f} KB/s) 超过USB极限！")
            print(f"   最大可达: 1,200 KB/s")
            print(f"   必然丢失: {(1 - 1.2e6/expected_rate)*100:.0f}%")

        # 数据模式分析（如果有足够数据）
        if len(data_buffer) > 1000:
            print(f"\n{'='*70}")
            print("🔍 数据模式分析")
            print("="*70)

            # 统计不同字节值的出现次数
            unique, counts = np.unique(data_buffer[:1000], return_counts=True)
            print(f"前1000字节中唯一值数量: {len(unique)}")

            if len(unique) <= 5:
                print(f"⚠️  数据模式单一，可能采样源信号不变")
                print(f"   值分布: {dict(zip([f'0x{v:02X}' for v in unique[:5]], counts[:5]))}")
            elif len(unique) == 256:
                print(f"✅ 数据模式丰富，采样正常")
            else:
                print(f"   常见值 (前5个): {dict(zip([f'0x{v:02X}' for v in unique[:5]], counts[:5]))}")

        print("="*70)

        # 推断实际采样率
        inferred_rate = total_bytes / actual_duration
        print(f"\n💡 推断实际采样率: {inferred_rate:.0f} Hz ({inferred_rate/1000:.1f} kHz)")

        if abs(inferred_rate - sample_rate) > sample_rate * 0.1:
            print(f"⚠️  实际采样率与设置值偏差 {abs(inferred_rate - sample_rate)/sample_rate*100:.0f}%！")

            # 尝试反推divider
            if inferred_rate > 0:
                inferred_divider = 60_000_000 / inferred_rate
                expected_divider = 60_000_000 / sample_rate
                print(f"\n🔧 Divider分析:")
                print(f"   预期divider: {expected_divider:.0f}")
                print(f"   推断divider: {inferred_divider:.0f}")
                print(f"   差异: {abs(inferred_divider - expected_divider):.0f}")
        else:
            print(f"✅ 实际采样率与设置值基本一致")

    except KeyboardInterrupt:
        print("\n\n用户中断")
    except Exception as e:
        print(f"❌ 错误: {e}")
        import traceback
        traceback.print_exc()
    finally:
        if 'ser' in locals() and ser.is_open:
            stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
            ser.write(stop_cmd)
            ser.close()

if __name__ == "__main__":
    print("=" * 70)
    print("🔬 采样率验证工具")
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

    # 测试多个采样率
    print("\n是否批量测试多个采样率？(y/n):", end=" ")
    batch = input().strip().lower() == 'y'

    if batch:
        test_rates = [
            100_000,   # 100 kHz
            200_000,   # 200 kHz
            400_000,   # 400 kHz (异常点)
            500_000,   # 500 kHz
            600_000,   # 600 kHz (异常点)
            800_000,   # 800 kHz
            1_000_000, # 1 MHz
        ]

        print("\n将测试以下采样率:")
        for rate in test_rates:
            print(f"  - {rate/1000:.0f} kHz")

        print("\n每个采样率采集5秒数据...\n")

        for rate in test_rates:
            print("\n" + "="*70)
            print(f"测试采样率: {rate/1000:.0f} kHz")
            print("="*70)
            analyze_sample_rate(selected_port, rate, duration=5)
            time.sleep(1)
    else:
        # 手动输入采样率
        print("\n请输入采样率 (Hz):", end=" ")
        try:
            sample_rate = int(input())
        except:
            print("❌ 无效输入")
            exit(1)

        analyze_sample_rate(selected_port, sample_rate, duration=10)
