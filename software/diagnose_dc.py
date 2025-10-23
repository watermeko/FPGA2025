#!/usr/bin/env python3
"""
DC 诊断工具 - 持续监控数据流，查看何时卡住
使用 WinUSB 通过 EP3 独立通道读取 Digital Capture 数据
"""

import usb.core
import usb.util
import time
import sys

# USB 设备标识 (根据 usb_descriptor.v 配置)
USB_VID = 0x33AA  # Gowin USB Vendor ID
USB_PID = 0x0000  # Product ID

# Endpoint 地址
EP_CTRL_OUT = 0x02  # EP2 OUT - 命令发送
EP_DC_IN = 0x83     # EP3 IN  - Digital Capture 数据读取
EP_DATA_IN = 0x82   # EP2 IN  - 通用数据读取 (备用)

def get_usb_backend():
    """获取可用的 USB 后端"""
    # 尝试多个后端，按优先级排序
    backends_to_try = []

    # 1. libusb1 (推荐，支持 WinUSB)
    try:
        import usb.backend.libusb1
        backend = usb.backend.libusb1.get_backend()
        if backend:
            backends_to_try.append(("libusb1", backend))
    except:
        pass

    # 2. libusb0 (备选)
    try:
        import usb.backend.libusb0
        backend = usb.backend.libusb0.get_backend()
        if backend:
            backends_to_try.append(("libusb0", backend))
    except:
        pass

    # 3. openusb (备选)
    try:
        import usb.backend.openusb
        backend = usb.backend.openusb.get_backend()
        if backend:
            backends_to_try.append(("openusb", backend))
    except:
        pass

    return backends_to_try

def find_usb_device():
    """查找 USB 设备 - 尝试多个后端"""
    backends = get_usb_backend()

    if not backends:
        print("❌ 没有可用的 USB 后端！")
        print("   请安装 libusb: https://github.com/libusb/libusb/releases")
        return None, None

    for backend_name, backend in backends:
        try:
            dev = usb.core.find(idVendor=USB_VID, idProduct=USB_PID, backend=backend)
            if dev:
                print(f"✅ 使用 {backend_name} 后端找到设备")
                return dev, backend_name
        except Exception as e:
            continue

    return None, None

def list_usb_devices():
    """列出所有匹配的 USB 设备 - 尝试多个后端"""
    backends = get_usb_backend()

    if not backends:
        return []

    all_devices = []
    for backend_name, backend in backends:
        try:
            devices = list(usb.core.find(find_all=True, idVendor=USB_VID, idProduct=USB_PID, backend=backend))
            if devices:
                print(f"✅ 使用 {backend_name} 后端")
                return devices
        except:
            continue

    return all_devices

def init_usb_device(dev):
    """初始化 USB 设备"""
    try:
        # Windows 下不需要分离内核驱动
        # 只在 Linux/macOS 上尝试分离
        try:
            if dev.is_kernel_driver_active(0):
                dev.detach_kernel_driver(0)
                print("✅ 已分离内核驱动")
        except (NotImplementedError, AttributeError):
            # Windows 不支持此操作，忽略
            pass
        except Exception as e:
            # 其他错误也忽略，继续尝试配置
            pass

        # 设置配置
        try:
            dev.set_configuration()
            print(f"✅ USB 设备已配置")
        except usb.core.USBError as e:
            # 配置可能已经设置，尝试继续
            print(f"⚠️  设置配置时出现警告: {e}")
            print(f"   尝试继续...")

        return True
    except usb.core.USBError as e:
        print(f"❌ USB 初始化失败: {e}")
        return False
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

    print(f"采样率: {sample_rate_hz} Hz, 分频系数: {divider}")
    print(f"命令: {' '.join([f'{b:02X}' for b in full_cmd])}")

    return full_cmd

