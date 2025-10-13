#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
JMD1.3C LCD驱动测试 (ST7789 240x240)
注意：需要DC引脚控制命令/数据模式
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
    """构建SPI命令帧"""
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

def send_spi_cmd(ser, cmd, params=[], description=""):
    """发送SPI命令（DC=0）+ 参数（DC=1）

    注意：当前实现假设DC引脚由上层控制
    实际应用中需要在命令和数据之间切换DC电平
    """
    # 发送命令字节 (需要 DC=0)
    frame = build_spi_frame([cmd])
    print(f"{description}")
    print(f"  CMD: 0x{cmd:02X} → {' '.join(f'{b:02X}' for b in frame)}")
    ser.write(frame)
    time.sleep(0.001)

    # 发送参数 (需要 DC=1)
    if params:
        frame = build_spi_frame(params)
        print(f"  DATA: {' '.join(f'0x{b:02X}' for b in params)} → {' '.join(f'{b:02X}' for b in frame)}")
        ser.write(frame)
        time.sleep(0.001)

def send_data_block(ser, data, description=""):
    """发送大块数据（DC=1）"""
    print(f"{description} ({len(data)} bytes)")

    # 分块发送，每次最大64字节
    chunk_size = 64
    for i in range(0, len(data), chunk_size):
        chunk = data[i:i+chunk_size]
        frame = build_spi_frame(chunk)
        ser.write(frame)
        if i % (chunk_size * 10) == 0:
            print(f"  进度: {i}/{len(data)} bytes")
        time.sleep(0.002)

# ============================================================================
# ST7789 命令定义
# ============================================================================
ST7789_NOP       = 0x00
ST7789_SWRESET   = 0x01  # 软件复位
ST7789_SLPIN     = 0x10  # 进入睡眠
ST7789_SLPOUT    = 0x11  # 退出睡眠
ST7789_INVOFF    = 0x20  # 反色关闭
ST7789_INVON     = 0x21  # 反色开启
ST7789_DISPOFF   = 0x28  # 关闭显示
ST7789_DISPON    = 0x29  # 打开显示
ST7789_CASET     = 0x2A  # 列地址设置
ST7789_RASET     = 0x2B  # 行地址设置
ST7789_RAMWR     = 0x2C  # 写显存
ST7789_MADCTL    = 0x36  # 内存访问控制
ST7789_COLMOD    = 0x3A  # 像素格式设置

def init_st7789(ser):
    """初始化ST7789"""
    print("\n" + "="*70)
    print("初始化 ST7789 (JMD1.3C)")
    print("="*70)

    # 软件复位
    send_spi_cmd(ser, ST7789_SWRESET, [], "1. 软件复位")
    time.sleep(0.15)

    # 退出睡眠模式
    send_spi_cmd(ser, ST7789_SLPOUT, [], "2. 退出睡眠模式")
    time.sleep(0.12)

    # 设置像素格式为 RGB565 (16位色)
    send_spi_cmd(ser, ST7789_COLMOD, [0x55], "3. 设置像素格式 RGB565")

    # 内存访问控制 (屏幕方向)
    # 0x00: 正常显示
    # 0x60: 横屏
    # 0xC0: 倒置
    send_spi_cmd(ser, ST7789_MADCTL, [0x00], "4. 设置屏幕方向")

    # 关闭反色
    send_spi_cmd(ser, ST7789_INVOFF, [], "5. 关闭反色")

    # 打开显示
    send_spi_cmd(ser, ST7789_DISPON, [], "6. 打开显示")
    time.sleep(0.02)

    print("\n初始化完成！\n")

def set_window(ser, x0, y0, x1, y1):
    """设置显示窗口"""
    # 列地址设置
    send_spi_cmd(ser, ST7789_CASET, [
        (x0 >> 8) & 0xFF, x0 & 0xFF,
        (x1 >> 8) & 0xFF, x1 & 0xFF
    ], f"设置列地址 ({x0}-{x1})")

    # 行地址设置
    send_spi_cmd(ser, ST7789_RASET, [
        (y0 >> 8) & 0xFF, y0 & 0xFF,
        (y1 >> 8) & 0xFF, y1 & 0xFF
    ], f"设置行地址 ({y0}-{y1})")

