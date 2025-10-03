import struct
import argparse
import serial
import time

# Constants from the protocol
FRAME_HEADER = b'\xAA\x55'
CMD_I2C_CONFIG = 0x04
CMD_I2C_TX = 0x05

# SSD1306 Constants
SSD1306_I2C_ADDR = 0x3C
SSD1306_CONTROL_CMD = 0x00
SSD1306_CONTROL_DATA = 0x40

def calculate_checksum(frame_bytes):
    """
    Calculates the checksum for a given byte array.
    The checksum is the sum of all bytes from the frame header to the end of the data body.
    """
    return sum(frame_bytes) & 0xFF

def create_frame(function_code, data_body):
    """Creates a complete USB-CDC frame."""
    data_length = len(data_body)
    data_length_bytes = struct.pack('>H', data_length) # Big-Endian

    # Frame content for checksum calculation
    frame_for_checksum = FRAME_HEADER + bytes([function_code]) + data_length_bytes + data_body
    
    checksum = calculate_checksum(frame_for_checksum)
    
    # Final frame to be sent
    full_frame = frame_for_checksum + struct.pack('B', checksum)
    
    return full_frame

def generate_i2c_config_command(clock_frequency, slave_address):
    """
    Generates a command frame to configure the I2C peripheral.
    - clock_frequency: 32-bit integer for clock speed in Hz (e.g., 100000)
    - slave_address: 8-bit integer for the device address (e.g., 0x3C)
    """
    # Data Body: Clock Frequency (4 bytes), Slave Address (1 byte)
    data_body = struct.pack('>IB', clock_frequency, slave_address)
    return create_frame(CMD_I2C_CONFIG, data_body)

def generate_i2c_tx_command(control_byte, payload):
    """
    Generates a command frame to send data via I2C.
    - control_byte: The SSD1306 control byte (0x00 for command, 0x40 for data)
    - payload: A bytes object containing the commands or data.
    """
    # Data Body: "Register Address" (Control Byte) (1 byte), Data (N bytes)
    data_body = struct.pack('B', control_byte) + payload
    return create_frame(CMD_I2C_TX, data_body)

def get_ssd1306_init_frames():
    """Returns a list of frames to initialize the SSD1306 display."""
    init_payload = bytes([
        0xAE,        # Display OFF
        0xD5, 0x80,  # Set Display Clock Divide Ratio/Oscillator Frequency
        0xA8, 0x3F,  # Set MUX Ratio
        0xD3, 0x00,  # Set Display Offset
        0x40,        # Set Display Start Line
        0x8D, 0x14,  # Charge Pump Setting: Enable Charge Pump
        0x20, 0x00,  # Set Memory Addressing Mode (Horizontal)
        0xA1,        # Set Segment Re-map (Column 127 is mapped to SEG0)
        0xC8,        # Set COM Output Scan Direction (Remapped)
        0xDA, 0x12,  # Set COM Pins Hardware Configuration
        0x81, 0xCF,  # Set Contrast Control
        0xD9, 0xF1,  # Set Pre-charge Period
        0xDB, 0x40,  # Set VCOMH Deselect Level
        0xA4,        # Entire Display ON from GDDRAM content
        0xA6,        # Set Normal Display
        0xAF,        # Display ON
    ])
    return [generate_i2c_tx_command(SSD1306_CONTROL_CMD, init_payload)]

def get_ssd1306_clear_frames():
    """Returns frames to clear the display memory."""
    frames = []
    # Set addressing to clear the whole screen
    set_address_payload = bytes([
        0x21, 0, 127, # Set Column Address Range
        0x22, 0, 7,   # Set Page Address Range
    ])
    frames.append(generate_i2c_tx_command(SSD1306_CONTROL_CMD, set_address_payload))

    # Send 1024 zeros (128 columns * 8 pages = 1024 bytes)
    clear_payload = b'\x00' * 1024
    frames.append(generate_i2c_tx_command(SSD1306_CONTROL_DATA, clear_payload))
    return frames

