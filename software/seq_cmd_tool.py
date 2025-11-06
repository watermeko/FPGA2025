#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
序列发生器命令生成和测试工具
作者: Claude
日期: 2025-10-24

功能：
1. 生成序列发生器配置命令（0xF0）
2. 支持多通道配置
3. 可视化命令包
4. 串口通信测试（可选）
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


class SeqCommandGenerator:
    """序列发生器命令生成器"""

    FRAME_HEADER = b'\xAA\x55'
    CMD_SEQ_CONFIG = 0xF0
    DEFAULT_SYSTEM_CLK = 60_000_000  # 60MHz

    def __init__(self, system_clk_hz=DEFAULT_SYSTEM_CLK):
        self.system_clk_hz = system_clk_hz

    def calculate_freq_div(self, base_freq_hz):
        """计算频率分频器值"""
        if base_freq_hz <= 0:
            raise ValueError("基准频率必须大于0")

        freq_div = int(self.system_clk_hz // base_freq_hz)

        if freq_div < 1 or freq_div > 65535:
            raise ValueError(
                f"基准频率 {base_freq_hz}Hz 超出范围\n"
                f"有效范围: {self.system_clk_hz // 65535}Hz - {self.system_clk_hz}Hz"
            )

        return freq_div

    def parse_pattern(self, pattern_str):
        """解析位模式字符串

        支持格式:
        - 二进制: "0101010101"
        - 十六进制: "0x155" 或 "155"
        - 整数: 341
        """
        if isinstance(pattern_str, int):
            seq_data = pattern_str
            seq_len = seq_data.bit_length()
        elif pattern_str.startswith('0x') or pattern_str.startswith('0X'):
            # 十六进制
            seq_data = int(pattern_str, 16)
            seq_len = seq_data.bit_length()
        elif all(c in '01' for c in pattern_str):
            # 二进制字符串
            seq_len = len(pattern_str)
            seq_data = 0
            for i, bit in enumerate(pattern_str):
                if bit == '1':
                    seq_data |= (1 << i)
        else:
            # 尝试作为十进制整数
            try:
                seq_data = int(pattern_str)
                seq_len = seq_data.bit_length()
            except ValueError:
                raise ValueError(
                    f"无效的位模式: {pattern_str}\n"
                    "支持格式: 二进制'0101', 十六进制'0x155', 或整数"
                )

        if seq_len < 1 or seq_len > 64:
            raise ValueError(f"序列长度必须在1-64位之间，当前: {seq_len}")

        return seq_data, seq_len

    def create_command(self, channel, enable, base_freq_hz, pattern, length=None):
        """创建序列配置命令"""
        # 验证参数
        if channel < 0 or channel > 7:
            raise ValueError(f"通道号必须在0-7之间，当前: {channel}")

        # 计算频率分频器
        freq_div = self.calculate_freq_div(base_freq_hz)

        # 解析位模式
        seq_data, auto_len = self.parse_pattern(pattern)
        seq_len = length if length is not None else auto_len

        if seq_len < 1 or seq_len > 64:
            raise ValueError(f"序列长度必须在1-64位之间，当前: {seq_len}")

        # 构建Payload (13字节)
        payload = bytearray()
        payload.append(channel & 0x07)                # Byte 0: 通道
        payload.append(1 if enable else 0)            # Byte 1: 使能
        payload.extend(struct.pack('>H', freq_div))   # Byte 2-3: 分频器（大端）
        payload.append(seq_len & 0x7F)                # Byte 4: 序列长度
        payload.extend(struct.pack('<Q', seq_data))   # Byte 5-12: 序列数据（小端）

        # 构建完整命令包
        packet = bytearray()
        packet.extend(self.FRAME_HEADER)              # 帧头
        packet.append(self.CMD_SEQ_CONFIG)            # 命令码
        packet.extend(struct.pack('>H', len(payload))) # 长度（大端）
        packet.extend(payload)                        # Payload

        # 计算校验和
        checksum = sum(packet[2:]) & 0xFF
        packet.append(checksum)

        return bytes(packet)

    def get_command_info(self, channel, enable, base_freq_hz, pattern, length=None):
        """获取命令详细信息"""
        freq_div = self.calculate_freq_div(base_freq_hz)
        seq_data, auto_len = self.parse_pattern(pattern)
        seq_len = length if length is not None else auto_len

        output_freq_hz = base_freq_hz / seq_len
        bit_period_us = 1_000_000 / base_freq_hz
        seq_period_us = 1_000_000 / output_freq_hz

        return {
            'channel': channel,
            'enable': enable,
            'system_clk_hz': self.system_clk_hz,
            'base_freq_hz': base_freq_hz,
            'freq_div': freq_div,
            'pattern': pattern,
            'seq_data_hex': f"0x{seq_data:X}",
            'seq_data_bin': format(seq_data, f'0{seq_len}b'),
            'seq_len': seq_len,
            'output_freq_hz': output_freq_hz,
            'bit_period_us': bit_period_us,
            'seq_period_us': seq_period_us,
        }


def print_command_details(gen, channel, enable, base_freq_hz, pattern, length=None):
    """打印命令详细信息"""
    info = gen.get_command_info(channel, enable, base_freq_hz, pattern, length)
    cmd = gen.create_command(channel, enable, base_freq_hz, pattern, length)

    print("\n" + "="*70)
    print("序列发生器配置命令")
    print("="*70)
    print(f"通道:            {info['channel']}")
    print(f"使能:            {'是' if info['enable'] else '否'}")
    print(f"系统时钟:        {info['system_clk_hz']/1e6:.1f} MHz")
    print()
    print(f"基准频率:        {info['base_freq_hz']/1e3:.3f} kHz")
    print(f"频率分频器:      {info['freq_div']}")
    print(f"每位周期:        {info['bit_period_us']:.3f} us")
    print()
    print(f"序列长度:        {info['seq_len']} 位")
    print(f"序列数据(Hex):   {info['seq_data_hex']}")
    print(f"序列数据(Bin):   {info['seq_data_bin']}")
    print()
    print(f"输出频率:        {info['output_freq_hz']/1e3:.3f} kHz")
    print(f"序列周期:        {info['seq_period_us']:.3f} us")
    print()
    print(f"命令包长度:      {len(cmd)} 字节")
    print(f"命令包(Hex):     {' '.join(f'{b:02X}' for b in cmd)}")
    print()
    print("命令包结构:")
    print(f"  帧头:          {cmd[0]:02X} {cmd[1]:02X}")
    print(f"  命令码:        {cmd[2]:02X}")
    print(f"  长度:          {cmd[3]:02X} {cmd[4]:02X} ({struct.unpack('>H', cmd[3:5])[0]} 字节)")
    print(f"  通道:          {cmd[5]:02X} ({cmd[5] & 0x07})")
    print(f"  使能:          {cmd[6]:02X} ({'是' if cmd[6] else '否'})")
    print(f"  分频器:        {cmd[7]:02X} {cmd[8]:02X} ({struct.unpack('>H', cmd[7:9])[0]})")
    print(f"  序列长度:      {cmd[9]:02X} ({cmd[9]} 位)")
    print(f"  序列数据:      {' '.join(f'{cmd[i]:02X}' for i in range(10, 18))}")
    print(f"  校验和:        {cmd[18]:02X}")
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
                    print(f"收到响应 ({len(response)} 字节)")
            return True
    except serial.SerialException as e:
        print(f"串口错误: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description='序列发生器命令生成工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 生成命令: 通道0, 1MHz基准, 10位交替模式
  python %(prog)s -c 0 -f 1000000 -p "0101010101"

  # 使用十六进制模式
  python %(prog)s -c 1 -f 2000000 -p 0xCC -l 8

  # 禁用通道2
  python %(prog)s -c 2 --disable

  # 发送到串口
  python %(prog)s -c 0 -f 1000000 -p "0101" --port COM3

  # 保存到文件
  python %(prog)s -c 0 -f 1000000 -p "0101" -o cmd.bin
        """
    )

    parser.add_argument('-c', '--channel', type=int, required=True,
                        help='通道号 (0-7)')
    parser.add_argument('-f', '--freq', type=float, default=1000000,
                        help='基准频率 (Hz，默认1MHz)')
    parser.add_argument('-p', '--pattern', type=str, default="01",
                        help='位模式 (默认"01")')
    parser.add_argument('-l', '--length', type=int,
                        help='序列长度（可选）')
    parser.add_argument('--disable', action='store_true',
                        help='禁用通道')
    parser.add_argument('--sysclk', type=float, default=60_000_000,
                        help='系统时钟频率 (Hz，默认60MHz)')
    parser.add_argument('-o', '--output', type=str,
                        help='保存命令到文件')
    parser.add_argument('--port', type=str,
                        help='串口端口 (如 COM3)')
    parser.add_argument('--baud', type=int, default=115200,
                        help='波特率 (默认115200)')
    parser.add_argument('-q', '--quiet', action='store_true',
                        help='安静模式')

    args = parser.parse_args()

    gen = SeqCommandGenerator(system_clk_hz=args.sysclk)
    enable = not args.disable

    try:
        cmd = gen.create_command(
            channel=args.channel,
            enable=enable,
            base_freq_hz=args.freq,
            pattern=args.pattern,
            length=args.length
        )

        if not args.quiet:
            print_command_details(
                gen, args.channel, enable, args.freq, args.pattern, args.length
            )

        if args.output:
            with open(args.output, 'wb') as f:
                f.write(cmd)
            print(f"命令已保存到: {args.output}")

        if args.port:
            send_via_serial(args.port, args.baud, cmd, verbose=not args.quiet)

    except ValueError as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
