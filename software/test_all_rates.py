#!/usr/bin/env python3
"""
测试所有采样率的实际传输速率
"""
import usb.core
import time
import sys

EP_DC_IN = 0x83
EP_CMD_OUT = 0x01

def find_device():
    """查找 USB 设备"""
    dev = usb.core.find(idVendor=0x33aa, idProduct=0x0000)
    if not dev:
        print("❌ 设备未找到")
        print("请确保:")
        print("  1. FPGA 已上电")
        print("  2. USB 已连接")
        print("  3. WinUSB 驱动已安装")
        sys.exit(1)

    try:
        dev.set_configuration()
    except:
        pass

    return dev

def send_start_cmd(dev, divider):
    """发送采样开始命令"""
    cmd = bytes([
        0xAA, 0x55,           # Header
        0x0B,                 # CMD_DC_START
        0x00, 0x02,           # Length = 2
        (divider >> 8) & 0xFF,  # Divider high byte
        divider & 0xFF,         # Divider low byte
        0x00, 0x00            # Checksum + Status (not used)
    ])
    dev.write(EP_CMD_OUT, cmd)

def send_stop_cmd(dev):
    """发送采样停止命令"""
    cmd = bytes([
        0xAA, 0x55,           # Header
        0x0C,                 # CMD_DC_STOP
        0x00, 0x00,           # Length = 0
        0x00, 0x00            # Checksum + Status
    ])
    dev.write(EP_CMD_OUT, cmd)

def measure_rate(dev, duration=3.0):
    """测量传输速率"""
    start = time.time()
    total = 0
    timeouts = 0

    while time.time() - start < duration:
        try:
            data = dev.read(EP_DC_IN, 4096, timeout=100)
            total += len(data)
        except usb.core.USBTimeoutError:
            timeouts += 1
            if timeouts > 100:
                print("  ⚠️  过多超时，可能无数据传输")
                break
        except Exception as e:
            print(f"  ❌ USB 错误: {e}")
            break

    actual_duration = time.time() - start
    return total, actual_duration

def test_rate(dev, rate_mhz):
    """测试指定采样率"""
    divider = 60 // rate_mhz

    if divider < 1:
        divider = 1

    print(f"\n{'='*60}")
    print(f"测试采样率: {rate_mhz} MHz (分频器 = {divider})")
    print(f"{'='*60}")

    # 发送开始命令
    send_start_cmd(dev, divider)
    time.sleep(0.2)  # 等待启动

    # 测量速率
    print("测量中 (3 秒)...", end='', flush=True)
    total, duration = measure_rate(dev)
    print(" 完成")

    # 停止采样
    send_stop_cmd(dev)
    time.sleep(0.1)

    # 计算结果
    rate_kbps = total / duration / 1024
    expected_kbps = rate_mhz * 1024
    percentage = (rate_kbps / expected_kbps) * 100 if expected_kbps > 0 else 0

    # 显示结果
    print(f"实际速率: {rate_kbps:.1f} KB/s ({rate_kbps/1024:.2f} MB/s)")
    print(f"理论速率: {expected_kbps:.1f} KB/s ({expected_kbps/1024:.2f} MB/s)")
    print(f"完成度: {percentage:.1f}%")

    # 判断结果
    if percentage >= 90:
        print("✅ 通过 (≥90%)")
        status = "PASS"
    elif percentage >= 50:
        print("⚠️  警告 (50-90%)")
        status = "WARN"
    elif total == 0:
        print("❌ 失败 (无数据)")
        status = "FAIL"
    else:
        print("❌ 失败 (<50%)")
        status = "FAIL"

    return {
        'rate_mhz': rate_mhz,
        'divider': divider,
        'actual_kbps': rate_kbps,
        'expected_kbps': expected_kbps,
        'percentage': percentage,
        'status': status
    }

def main():
    print("USB Bulk 传输速率测试")
    print("="*60)

    dev = find_device()
    print("✅ 设备已连接")

    # 测试不同采样率
    rates = [1, 5, 10, 20, 30]
    results = []

    for rate in rates:
        result = test_rate(dev, rate)
        results.append(result)
        time.sleep(0.5)  # 间隔

    # 打印汇总表格
    print("\n" + "="*60)
    print("测试结果汇总")
    print("="*60)
    print(f"{'采样率':<10} {'实际速率':<15} {'理论速率':<15} {'完成度':<10} {'状态':<6}")
    print("-"*60)

    for r in results:
        print(f"{r['rate_mhz']:>3} MHz    "
              f"{r['actual_kbps']:>6.1f} KB/s    "
              f"{r['expected_kbps']:>6.1f} KB/s    "
              f"{r['percentage']:>5.1f}%     "
              f"{r['status']}")

    # 统计
    passed = sum(1 for r in results if r['status'] == 'PASS')
    warned = sum(1 for r in results if r['status'] == 'WARN')
    failed = sum(1 for r in results if r['status'] == 'FAIL')

    print("-"*60)
    print(f"总计: {passed} 通过, {warned} 警告, {failed} 失败")

    if failed == 0 and warned == 0:
        print("\n🎉 所有测试通过！")
    elif failed == 0:
        print("\n⚠️  部分测试有警告")
    else:
        print("\n❌ 部分测试失败")

    print("\n建议:")
    if any(r['percentage'] < 90 and r['rate_mhz'] <= 10 for r in results):
        print("- 10 MHz 以下速率未达标，检查 FIFO 配置")
    if any(r['percentage'] < 80 and r['rate_mhz'] >= 20 for r in results):
        print("- 20 MHz 以上速率受限，这接近 USB 2.0 Bulk 极限")
        print("- 如需更高速率，考虑切换到 ISO 传输")

if __name__ == '__main__':
    main()