def get_ssd1306_demo_frames():
    """Returns frames to draw a demo pattern on the screen."""
    frames = []
    # Set position (e.g., Page 3, Column 32)
    set_position_payload = bytes([
        0xB3,        # Set Page Start Address to 3
        0x00 | (32 & 0x0F), # Set Lower Column Start Address
        0x10 | (32 >> 4),   # Set Higher Column Start Address
    ])
    frames.append(generate_i2c_tx_command(SSD1306_CONTROL_CMD, set_position_payload))

    # A simple 8x8 bitmap pattern (a smiley face)
    pattern_payload = bytes([
        0b00111100,
        0b01000010,
        0b10100101,
        0b10000001,
        0b10100101,
        0b10011001,
        0b01000010,
        0b00111100,
    ])
    frames.append(generate_i2c_tx_command(SSD1306_CONTROL_DATA, pattern_payload))
    return frames

def print_frame_as_hex(name, frame, index=None):
    """Helper function to print a command frame in a readable hex format."""
    title = f"{name}"
    if index is not None:
        title += f" (Part {index + 1})"
    
    hex_str = ' '.join(f'{b:02X}' for b in frame)
    print(f"{title}:")
    print(f"  - Bytes: {hex_str}")
    print(f"  - Length: {len(frame)} bytes\n")

def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Generate I2C OLED command frames for the protocol.")
    subparsers = parser.add_subparsers(dest='command', help='Command type', required=True)
    
    # Parser for I2C config command
    config_parser = subparsers.add_parser('config', help='Generate I2C configuration command')
    config_parser.add_argument('--clk', type=int, default=100000, help='Clock frequency in Hz (default: 100000)')
    config_parser.add_argument('--addr', type=lambda x: int(x, 0), default=SSD1306_I2C_ADDR, 
                               help=f'I2C slave address (default: {SSD1306_I2C_ADDR:#X})')
    
    # Parser for SSD1306 init
    subparsers.add_parser('init', help='Generate SSD1306 initialization command sequence')
    
    # Parser for SSD1306 clear
    subparsers.add_parser('clear', help='Generate commands to clear the screen')
    
    # Parser for SSD1306 demo pattern
    subparsers.add_parser('demo', help='Generate commands to draw a demo pattern')

    return parser.parse_args()

def send_frames_to_fpga(port, frames):
    """通过串口将一个或多个帧发送到FPGA"""
    try:
        # 配置串口：波特率可以根据你的FPGA设计来定，这里假设为115200
        with serial.Serial(port, 115200, timeout=1) as ser:
            print(f"成功打开串口 {port}")
            for i, frame in enumerate(frames):
                ser.write(frame)
                hex_str = ' '.join(f'{b:02X}' for b in frame)
                print(f" -> 已发送第 {i+1} 帧: {hex_str}")
                time.sleep(0.05) # 发送间隙，防止FPGA处理不过来
            print("所有帧发送完毕。")
    except serial.SerialException as e:
        print(f"错误: 无法打开或写入串口 {port}。")
        print(f"请检查串口号是否正确，或设备是否被占用。")
        print(f"详细信息: {e}")

def main():
    """Main function to handle command line arguments and generate commands."""
    args = parse_arguments()
    # 添加一个新的参数用于指定串口和是否真的发送
    parser = argparse.ArgumentParser(description="生成并发送I2C OLED命令帧。")
    
    # --- 新的执行逻辑 ---
    # 1. 先像之前一样，根据命令生成帧列表
    frames = []
    title = ""
    if args.command == 'config':
        title = "I2C Config Command"
        frames.append(generate_i2c_config_command(args.clk, args.addr))
    elif args.command == 'init':
        title = "SSD1306 Init Command"
        frames.extend(get_ssd1306_init_frames())
    elif args.command == 'clear':
        title = "SSD1306 Clear Screen Commands"
        frames.extend(get_ssd1306_clear_frames())
    elif args.command == 'demo':
        title = "SSD1306 Draw Demo Pattern Commands"
        frames.extend(get_ssd1306_demo_frames())

    # 2. 打印并发送这些帧
    print("--- 准备发送的命令帧 ---")
    if len(frames) == 1:
        print_frame_as_hex(title, frames[0])
    else:
        for i, frame in enumerate(frames):
            print_frame_as_hex(title, frame, index=i)
    
    # 3. 询问是否发送
    # !!! 将 'YOUR_SERIAL_PORT' 替换为你的实际串口号 !!!
    serial_port = 'COM7' # 例如: 'COM4' 或 '/dev/ttyACM0'
    
    confirm = input(f"是否要将这些命令发送到串口 {serial_port}? (y/n): ")
    if confirm.lower() == 'y':
        send_frames_to_fpga(serial_port, frames)

if __name__ == "__main__":
    main()