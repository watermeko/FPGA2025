#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SPI从机命令生成和测试工具
作者: Claude
日期: 2025-10-24

功能：
1. 生成SPI从机预装数据命令（0x14）
2. 支持文本、十六进制、二进制数据
3. 可视化命令包
4. 串口通信测试（可选）
5. 预设常用数据模板
"""

import argparse
import struct
import sys
import time

try:
    import serial
    SERIAL_AVAILABLE = True
except ImportError:
    SERIAL_AVAILABLE = False
    print("警告: pyserial 未安装，串口功能不可用")
    print("安装: pip install pyserial")


class SPISlaveCommandGenerator:
    """SPI从机命令生成器"""

    FRAME_HEADER = b'\xAA\x55'
    CMD_SPI_PRELOAD = 0x14  # 配置从机发送缓冲区（主机读取）
    CMD_SPI_UPLOAD_CTRL = 0x15  # 控制从机上传使能（主机写入数据是否上传）
    MAX_DATA_LENGTH = 256

    def __init__(self):
        pass

    def calculate_checksum(self, data):
        """计算校验和（从命令码开始累加）"""
        return sum(data) & 0xFF

    def create_command(self, data, cmd_code=None):
        """创建SPI命令

        Args:
            data: bytes或bytearray，命令数据
            cmd_code: 命令码，默认0x14（预装数据）

        Returns:
            完整的命令包
        """
        if not isinstance(data, (bytes, bytearray)):
            raise TypeError("数据必须是bytes或bytearray类型")

        if cmd_code is None:
            cmd_code = self.CMD_SPI_PRELOAD

        data_len = len(data)
        if data_len < 1 or data_len > self.MAX_DATA_LENGTH:
            raise ValueError(f"数据长度必须在1-{self.MAX_DATA_LENGTH}字节之间，当前: {data_len}")

        # 构建完整命令包
        packet = bytearray()
        packet.extend(self.FRAME_HEADER)              # 帧头
        packet.append(cmd_code)                       # 命令码
        packet.extend(struct.pack('>H', data_len))    # 长度（大端）
        packet.extend(data)                           # Payload

        # 计算校验和
        checksum = self.calculate_checksum(packet[2:])
        packet.append(checksum)

        return bytes(packet)

    def create_upload_control(self, enable):
        """创建上传控制命令（0x15）

        Args:
            enable: True=启用上传, False=禁用上传

        Returns:
            完整的命令包
        """
        data = bytes([0x01 if enable else 0x00])
        return self.create_command(data, cmd_code=self.CMD_SPI_UPLOAD_CTRL)

    def parse_text(self, text_str):
        """解析文本字符串为字节数据"""
        return text_str.encode('utf-8')

    def parse_hex(self, hex_str):
        """解析十六进制字符串

        支持格式:
        - "48656C6C6F"
        - "48 65 6C 6C 6F"
        - "0x48 0x65 0x6C 0x6C 0x6F"
        """
        # 移除空格和0x前缀
        hex_str = hex_str.replace(' ', '').replace('0x', '').replace('0X', '')

        if len(hex_str) % 2 != 0:
            raise ValueError("十六进制字符串长度必须是偶数")

        try:
            return bytes.fromhex(hex_str)
        except ValueError:
            raise ValueError("无效的十六进制字符串")

    def parse_binary(self, bin_str):
        """解析二进制字符串

        支持格式:
        - "01001000" (单个字节)
        - "01001000 01000101" (多个字节)
        """
        bin_str = bin_str.replace(' ', '')

        if len(bin_str) % 8 != 0:
            raise ValueError("二进制字符串长度必须是8的倍数")

        if not all(c in '01' for c in bin_str):
            raise ValueError("二进制字符串只能包含0和1")

        data = bytearray()
        for i in range(0, len(bin_str), 8):
            byte_str = bin_str[i:i+8]
            data.append(int(byte_str, 2))

        return bytes(data)

    def create_sensor_id(self, device_type, serial_number, version):
        """创建传感器ID数据

        Args:
            device_type: 设备类型 (0-65535)
            serial_number: 序列号 (0-4294967295)
            version: 版本号 (0-65535)
        """
        return struct.pack('>HLH', device_type, serial_number, version)

    def create_config(self, sample_rate, gain, mode, enable):
        """创建配置参数数据

        Args:
            sample_rate: 采样率 (Hz)
            gain: 增益 (0-65535)
            mode: 模式 (0-255)
            enable: 使能 (0/1)
        """
        return struct.pack('>LHBB', sample_rate, gain, mode, enable)

    def create_status(self, temperature, voltage, flags):
        """创建状态寄存器数据

        Args:
            temperature: 温度 (°C × 100)
            voltage: 电压 (mV)
            flags: 状态标志位
        """
        return struct.pack('>HHB', temperature, voltage, flags)

    def create_lookup_table(self, table_type='square', size=16):
        """创建查找表

        Args:
            table_type: 表类型 ('square', 'sine', 'triangle')
            size: 表大小
        """
        if table_type == 'square':
            # 平方表
            return bytearray([i*i for i in range(size)])
        elif table_type == 'sine':
            # 正弦表 (0-255)
            import math
            return bytearray([
                int(127.5 + 127.5 * math.sin(2 * math.pi * i / size))
                for i in range(size)
            ])
        elif table_type == 'triangle':
            # 三角波表
            data = bytearray()
            for i in range(size):
                if i < size // 2:
                    data.append(int(255 * i / (size // 2)))
                else:
                    data.append(int(255 * (size - i) / (size // 2)))
            return data
        else:
            raise ValueError(f"未知的表类型: {table_type}")


def print_command_details(cmd):
    """打印命令详细信息"""
    print("\n" + "="*70)
    print("SPI从机预装数据命令")
    print("="*70)

    # 解析命令包
    header = cmd[0:2]
    cmd_code = cmd[2]
    length = struct.unpack('>H', cmd[3:5])[0]
    data = cmd[5:-1]
    checksum = cmd[-1]

    print(f"命令码:          0x{cmd_code:02X} (SPI从机预装)")
    print(f"数据长度:        {length} 字节")
    print(f"校验和:          0x{checksum:02X}")
    print()
    print(f"命令包长度:      {len(cmd)} 字节")
    print(f"命令包(Hex):     {' '.join(f'{b:02X}' for b in cmd)}")
    print()

    print("命令包结构:")
    print(f"  帧头:          {cmd[0]:02X} {cmd[1]:02X}")
    print(f"  命令码:        {cmd[2]:02X}")
    print(f"  长度:          {cmd[3]:02X} {cmd[4]:02X} ({struct.unpack('>H', cmd[3:5])[0]} 字节)")
    print(f"  数据:          {' '.join(f'{cmd[i]:02X}' for i in range(5, min(5+length, len(cmd)-1)))}")
    if length > 16:
        print(f"                 ... ({length - 16} more bytes)")
    print(f"  校验和:        {cmd[-1]:02X}")
    print()

    print("数据内容预览:")
    print(f"  Hex:           {data[:32].hex(' ')}" + (" ..." if len(data) > 32 else ""))

    # 尝试显示为文本
    try:
        text = data.decode('utf-8', errors='ignore')
        if text.isprintable():
            print(f"  Text:          {text[:64]}" + ("..." if len(text) > 64 else ""))
    except:
        pass

    print("="*70 + "\n")


def send_via_serial(port, baudrate, cmd, verbose=True):
    """通过串口发送命令"""
    if not SERIAL_AVAILABLE:
        print("错误: pyserial未安装")
        return False

    try:
        with serial.Serial(port, baudrate, timeout=1) as ser:
            if verbose:
                print(f"串口已打开: {port} @ {baudrate} baud")
            ser.write(cmd)
            if verbose:
                print(f"已发送 {len(cmd)} 字节")
            time.sleep(0.1)
            if ser.in_waiting > 0:
                response = ser.read(ser.in_waiting)
                if verbose:
                    print(f"收到响应 ({len(response)} 字节): {response.hex(' ')}")
            return True
    except serial.SerialException as e:
        print(f"串口错误: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description='SPI从机预装数据命令生成工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:

  # 1. 预装文本字符串（0x14命令，外部SPI主机读取）
  python %(prog)s --text "Hello SPI"

  # 2. 预装十六进制数据
  python %(prog)s --hex "48 65 6C 6C 6F"

  # 3. 预装二进制数据
  python %(prog)s --bin "01001000 01000101"

  # 4. 创建传感器ID
  python %(prog)s --sensor-id 0x1234 0xABCD5678 0x0102

  # 5. 创建配置参数
  python %(prog)s --config 1000000 128 3 1

  # 6. 创建状态寄存器
  python %(prog)s --status 2530 3300 0b10100001

  # 7. 创建查找表
  python %(prog)s --lut square 16
  python %(prog)s --lut sine 128

  # 8. 启用上传（0x15命令，外部SPI主机写入数据会上传到PC）
  python %(prog)s --upload-enable --port COM3

  # 9. 禁用上传
  python %(prog)s --upload-disable --port COM3

  # 10. 发送到串口
  python %(prog)s --text "Hello" --port COM3

  # 11. 保存到文件
  python %(prog)s --text "Hello" -o spi_cmd.bin
        """
    )

    # 数据输入方式（互斥）
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument('--text', type=str,
                            help='文本字符串')
    input_group.add_argument('--hex', type=str,
                            help='十六进制字符串 (如 "48 65 6C 6C 6F")')
    input_group.add_argument('--bin', type=str,
                            help='二进制字符串 (如 "01001000 01000101")')
    input_group.add_argument('--sensor-id', nargs=3, metavar=('TYPE', 'SERIAL', 'VER'),
                            help='传感器ID (设备类型 序列号 版本)')
    input_group.add_argument('--config', nargs=4, metavar=('RATE', 'GAIN', 'MODE', 'EN'),
                            help='配置参数 (采样率 增益 模式 使能)')
    input_group.add_argument('--status', nargs=3, metavar=('TEMP', 'VOLT', 'FLAGS'),
                            help='状态寄存器 (温度×100 电压mV 标志位)')
    input_group.add_argument('--lut', nargs=2, metavar=('TYPE', 'SIZE'),
                            help='查找表 (类型:square/sine/triangle 大小)')
    input_group.add_argument('--file', type=str,
                            help='从文件读取数据')
    input_group.add_argument('--upload-enable', action='store_true',
                            help='启用SPI从机数据上传 (0x15命令)')
    input_group.add_argument('--upload-disable', action='store_true',
                            help='禁用SPI从机数据上传 (0x15命令)')

    # 输出选项
    parser.add_argument('-o', '--output', type=str,
                        help='保存命令到文件')
    parser.add_argument('--port', type=str,
                        help='串口端口 (如 COM3)')
    parser.add_argument('--baud', type=int, default=115200,
                        help='波特率 (默认115200)')
    parser.add_argument('-q', '--quiet', action='store_true',
                        help='安静模式')

    args = parser.parse_args()

    gen = SPISlaveCommandGenerator()
    data = None

    try:
        # 根据输入类型解析数据
        if args.upload_enable:
            # 上传使能命令
            cmd = gen.create_upload_control(True)
            if not args.quiet:
                print("\n" + "="*70)
                print("SPI从机上传控制命令")
                print("="*70)
                print("命令码:          0x15 (上传控制)")
                print("操作:            启用上传")
                print("说明:            外部SPI主机写入的数据将通过USB-CDC上传到PC")
                print(f"命令包(Hex):     {' '.join(f'{b:02X}' for b in cmd)}")
                print("="*70 + "\n")
        elif args.upload_disable:
            # 上传禁用命令
            cmd = gen.create_upload_control(False)
            if not args.quiet:
                print("\n" + "="*70)
                print("SPI从机上传控制命令")
                print("="*70)
                print("命令码:          0x15 (上传控制)")
                print("操作:            禁用上传")
                print("说明:            外部SPI主机写入的数据不会上传")
                print(f"命令包(Hex):     {' '.join(f'{b:02X}' for b in cmd)}")
                print("="*70 + "\n")
        else:
            # 其他数据类型（0x14命令）
            if args.text:
                data = gen.parse_text(args.text)
            elif args.hex:
                data = gen.parse_hex(args.hex)
            elif args.bin:
                data = gen.parse_binary(args.bin)
            elif args.sensor_id:
                device_type = int(args.sensor_id[0], 0)
                serial_num = int(args.sensor_id[1], 0)
                version = int(args.sensor_id[2], 0)
                data = gen.create_sensor_id(device_type, serial_num, version)
            elif args.config:
                sample_rate = int(args.config[0])
                gain = int(args.config[1])
                mode = int(args.config[2], 0)
                enable = int(args.config[3], 0)
                data = gen.create_config(sample_rate, gain, mode, enable)
            elif args.status:
                temp = int(args.status[0])
                volt = int(args.status[1])
                flags = int(args.status[2], 0)
                data = gen.create_status(temp, volt, flags)
            elif args.lut:
                lut_type = args.lut[0]
                lut_size = int(args.lut[1])
                data = gen.create_lookup_table(lut_type, lut_size)
            elif args.file:
                with open(args.file, 'rb') as f:
                    data = f.read()

            # 创建命令
            cmd = gen.create_command(data)

            if not args.quiet:
                print_command_details(cmd)

        # 保存到文件
        if args.output:
            with open(args.output, 'wb') as f:
                f.write(cmd)
            print(f"命令已保存到: {args.output}")

        # 发送到串口
        if args.port:
            send_via_serial(args.port, args.baud, cmd, verbose=not args.quiet)

    except ValueError as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
