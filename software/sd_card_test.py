#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SD Card SPI Test Script
用于通过FPGA的SPI接口测试SD卡的读写操作
"""

import serial
import time
import sys

# --- Configuration ---
SERIAL_PORT = "COM19"  # 修改为你的串口号
BAUD_RATE = 115200
TIMEOUT = 2

# Protocol Constants
FRAME_HEADER = [0xAA, 0x55]
CMD_SPI_WRITE = 0x11

# SD Card Command Indices
CMD0_GO_IDLE_STATE = 0
CMD8_SEND_IF_COND = 8
CMD55_APP_CMD = 55
ACMD41_SD_SEND_OP_COND = 41
CMD58_READ_OCR = 58
CMD17_READ_SINGLE_BLOCK = 17
CMD24_WRITE_BLOCK = 24

class SDCardSPI:
    """SD Card SPI Interface"""

    def __init__(self, port, baudrate=115200):
        """初始化串口连接"""
        try:
            self.ser = serial.Serial(port, baudrate, timeout=TIMEOUT)
            print(f"✓ 串口 {port} 打开成功 @ {baudrate} baud")
            time.sleep(0.5)  # 等待串口稳定
        except serial.SerialException as e:
            print(f"✗ 串口打开失败: {e}")
            sys.exit(1)

    def close(self):
        """关闭串口"""
        if self.ser and self.ser.is_open:
            self.ser.close()
            print("串口已关闭")

    def _calculate_crc7(self, data):
        """
        计算CRC7校验码（SD卡命令用）
        简化版本：对于CMD0和CMD8使用固定值，其他命令使用0xFF
        """
        if len(data) == 5:
            cmd_idx = data[0] & 0x3F
            if cmd_idx == 0:
                return 0x95
            elif cmd_idx == 8:
                return 0x87
        return 0xFF

    def _build_sd_command(self, cmd_index, arg=0x00000000):
        """
        构建SD卡命令（6字节）

        Args:
            cmd_index: 命令索引 (0-63)
            arg: 32位参数

        Returns:
            list: 6字节命令
        """
        cmd = [
            0x40 | cmd_index,           # 起始位 + 命令索引
            (arg >> 24) & 0xFF,         # 参数字节3
            (arg >> 16) & 0xFF,         # 参数字节2
            (arg >> 8) & 0xFF,          # 参数字节1
            arg & 0xFF,                 # 参数字节0
        ]
        crc = self._calculate_crc7(cmd)
        cmd.append(crc)
        return cmd

    def _build_spi_frame(self, write_data, read_len):
        """
        构建SPI命令帧

        Args:
            write_data: 要写入的字节列表
            read_len: 要读取的字节数

        Returns:
            bytes: 完整的协议帧
        """
        # Payload: [write_len, read_len, data...]
        write_len = len(write_data)
        payload = [write_len, read_len] + write_data
        payload_length = len(payload)

        # 构建帧（用于校验和计算）
        frame_data = [
            CMD_SPI_WRITE,
            (payload_length >> 8) & 0xFF,
            payload_length & 0xFF
        ] + payload

        # 计算校验和
        checksum = sum(frame_data) & 0xFF

        # 组装最终帧
        final_frame = FRAME_HEADER + frame_data + [checksum]
        return bytes(final_frame)

    def send_sd_command(self, cmd_index, arg=0, read_len=1, description="", wait_time=0.2):
        """
        发送SD卡命令并读取响应

        Args:
            cmd_index: SD命令索引
            arg: 命令参数
            read_len: 期望读取的字节数
            description: 命令描述
            wait_time: 等待响应的时间（秒）

        Returns:
            list: 读取到的数据，或None表示失败
        """
        # 构建SD命令
        sd_cmd = self._build_sd_command(cmd_index, arg)

        # 构建SPI帧
        frame = self._build_spi_frame(sd_cmd, read_len)

        print(f"\n→ 发送 CMD{cmd_index} {description}")
        print(f"  SD命令: {' '.join(f'{b:02X}' for b in sd_cmd)}")
        print(f"  完整帧: {' '.join(f'{b:02X}' for b in frame)}")
        print(f"  期望读取: {read_len} 字节")

        # 清空接收缓冲区
        if self.ser.in_waiting > 0:
            old_data = self.ser.read(self.ser.in_waiting)
            print(f"  清空旧数据: {len(old_data)} 字节")

        # 发送
        self.ser.write(frame)
        self.ser.flush()

        # 读取响应（多次尝试）
        time.sleep(wait_time)

        total_response = []
        max_attempts = 5
        for attempt in range(max_attempts):
            if self.ser.in_waiting > 0:
                response = self.ser.read(self.ser.in_waiting)
                total_response.extend(response)
                print(f"← 收到 {len(response)} 字节 (尝试 {attempt+1}): {' '.join(f'{b:02X}' for b in response)}")

                if len(total_response) >= read_len:
                    break

            if attempt < max_attempts - 1:
                time.sleep(0.1)

        if len(total_response) > 0:
            print(f"← 总共收到 {len(total_response)} 字节")
            return list(total_response)
        else:
            print("← 无响应")
            return None

    def send_dummy_clocks(self, count=10):
        """发送空时钟（0xFF字节）用于初始化"""
        print(f"\n→ 发送 {count} 个空时钟字节 (0xFF)")
        dummy_data = [0xFF] * count
        frame = self._build_spi_frame(dummy_data, 0)
        self.ser.write(frame)
        self.ser.flush()
        time.sleep(0.1)

    def initialize_sd_card(self):
        """SD卡初始化序列"""
        print("\n" + "="*60)
        print("开始 SD 卡初始化")
        print("="*60)

        # 1. 等待SD卡上电稳定（建议至少1ms，这里等待更长时间确保稳定）
        print("\n等待 SD 卡上电稳定...")
        time.sleep(0.1)

        # 1.5. 发送至少74个空时钟让SD卡进入原生模式
        # 注意：理想情况下需要在CS=1时连续发送，但我们的SPI模块每次传输会拉低CS
        # 作为变通方案，我们发送多组0xFF字节，让SD卡接收足够的时钟
        print("\n发送初始化时钟（多轮发送）...")
        for i in range(5):
            self.send_dummy_clocks(10)  # 每轮10字节 = 80个时钟
            time.sleep(0.05)
        print("  总共发送: 50字节 = 400个时钟")
        time.sleep(0.2)

        # 2. CMD0: 进入空闲状态 (多次尝试)
        print("\n尝试进入 SPI 模式 (CMD0)...")
        for attempt in range(5):
            print(f"  尝试 {attempt + 1}/5")
            resp = self.send_sd_command(CMD0_GO_IDLE_STATE, 0, 1, "(GO_IDLE_STATE)", wait_time=0.5)

            if resp and len(resp) > 0:
                print(f"  收到响应: 0x{resp[0]:02X}")
                if resp[0] == 0x01:
                    print("  ✓ SD卡进入空闲状态 (收到 0x01)")
                    break
                elif resp[0] == 0xFF:
                    print("  ⚠ 收到 0xFF (SD卡可能未就绪，继续尝试...)")
                else:
                    print(f"  ⚠ 收到意外响应: 0x{resp[0]:02X}")
            else:
                print("  ⚠ 无响应")

            time.sleep(0.2)
        else:
            print("  ✗ CMD0 失败，SD卡未进入 SPI 模式")
            return False

        # 3. CMD8: 检查电压范围（仅SDHC/SDXC需要）
        resp = self.send_sd_command(CMD8_SEND_IF_COND, 0x000001AA, 5, "(SEND_IF_COND)")

        # 4. CMD55 + ACMD41: 初始化过程
        for attempt in range(10):
            # 发送CMD55（应用命令前缀）
            resp = self.send_sd_command(CMD55_APP_CMD, 0, 1, "(APP_CMD)")

            # 发送ACMD41（SD卡初始化）
            resp = self.send_sd_command(ACMD41_SD_SEND_OP_COND, 0x40000000, 1, "(SD_SEND_OP_COND)")

            if resp and resp[0] == 0x00:
                print(f"  ✓ SD卡初始化完成 (尝试 {attempt+1})")
                break
            time.sleep(0.1)
        else:
            print("  ✗ ACMD41 初始化超时")
            return False

        # 5. CMD58: 读取OCR寄存器
        resp = self.send_sd_command(CMD58_READ_OCR, 0, 5, "(READ_OCR)")

        print("\n✓ SD卡初始化完成！")
        return True

    def write_single_block(self, block_addr, data):
        """
        写入单个512字节块

        Args:
            block_addr: 块地址
            data: 512字节数据（list或bytes）

        Returns:
            bool: 成功返回True
        """
        if len(data) != 512:
            print(f"✗ 数据必须是512字节，当前: {len(data)}")
            return False

        print(f"\n→ 写入块 {block_addr}")

        # 构建写命令 + 数据令牌 + 数据 + CRC
        sd_cmd = self._build_sd_command(CMD24_WRITE_BLOCK, block_addr)
        write_data = sd_cmd + [0xFE] + list(data) + [0xFF, 0xFF]  # 0xFE=数据令牌, 0xFFFF=CRC

        frame = self._build_spi_frame(write_data, 1)  # 读取1字节数据响应

        self.ser.write(frame)
        self.ser.flush()
        time.sleep(0.5)  # 等待写入完成

        if self.ser.in_waiting > 0:
            response = self.ser.read(self.ser.in_waiting)
            print(f"← 写响应: {' '.join(f'{b:02X}' for b in response)}")
            # 检查数据响应令牌 (0xX5 表示接受)
            if len(response) > 0 and (response[0] & 0x1F) == 0x05:
                print("✓ 写入成功")
                return True

        print("✗ 写入失败")
        return False

    def read_single_block(self, block_addr):
        """
        读取单个512字节块

        Args:
            block_addr: 块地址

        Returns:
            list: 512字节数据，失败返回None
        """
        print(f"\n→ 读取块 {block_addr}")

        # CMD17: 读单块
        sd_cmd = self._build_sd_command(CMD17_READ_SINGLE_BLOCK, block_addr)

        # 读取: R1响应(1) + 数据令牌(1) + 数据(512) + CRC(2) = 516字节
        frame = self._build_spi_frame(sd_cmd, 516)

        self.ser.write(frame)
        self.ser.flush()
        time.sleep(0.2)

        if self.ser.in_waiting > 0:
            response = self.ser.read(self.ser.in_waiting)
            print(f"← 读取 {len(response)} 字节")

            # 查找数据令牌 0xFE
            try:
                token_idx = response.index(0xFE)
                data = response[token_idx+1:token_idx+513]
                if len(data) == 512:
                    print("✓ 读取成功")
                    return list(data)
            except ValueError:
                pass

        print("✗ 读取失败")
        return None

def test_sd_card():
    """SD卡测试主程序"""
    print("\n" + "="*60)
    print("SD Card SPI 测试程序")
    print("="*60)

    # 创建SD卡接口
    sd = SDCardSPI(SERIAL_PORT, BAUD_RATE)

    try:
        # 1. 初始化SD卡
        if not sd.initialize_sd_card():
            print("\n✗ 初始化失败，退出")
            return

        # 2. 准备测试数据（512字节）
        test_data = [0x00] * 512
        for i in range(256):
            test_data[i] = i & 0xFF  # 前256字节: 0x00-0xFF
            test_data[i+256] = 0xFF - (i & 0xFF)  # 后256字节: 0xFF-0x00

        # 3. 写入数据到块0
        print("\n" + "-"*60)
        print("测试：写入数据到块 0")
        print("-"*60)
        if not sd.write_single_block(0, test_data):
            print("写入失败，跳过读取测试")
            return

        # 4. 读取块0数据
        print("\n" + "-"*60)
        print("测试：读取块 0 数据")
        print("-"*60)
        read_data = sd.read_single_block(0)

        if read_data:
            # 5. 验证数据
            print("\n" + "-"*60)
            print("验证数据完整性")
            print("-"*60)

            errors = 0
            for i in range(512):
                if read_data[i] != test_data[i]:
                    if errors < 10:  # 只显示前10个错误
                        print(f"  [0x{i:03X}] 期望: 0x{test_data[i]:02X}, 实际: 0x{read_data[i]:02X}")
                    errors += 1

            if errors == 0:
                print("✓ 数据验证通过！所有512字节匹配")
            else:
                print(f"✗ 发现 {errors} 个错误")

            # 显示前16字节
            print("\n前16字节数据:")
            print("  写入:", ' '.join(f'{b:02X}' for b in test_data[:16]))
            print("  读取:", ' '.join(f'{b:02X}' for b in read_data[:16]))

    finally:
        sd.close()
        print("\n测试完成")

if __name__ == "__main__":
    test_sd_card()
