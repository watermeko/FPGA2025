#!/usr/bin/env python3
"""
SPI从机预装数据测试示例
演示如何通过USB CDC预装数据，然后由外部SPI主机读取
"""

import serial
import struct
import time

def calculate_checksum(data):
    """计算校验和（从功能码开始累加）"""
    return sum(data) & 0xFF

def send_command(ser, cmd, length, data):
    """发送命令到FPGA"""
    frame = bytearray([0xAA, 0x55, cmd])
    frame += struct.pack('>H', length)  # 大端模式
    frame += data
    checksum = calculate_checksum(frame[2:])
    frame.append(checksum)
    ser.write(frame)
    print(f"发送: {frame.hex(' ')}")
    return frame

# =============================================================================
# 测试场景1：预装简单文本数据
# =============================================================================
def test_preload_text():
    """预装文本数据示例"""
    print("\n" + "="*70)
    print("测试场景1：预装文本数据 'Hello SPI'")
    print("="*70)

    ser = serial.Serial('COM3', 115200, timeout=1)

    # 步骤1：预装数据到FPGA从机发送缓冲区
    test_data = b"Hello SPI"
    print(f"\n[步骤1] 预装数据: {test_data.decode()}")
    send_command(ser, 0x14, len(test_data), test_data)
    time.sleep(0.1)

    # 步骤2：提示用户
    print("\n[步骤2] 数据已预装到FPGA从机缓冲区")
    print("        现在可以用外部SPI主机读取这些数据")
    print("\n外部主机（如Arduino）代码示例：")
    print("""
    digitalWrite(SS, LOW);
    for(int i = 0; i < 9; i++) {
        char c = SPI.transfer(0x00);  // 读取一个字节
        Serial.print(c);
    }
    digitalWrite(SS, HIGH);
    // 输出: Hello SPI
    """)

    ser.close()

# =============================================================================
# 测试场景2：预装传感器ID数据
# =============================================================================
def test_preload_sensor_id():
    """预装传感器ID示例"""
    print("\n" + "="*70)
    print("测试场景2：预装传感器ID数据")
    print("="*70)

    ser = serial.Serial('COM3', 115200, timeout=1)

    # 模拟传感器ID：设备类型(2字节) + 序列号(4字节) + 版本(2字节)
    device_type = 0x1234
    serial_number = 0xABCD5678
    version = 0x0102

    sensor_id = struct.pack('>HLH', device_type, serial_number, version)

    print(f"\n[步骤1] 预装传感器ID:")
    print(f"        设备类型: 0x{device_type:04X}")
    print(f"        序列号:   0x{serial_number:08X}")
    print(f"        版本:     0x{version:04X}")

    send_command(ser, 0x14, len(sensor_id), sensor_id)
    time.sleep(0.1)

    print("\n[步骤2] 外部主机可以读取8字节传感器信息")

    ser.close()

# =============================================================================
# 测试场景3：预装查找表（LUT）
# =============================================================================
def test_preload_lookup_table():
    """预装查找表示例"""
    print("\n" + "="*70)
    print("测试场景3：预装查找表（平方表）")
    print("="*70)

    ser = serial.Serial('COM3', 115200, timeout=1)

    # 生成0-15的平方表
    lut_data = bytearray([i*i for i in range(16)])

    print(f"\n[步骤1] 预装查找表（0-15的平方）:")
    print(f"        数据: {' '.join(f'{x:3d}' for x in lut_data)}")

    send_command(ser, 0x14, len(lut_data), lut_data)
    time.sleep(0.1)

    print("\n[步骤2] 外部主机可以通过索引读取对应的平方值")
    print("        例如：读取索引5的数据 → 返回25")

    ser.close()

# =============================================================================
# 测试场景4：预装配置参数
# =============================================================================
def test_preload_config():
    """预装配置参数示例"""
    print("\n" + "="*70)
    print("测试场景4：预装设备配置参数")
    print("="*70)

    ser = serial.Serial('COM3', 115200, timeout=1)

    # 配置结构：采样率(4字节) + 增益(2字节) + 模式(1字节) + 使能(1字节)
    config = struct.pack('>LHBB',
        1000000,    # 采样率: 1MHz
        128,        # 增益: 128
        0x03,       # 模式: 连续采样
        0x01        # 使能: 启用
    )

    print(f"\n[步骤1] 预装配置参数:")
    print(f"        采样率: 1MHz")
    print(f"        增益:   128")
    print(f"        模式:   连续采样(0x03)")
    print(f"        使能:   启用(0x01)")

    send_command(ser, 0x14, len(config), config)
    time.sleep(0.1)

    print("\n[步骤2] 外部主机可以读取这些配置参数")

    ser.close()

