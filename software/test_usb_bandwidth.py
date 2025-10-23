#!/usr/bin/env python3
"""
USB 带宽极限测试工具 - 测试真实的 USB High-Speed 吞吐量
"""

import usb.core
import usb.util
import time
import sys

# USB 设备标识
USB_VID = 0x33AA
USB_PID = 0x0000

# Endpoint 地址
EP_CTRL_OUT = 0x02
EP_DC_IN = 0x83

def get_usb_backend():
    """获取可用的 USB 后端"""
    backends_to_try = []
    try:
        import usb.backend.libusb1
        backend = usb.backend.libusb1.get_backend()
        if backend:
            backends_to_try.append(("libusb1", backend))
    except:
        pass
    try:
        import usb.backend.libusb0
        backend = usb.backend.libusb0.get_backend()
        if backend:
            backends_to_try.append(("libusb0", backend))
    except:
        pass
    return backends_to_try

def find_usb_device():
    """查找 USB 设备"""
    backends = get_usb_backend()
    for backend_name, backend in backends:
        try:
            dev = usb.core.find(idVendor=USB_VID, idProduct=USB_PID, backend=backend)
            if dev:
                print(f"✅ 使用 {backend_name} 后端找到设备")
                return dev, backend_name
        except:
            continue
    return None, None

def init_usb_device(dev):
    """初始化 USB 设备"""
    try:
        try:
            if dev.is_kernel_driver_active(0):
                dev.detach_kernel_driver(0)
        except:
            pass

        try:
            dev.set_configuration()
        except:
            pass
        return True
    except Exception as e:
        print(f"❌ 初始化错误: {e}")
        return False

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

    print(f"采样率: {sample_rate_hz/1e6:.2f} MHz (divider={divider})")
    print(f"预期数据速率: {sample_rate_hz/1024:.1f} KB/s ({sample_rate_hz/1024/1024:.2f} MB/s)")

    return full_cmd

def test_bandwidth(dev):
    """测试 USB 带宽"""
    print("\n" + "=" * 80)
    print("USB High-Speed 带宽极限测试")
    print("=" * 80)

    # 测试不同的采样率
    test_rates = [
        (100_000, "100 kHz", 2),      # 100 KB/s
        (500_000, "500 kHz", 2),      # 500 KB/s
        (1_000_000, "1 MHz", 3),      # 1 MB/s
        (5_000_000, "5 MHz", 3),      # 5 MB/s
        (10_000_000, "10 MHz", 5),    # 10 MB/s
        (20_000_000, "20 MHz", 5),    # 20 MB/s
        (30_000_000, "30 MHz", 5),    # 30 MB/s (极限)
    ]

    results = []

    for sample_rate, name, test_duration in test_rates:
        print(f"\n{'='*80}")
        print(f"测试采样率: {name}")
        print(f"{'='*80}")

        # 发送 STOP 命令
        stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
        dev.write(EP_CTRL_OUT, stop_cmd)
        time.sleep(0.1)

        # 发送 START 命令
        cmd = generate_dc_start_command(sample_rate)
        dev.write(EP_CTRL_OUT, cmd)
        time.sleep(0.5)  # 等待稳定

        # 测试数据速率
        total_bytes = 0
        start_time = time.time()
        test_end_time = start_time + test_duration

        read_size = 4096  # 增大读取缓冲区
        timeout_ms = 100

        print(f"开始测试 {test_duration} 秒...", end="", flush=True)

        while time.time() < test_end_time:
            try:
                data = dev.read(EP_DC_IN, read_size, timeout=timeout_ms)
                if data:
                    total_bytes += len(data)
            except usb.core.USBError as e:
                if e.errno == 110:  # ETIMEDOUT
                    continue
                else:
                    print(f"\n❌ USB 错误: {e}")
                    break

        elapsed = time.time() - start_time
        actual_rate = total_bytes / elapsed
        expected_rate = sample_rate
        efficiency = (actual_rate / expected_rate * 100) if expected_rate > 0 else 0

        print(f" 完成")
        print(f"  总数据量:   {total_bytes:,} bytes ({total_bytes/1024:.1f} KB)")
        print(f"  测试时间:   {elapsed:.2f} 秒")
        print(f"  实际速率:   {actual_rate/1024:.1f} KB/s ({actual_rate/1024/1024:.2f} MB/s)")
        print(f"  理论速率:   {expected_rate/1024:.1f} KB/s ({expected_rate/1024/1024:.2f} MB/s)")
        print(f"  效率:       {efficiency:.1f}%")

        results.append({
            'name': name,
            'sample_rate': sample_rate,
            'actual_rate': actual_rate,
            'expected_rate': expected_rate,
            'efficiency': efficiency,
            'total_bytes': total_bytes,
            'duration': elapsed
        })

        if efficiency < 50:
            print(f"  ⚠️  效率低于 50%，可能已达到瓶颈")
            break

    # 发送 STOP 命令
    stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
    dev.write(EP_CTRL_OUT, stop_cmd)

    # 汇总报告
    print("\n" + "=" * 80)
    print("测试结果汇总")
    print("=" * 80)
    print(f"{'采样率':<12} {'理论速率':<15} {'实际速率':<15} {'效率':<10} {'状态':<10}")
    print("-" * 80)

    for r in results:
        status = "✅ 正常" if r['efficiency'] > 90 else ("⚠️  偏低" if r['efficiency'] > 50 else "❌ 瓶颈")
        print(f"{r['name']:<12} "
              f"{r['expected_rate']/1024/1024:>6.2f} MB/s    "
              f"{r['actual_rate']/1024/1024:>6.2f} MB/s    "
              f"{r['efficiency']:>6.1f}%    "
              f"{status}")

    # 找到最大稳定速率
    stable_results = [r for r in results if r['efficiency'] > 90]
    if stable_results:
        max_stable = max(stable_results, key=lambda x: x['actual_rate'])
        print(f"\n💡 最大稳定吞吐: {max_stable['actual_rate']/1024/1024:.2f} MB/s @ {max_stable['name']}")

    print("=" * 80)

if __name__ == "__main__":
    print("=" * 80)
    print("USB High-Speed 带宽测试工具")
    print("=" * 80)

    dev, backend = find_usb_device()
    if not dev:
        print(f"\n❌ 未找到设备 (VID: 0x{USB_VID:04X}, PID: 0x{USB_PID:04X})")
        sys.exit(1)

    if not init_usb_device(dev):
        print("❌ USB 设备初始化失败")
        sys.exit(1)

    print("✅ USB 设备已就绪\n")

    try:
        test_bandwidth(dev)
    except KeyboardInterrupt:
        print("\n\n⚠️  测试被用户中断")
    except Exception as e:
        print(f"\n❌ 测试错误: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # 确保停止采样
        try:
            stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
            dev.write(EP_CTRL_OUT, stop_cmd)
            print("\n✅ 已发送 STOP 命令")
        except:
            pass
