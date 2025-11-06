#!/usr/bin/env python3
"""
SEQ Command Tool - 自定义序列发生器配置工具
用于配置 8 通道自定义序列发生器，支持 USB 发送命令和实时监控
"""

import usb.core
import usb.util
import time
import sys
import argparse

# USB 设备标识 (根据 usb_descriptor.v 配置)
USB_VID = 0x33AA  # Gowin USB Vendor ID
USB_PID = 0x0000  # Product ID

# Endpoint 地址
EP_CTRL_OUT = 0x02  # EP2 OUT - 命令发送
EP_DATA_IN = 0x82   # EP2 IN  - 通用数据读取

# 系统时钟频率 (Hz)
SYSTEM_CLK = 60_000_000  # 60 MHz

def get_usb_backend():
    """获取可用的 USB 后端"""
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
    """列出所有匹配的 USB 设备"""
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
        try:
            if dev.is_kernel_driver_active(0):
                dev.detach_kernel_driver(0)
                print("✅ 已分离内核驱动")
        except (NotImplementedError, AttributeError):
            pass
        except Exception as e:
            pass

        # 设置配置
        try:
            dev.set_configuration()
            print(f"✅ USB 设备已配置")
        except usb.core.USBError as e:
            print(f"⚠️  设置配置时出现警告: {e}")
            print(f"   尝试继续...")

        return True
    except usb.core.USBError as e:
        print(f"❌ USB 初始化失败: {e}")
        return False
    except Exception as e:
        print(f"❌ 初始化错误: {e}")
        return False

def generate_seq_config_command(channel, enable, base_freq_hz, seq_data, seq_length):
    """
    生成 SEQ 配置命令

    参数:
        channel      : 通道索引 (0-7)
        enable       : 使能标志 (0=禁用, 1=使能)
        base_freq_hz : 基础频率 (Hz) - 每个 bit 的持续时间
        seq_data     : 序列数据 (整数或字符串)
        seq_length   : 序列长度 (1-64 bits)

    返回:
        bytes: 完整的命令帧

    命令格式:
        Header(2) + Command(1) + Length(2) + Payload(13) + Checksum(1)

    Payload 格式 (13 bytes):
        Byte 0:      Channel index [2:0] (0-7)
        Byte 1:      Enable flag (0=disable, 1=enable)
        Byte 2-3:    Frequency divider (16-bit, big-endian)
        Byte 4:      Sequence length in bits (1-64)
        Byte 5-12:   Sequence data (8 bytes, 64 bits, LSB first)
    """
    # 计算分频系数
    divider = SYSTEM_CLK // base_freq_hz
    if divider > 65535:
        divider = 65535
        print(f"⚠️  警告: 分频系数超过最大值，限制为 65535")
    if divider < 1:
        divider = 1
        print(f"⚠️  警告: 分频系数小于最小值，设置为 1")

    # 实际基础频率
    actual_freq = SYSTEM_CLK / divider

    # 计算序列重复频率
    seq_repeat_freq = actual_freq / seq_length if seq_length > 0 else 0

    # 命令头
    cmd_type = 0xF0  # SEQ_CONFIG
    len_h = 0x00
    len_l = 0x0D  # 13 bytes payload

    # Payload
    ch = channel & 0x07
    en = 1 if enable else 0
    div_h = (divider >> 8) & 0xFF
    div_l = divider & 0xFF
    length = seq_length & 0x7F

    # 处理序列数据
    if isinstance(seq_data, str):
        # 如果是字符串，尝试解析为二进制或十六进制
        if seq_data.startswith('0b'):
            seq_int = int(seq_data, 2)
        elif seq_data.startswith('0x'):
            seq_int = int(seq_data, 16)
        else:
            seq_int = int(seq_data, 2)  # 默认当二进制处理
    else:
        seq_int = seq_data

    # 将序列数据转换为 8 字节 (LSB first)
    seq_bytes = []
    for i in range(8):
        seq_bytes.append((seq_int >> (i * 8)) & 0xFF)

    # 构建完整payload
    payload = [ch, en, div_h, div_l, length] + seq_bytes

    # 计算校验和
    checksum = (cmd_type + len_h + len_l + sum(payload)) & 0xFF

    # 完整命令
    full_cmd = bytes([0xAA, 0x55, cmd_type, len_h, len_l] + payload + [checksum])

    # 打印信息
    print(f"\n{'='*80}")
    print(f"SEQ 配置命令 - 通道 {channel}")
    print(f"{'='*80}")
    print(f"使能状态:     {'启用' if enable else '禁用'}")
    print(f"基础频率:     {base_freq_hz:,} Hz ({base_freq_hz/1000:.3f} kHz)")
    print(f"实际频率:     {actual_freq:,.2f} Hz ({actual_freq/1000:.3f} kHz)")
    print(f"分频系数:     {divider}")
    print(f"序列长度:     {seq_length} bits")
    print(f"序列数据:     0x{seq_int:016X} (0b{seq_int:0{seq_length}b})")
    print(f"序列周期:     {seq_length / actual_freq * 1e6:.3f} us")
    print(f"重复频率:     {seq_repeat_freq:.2f} Hz ({seq_repeat_freq/1000:.3f} kHz)")
    print(f"\n命令帧: {' '.join([f'{b:02X}' for b in full_cmd])}")
    print(f"{'='*80}\n")

    return full_cmd

