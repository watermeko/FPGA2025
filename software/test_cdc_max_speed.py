#!/usr/bin/env python3
"""
CDC最大速率测试工具
测试USB CDC的真实吞吐能力，排查瓶颈
"""

import serial
import serial.tools.list_ports
import time
import threading

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

    print(f"采样率: {sample_rate_hz} Hz, 分频系数: {divider}")
    print(f"命令: {' '.join([f'{b:02X}' for b in full_cmd])}")

    return full_cmd

def test_read_methods(port, sample_rate):
    """测试不同的读取方法"""

    print("=" * 80)
    print("CDC 最大速率测试")
    print("=" * 80)

    try:
        # 测试不同的缓冲区配置
        for buffer_size in [4096, 8192, 16384, 32768]:
            print(f"\n{'='*80}")
            print(f"测试 read() 缓冲区大小: {buffer_size} bytes")
            print(f"{'='*80}")

            ser = serial.Serial(
                port=port,
                baudrate=115200,
                timeout=0.01,  # 10ms超时
                # write_timeout=1,
                # inter_byte_timeout=None
            )

            # 清空缓冲区
            ser.reset_input_buffer()
            ser.reset_output_buffer()

            # 发送启动命令
            cmd = generate_dc_start_command(sample_rate)
            ser.write(cmd)
            print(f"✅ 已发送START命令\n")

            time.sleep(0.2)  # 等待启动

            # 测试10秒
            total_bytes = 0
            start_time = time.time()
            test_duration = 10.0

            read_count = 0
            min_chunk = float('inf')
            max_chunk = 0
            chunk_sizes = []

            print(f"{'时间':<8} {'累计接收':<15} {'瞬时速率':<15} {'缓冲区大小':<12} {'读取次数':<10}")
            print("-" * 80)

            last_print = start_time
            last_total = 0

            while time.time() - start_time < test_duration:
                # 尝试读取
                waiting = ser.in_waiting
                if waiting > 0:
                    chunk = ser.read(min(waiting, buffer_size))
                    chunk_size = len(chunk)

                    if chunk_size > 0:
                        total_bytes += chunk_size
                        read_count += 1

                        min_chunk = min(min_chunk, chunk_size)
                        max_chunk = max(max_chunk, chunk_size)
                        chunk_sizes.append(chunk_size)

                # 每秒打印一次
                now = time.time()
                if now - last_print >= 1.0:
                    elapsed = now - start_time
                    new_bytes = total_bytes - last_total
                    instant_rate = new_bytes / (now - last_print)

                    print(f"{elapsed:7.1f}s {total_bytes:13,} B  "
                          f"{instant_rate/1024:>10.1f} KB/s  "
                          f"{waiting:10} B  "
                          f"{read_count:8}")

                    last_print = now
                    last_total = total_bytes

            elapsed = time.time() - start_time
            avg_rate = total_bytes / elapsed

            # 发送停止命令
            stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
            ser.write(stop_cmd)

            ser.close()

            # 统计
            print(f"\n结果统计 (缓冲区: {buffer_size} bytes):")
            print("-" * 80)
            print(f"总接收:       {total_bytes:,} bytes ({total_bytes/1024:.1f} KB)")
            print(f"测试时长:     {elapsed:.2f} 秒")
            print(f"平均速率:     {avg_rate/1024:.1f} KB/s ({avg_rate/1024/1024:.2f} MB/s)")
            print(f"读取次数:     {read_count}")
            print(f"平均块大小:   {total_bytes/read_count:.1f} bytes" if read_count > 0 else "N/A")
            print(f"最小块大小:   {min_chunk} bytes" if min_chunk != float('inf') else "N/A")
            print(f"最大块大小:   {max_chunk} bytes")

            # USB利用率
            USB_HIGH_SPEED_PRACTICAL = 40 * 1024 * 1024  # 40 MB/s
            usb_util = (avg_rate / USB_HIGH_SPEED_PRACTICAL * 100)
            print(f"\nUSB High-Speed利用率: {usb_util:.2f}%")

            if avg_rate < 100 * 1024:  # < 100 KB/s
                print("⚠️  速率异常低！可能的原因：")
                print("   1. Python读取速度不够")
                print("   2. 串口驱动配置问题")
                print("   3. FPGA端缓冲区太小")
            elif avg_rate < 1 * 1024 * 1024:  # < 1 MB/s
                print("⚠️  速率偏低，未达到High-Speed CDC能力")
            else:
                print("✅ 速率正常，接近CDC理论值")

            time.sleep(1)  # 等待FPGA复位

    except Exception as e:
        print(f"❌ 错误: {e}")
        import traceback
        traceback.print_exc()

