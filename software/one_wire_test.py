#!/usr/bin/env python3
"""
1-Wire DS18B20 温度传感器测试脚本
适用于 FPGA2025 项目的 1-Wire 主机功能

依赖: pip install pyserial
"""

import serial
import time
import sys

class OneWireTester:
    def __init__(self, port='COM3', baudrate=115200):
        """初始化串口连接"""
        try:
            self.ser = serial.Serial(port, baudrate, timeout=2)
            print(f"✓ 串口 {port} 打开成功 (波特率: {baudrate})")
        except serial.SerialException as e:
            print(f"✗ 串口打开失败: {e}")
            sys.exit(1)

    def calc_checksum(self, data):
        """计算校验和（所有字节累加取低8位）"""
        return sum(data) & 0xFF

    def send_command(self, cmd_list, description=""):
        """发送命令"""
        cmd = cmd_list.copy()
        checksum = self.calc_checksum(cmd)
        cmd.append(checksum)

        if description:
            print(f"→ {description}")
        print(f"  发送: {' '.join([f'{b:02X}' for b in cmd])}")

        self.ser.write(bytes(cmd))
        time.sleep(0.05)  # 短暂延迟

    def read_response(self, expected_len=13):
        """读取响应数据"""
        response = self.ser.read(expected_len)
        if len(response) > 0:
            print(f"  接收: {' '.join([f'{b:02X}' for b in response])}")
            return response
        else:
            print(f"  接收: (无数据)")
            return None

    def test_reset(self):
        """测试1: 1-Wire 复位"""
        print("\n" + "="*60)
        print("测试 1: 1-Wire 总线复位")
        print("="*60)

        cmd = [0xAA, 0x55, 0x20, 0x00, 0x00]
        self.send_command(cmd, "复位总线并检测应答")
        time.sleep(0.01)
        print("✓ 复位命令已发送")

    def test_read_rom(self):
        """测试2: 读取ROM ID"""
        print("\n" + "="*60)
        print("测试 2: 读取 ROM ID (8字节)")
        print("="*60)

        # 复位
        cmd = [0xAA, 0x55, 0x20, 0x00, 0x00]
        self.send_command(cmd, "步骤1: 复位")
        time.sleep(0.01)

        # 读ROM命令 (0x33) - 写1字节读8字节
        cmd = [0xAA, 0x55, 0x23, 0x00, 0x03, 0x01, 0x08, 0x33]
        self.send_command(cmd, "步骤2: Read ROM (0x33)")

        # 读取响应
        response = self.read_response(13)  # 帧头(2) + 源(1) + 长度(2) + 数据(8) + 校验(1)

        if response and len(response) == 13:
            if response[0] == 0xAA and response[1] == 0x44:
                rom_id = response[5:13]
                print(f"\n✓ ROM ID: {' '.join([f'{b:02X}' for b in rom_id])}")

                # 解析ROM ID
                family_code = rom_id[0]
                serial_num = rom_id[1:7]
                crc = rom_id[7]

                print(f"  - 家族代码: 0x{family_code:02X}")
                print(f"  - 序列号: {' '.join([f'{b:02X}' for b in serial_num])}")
                print(f"  - CRC: 0x{crc:02X}")
            else:
                print("✗ 响应帧头错误")
        else:
            print("✗ 未收到响应或长度错误")

    def test_read_temperature(self):
        """测试3: 读取DS18B20温度"""
        print("\n" + "="*60)
        print("测试 3: DS18B20 温度读取")
        print("="*60)

        # 步骤1: 复位
        cmd = [0xAA, 0x55, 0x20, 0x00, 0x00]
        self.send_command(cmd, "步骤1: 复位总线")
        time.sleep(0.01)

        # 步骤2: Skip ROM (0xCC)
        cmd = [0xAA, 0x55, 0x21, 0x00, 0x01, 0xCC]
        self.send_command(cmd, "步骤2: Skip ROM (0xCC)")
        time.sleep(0.01)

        # 步骤3: Convert T (0x44)
        cmd = [0xAA, 0x55, 0x21, 0x00, 0x01, 0x44]
        self.send_command(cmd, "步骤3: Convert T (0x44)")
        print("  等待温度转换 (750ms)...")
        time.sleep(0.75)

        # 步骤4: 复位
        cmd = [0xAA, 0x55, 0x20, 0x00, 0x00]
        self.send_command(cmd, "步骤4: 复位总线")
        time.sleep(0.01)

        # 步骤5: Skip ROM
        cmd = [0xAA, 0x55, 0x21, 0x00, 0x01, 0xCC]
        self.send_command(cmd, "步骤5: Skip ROM (0xCC)")
        time.sleep(0.01)

        # 步骤6: Read Scratchpad (0xBE) - 写1读9
        cmd = [0xAA, 0x55, 0x23, 0x00, 0x03, 0x01, 0x09, 0xBE]
        self.send_command(cmd, "步骤6: Read Scratchpad (0xBE)")

        # 读取响应
        response = self.read_response(14)  # 帧头(2) + 源(1) + 长度(2) + 数据(9) + 校验(1)

        if response and len(response) >= 14:
            if response[0] == 0xAA and response[1] == 0x44:
                scratchpad = response[5:14]
                print(f"\n✓ 暂存器数据: {' '.join([f'{b:02X}' for b in scratchpad])}")

                # 解析温度
                temp_lsb = scratchpad[0]
                temp_msb = scratchpad[1]
                temp_raw = (temp_msb << 8) | temp_lsb

                # 处理负温度（补码）
                if temp_raw & 0x8000:
                    temp_raw = -(0x10000 - temp_raw)

                temperature = temp_raw / 16.0

                print(f"\n🌡️  温度: {temperature:.2f}°C")

                # 显示其他信息
                th = scratchpad[2]
                tl = scratchpad[3]
                config = scratchpad[4]
                crc = scratchpad[8]

                print(f"  - TH (高温报警): {th}°C")
                print(f"  - TL (低温报警): {tl}°C")
                print(f"  - 配置: 0x{config:02X}")
                print(f"  - CRC: 0x{crc:02X}")

                # 分辨率
                resolution_bits = ((config >> 5) & 0x03)
                resolution_map = {0: 9, 1: 10, 2: 11, 3: 12}
                resolution = resolution_map.get(resolution_bits, 12)
                print(f"  - 分辨率: {resolution}位")

            else:
                print("✗ 响应帧头错误")
        else:
            print("✗ 未收到响应或长度错误")

    def run_all_tests(self):
        """运行所有测试"""
        print("\n" + "█"*60)
        print("█" + " "*58 + "█")
        print("█  1-Wire Master 功能测试套件".ljust(59) + "█")
        print("█  FPGA2025 项目".ljust(59) + "█")
        print("█" + " "*58 + "█")
        print("█"*60 + "\n")

        try:
            # self.test_reset()
            # time.sleep(0.5)

            # self.test_read_rom()
            # time.sleep(0.5)

            self.test_read_temperature()

        except KeyboardInterrupt:
            print("\n\n⚠ 用户中断测试")
        except Exception as e:
            print(f"\n✗ 测试过程中发生错误: {e}")
        finally:
            print("\n" + "="*60)
            print("测试完成")
            print("="*60 + "\n")

    def close(self):
        """关闭串口"""
        if self.ser.is_open:
            self.ser.close()
            print("✓ 串口已关闭")

def main():
    """主函数"""
    import argparse

    parser = argparse.ArgumentParser(description='1-Wire DS18B20 测试工具')
    parser.add_argument('-p', '--port', default='COM3', help='串口号 (默认: COM3)')
    parser.add_argument('-b', '--baudrate', type=int, default=115200, help='波特率 (默认: 115200)')
    parser.add_argument('-t', '--test', choices=['reset', 'rom', 'temp', 'all'],
                        default='all', help='测试类型')

    args = parser.parse_args()

    tester = OneWireTester(args.port, args.baudrate)

    try:
        if args.test == 'reset':
            tester.test_reset()
        elif args.test == 'rom':
            tester.test_read_rom()
        elif args.test == 'temp':
            tester.test_read_temperature()
        else:
            tester.run_all_tests()
    finally:
        tester.close()

if __name__ == '__main__':
    main()
