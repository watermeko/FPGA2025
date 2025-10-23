#!/usr/bin/env python3
"""
长时间稳定性测试
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
        (divider >> 8) & 0xFF,
        divider & 0xFF,
        0x00, 0x00
    ])
    dev.write(EP_CMD_OUT, cmd)

def send_stop_cmd(dev):
    """发送采样停止命令"""
    cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x00, 0x00])
    dev.write(EP_CMD_OUT, cmd)

def stability_test(dev, rate_mhz, duration_sec):
    """稳定性测试"""
    divider = 60 // rate_mhz
    if divider < 1:
        divider = 1

    print(f"稳定性测试: {rate_mhz} MHz, 持续 {duration_sec} 秒")
    print("="*60)

    # 启动采样
    send_start_cmd(dev, divider)
    time.sleep(0.2)

    start = time.time()
    total = 0
    errors = 0
    last_report = start

    try:
        while time.time() - start < duration_sec:
            try:
                data = dev.read(EP_DC_IN, 4096, timeout=100)
                total += len(data)

                # 每 10 秒报告一次
                if time.time() - last_report >= 10:
                    elapsed = time.time() - start
                    rate = total / elapsed / 1024 / 1024
                    print(f"[{elapsed:>5.0f}s] {rate:.2f} MB/s, 错误: {errors}")
                    last_report = time.time()

            except usb.core.USBTimeoutError:
                # 超时不算错误（可能暂时无数据）
                pass
            except Exception as e:
                errors += 1
                print(f"  ⚠️  USB 错误 ({errors}): {e}")
                if errors > 20:
                    print("  ❌ 错误过多，停止测试")
                    break
                time.sleep(0.1)

    except KeyboardInterrupt:
        print("\n⚠️  用户中断")

    finally:
        # 停止采样
        send_stop_cmd(dev)

    # 最终统计
    duration = time.time() - start
    rate_mbps = total / duration / 1024 / 1024
    expected_mbps = rate_mhz

    print("\n" + "="*60)
    print("测试结果")
    print("="*60)
    print(f"持续时间: {duration:.1f} 秒")
    print(f"总传输: {total / 1024 / 1024:.2f} MB")
    print(f"平均速率: {rate_mbps:.2f} MB/s")
    print(f"理论速率: {expected_mbps:.2f} MB/s")
    print(f"完成度: {(rate_mbps / expected_mbps * 100):.1f}%")
    print(f"错误次数: {errors}")

    if errors == 0 and rate_mbps >= expected_mbps * 0.9:
        print("✅ 稳定性测试通过")
    elif errors < 5:
        print("⚠️  稳定性测试有少量错误")
    else:
        print("❌ 稳定性测试失败")

def main():
    print("USB Bulk 长时间稳定性测试")
    print("="*60)

    dev = find_device()
    print("✅ 设备已连接\n")

    # 10 MHz, 5 分钟测试
    stability_test(dev, rate_mhz=10, duration_sec=300)

if __name__ == '__main__':
    main()
