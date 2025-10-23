#!/usr/bin/env python3
"""
USB 速度和配置检测工具
"""

import usb.core
import usb.util
import sys

# USB 设备标识
USB_VID = 0x33AA
USB_PID = 0x0000

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

print("=" * 80)
print("USB 速度和配置检测工具")
print("=" * 80)

# 查找设备
backends = get_usb_backend()
dev = None

for backend_name, backend in backends:
    try:
        dev = usb.core.find(idVendor=USB_VID, idProduct=USB_PID, backend=backend)
        if dev:
            print(f"\n✅ 使用 {backend_name} 后端找到设备")
            break
    except:
        continue

if not dev:
    print(f"\n❌ 未找到设备 (VID: 0x{USB_VID:04X}, PID: 0x{USB_PID:04X})")
    sys.exit(1)

# 基本信息
print("\n" + "=" * 80)
print("设备基本信息")
print("=" * 80)
print(f"Bus:           {dev.bus}")
print(f"Address:       {dev.address}")
print(f"VID:PID:       0x{dev.idVendor:04X}:0x{dev.idProduct:04X}")

try:
    if dev.iManufacturer:
        mfr = usb.util.get_string(dev, dev.iManufacturer)
        print(f"Manufacturer:  {mfr}")
except:
    print(f"Manufacturer:  (无法读取)")

try:
    if dev.iProduct:
        prod = usb.util.get_string(dev, dev.iProduct)
        print(f"Product:       {prod}")
except:
    print(f"Product:       (无法读取)")

# USB 速度 (关键信息！)
print("\n" + "=" * 80)
print("USB 速度检测 (关键)")
print("=" * 80)

try:
    speed = dev.speed
    speed_names = {
        None: "Unknown",
        1: "Low Speed (1.5 Mbps)",
        2: "Full Speed (12 Mbps)",
        3: "High Speed (480 Mbps)",
        4: "Super Speed (5 Gbps)",
        5: "Super Speed+ (10 Gbps)"
    }
    speed_name = speed_names.get(speed, f"Unknown ({speed})")
    print(f"USB Speed:     {speed_name}")

    if speed == 2:
        print("\n⚠️  警告: 设备运行在 Full-Speed 模式")
        print("   理论带宽: 1.2 MB/s (实际约 600-800 KB/s)")
        print("   建议: 检查为什么没有枚举为 High-Speed")
    elif speed == 3:
        print("\n✅ 设备运行在 High-Speed 模式")
        print("   理论带宽: 60 MB/s (实际约 30-40 MB/s)")
        print("   问题: RTL 代码中 EP3 MaxPacketSize 需要改为 512 字节")
    else:
        print(f"\n⚠️  未知速度: {speed}")

except Exception as e:
    print(f"❌ 无法读取速度: {e}")

# 配置信息
print("\n" + "=" * 80)
print("配置和端点信息")
print("=" * 80)

try:
    # 尝试设置配置
    try:
        dev.set_configuration()
    except:
        pass

    cfg = dev.get_active_configuration()
    print(f"\n当前配置: {cfg.bConfigurationValue}")
    print(f"接口数:     {cfg.bNumInterfaces}")

    for intf in cfg:
        print(f"\n  接口 {intf.bInterfaceNumber}:")
        print(f"    类:       0x{intf.bInterfaceClass:02X}")
        print(f"    子类:     0x{intf.bInterfaceSubClass:02X}")
        print(f"    协议:     0x{intf.bInterfaceProtocol:02X}")
        print(f"    端点数:   {intf.bNumEndpoints}")

        for ep in intf:
            ep_addr = ep.bEndpointAddress
            ep_type = ep.bmAttributes & 0x03
            ep_dir = "IN " if ep_addr & 0x80 else "OUT"
            ep_types = {0: "Control", 1: "Isochronous", 2: "Bulk", 3: "Interrupt"}
            ep_type_name = ep_types.get(ep_type, 'Unknown')
            max_packet = ep.wMaxPacketSize

            print(f"    EP 0x{ep_addr:02X} ({ep_dir}): {ep_type_name:12s} MaxPacket={max_packet:4d} bytes", end="")

            # 特别标记 EP3
            if ep_addr == 0x83:
                print(" ⭐ EP3 - Digital Capture")
                if max_packet == 64:
                    print(f"       ⚠️  MaxPacketSize = 64 (Full-Speed)")
                    print(f"       → 理论最大吞吐: ~600 KB/s")
                elif max_packet == 512:
                    print(f"       ✅ MaxPacketSize = 512 (High-Speed)")
                    print(f"       → 理论最大吞吐: ~30 MB/s")
                else:
                    print(f"       ❓ MaxPacketSize = {max_packet} (非标准)")
            else:
                print()

except Exception as e:
    print(f"❌ 读取配置失败: {e}")
    import traceback
    traceback.print_exc()

# 性能测试
print("\n" + "=" * 80)
print("性能预测")
print("=" * 80)

try:
    speed = dev.speed
    if speed == 2:  # Full-Speed
        print("当前速度: Full-Speed (12 Mbps)")
        print("EP3 MaxPacketSize: 64 bytes")
        print("预期吞吐: 600-800 KB/s")
        print("\n当前问题: 实际只有 6 KB/s")
        print("可能原因:")
        print("  1. FIFO 发送逻辑有延迟 (每包间隔 10ms)")
        print("  2. USB 轮询频率过低")
        print("  3. 数据生成速度不够")
        print("\n建议检查: rtl/usb/sync_fifo/usb_fifo.v 中的 EP3 发送状态机")

    elif speed == 3:  # High-Speed
        print("当前速度: High-Speed (480 Mbps)")
        print("\n如果 RTL 中 i_ep3_tx_max = 64:")
        print("  预期吞吐: ~6-10 MB/s (受限于 64 字节包)")
        print("\n如果修改为 i_ep3_tx_max = 512:")
        print("  预期吞吐: ~30-40 MB/s")
        print("\n当前问题: 实际只有 6 KB/s")
        print("  → RTL 代码中 i_ep3_tx_max 需要改为 512")
        print("  → 同时检查 FIFO 发送逻辑")

except:
    pass

print("\n" + "=" * 80)
print("下一步建议")
print("=" * 80)
print("1. 记录上面显示的 USB Speed")
print("2. 记录 EP3 的 MaxPacketSize")
print("3. 参考 software/usb_bandwidth_analysis.md 中的解决方案")
print("4. 修改 rtl/usb/usb_cdc.v:229 行的 i_ep3_tx_max 参数")
print("=" * 80)