def send_seq_command(dev, channel, enable, base_freq_hz, seq_data, seq_length):
    """发送 SEQ 配置命令到 USB 设备"""
    try:
        cmd = generate_seq_config_command(channel, enable, base_freq_hz, seq_data, seq_length)

        # 发送命令到 EP2 OUT
        bytes_written = dev.write(EP_CTRL_OUT, cmd)

        if bytes_written == len(cmd):
            print(f"✅ 命令发送成功 ({bytes_written} bytes)")
            return True
        else:
            print(f"⚠️  发送字节数不匹配: {bytes_written}/{len(cmd)}")
            return False

    except usb.core.USBError as e:
        print(f"❌ USB 发送错误: {e}")
        return False
    except Exception as e:
        print(f"❌ 发送错误: {e}")
        import traceback
        traceback.print_exc()
        return False

def parse_sequence_string(seq_str):
    """
    解析序列字符串
    支持格式:
        - 二进制: "0101010101" 或 "0b0101010101"
        - 十六进制: "0x15A" 或 "15A"
        - 整数: "345"

    返回: (seq_data, seq_length)
    """
    seq_str = seq_str.strip()

    if seq_str.startswith('0b'):
        # 二进制
        seq_data = int(seq_str, 2)
        seq_length = len(seq_str) - 2
    elif seq_str.startswith('0x'):
        # 十六进制
        seq_data = int(seq_str, 16)
        seq_length = (len(seq_str) - 2) * 4
    else:
        # 尝试判断是二进制还是十进制
        if all(c in '01' for c in seq_str):
            # 全是 0 和 1，当二进制处理
            seq_data = int(seq_str, 2)
            seq_length = len(seq_str)
        else:
            # 包含其他字符，尝试十六进制
            try:
                seq_data = int(seq_str, 16)
                seq_length = len(seq_str) * 4
            except ValueError:
                # 最后尝试十进制
                seq_data = int(seq_str)
                seq_length = seq_data.bit_length()

    # 限制长度
    if seq_length > 64:
        print(f"⚠️  警告: 序列长度 {seq_length} 超过最大值 64，截断")
        seq_length = 64
        seq_data &= (1 << 64) - 1

    if seq_length < 1:
        print(f"⚠️  警告: 序列长度为 0，设置为 1")
        seq_length = 1

    return seq_data, seq_length

