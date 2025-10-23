#!/usr/bin/env python3
"""
DC 诊断工具 - 持续监控数据流，查看何时卡住
"""

import serial
import serial.tools.list_ports
import time

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

    print(f"采样率: {sample_rate_hz} Hz, 分频系数: {divider}")
    print(f"命令: {' '.join([f'{b:02X}' for b in full_cmd])}")

    return full_cmd

def diagnose(port, sample_rate):
    """诊断数据流"""
    try:
        ser = serial.Serial(port, 115200, timeout=0.1)
        print(f"✅ 已连接到 {port}\n")

        # 发送启动命令
        cmd = generate_dc_start_command(sample_rate)
        ser.write(cmd)
        print("✅ 已发送 START 命令\n")

        time.sleep(0.5)

        # 持续读取，监控数据流
        total = 0
        last_total = 0
        start_time = time.time()
        last_check = start_time
        stuck_count = 0
        peak_rate = 0  # 峰值速率
        min_rate = float('inf')  # 最低速率（排除0）

        # USB High-Speed 理论极限 (你的FPGA支持High-Speed)
        USB_HIGH_SPEED_MAX = 60 * 1024 * 1024  # 60 MB/s = 理论极限
        USB_HIGH_SPEED_PRACTICAL = 40 * 1024 * 1024  # 实际约 40 MB/s
        # 但CDC协议限制实际吞吐率约10-50 KB/s

        print("开始监控数据流 (按 Ctrl+C 停止)...\n")
        print(f"{'时间':<8} {'总字节':<12} {'本秒速率':<15} {'平均速率':<15} {'USB利用率':<12} {'状态':<10}")
        print("-" * 85)

        while True:
            # 读取数据
            if ser.in_waiting > 0:
                data = ser.read(ser.in_waiting)
                total += len(data)

            # 每秒检查一次
            now = time.time()
            if now - last_check >= 1.0:
                elapsed = now - start_time
                new_bytes = total - last_total
                instant_rate = new_bytes / (now - last_check)  # 瞬时速率
                avg_rate = total / elapsed if elapsed > 0 else 0  # 平均速率

                # 更新峰值和最低速率
                if instant_rate > peak_rate:
                    peak_rate = instant_rate
                if instant_rate > 0 and instant_rate < min_rate:
                    min_rate = instant_rate

                # 计算 USB 带宽利用率
                usb_util = (instant_rate / USB_HIGH_SPEED_PRACTICAL * 100) if USB_HIGH_SPEED_PRACTICAL > 0 else 0

                # 检测是否卡住
                if new_bytes == 0:
                    stuck_count += 1
                    status = f"⚠️ 卡住 x{stuck_count}"
                else:
                    stuck_count = 0
                    if usb_util > 80:
                        status = "🔥 高负载"
                    elif usb_util > 50:
                        status = "⚡ 中负载"
                    else:
                        status = "✅ 正常"

                # 格式化速率显示
                instant_str = f"{instant_rate/1024:.1f} KB/s"
                avg_str = f"{avg_rate/1024:.1f} KB/s"
                util_str = f"{usb_util:.1f}%"

                print(f"{elapsed:7.1f}s {total:10,} B  {instant_str:>13}  {avg_str:>13}  {util_str:>10}  {status}")

                # 连续 3 秒卡住则报警
                if stuck_count >= 3:
                    print(f"\n{'='*85}")
                    print(f"❌ 检测到数据流卡住！已持续 {stuck_count} 秒")
                    print(f"{'='*85}")
                    print(f"总接收:     {total:,} bytes ({total/1024:.1f} KB)")
                    print(f"运行时间:   {elapsed:.1f} 秒")
                    print(f"平均速率:   {avg_rate/1024:.1f} KB/s ({avg_rate/1024/1024:.2f} MB/s)")
                    print(f"峰值速率:   {peak_rate/1024:.1f} KB/s ({peak_rate/1024/1024:.2f} MB/s)")
                    if min_rate != float('inf'):
                        print(f"最低速率:   {min_rate/1024:.1f} KB/s ({min_rate/1024/1024:.2f} MB/s)")
                    print(f"串口缓冲区: {ser.in_waiting} bytes")
                    print(f"\nUSB 带宽分析:")
                    print(f"  理论极限:   {USB_HIGH_SPEED_MAX/1024/1024:.2f} MB/s")
                    print(f"  实际极限:   {USB_HIGH_SPEED_PRACTICAL/1024/1024:.2f} MB/s")
                    print(f"  峰值利用率: {peak_rate/USB_HIGH_SPEED_PRACTICAL*100:.1f}%")
                    print(f"  平均利用率: {avg_rate/USB_HIGH_SPEED_PRACTICAL*100:.1f}%")
                    print(f"\n可能原因:")
                    if peak_rate > USB_HIGH_SPEED_PRACTICAL * 0.9:
                        print(f"  ✅ 已接近 USB High-Speed 极限 (>{USB_HIGH_SPEED_PRACTICAL/1024/1024:.1f} MB/s)")
                        print(f"  → 瓶颈：USB 物理带宽不足")
                        print(f"  → 建议：降低采样率")
                    elif peak_rate > 100*1024:  # > 100 KB/s
                        print(f"  ⚠️  USB 未达极限，但 FIFO 满导致死锁")
                        print(f"  → 瓶颈：FPGA 状态机死锁")
                        print(f"  → 建议：修改 RTL，添加丢弃机制")
                    else:
                        print(f"  ❓ USB 速率很低，可能其他问题")
                        print(f"  → 检查 USB 驱动、线缆质量")
                    print(f"{'='*85}\n")
                    break

                last_total = total
                last_check = now

            time.sleep(0.01)

    except KeyboardInterrupt:
        print("\n\n" + "="*85)
        print("用户中断")
        print("="*85)
        elapsed = time.time() - start_time
        avg_rate = total / elapsed if elapsed > 0 else 0

        print(f"总接收:     {total:,} bytes ({total/1024:.1f} KB)")
        print(f"运行时间:   {elapsed:.1f} 秒")
        print(f"平均速率:   {avg_rate/1024:.1f} KB/s ({avg_rate/1024/1024:.2f} MB/s)")
        print(f"峰值速率:   {peak_rate/1024:.1f} KB/s ({peak_rate/1024/1024:.2f} MB/s)")
        if min_rate != float('inf') and min_rate > 0:
            print(f"最低速率:   {min_rate/1024:.1f} KB/s ({min_rate/1024/1024:.2f} MB/s)")

        print(f"\nUSB 带宽分析:")
        print(f"  理论极限:   {USB_HIGH_SPEED_MAX/1024/1024:.2f} MB/s (100%)")
        print(f"  实际极限:   {USB_HIGH_SPEED_PRACTICAL/1024/1024:.2f} MB/s (~66%)")
        print(f"  峰值利用率: {peak_rate/USB_HIGH_SPEED_PRACTICAL*100:.1f}%")
        print(f"  平均利用率: {avg_rate/USB_HIGH_SPEED_PRACTICAL*100:.1f}%")

        if peak_rate > USB_HIGH_SPEED_PRACTICAL * 0.9:
            print(f"\n💡 结论: 已达到 USB High-Speed 带宽极限")
        elif peak_rate > USB_HIGH_SPEED_PRACTICAL * 0.5:
            print(f"\n💡 结论: USB 带宽利用中等，可能有优化空间")
        else:
            print(f"\n💡 结论: USB 带宽利用率低，瓶颈不在 USB")
        print("="*85)

    except Exception as e:
        print(f"❌ 错误: {e}")
    finally:
        if 'ser' in locals() and ser.is_open:
            # 发送停止命令
            stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
            ser.write(stop_cmd)
            print("\n✅ 已发送 STOP 命令")
            ser.close()

if __name__ == "__main__":
    print("=" * 70)
    print("🔬 DC 数据流诊断工具")
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

    # 选择采样率
    print("\n选择采样率:")
    rates = [
        ("1 kHz", 1000),
        ("2 kHz", 2000),
        ("5 kHz", 5000),
        ("10 kHz", 10000),
        ("20 kHz", 20000),
        ("50 kHz", 50000),
        ("100 kHz", 100000),
        ("200 kHz", 200000),
        ("400 kHz (divider=150)", 400000),
        ("500 kHz", 500000),
        ("600 kHz (divider=100)", 600000),
        ("1 MHz", 1000000),
        ("2 MHz", 2000000),
        ("5 MHz", 5000000),
        ("10 MHz", 10000000),
        ("20 MHz", 20000000),
        ("30 MHz (极限)", 30000000),
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

    print("\n" + "=" * 70 + "\n")

    # 运行诊断
    diagnose(selected_port, selected_rate)
