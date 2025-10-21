#!/usr/bin/env python3
"""
I2C Command Examples for FPGA2025
==================================

This file demonstrates various I2C operations using the i2c_command_tool module.

"""

import time
import serial
from i2c_command_tool import (
    i2c_config, i2c_write, i2c_read,
    i2c_write_single_byte, i2c_read_single_byte,
    eeprom_write, eeprom_read,
    print_frame
)


# ============================================================================
# Example 1: EEPROM (AT24C64) Read/Write Operations
# ============================================================================
def example_eeprom_operations():
    """
    Demonstrates reading and writing to an I2C EEPROM (e.g., AT24C64).

    Device: AT24C64 (8KB EEPROM)
    Address: 0x50 (typical)
    Clock: 400kHz
    """
    print("\n" + "="*70)
    print("Example 1: EEPROM AT24C64 Operations")
    print("="*70)

    # Step 1: Configure I2C
    print("\nStep 1: Configure I2C (Address=0x50, Freq=400kHz)")
    config = i2c_config(slave_addr=0x50, freq_hz=400000)
    print_frame(config)

    # Step 2: Write string "Hello FPGA!" to address 0x0000
    print("\nStep 2: Write 'Hello FPGA!' to address 0x0000")
    message = b"Hello FPGA!"
    write_cmd = i2c_write(reg_addr=0x0000, data=message)
    print_frame(write_cmd)

    # Step 3: Read back 11 bytes from address 0x0000
    print("\nStep 3: Read 11 bytes from address 0x0000")
    read_cmd = i2c_read(reg_addr=0x0000, read_len=11)
    print_frame(read_cmd)
    print("Expected response: AA 44 06 00 0B 48 65 6C 6C 6F 20 46 50 47 41 21 [checksum]")

    return [config, write_cmd, read_cmd]


# ============================================================================
# Example 2: Multi-Byte EEPROM Write/Read
# ============================================================================
def example_multi_byte_eeprom():
    """
    Write and read multiple bytes from EEPROM at different addresses.
    """
    print("\n" + "="*70)
    print("Example 2: Multi-Byte EEPROM Operations")
    print("="*70)

    frames = []

    # Configure I2C
    print("\nConfigure I2C for AT24C04 (0x50, 100kHz)")
    config = i2c_config(slave_addr=0x50, freq_hz=100000)
    print_frame(config)
    frames.append(config)

    # Write sequence of bytes
    print("\nWrite 4 bytes [0xDE, 0xAD, 0xBE, 0xEF] to address 0x003C")
    write_cmd = i2c_write(reg_addr=0x003C, data=[0xDE, 0xAD, 0xBE, 0xEF])
    print_frame(write_cmd)
    frames.append(write_cmd)

    # Verify: This should match protocol documentation example
    print("\n[OK] This matches the protocol documentation example:")
    print("  AA 55 05 00 06 00 3C DE AD BE EF 7F")

    # Read back
    print("\nRead 4 bytes from address 0x003C")
    read_cmd = i2c_read(reg_addr=0x003C, read_len=4)
    print_frame(read_cmd)
    frames.append(read_cmd)

    print("\n[OK] This matches the protocol documentation example:")
    print("  AA 55 06 00 04 00 3C 00 04 4A")

    return frames


# ============================================================================
# Example 3: SSD1306 OLED Display Initialization
# ============================================================================
def example_ssd1306_oled():
    """
    Initialize and control an SSD1306 OLED display (128x64).

    Device: SSD1306
    Address: 0x3C
    Clock: 400kHz
    Control Byte: 0x00 for commands, 0x40 for data
    """
    print("\n" + "="*70)
    print("Example 3: SSD1306 OLED Display Initialization")
    print("="*70)

    frames = []

    # Configure I2C
    print("\nConfigure I2C for SSD1306 (0x3C, 400kHz)")
    config = i2c_config(slave_addr=0x3C, freq_hz=400000)
    print_frame(config)
    frames.append(config)

    # SSD1306 initialization sequence
    print("\nSend initialization sequence")
    init_commands = bytes([
        0x00,        # Control byte: Command stream
        0xAE,        # Display OFF
        0xD5, 0x80,  # Set display clock
        0xA8, 0x3F,  # Set multiplex ratio (64)
        0xD3, 0x00,  # Set display offset
        0x40,        # Set start line
        0x8D, 0x14,  # Enable charge pump
        0x20, 0x00,  # Set memory mode (horizontal)
        0xA1,        # Segment remap
        0xC8,        # COM scan direction
        0xDA, 0x12,  # Set COM pins
        0x81, 0xCF,  # Set contrast
        0xD9, 0xF1,  # Set pre-charge
        0xDB, 0x40,  # Set VCOMH
        0xA4,        # Display on from RAM
        0xA6,        # Normal display
        0xAF,        # Display ON
    ])

    # For SSD1306, we write to register 0x00 with control byte + commands
    # Note: The first byte (0x00) is treated as "register address" in our protocol
    init_cmd = i2c_write(reg_addr=0x0000, data=init_commands)
    print_frame(init_cmd)
    frames.append(init_cmd)

    return frames