def diagnose(dev, sample_rate):
    """诊断数据流 - 使用 EP3 独立通道"""
    try:
        # ===== 修复问题2：先发送STOP命令，确保模块回到IDLE状态 =====
        stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
        dev.write(EP_CTRL_OUT, stop_cmd)
        time.sleep(0.1)
        print("✅ 已发送 STOP 命令（清理前序状态）\n")

        # 发送启动命令到 EP2 OUT
        cmd = generate_dc_start_command(sample_rate)
        dev.write(EP_CTRL_OUT, cmd)
        print("✅ 已发送 START 命令到 EP2 OUT\n")

        # ===== 修复问题1：智能等待策略，根据采样率调整 =====
        if sample_rate > 200_000:
            # 高速采样：需要更长时间等待USB驱动稳定
            print(f"⏳ 高速采样模式 ({sample_rate/1000:.0f} kHz)，等待USB驱动稳定...")
            wait_time = 1.5
            time.sleep(wait_time)
        else:
            # 低速采样：等待至少10个采样周期
            wait_time = max(0.5, 10.0 / sample_rate)
            print(f"⏳ 等待FPGA初始化 ({wait_time:.2f}s)...")
            time.sleep(wait_time)

        # ===== 修复问题3：添加速率预警 =====
        expected_rate = sample_rate  # 1 byte per sample
        if expected_rate > 500_000:
            print(f"{'='*85}")
            print(f"⚠️  警告：采样率 {sample_rate/1000:.0f} kHz 超过USB带宽限制")
            print(f"    预期速率: {expected_rate/1024:.1f} KB/s ({expected_rate/1024/1024:.2f} MB/s)")
            print(f"    USB极限:  ~1200 KB/s (1.17 MB/s) [USB Full-Speed]")
            loss_rate = (expected_rate - 1.2e6) / expected_rate * 100
            if loss_rate > 0:
                print(f"    预计丢失: ~{loss_rate:.0f}% 数据")
            print(f"    建议: 降低采样率至 500 kHz 以下以避免数据丢失")
            print(f"{'='*85}\n")

        # 持续读取，监控数据流
        total = 0
        last_total = 0
        start_time = time.time()
        last_check = start_time
        stuck_count = 0
        peak_rate = 0  # 峰值速率
        min_rate = float('inf')  # 最低速率（排除0）
        timeout_count = 0

        # USB High-Speed 理论极限
        USB_HIGH_SPEED_MAX = 60 * 1024 * 1024  # 60 MB/s = 理论极限
        USB_HIGH_SPEED_PRACTICAL = 40 * 1024 * 1024  # 实际约 40 MB/s

        print("开始监控数据流 (按 Ctrl+C 停止)...\n")
        print(f"数据源: EP3 (0x{EP_DC_IN:02X}) - Digital Capture 独立通道")
        print(f"{'时间':<8} {'总字节':<12} {'本秒速率':<15} {'平均速率':<15} {'USB利用率':<12} {'状态':<10}")
        print("-" * 85)

        read_size = 512  # 每次读取的字节数 (可根据需要调整)
        timeout_ms = 100  # 超时时间 (毫秒)

        while True:
            # 从 EP3 读取数据
            try:
                data = dev.read(EP_DC_IN, read_size, timeout=timeout_ms)
                if data:
                    total += len(data)
                    timeout_count = 0  # 重置超时计数
            except usb.core.USBError as e:
                if e.errno == 110:  # ETIMEDOUT
                    timeout_count += 1
                    # 超时不算错误，只是暂时没有数据
                    pass
                else:
                    print(f"\n❌ USB 读取错误: {e}")
                    break

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

    except usb.core.USBError as e:
        print(f"\n❌ USB 错误: {e}")
    except Exception as e:
        print(f"\n❌ 错误: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # 发送停止命令
        try:
            stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
            dev.write(EP_CTRL_OUT, stop_cmd)
            print("\n✅ 已发送 STOP 命令")
        except:
            pass

if __name__ == "__main__":
    print("=" * 70)
    print("🔬 DC 数据流诊断工具 (WinUSB版本)")
    print("=" * 70)

    # 查找 USB 设备
    print("\n正在查找 USB 设备...")
    devices = list_usb_devices()

    if not devices:
        print(f"❌ 未找到 USB 设备 (VID: 0x{USB_VID:04X}, PID: 0x{USB_PID:04X})")
        print("\n请检查:")
        print("  1. FPGA 是否正确连接到 PC")
        print("  2. USB 设备是否已枚举")
        print("  3. Windows 是否已安装 WinUSB 驱动")
        print("\n提示: 可使用 Zadig 工具安装 WinUSB 驱动")
        sys.exit(1)

    print(f"\n找到 {len(devices)} 个匹配的设备:")
    for i, dev in enumerate(devices, 1):
        try:
            manufacturer = usb.util.get_string(dev, dev.iManufacturer) if dev.iManufacturer else "N/A"
            product = usb.util.get_string(dev, dev.iProduct) if dev.iProduct else "N/A"
            serial = usb.util.get_string(dev, dev.iSerialNumber) if dev.iSerialNumber else "N/A"
        except:
            manufacturer = "N/A"
            product = "N/A"
            serial = "N/A"

        print(f"{i}. Bus {dev.bus} Device {dev.address}")
        print(f"   制造商: {manufacturer}")
        print(f"   产品:   {product}")
        print(f"   序列号: {serial}")

    # 选择设备
    selected_dev = None
    if len(devices) == 1:
        selected_dev = devices[0]
        print(f"\n自动选择设备 1")
    else:
        print("\n请输入设备编号:", end=" ")
        try:
            dev_idx = int(input()) - 1
            selected_dev = devices[dev_idx]
        except:
            print("❌ 无效输入")
            sys.exit(1)

    # 初始化设备
    print(f"\n正在初始化 USB 设备...")
    if not init_usb_device(selected_dev):
        print("❌ USB 设备初始化失败")
        sys.exit(1)

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
        sys.exit(1)

    print("\n" + "=" * 70 + "\n")

    # 运行诊断
    diagnose(selected_dev, selected_rate)