def test_continuous_read(port, sample_rate, duration=30):
    """测试连续读取性能"""

    print("\n" + "=" * 80)
    print("持续读取测试（使用最优配置）")
    print("=" * 80)

    try:
        ser = serial.Serial(
            port=port,
            baudrate=115200,
            timeout=0.01
        )

        # 清空缓冲区
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        # 发送启动命令
        cmd = generate_dc_start_command(sample_rate)
        ser.write(cmd)
        print(f"✅ 已发送START命令\n")

        time.sleep(0.2)

        # 连续读取
        total_bytes = 0
        start_time = time.time()
        last_print = start_time
        last_total = 0

        rates = []

        print(f"{'时间':<8} {'累计接收':<15} {'瞬时速率':<15} {'平均速率':<15}")
        print("-" * 80)

        while time.time() - start_time < duration:
            waiting = ser.in_waiting
            if waiting > 0:
                chunk = ser.read(waiting)
                total_bytes += len(chunk)

            now = time.time()
            if now - last_print >= 1.0:
                elapsed = now - start_time
                new_bytes = total_bytes - last_total
                instant_rate = new_bytes / (now - last_print)
                avg_rate = total_bytes / elapsed

                rates.append(instant_rate)

                print(f"{elapsed:7.1f}s {total_bytes:13,} B  "
                      f"{instant_rate/1024:>10.1f} KB/s  "
                      f"{avg_rate/1024:>10.1f} KB/s")

                last_print = now
                last_total = total_bytes

        elapsed = time.time() - start_time
        avg_rate = total_bytes / elapsed

        # 发送停止命令
        stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
        ser.write(stop_cmd)
        ser.close()

        # 统计
        print(f"\n最终统计:")
        print("-" * 80)
        print(f"总接收:       {total_bytes:,} bytes ({total_bytes/1024:.1f} KB, {total_bytes/1024/1024:.2f} MB)")
        print(f"测试时长:     {elapsed:.2f} 秒")
        print(f"平均速率:     {avg_rate/1024:.1f} KB/s ({avg_rate/1024/1024:.2f} MB/s)")

        if len(rates) > 0:
            min_rate = min(rates)
            max_rate = max(rates)
            print(f"峰值速率:     {max_rate/1024:.1f} KB/s ({max_rate/1024/1024:.2f} MB/s)")
            print(f"最低速率:     {min_rate/1024:.1f} KB/s ({min_rate/1024/1024:.2f} MB/s)")
            print(f"速率方差:     {(max_rate - min_rate)/1024:.1f} KB/s")

        # USB利用率
        USB_HIGH_SPEED_PRACTICAL = 40 * 1024 * 1024
        usb_util = (avg_rate / USB_HIGH_SPEED_PRACTICAL * 100)
        print(f"\nUSB High-Speed利用率: {usb_util:.2f}%")

        # 判断
        if avg_rate > 10 * 1024 * 1024:  # > 10 MB/s
            print("✅ CDC性能优秀！")
        elif avg_rate > 1 * 1024 * 1024:  # > 1 MB/s
            print("✅ CDC性能良好")
        elif avg_rate > 100 * 1024:  # > 100 KB/s
            print("⚠️  CDC性能一般，存在优化空间")
        else:
            print("❌ CDC性能异常低！需要排查问题")

    except Exception as e:
        print(f"❌ 错误: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    print("=" * 80)
    print("🔬 CDC最大速率测试工具")
    print("=" * 80)

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

    # 选择测试模式
    print("\n选择测试模式:")
    print("1. 快速测试不同缓冲区大小（推荐）")
    print("2. 持续读取测试（30秒）")
    print("\n请输入模式编号:", end=" ")
    try:
        mode = int(input())
    except:
        mode = 1

    # 选择采样率
    print("\n选择采样率:")
    rates = [
        ("1 MHz", 1_000_000),
        ("500 kHz", 500_000),
        ("100 kHz", 100_000),
        ("10 kHz", 10_000),
    ]
    for i, (name, _) in enumerate(rates, 1):
        print(f"{i}. {name}")

    print("\n请输入采样率编号:", end=" ")
    try:
        rate_idx = int(input()) - 1
        selected_rate = rates[rate_idx][1]
    except:
        print("❌ 无效输入")
        exit(1)

    print("\n" + "=" * 80 + "\n")

    # 运行测试
    if mode == 1:
        test_read_methods(selected_port, selected_rate)
    else:
        test_continuous_read(selected_port, selected_rate)

    print("\n✅ 测试完成！")
