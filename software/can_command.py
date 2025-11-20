#!/usr/bin/env python3
"""
CAN总线命令生成工具
用于生成符合USB-CDC协议的CAN配置、发送和接收命令
"""

def calculate_checksum(data):
    """
    计算校验和（从功能码开始累加，包含所有数据）
    Args:
        data: 字节列表（不包含帧头0xAA55）
    Returns:
        校验和（取低8位）
    """
    return sum(data) & 0xFF

def can_config(local_id=0x001, rx_id=0x002, baudrate_pts=34):
    """
    生成CAN配置命令（功能码 0x27）

    Args:
        local_id: 本地发送ID (11位，0x000-0x7FF)
        rx_id: 接收过滤器ID (11位，0x000-0x7FF)
        baudrate_pts: 时序参数c_pts (默认34 → 1.224Mbps @ 60MHz)

    Returns:
        十六进制字符串命令
    """
    if local_id > 0x7FF or rx_id > 0x7FF:
        raise ValueError("CAN ID必须在0x000-0x7FF范围内（11位）")

    # 数据体（16字节）
    cmd = [
        0x27,                                      # 功能码
        0x00, 0x10,                                # 数据长度=16字节（大端）
        local_id & 0xFF, (local_id >> 8) & 0x07,  # 本地ID（小端，低字节在前）
        rx_id & 0xFF, (rx_id >> 8) & 0x07,        # 接收过滤器（小端）
        0xFF, 0x07,                                # 接收掩码=0x7FF（小端，精确匹配）
        0x00, 0x00, 0x00, 0x00,                    # 长ID过滤器（小端）
        0xFF, 0xFF, 0xFF, 0x1F,                    # 长ID掩码=0x1FFFFFFF（小端）
        baudrate_pts & 0xFF, (baudrate_pts >> 8) & 0xFF  # c_pts时序参数（小端）
    ]

    checksum = calculate_checksum(cmd)
    frame = [0xAA, 0x55] + cmd + [checksum]

    hex_str = ' '.join(f'{b:02X}' for b in frame)

    print(f"=== CAN配置命令 ===")
    print(f"本地发送ID: 0x{local_id:03X}")
    print(f"接收过滤ID: 0x{rx_id:03X}")
    print(f"波特率参数: c_pts={baudrate_pts} → {60000000/(baudrate_pts+5+10):.0f} bps")
    print(f"命令: {hex_str}")
    print()

    return hex_str

def can_send(data):
    """
    生成CAN发送命令（功能码 0x28）

    Args:
        data: 4字节数据列表 [byte0, byte1, byte2, byte3]

    Returns:
        十六进制字符串命令
    """
    if len(data) != 4:
        raise ValueError("CAN数据必须为4字节")

    cmd = [0x28, 0x00, 0x04] + data
    checksum = calculate_checksum(cmd)
    frame = [0xAA, 0x55] + cmd + [checksum]

    hex_str = ' '.join(f'{b:02X}' for b in frame)

    print(f"=== CAN发送命令 ===")
    print(f"发送数据: {' '.join(f'0x{b:02X}' for b in data)}")
    print(f"命令: {hex_str}")
    print()

    return hex_str

def can_read():
    """
    生成CAN读取命令（功能码 0x29）

    Returns:
        十六进制字符串命令
    """
    cmd = [0x29, 0x00, 0x00]
    checksum = calculate_checksum(cmd)
    frame = [0xAA, 0x55] + cmd + [checksum]

    hex_str = ' '.join(f'{b:02X}' for b in frame)

    print(f"=== CAN读取命令 ===")
    print(f"命令: {hex_str}")
    print()

    return hex_str

def verify_command(cmd_hex):
    """
    验证命令的校验和是否正确

    Args:
        cmd_hex: 十六进制字符串（用空格分隔）
    """
    bytes_list = [int(b, 16) for b in cmd_hex.split()]

    if len(bytes_list) < 6:
        print("❌ 命令长度不足")
        return False

    if bytes_list[0] != 0xAA or bytes_list[1] != 0x55:
        print("❌ 帧头错误，应为 AA 55")
        return False

    # 计算校验和（从功能码到数据体结束）
    data = bytes_list[2:-1]  # 去掉帧头和校验和
    calc_checksum = calculate_checksum(data)
    recv_checksum = bytes_list[-1]

    if calc_checksum == recv_checksum:
        print(f"✅ 校验和正确: 0x{calc_checksum:02X}")
        return True
    else:
        print(f"❌ 校验和错误: 期望 0x{calc_checksum:02X}, 实际 0x{recv_checksum:02X}")
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("CAN总线命令生成工具")
    print("=" * 60)
    print()

    # 示例1：配置CAN（ID=0x001，接收ID=0x002，波特率1.224Mbps）
    cmd1 = can_config(local_id=0x001, rx_id=0x002, baudrate_pts=34)
    verify_command(cmd1)
    print()

    # 示例2：发送测试数据
    cmd2 = can_send([0x11, 0x22, 0x33, 0x44])
    verify_command(cmd2)
    print()

    # 示例3：发送0xAA 0xBB 0xCC 0xDD
    cmd3 = can_send([0xAA, 0xBB, 0xCC, 0xDD])
    verify_command(cmd3)
    print()

    # 示例4：读取接收数据
    cmd4 = can_read()
    verify_command(cmd4)
    print()

    print("=" * 60)
    print("测试命令序列（两节点互发）")
    print("=" * 60)
    print()
    print("节点1配置（ID=0x001，接收ID=0x002）：")
    can_config(0x001, 0x002)
    print("节点2配置（ID=0x002，接收ID=0x001）：")
    can_config(0x002, 0x001)
    print()
    print("节点1发送数据：")
    can_send([0x12, 0x34, 0x56, 0x78])
    print("节点2读取数据：")
    can_read()
