#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SPI OLED 驱动测试 (SSD1306)
注意：此脚本假设OLED支持纯SPI协议，需要DC引脚由FPGA控制或者使用特殊的数据格式
"""

import serial
import time
import sys

SERIAL_PORT = "COM17"
BAUD_RATE = 115200
TIMEOUT = 2

FRAME_HEADER = [0xAA, 0x55]
CMD_SPI = 0x11

def calculate_checksum(data):
    """计算校验和"""
    return sum(data) & 0xFF

def build_spi_frame(write_data, read_len=0):
    """构建SPI命令帧

    格式：AA 55 11 [len_h] [len_l] [write_len] [read_len] [data...] [checksum]
    """
    write_len = len(write_data)
    payload = [write_len, read_len] + write_data
    payload_length = len(payload)

    frame_data = [
        CMD_SPI,
        (payload_length >> 8) & 0xFF,
        payload_length & 0xFF
    ] + payload

    checksum = calculate_checksum(frame_data)
    final_frame = FRAME_HEADER + frame_data + [checksum]
    return bytes(final_frame)

def send_spi_command(ser, data, description=""):
    """发送SPI命令"""
    frame = build_spi_frame(data)
    print(f"\n{description}")
    print(f"  发送: {' '.join(f'{b:02X}' for b in frame)}")
    ser.write(frame)
    ser.flush()
    time.sleep(0.05)

# ============================================================================
# SSD1306 OLED 初始化序列
# ============================================================================

# SSD1306命令（DC=0时发送）
SSD1306_DISPLAYOFF = 0xAE
SSD1306_SETDISPLAYCLOCKDIV = 0xD5
SSD1306_SETMULTIPLEX = 0xA8
SSD1306_SETDISPLAYOFFSET = 0xD3
SSD1306_SETSTARTLINE = 0x40
SSD1306_CHARGEPUMP = 0x8D
SSD1306_MEMORYMODE = 0x20
SSD1306_SEGREMAP = 0xA1
SSD1306_COMSCANDEC = 0xC8
SSD1306_SETCOMPINS = 0xDA
SSD1306_SETCONTRAST = 0x81
SSD1306_SETPRECHARGE = 0xD9
SSD1306_SETVCOMDETECT = 0xDB
SSD1306_DISPLAYALLON_RESUME = 0xA4
SSD1306_NORMALDISPLAY = 0xA6
SSD1306_DISPLAYON = 0xAF
SSD1306_COLUMNADDR = 0x21
SSD1306_PAGEADDR = 0x22

# 初始化序列
INIT_SEQUENCE = [
    ([SSD1306_DISPLAYOFF], "关闭显示"),
    ([SSD1306_SETDISPLAYCLOCKDIV, 0x80], "设置时钟分频"),
    ([SSD1306_SETMULTIPLEX, 0x3F], "设置复用率（64行）"),
    ([SSD1306_SETDISPLAYOFFSET, 0x00], "设置显示偏移为0"),
    ([SSD1306_SETSTARTLINE | 0x00], "设置起始行为0"),
    ([SSD1306_CHARGEPUMP, 0x14], "使能电荷泵"),
    ([SSD1306_MEMORYMODE, 0x00], "设置水平寻址模式"),
    ([SSD1306_SEGREMAP | 0x01], "列地址翻转"),
    ([SSD1306_COMSCANDEC], "行扫描反向"),
    ([SSD1306_SETCOMPINS, 0x12], "设置COM引脚配置"),
    ([SSD1306_SETCONTRAST, 0xCF], "设置对比度"),
    ([SSD1306_SETPRECHARGE, 0xF1], "设置预充电周期"),
    ([SSD1306_SETVCOMDETECT, 0x40], "设置VCOM检测"),
    ([SSD1306_DISPLAYALLON_RESUME], "恢复显示RAM内容"),
    ([SSD1306_NORMALDISPLAY], "正常显示模式"),
    ([SSD1306_DISPLAYON], "打开显示"),
]

def clear_screen(ser):
    """清屏：填充全0"""
    print("\n清屏操作...")
    # 设置列地址范围 0-127
    send_spi_command(ser, [SSD1306_COLUMNADDR, 0x00, 0x7F], "设置列地址")
    # 设置页地址范围 0-7 (8页 x 8行 = 64行)
    send_spi_command(ser, [SSD1306_PAGEADDR, 0x00, 0x07], "设置页地址")

    # 发送1024字节的0x00（128x64 / 8 = 1024）
    # 分块发送，每次发送64字节
    chunk_size = 64
    total_bytes = 1024
    for i in range(0, total_bytes, chunk_size):
        data = [0x00] * chunk_size
        send_spi_command(ser, data, f"清屏数据块 {i//chunk_size + 1}/{total_bytes//chunk_size}")
        time.sleep(0.02)

def fill_screen(ser, pattern=0xFF):
    """填充屏幕"""
    print(f"\n填充屏幕（图案: 0x{pattern:02X}）...")
    send_spi_command(ser, [SSD1306_COLUMNADDR, 0x00, 0x7F], "设置列地址")
    send_spi_command(ser, [SSD1306_PAGEADDR, 0x00, 0x07], "设置页地址")

    chunk_size = 64
    total_bytes = 1024
    for i in range(0, total_bytes, chunk_size):
        data = [pattern] * chunk_size
        send_spi_command(ser, data, f"填充数据块 {i//chunk_size + 1}/{total_bytes//chunk_size}")
        time.sleep(0.02)

def main():
    print("\n" + "="*70)
    print("SPI OLED (SSD1306) 驱动测试")
    print("="*70)
    print("\n⚠️  警告：")
    print("  1. 此脚本假设你的OLED支持4线SPI接口")
    print("  2. 需要DC引脚控制命令/数据模式")
    print("  3. 如果你的FPGA设计没有DC控制，此脚本可能无法工作")
    print("  4. 请确认你的OLED接线正确：")
    print("     - MOSI → FPGA SPI_MOSI")
    print("     - CLK  → FPGA SPI_CLK")
    print("     - CS   → FPGA SPI_CS")
    print("     - DC   → 需要额外GPIO控制")
    print("     - RES  → 需要额外GPIO控制或上拉\n")

    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=TIMEOUT)
        print(f"✓ 串口 {SERIAL_PORT} 打开成功\n")
        time.sleep(0.5)
    except serial.SerialException as e:
        print(f"✗ 串口打开失败: {e}")
        sys.exit(1)

    # 初始化OLED
    print("\n" + "="*70)
    print("步骤1: 初始化OLED")
    print("="*70)
    for cmd_data, description in INIT_SEQUENCE:
        send_spi_command(ser, cmd_data, description)
        time.sleep(0.01)

    print("\n初始化完成！")
    time.sleep(0.5)

    # 清屏测试
    print("\n" + "="*70)
    print("步骤2: 清屏测试")
    print("="*70)
    clear_screen(ser)
    time.sleep(1)

    # 填充测试
    print("\n" + "="*70)
    print("步骤3: 填充测试")
    print("="*70)

    # 棋盘格图案
    print("\n测试1: 棋盘格图案 (0x55)")
    fill_screen(ser, 0x55)
    time.sleep(2)

    print("\n测试2: 全亮 (0xFF)")
    fill_screen(ser, 0xFF)
    time.sleep(2)

    print("\n测试3: 清屏 (0x00)")
    clear_screen(ser)

    ser.close()
    print("\n" + "="*70)
    print("测试完成")
    print("="*70)

if __name__ == "__main__":
    main()
