#!/usr/bin/env python3
"""
CDC极限速率测试工具
通过逐步提高采样率，找到CDC的真正传输极限
"""

import serial
import serial.tools.list_ports
import time

def generate_dc_start_command(sample_rate_hz):
    """生成DC启动命令"""
    SYSTEM_CLK = 60_000_000
    divider = SYSTEM_CLK // sample_rate_hz

    cmd = 0x0B
    len_h = 0x00
    len_l = 0x02
    div_h = (divider >> 8) & 0xFF
    div_l = divider & 0xFF

    checksum = (cmd + len_h + len_l + div_h + div_l) & 0xFF
    full_cmd = bytes([0xAA, 0x55, cmd, len_h, len_l, div_h, div_l, checksum])

    return full_cmd

def test_single_rate(ser, sample_rate, test_duration=10):
    """测试单个采样率"""

    # 清空缓冲区
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    # 发送启动命令
    cmd = generate_dc_start_command(sample_rate)
    ser.write(cmd)

    time.sleep(0.2)  # 等待启动

    # 测试
    total_bytes = 0
    start_time = time.time()
    stuck_time = 0
    last_total = 0
    last_check = start_time

    while time.time() - start_time < test_duration:
        waiting = ser.in_waiting
        if waiting > 0:
            chunk = ser.read(waiting)
            total_bytes += len(chunk)

        # 每秒检查一次
        now = time.time()
        if now - last_check >= 1.0:
            new_bytes = total_bytes - last_total

            # 检测是否卡住
            if new_bytes == 0:
                stuck_time += (now - last_check)
            else:
                stuck_time = 0

            # 如果卡住超过3秒，提前结束
            if stuck_time >= 3.0:
                break

            last_total = total_bytes
            last_check = now

    elapsed = time.time() - start_time

    # 发送停止命令
    stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
    ser.write(stop_cmd)
    time.sleep(0.1)

    # 计算结果
    avg_rate = total_bytes / elapsed if elapsed > 0 else 0
    expected_rate = sample_rate  # 期望速率（每秒采样数 = 每秒字节数）
    efficiency = (avg_rate / expected_rate * 100) if expected_rate > 0 else 0
    is_stuck = (stuck_time >= 3.0)

    return {
        'total_bytes': total_bytes,
        'elapsed': elapsed,
        'avg_rate': avg_rate,
        'expected_rate': expected_rate,
        'efficiency': efficiency,
        'is_stuck': is_stuck,
        'stuck_time': stuck_time
    }

def find_cdc_limit(port):
    """通过二分查找，找到CDC的极限速率"""

    print("=" * 80)
    print("CDC极限速率自动测试")
    print("=" * 80)
    print("\n策略：逐步提高采样率，找到能稳定传输的最大速率\n")

    # 测试采样率列表（从低到高）
    test_rates = [
        1_000,      # 1 kHz
        5_000,      # 5 kHz
        10_000,     # 10 kHz
        20_000,     # 20 kHz
        50_000,     # 50 kHz
        100_000,    # 100 kHz
        200_000,    # 200 kHz
        500_000,    # 500 kHz
        1_000_000,  # 1 MHz
    ]

    try:
        ser = serial.Serial(
            port=port,
            baudrate=115200,
            timeout=0.01
        )

        print(f"{'采样率':<12} {'期望速率':<12} {'实际速率':<12} {'效率':<8} {'状态':<10}")
        print("-" * 80)

        results = []
        max_stable_rate = 0

        for rate in test_rates:
            print(f"{rate/1000:>8.0f} kHz  ", end='', flush=True)
            print(f"{rate/1024:>8.1f} KB/s  ", end='', flush=True)

            result = test_single_rate(ser, rate, test_duration=10)
            results.append((rate, result))

            print(f"{result['avg_rate']/1024:>8.1f} KB/s  ", end='', flush=True)
            print(f"{result['efficiency']:>6.1f}%  ", end='', flush=True)

            if result['is_stuck']:
                print("❌ 卡住")
                print(f"\n⚠️  在 {rate/1000:.0f} kHz ({rate/1024:.1f} KB/s) 时发生死锁")
                break
            elif result['efficiency'] < 50:
                print("⚠️  丢包严重")
                print(f"\n⚠️  在 {rate/1000:.0f} kHz ({rate/1024:.1f} KB/s) 时效率低于50%")
                break
            elif result['efficiency'] < 90:
                print("⚠️  有丢包")
            else:
                print("✅ 正常")
                max_stable_rate = rate

            time.sleep(1)  # 等待FPGA复位

        ser.close()

        # 总结
        print("\n" + "=" * 80)
        print("测试总结")
        print("=" * 80)

        if max_stable_rate > 0:
            print(f"✅ CDC最大稳定速率: {max_stable_rate/1000:.0f} kHz ({max_stable_rate/1024:.1f} KB/s, {max_stable_rate/1024/1024:.2f} MB/s)")

            # 判断CDC能力
            if max_stable_rate >= 10_000_000:  # >= 10 MHz
                print("🎉 CDC性能极佳！达到了 10+ MB/s")
            elif max_stable_rate >= 1_000_000:  # >= 1 MHz
                print("✅ CDC性能良好，达到了 1+ MB/s")
            elif max_stable_rate >= 100_000:  # >= 100 kHz
                print("⚠️  CDC性能一般，只有 100+ KB/s")
            else:
                print("❌ CDC性能异常低，需要排查问题")

            # USB利用率
            USB_HIGH_SPEED = 40 * 1024 * 1024  # 40 MB/s实际极限
            util = (max_stable_rate / USB_HIGH_SPEED * 100)
            print(f"\nUSB High-Speed利用率: {util:.2f}%")

            if util < 1:
                print("❌ 严重未达到High-Speed CDC能力（应该能达到15-30 MB/s）")
                print("\n可能的瓶颈：")
                print("1. Arbiter FIFO太小（只有128字节）")
                print("2. Python读取速度限制")
                print("3. Windows驱动配置问题")
                print("4. FPGA端缓冲区配置问题")
            elif util < 10:
                print("⚠️  未达到High-Speed CDC理论能力")
            else:
                print("✅ 接近High-Speed CDC理论能力")
        else:
            print("❌ 所有测试都失败了，CDC无法正常工作")

        print("\n详细结果：")
        print(f"{'采样率':<12} {'实际速率':<15} {'效率':<8} {'状态':<10}")
        print("-" * 80)
        for rate, result in results:
            status = "卡住" if result['is_stuck'] else f"{result['efficiency']:.1f}%"
            print(f"{rate/1000:>8.0f} kHz  {result['avg_rate']/1024:>10.1f} KB/s  {result['efficiency']:>6.1f}%  {status}")

    except Exception as e:
        print(f"\n❌ 错误: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    print("=" * 80)
    print("🔬 CDC极限速率自动测试工具")
    print("=" * 80)
    print("\n本工具通过逐步提高采样率，自动找到CDC的真实传输极限")
    print("测试策略：从1 kHz开始，逐步提高到1 MHz，直到出现死锁或丢包\n")

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

    print("\n" + "=" * 80 + "\n")

    # 运行测试
    find_cdc_limit(selected_port)

    print("\n✅ 测试完成！")
