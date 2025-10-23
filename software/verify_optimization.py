#!/usr/bin/env python3
"""
优化验证工具 - 快速验证高速优化是否生效
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
    if not backends:
        return None, None

    for backend_name, backend in backends:
        try:
            dev = usb.core.find(idVendor=USB_VID, idProduct=USB_PID, backend=backend)
            if dev:
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

    return full_cmd, divider

def quick_test(dev, sample_rate, test_duration=3):
    """快速测试指定采样率"""
    try:
        # 发送 STOP 命令
        stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
        dev.write(EP_CTRL_OUT, stop_cmd)
        time.sleep(0.1)

        # 发送 START 命令
        cmd, divider = generate_dc_start_command(sample_rate)
        dev.write(EP_CTRL_OUT, cmd)

        # 等待稳定
        if sample_rate > 1_000_000:
            time.sleep(1.5)
        else:
            time.sleep(0.5)

        # 测试数据速率
        total_bytes = 0
        start_time = time.time()
        test_end_time = start_time + test_duration

        read_size = 8192
        timeout_ms = 100
        consecutive_timeouts = 0

        while time.time() < test_end_time:
            try:
                data = dev.read(EP_DC_IN, read_size, timeout=timeout_ms)
                if data:
                    total_bytes += len(data)
                    consecutive_timeouts = 0
            except usb.core.USBError as e:
                if e.errno == 110 or e.errno is None:
                    consecutive_timeouts += 1
                    if consecutive_timeouts > 10:
                        time.sleep(0.001)
                    continue
                else:
                    raise

        elapsed = time.time() - start_time
        actual_rate = total_bytes / elapsed
        expected_rate = sample_rate
        efficiency = (actual_rate / expected_rate * 100) if expected_rate > 0 else 0

        # 发送 STOP 命令
        stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
        dev.write(EP_CTRL_OUT, stop_cmd)

        return {
            'success': True,
            'total_bytes': total_bytes,
            'duration': elapsed,
            'actual_rate': actual_rate,
            'expected_rate': expected_rate,
            'efficiency': efficiency,
            'divider': divider
        }

    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def main():
    print("=" * 80)
    print("🔬 Digital Capture 高速优化验证工具")
    print("=" * 80)

    # 查找设备
    print("\n正在查找 USB 设备...")
    dev, backend = find_usb_device()
    if not dev:
        print(f"❌ 未找到设备 (VID: 0x{USB_VID:04X}, PID: 0x{USB_PID:04X})")
        sys.exit(1)

    print(f"✅ 找到设备 (使用 {backend} 后端)")

    if not init_usb_device(dev):
        print("❌ USB 设备初始化失败")
        sys.exit(1)

    print("✅ USB 设备已就绪\n")

    # 验证测试
    print("=" * 80)
    print("开始验证测试")
    print("=" * 80)
    print()

    # 定义测试采样率
    test_rates = [
        (1_000_000, "1 MHz", "基准测试 (应该始终工作)"),
        (5_000_000, "5 MHz", "优化验证 (修改前会失败)"),
        (10_000_000, "10 MHz", "高速验证 (修改前会失败)"),
    ]

    results = []

    for sample_rate, name, description in test_rates:
        print(f"{'='*80}")
        print(f"测试 {name} - {description}")
        print(f"{'='*80}")

        result = quick_test(dev, sample_rate, test_duration=3)

        if result['success']:
            actual_rate = result['actual_rate']
            expected_rate = result['expected_rate']
            efficiency = result['efficiency']
            divider = result['divider']

            print(f"  分频系数:   {divider}")
            print(f"  实际速率:   {actual_rate/1024/1024:.2f} MB/s")
            print(f"  理论速率:   {expected_rate/1024/1024:.2f} MB/s")
            print(f"  效率:       {efficiency:.1f}%")

            # 判断状态
            if actual_rate < 1000:  # < 1 KB/s
                status = "❌ 失败 (速率为 0)"
                verdict = "FAILED"
            elif efficiency > 80:
                status = "✅ 优秀"
                verdict = "PASSED"
            elif efficiency > 50:
                status = "⚠️  可用"
                verdict = "MARGINAL"
            else:
                status = "❌ 不合格"
                verdict = "FAILED"

            print(f"  状态:       {status}")

            results.append({
                'name': name,
                'rate': sample_rate,
                'actual_rate': actual_rate,
                'efficiency': efficiency,
                'verdict': verdict,
                'status': status
            })
        else:
            print(f"  ❌ 测试失败: {result['error']}")
            results.append({
                'name': name,
                'rate': sample_rate,
                'verdict': 'ERROR',
                'error': result['error']
            })

        print()

    # 汇总结果
    print("=" * 80)
    print("验证结果汇总")
    print("=" * 80)
    print(f"{'采样率':<12} {'实际速率':<15} {'效率':<10} {'判定':<10} {'状态'}")
    print("-" * 80)

    for r in results:
        if r['verdict'] != 'ERROR':
            print(f"{r['name']:<12} "
                  f"{r['actual_rate']/1024/1024:>6.2f} MB/s    "
                  f"{r['efficiency']:>6.1f}%    "
                  f"{r['verdict']:<10} "
                  f"{r['status']}")
        else:
            print(f"{r['name']:<12} ERROR: {r['error']}")

    print("=" * 80)

    # 最终判定
    print("\n" + "=" * 80)
    print("🎯 最终判定")
    print("=" * 80)

    passed = [r for r in results if r['verdict'] == 'PASSED']
    failed = [r for r in results if r['verdict'] == 'FAILED']

    if len(passed) >= 2:  # 至少 5 MHz 和 10 MHz 通过
        print("✅ 优化成功！高速采样已正常工作")
        print(f"   - 通过测试: {len(passed)}/{len(results)}")
        print(f"   - 最高稳定速率: {max([r['actual_rate'] for r in passed])/1024/1024:.2f} MB/s")
        print("\n💡 建议: 可以运行 test_usb_bandwidth.py 进行完整性能测试")
    elif len(passed) == 1 and passed[0]['name'] == "1 MHz":
        print("❌ 优化未生效！仅 1 MHz 工作，高速采样失败")
        print("\n可能原因:")
        print("  1. 优化的 RTL 文件未正确替换")
        print("  2. FPGA 未重新综合和烧录")
        print("  3. 综合时出现错误")
        print("\n排查步骤:")
        print("  1. 检查 rtl/logic/digital_capture_handler.v 是否包含 'HIGH-SPEED OPTIMIZED VERSION'")
        print("  2. 在 GOWIN EDA 中重新综合项目")
        print("  3. 检查综合日志是否有错误")
        print("  4. 重新烧录 FPGA")
    else:
        print("❌ 测试失败！请检查 USB 连接和设备状态")

    print("=" * 80)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  测试被用户中断")
    except Exception as e:
        print(f"\n❌ 测试错误: {e}")
        import traceback
        traceback.print_exc()