def interactive_mode(dev):
    """交互式配置模式"""
    print("\n" + "="*80)
    print("SEQ 交互式配置模式")
    print("="*80)

    while True:
        print("\n请输入配置参数 (输入 'q' 退出):")

        # 通道
        channel_str = input("  通道 (0-7): ").strip()
        if channel_str.lower() == 'q':
            break
        try:
            channel = int(channel_str)
            if channel < 0 or channel > 7:
                print("❌ 通道必须在 0-7 之间")
                continue
        except ValueError:
            print("❌ 无效的通道号")
            continue

        # 使能
        enable_str = input("  使能 (0=禁用, 1=启用): ").strip()
        if enable_str.lower() == 'q':
            break
        try:
            enable = int(enable_str)
        except ValueError:
            print("❌ 无效的使能值")
            continue

        # 基础频率
        freq_str = input("  基础频率 (Hz, 例如 1000000 表示 1MHz): ").strip()
        if freq_str.lower() == 'q':
            break
        try:
            base_freq_hz = int(freq_str)
        except ValueError:
            print("❌ 无效的频率值")
            continue

        # 序列数据
        seq_str = input("  序列数据 (二进制/十六进制/十进制, 例如 0b0101 或 0x15): ").strip()
        if seq_str.lower() == 'q':
            break
        try:
            seq_data, auto_length = parse_sequence_string(seq_str)
        except ValueError as e:
            print(f"❌ 无效的序列数据: {e}")
            continue

        # 序列长度
        length_str = input(f"  序列长度 (bits, 默认 {auto_length}): ").strip()
        if length_str.lower() == 'q':
            break
        if length_str == '':
            seq_length = auto_length
        else:
            try:
                seq_length = int(length_str)
            except ValueError:
                print("❌ 无效的长度值")
                continue

        # 发送命令
        success = send_seq_command(dev, channel, enable, base_freq_hz, seq_data, seq_length)

        if success:
            print("\n✅ 配置完成")
        else:
            print("\n❌ 配置失败")

        # 继续
        cont = input("\n继续配置? (y/n): ").strip().lower()
        if cont != 'y' and cont != 'yes' and cont != '':
            break

def main():
    parser = argparse.ArgumentParser(
        description='SEQ Command Tool - 自定义序列发生器配置工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 交互式模式
  python seq_command_tool.py

  # 配置通道 0: 1MHz 基础频率, 10-bit 序列 0b0101010101
  python seq_command_tool.py -c 0 -e 1 -f 1000000 -s 0b0101010101 -l 10

  # 配置通道 1: 100kHz 基础频率, 8-bit 序列 0xAA
  python seq_command_tool.py -c 1 -e 1 -f 100000 -s 0xAA -l 8

  # 禁用通道 2
  python seq_command_tool.py -c 2 -e 0

  # 配置通道 3: 10kHz 基础频率, 16-bit 序列 0xF0F0
  python seq_command_tool.py -c 3 -e 1 -f 10000 -s 0xF0F0 -l 16
        """
    )

    parser.add_argument('-c', '--channel', type=int,
                        help='通道索引 (0-7)')
    parser.add_argument('-e', '--enable', type=int, choices=[0, 1],
                        help='使能标志 (0=禁用, 1=启用)')
    parser.add_argument('-f', '--frequency', type=int,
                        help='基础频率 (Hz)')
    parser.add_argument('-s', '--sequence', type=str,
                        help='序列数据 (二进制/十六进制/十进制)')
    parser.add_argument('-l', '--length', type=int,
                        help='序列长度 (bits, 1-64)')

    args = parser.parse_args()

    print("=" * 80)
    print("SEQ Command Tool - 自定义序列发生器配置工具")
    print("=" * 80)

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

    # 判断模式
    if args.channel is not None:
        # 命令行模式
        channel = args.channel
        enable = args.enable if args.enable is not None else 1

        if args.enable == 0:
            # 禁用模式，不需要其他参数
            seq_data = 0
            seq_length = 1
            base_freq_hz = 1000
        else:
            # 启用模式，需要频率和序列
            if args.frequency is None or args.sequence is None:
                print("❌ 启用模式需要指定 --frequency 和 --sequence")
                sys.exit(1)

            base_freq_hz = args.frequency

            try:
                seq_data, auto_length = parse_sequence_string(args.sequence)
            except ValueError as e:
                print(f"❌ 无效的序列数据: {e}")
                sys.exit(1)

            seq_length = args.length if args.length is not None else auto_length

        # 发送命令
        success = send_seq_command(selected_dev, channel, enable, base_freq_hz, seq_data, seq_length)

        if success:
            print("✅ 配置完成")
        else:
            print("❌ 配置失败")
            sys.exit(1)
    else:
        # 交互式模式
        interactive_mode(selected_dev)

    print("\n" + "="*80)
    print("程序结束")
    print("="*80)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n用户中断")
        sys.exit(0)
