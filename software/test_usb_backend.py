#!/usr/bin/env python3
"""
USB 后端诊断工具 - 检查 PyUSB 配置和可用设备
"""

import sys

print("=" * 70)
print("USB 后端诊断工具")
print("=" * 70)

# 1. 检查 PyUSB 是否已安装
print("\n[1] 检查 PyUSB 安装...")
try:
    import usb.core
    import usb.util
    import usb.backend.libusb1
    print("✅ PyUSB 已安装")
except ImportError as e:
    print(f"❌ PyUSB 未安装: {e}")
    print("   请运行: pip install pyusb")
    sys.exit(1)

# 2. 检查可用的后端
print("\n[2] 检查可用的 USB 后端...")
backends = []

# 尝试 libusb1 (推荐)
try:
    backend = usb.backend.libusb1.get_backend()
    if backend:
        backends.append(("libusb1", backend))
        print(f"✅ libusb1 后端可用")
except Exception as e:
    print(f"❌ libusb1 后端不可用: {e}")

# 尝试 libusb0
try:
    import usb.backend.libusb0
    backend = usb.backend.libusb0.get_backend()
    if backend:
        backends.append(("libusb0", backend))
        print(f"✅ libusb0 后端可用")
except Exception as e:
    print(f"⚠️  libusb0 后端不可用: {e}")

# 尝试 openusb
try:
    import usb.backend.openusb
    backend = usb.backend.openusb.get_backend()
    if backend:
        backends.append(("openusb", backend))
        print(f"✅ openusb 后端可用")
except Exception as e:
    print(f"⚠️  openusb 后端不可用: {e}")

if not backends:
    print("\n" + "=" * 70)
    print("❌ 没有可用的 USB 后端！")
    print("=" * 70)
    print("\n解决方案 (Windows):")
    print("1. 下载 libusb-1.0.dll:")
    print("   https://github.com/libusb/libusb/releases")
    print("   (选择最新版本，下载 libusb-1.0.XX.7z)")
    print("\n2. 解压后，根据你的 Python 版本:")
    print("   - 64位 Python: 复制 VS2019/MS64/dll/libusb-1.0.dll")
    print("   - 32位 Python: 复制 VS2019/MS32/dll/libusb-1.0.dll")
    print("\n3. 将 dll 文件放到以下任一位置:")
    print("   - C:\\Windows\\System32\\")
    print("   - 你的 Python 安装目录")
    print("   - 脚本所在目录")
    print("\n或者使用 libusb-win32 (备选方案):")
    print("   在 Zadig 中选择 'libusb-win32' 驱动代替 'WinUSB'")
    print("=" * 70)
    sys.exit(1)

# 3. 枚举所有 USB 设备
print("\n[3] 枚举所有 USB 设备...")
for backend_name, backend in backends:
    print(f"\n使用后端: {backend_name}")
    try:
        devices = list(usb.core.find(find_all=True, backend=backend))
        print(f"找到 {len(devices)} 个 USB 设备")

        for i, dev in enumerate(devices[:10], 1):  # 只显示前10个
            try:
                mfr = usb.util.get_string(dev, dev.iManufacturer) if dev.iManufacturer else "N/A"
            except:
                mfr = "N/A"

            try:
                prod = usb.util.get_string(dev, dev.iProduct) if dev.iProduct else "N/A"
            except:
                prod = "N/A"

            print(f"  {i}. VID:0x{dev.idVendor:04X} PID:0x{dev.idProduct:04X} - {mfr} {prod}")

            # 特别标记我们的设备
            if dev.idVendor == 0x33AA and dev.idProduct == 0x0120:
                print(f"     ✅✅✅ 找到目标设备！ ✅✅✅")

        if len(devices) > 10:
            print(f"  ... 还有 {len(devices) - 10} 个设备未显示")

    except Exception as e:
        print(f"❌ 枚举设备失败: {e}")

# 4. 专门查找我们的设备
print("\n[4] 查找目标设备 (VID:0x33AA, PID:0x0120)...")
target_found = False

for backend_name, backend in backends:
    try:
        dev = usb.core.find(idVendor=0x33AA, idProduct=0x0120, backend=backend)
        if dev:
            target_found = True
            print(f"✅ 使用 {backend_name} 后端找到设备！")
            print(f"   Bus {dev.bus} Device {dev.address}")
            print(f"   配置数: {dev.bNumConfigurations}")
            print(f"   设备类: 0x{dev.bDeviceClass:02X}")
            print(f"   子类:   0x{dev.bDeviceSubClass:02X}")
            print(f"   协议:   0x{dev.bDeviceProtocol:02X}")

            # 尝试读取字符串描述符
            try:
                if dev.iManufacturer:
                    mfr = usb.util.get_string(dev, dev.iManufacturer)
                    print(f"   制造商: {mfr}")
            except:
                print(f"   制造商: (无法读取)")

            try:
                if dev.iProduct:
                    prod = usb.util.get_string(dev, dev.iProduct)
                    print(f"   产品:   {prod}")
            except:
                print(f"   产品:   (无法读取)")

            # 显示配置信息
            try:
                cfg = dev.get_active_configuration()
                print(f"\n   当前配置: {cfg.bConfigurationValue}")
                print(f"   接口数: {cfg.bNumInterfaces}")

                for intf in cfg:
                    print(f"\n   接口 {intf.bInterfaceNumber}:")
                    print(f"     端点数: {intf.bNumEndpoints}")
                    for ep in intf:
                        ep_addr = ep.bEndpointAddress
                        ep_type = ep.bmAttributes & 0x03
                        ep_dir = "IN" if ep_addr & 0x80 else "OUT"
                        ep_types = {0: "Control", 1: "Isochronous", 2: "Bulk", 3: "Interrupt"}
                        print(f"     EP 0x{ep_addr:02X} ({ep_dir}): {ep_types.get(ep_type, 'Unknown')}, MaxPacket={ep.wMaxPacketSize}")
            except Exception as e:
                print(f"\n   ⚠️  无法读取配置信息: {e}")
                print(f"   (可能需要设置配置或分离内核驱动)")

            break
    except Exception as e:
        print(f"⚠️  使用 {backend_name} 后端查找失败: {e}")

if not target_found:
    print("\n" + "=" * 70)
    print("❌ 未找到目标设备 (VID:0x33AA, PID:0x0120)")
    print("=" * 70)
    print("\n可能的原因:")
    print("1. 设备未正确枚举")
    print("   → 检查设备管理器，确认设备显示正常")
    print("\n2. 驱动安装问题")
    print("   → 在 Zadig 中，尝试切换到 'libusb-win32' 驱动")
    print("   → 或者重新安装 'WinUSB' 驱动")
    print("\n3. USB 后端无法访问 WinUSB 设备")
    print("   → 确保已安装 libusb-1.0.dll (见上面的说明)")
    print("\n4. 权限问题")
    print("   → 尝试以管理员身份运行脚本")
    print("=" * 70)
else:
    print("\n" + "=" * 70)
    print("✅ 诊断完成！设备已找到并可以访问")
    print("=" * 70)
    print("\n建议:")
    print(f"在你的脚本中使用 {backends[0][0]} 后端")
    print(f"\n示例代码:")
    print(f"import usb.core")
    print(f"import usb.backend.{backends[0][0].replace('libusb', 'libusb')}")
    print(f"backend = usb.backend.{backends[0][0].replace('libusb', 'libusb')}.get_backend()")
    print(f"dev = usb.core.find(idVendor=0x33AA, idProduct=0x0120, backend=backend)")
    print("=" * 70)