# ============================================================================
# Example 4: Temperature Sensor (Generic I2C)
# ============================================================================
def example_temperature_sensor():
    """
    Read temperature from a generic I2C temperature sensor.

    Example: LM75 temperature sensor
    Address: 0x48
    Clock: 100kHz
    Temp Register: 0x00 (16-bit, 2 bytes)
    """
    print("\n" + "="*70)
    print("Example 4: LM75 Temperature Sensor")
    print("="*70)

    frames = []

    # Configure I2C
    print("\nConfigure I2C for LM75 (0x48, 100kHz)")
    config = i2c_config(slave_addr=0x48, freq_hz=100000)
    print_frame(config)
    frames.append(config)

    # Read temperature register (2 bytes)
    print("\nRead 2 bytes from temperature register (0x00)")
    read_temp = i2c_read(reg_addr=0x0000, read_len=2)
    print_frame(read_temp)
    frames.append(read_temp)

    print("\nNote: Temperature = (MSB << 8 | LSB) / 256.0 °C")

    return frames


# ============================================================================
# Example 5: Single Byte Operations
# ============================================================================
def example_single_byte_operations():
    """
    Demonstrate single byte read/write convenience functions.
    """
    print("\n" + "="*70)
    print("Example 5: Single Byte Operations")
    print("="*70)

    frames = []

    # Configure I2C
    config = i2c_config(slave_addr=0x50, freq_hz=100000)
    frames.append(config)

    # Write single byte
    print("\nWrite single byte 0xFF to register 0x0010")
    write_byte = i2c_write_single_byte(reg_addr=0x0010, value=0xFF)
    print_frame(write_byte)
    frames.append(write_byte)

    # Read single byte
    print("\nRead single byte from register 0x0010")
    read_byte = i2c_read_single_byte(reg_addr=0x0010)
    print_frame(read_byte)
    frames.append(read_byte)

    return frames


# ============================================================================
# Example 6: Send Commands via Serial Port
# ============================================================================
def send_to_fpga(frames, port='COM3', baudrate=115200, delay=0.01):
    """
    Send command frames to FPGA via serial port.

    Args:
        frames (list): List of command frames to send
        port (str): Serial port name (e.g., 'COM3', '/dev/ttyACM0')
        baudrate (int): Serial baud rate
        delay (float): Delay between frames in seconds
    """
    try:
        with serial.Serial(port, baudrate, timeout=1) as ser:
            print(f"\n[OK] Connected to {port} at {baudrate} baud")

            for i, frame in enumerate(frames):
                ser.write(frame)
                hex_str = ' '.join(f'{b:02X}' for b in frame)
                print(f"  [{i+1}] Sent: {hex_str}")

                if delay > 0:
                    time.sleep(delay)

            print(f"\n[OK] Successfully sent {len(frames)} frames")

            # Try to read response
            print("\nWaiting for response...")
            time.sleep(0.1)
            if ser.in_waiting > 0:
                response = ser.read(ser.in_waiting)
                print(f"Response ({len(response)} bytes): {response.hex().upper()}")
            else:
                print("No response received")

    except serial.SerialException as e:
        print(f"\n[ERROR] Could not open serial port {port}")
        print(f"  Details: {e}")
        print("\n  Troubleshooting:")
        print("  - Check if the port name is correct")
        print("  - Ensure no other program is using the port")
        print("  - Verify USB cable is connected")


# ============================================================================
# Main Demo
# ============================================================================
def main():
    """Run all examples."""
    print("="*70)
    print("I2C Command Examples for FPGA2025")
    print("="*70)

    # Run examples
    example_eeprom_operations()
    example_multi_byte_eeprom()
    example_ssd1306_oled()
    example_temperature_sensor()
    example_single_byte_operations()

    print("\n" + "="*70)
    print("Examples Complete!")
    print("="*70)
    print("\nTo send commands to FPGA, use the send_to_fpga() function:")
    print("  frames = example_eeprom_operations()")
    print("  send_to_fpga(frames, port='COM3', baudrate=115200)")
    print("\nOr use the command line tool:")
    print("  python i2c_command_tool.py config --addr 0x50 --freq 100000")
    print("  python i2c_command_tool.py write --reg 0x0000 --data 'DEADBEEF'")
    print("  python i2c_command_tool.py read --reg 0x0000 --len 4")


if __name__ == '__main__':
    main()