def fill_screen(ser, color):
    """填充屏幕 (RGB565颜色)"""
    print(f"\n填充屏幕颜色: 0x{color:04X}")

    # 设置全屏窗口
    set_window(ser, 0, 0, 239, 239)

    # 发送写RAM命令
    send_spi_cmd(ser, ST7789_RAMWR, [], "发送写RAM命令")

    # 生成颜色数据 (240x240 = 57600像素，每像素2字节 = 115200字节)
    color_high = (color >> 8) & 0xFF
    color_low = color & 0xFF
    pixel_data = [color_high, color_low] * (240 * 240)

    # 发送数据
    send_data_block(ser, pixel_data, "发送颜色数据")
    print("填充完成！")

def draw_gradient(ser):
    """绘制渐变色"""
    print("\n绘制RGB渐变")

    set_window(ser, 0, 0, 239, 239)
    send_spi_cmd(ser, ST7789_RAMWR, [], "发送写RAM命令")

    pixel_data = []
    for y in range(240):
        for x in range(240):
            # 生成渐变色 RGB565
            r = (x * 31) // 240  # 0-31 (5位)
            g = (y * 63) // 240  # 0-63 (6位)
            b = ((x + y) * 31) // 480  # 0-31 (5位)

            color = (r << 11) | (g << 5) | b
            pixel_data.append((color >> 8) & 0xFF)
            pixel_data.append(color & 0xFF)

    send_data_block(ser, pixel_data, "发送渐变数据")
    print("渐变绘制完成！")

# RGB565颜色定义
COLOR_BLACK   = 0x0000
COLOR_RED     = 0xF800
COLOR_GREEN   = 0x07E0
COLOR_BLUE    = 0x001F
COLOR_WHITE   = 0xFFFF
COLOR_YELLOW  = 0xFFE0
COLOR_MAGENTA = 0xF81F
COLOR_CYAN    = 0x07FF

def main():
    print("\n" + "="*70)
    print("JMD1.3C (ST7789) SPI LCD 驱动测试")
    print("="*70)
    print("\n⚠️  重要提示：")
    print("  1. 你的FPGA设计需要支持DC引脚控制！")
    print("  2. DC=0: 发送命令, DC=1: 发送数据")
    print("  3. 当前脚本假设你已经修改了SPI handler支持DC控制")
    print("\n  接线：")
    print("     - MOSI → LCD SDA")
    print("     - CLK  → LCD SCL")
    print("     - CS   → LCD CS")
    print("     - DC   → LCD DC (需要FPGA GPIO控制)")
    print("     - RST  → LCD RST (可以上拉或GPIO控制)")
    print("     - BL   → LCD BL (背光，接VCC或PWM)")
    print()

    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=TIMEOUT)
        print(f"✓ 串口 {SERIAL_PORT} 打开成功\n")
        time.sleep(0.5)
    except serial.SerialException as e:
        print(f"✗ 串口打开失败: {e}")
        sys.exit(1)

    # 初始化LCD
    init_st7789(ser)
    time.sleep(0.5)

    # 测试1: 填充纯色
    print("\n" + "="*70)
    print("测试1: 纯色填充")
    print("="*70)

    colors = [
        (COLOR_RED, "红色"),
        (COLOR_GREEN, "绿色"),
        (COLOR_BLUE, "蓝色"),
        (COLOR_WHITE, "白色"),
        (COLOR_BLACK, "黑色"),
    ]

    for color, name in colors:
        print(f"\n显示 {name}...")
        fill_screen(ser, color)
        time.sleep(1.5)

    # 测试2: 渐变色
    print("\n" + "="*70)
    print("测试2: RGB渐变")
    print("="*70)
    draw_gradient(ser)

    ser.close()
    print("\n" + "="*70)
    print("测试完成")
    print("="*70)

if __name__ == "__main__":
    main()
