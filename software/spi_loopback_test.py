#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SPI 回环测试 - 不依赖SD卡，测试FPGA的SPI和上传功能
可以用一根线把 MOSI 和 MISO 短接来测试
"""

import serial
import time
import sys

# --- Configuration ---
SERIAL_PORT = "COM17"
BAUD_RATE = 115200
TIMEOUT = 2

# Protocol Constants
FRAME_HEADER = [0xAA, 0x55]
CMD_SPI_WRITE = 0x11

def build_spi_frame(write_data, read_len):
    """构建SPI命令帧"""
    write_len = len(write_data)
    payload = [write_len, read_len] + write_data
    payload_length = len(payload)

    frame_data = [
        CMD_SPI_WRITE,
        (payload_length >> 8) & 0xFF,
        payload_length & 0xFF
    ] + payload

    checksum = sum(frame_data) & 0xFF
    final_frame = FRAME_HEADER + frame_data + [checksum]
    return bytes(final_frame)

def main():
    print("\n" + "="*70)
    print("SPI 回环测试")
    print("="*70)
    print("\n提示：")
    print("  1. 如果MOSI和MISO短接，读取的数据应该和写入的数据相同")
    print("  2. 如果没有短接，读取的数据取决于MISO的电平状态")
    print("  3. 这个测试主要验证FPGA的SPI和USB上传功能是否正常\n")

    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=TIMEOUT)
        print(f"✓ 串口 {SERIAL_PORT} 打开成功\n")
        time.sleep(0.5)
    except serial.SerialException as e:
        print(f"✗ 串口打开失败: {e}")
        sys.exit(1)

    tests = [
        {"name": "测试1: 写1字节(0xAA), 读1字节", "write": [0xAA], "read": 1},
        {"name": "测试2: 写4字节(DE AD BE EF), 读4字节", "write": [0xDE, 0xAD, 0xBE, 0xEF], "read": 4},
        {"name": "测试3: 只读2字节", "write": [], "read": 2},
        {"name": "测试4: 写入递增序列(00-0F), 读16字节", "write": list(range(16)), "read": 16},
    ]

    for idx, test in enumerate(tests, 1):
        print("-"*70)
        print(f"{test['name']}")
        print("-"*70)

        write_data = test['write']
        read_len = test['read']

        if write_data:
            print(f"写入: {' '.join(f'{b:02X}' for b in write_data)}")
        print(f"期望读取: {read_len} 字节")

        # 构建并发送帧
        frame = build_spi_frame(write_data, read_len)
        print(f"发送帧({len(frame)}字节): {' '.join(f'{b:02X}' for b in frame)}")

        # 清空旧数据
        if ser.in_waiting > 0:
            ser.read(ser.in_waiting)

        ser.write(frame)
        ser.flush()

        # 等待响应
        time.sleep(0.3)

        # 读取响应
        received = []
        for attempt in range(5):
            if ser.in_waiting > 0:
                data = ser.read(ser.in_waiting)
                received.extend(data)
                if len(received) >= read_len:
                    break
            time.sleep(0.1)

        if received:
            print(f"收到({len(received)}字节): {' '.join(f'{b:02X}' for b in received)}")

            # 如果是回环测试（MOSI-MISO短接），验证数据
            if write_data and len(received) == len(write_data):
                if list(received) == write_data:
                    print("✓ 数据匹配！(MOSI-MISO可能已短接)")
                else:
                    print("✗ 数据不匹配")
                    print(f"  期望: {' '.join(f'{b:02X}' for b in write_data)}")
                    print(f"  实际: {' '.join(f'{b:02X}' for b in received)}")
        else:
            print("✗ 无响应")

        print()

    ser.close()
    print("="*70)
    print("测试完成")
    print("="*70)

if __name__ == "__main__":
    main()