# =============================================================================
# 测试场景5：预装固件版本信息
# =============================================================================
def test_preload_version():
    """预装固件版本信息示例"""
    print("\n" + "="*70)
    print("测试场景5：预装固件版本信息")
    print("="*70)

    ser = serial.Serial('COM3', 115200, timeout=1)

    # 版本字符串 + 版本号
    version_string = b"FPGA2025 v1.2.3"

    print(f"\n[步骤1] 预装版本信息:")
    print(f"        {version_string.decode()}")

    send_command(ser, 0x14, len(version_string), version_string)
    time.sleep(0.1)

    print("\n[步骤2] 外部主机可以读取版本信息进行识别")

    ser.close()

# =============================================================================
# 测试场景6：预装状态寄存器
# =============================================================================
def test_preload_status_register():
    """预装状态寄存器示例"""
    print("\n" + "="*70)
    print("测试场景6：预装状态寄存器（动态更新）")
    print("="*70)

    ser = serial.Serial('COM3', 115200, timeout=1)

    # 状态寄存器：温度(2字节) + 电压(2字节) + 状态标志(1字节)
    temperature = 2530  # 25.30°C (放大100倍)
    voltage = 3300      # 3.3V (单位mV)
    status_flags = 0b10100001  # bit7=ready, bit5=calibrated, bit0=power_on

    status_data = struct.pack('>HHB', temperature, voltage, status_flags)

    print(f"\n[步骤1] 预装当前状态:")
    print(f"        温度:     25.30°C")
    print(f"        电压:     3.3V")
    print(f"        状态:     0b{status_flags:08b}")
    print(f"                  - Ready: {bool(status_flags & 0x80)}")
    print(f"                  - Calibrated: {bool(status_flags & 0x20)}")
    print(f"                  - Power On: {bool(status_flags & 0x01)}")

    send_command(ser, 0x14, len(status_data), status_data)
    time.sleep(0.1)

    print("\n[步骤2] 外部主机可以定期读取状态")
    print("        注意：如果状态变化，需要重新发送0x14命令更新")

    ser.close()

# =============================================================================
# 测试场景7：预装大数据块（最大256字节）
# =============================================================================
def test_preload_large_data():
    """预装大数据块示例"""
    print("\n" + "="*70)
    print("测试场景7：预装大数据块（波形数据）")
    print("="*70)

    ser = serial.Serial('COM3', 115200, timeout=1)

    # 生成一个正弦波查找表（128个点）
    import math
    waveform = bytearray([
        int(127.5 + 127.5 * math.sin(2 * math.pi * i / 128))
        for i in range(128)
    ])

    print(f"\n[步骤1] 预装正弦波数据（128字节）:")
    print(f"        前10个采样点: {list(waveform[:10])}")

    send_command(ser, 0x14, len(waveform), waveform)
    time.sleep(0.1)

    print("\n[步骤2] 外部主机可以读取整个波形表用于DAC输出")

    ser.close()

# =============================================================================
# 主测试入口
# =============================================================================
def main():
    print("\n" + "#"*70)
    print("# SPI从机预装数据功能测试")
    print("# 功能码 0x14 - 配置从机发送缓冲区")
    print("#"*70)

    print("\n说明：")
    print("  1. 通过USB CDC发送0x14命令预装数据到FPGA从机缓冲区")
    print("  2. 外部SPI主机（如Arduino、STM32等）发起读取操作")
    print("  3. FPGA从机自动输出预装的数据")
    print("  4. 最大支持256字节数据")

    # 运行所有测试场景
    test_preload_text()
    test_preload_sensor_id()
    test_preload_lookup_table()
    test_preload_config()
    test_preload_version()
    test_preload_status_register()
    test_preload_large_data()

    print("\n" + "#"*70)
    print("# 所有测试场景演示完成")
    print("#"*70)
    print("\n提示：")
    print("  - 预装数据后会一直保存在缓冲区中")
    print("  - 可以随时重新发送0x14命令更新数据")
    print("  - 外部主机读取时，按字节顺序依次输出")
    print("  - 如果读取超过预装长度，会输出0xFF填充")

if __name__ == '__main__':
    main()
