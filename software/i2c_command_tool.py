#!/usr/bin/env python3
"""
I2C Command Generator for FPGA2025 USB-CDC Protocol
====================================================

This script generates I2C command frames compatible with the FPGA2025
USB-CDC communication protocol for I2C operations.

Protocol Frame Format:
    [Header(2)] [Command(1)] [Length(2)] [Payload(N)] [Checksum(1)]
    0xAA55      0x04-0x06    Big-Endian  Data         Sum & 0xFF

Supported Commands:
    0x04: I2C Config - Configure I2C slave address and clock frequency
    0x05: I2C Write  - Write data to I2C device register
    0x06: I2C Read   - Read data from I2C device register

Author: FPGA2025 Project
License: MIT
"""

import struct
import argparse
import sys

# ============================================================================
# Protocol Constants
# ============================================================================
FRAME_HEADER = b'\xAA\x55'
UPLOAD_HEADER = b'\xAA\x44'

CMD_I2C_CONFIG = 0x04
CMD_I2C_WRITE = 0x05
CMD_I2C_READ = 0x06

# I2C Clock Frequency Codes (from i2c_handler.v:172-177)
I2C_CLK_50KHZ = 0x00
I2C_CLK_100KHZ = 0x01
I2C_CLK_200KHZ = 0x02
I2C_CLK_400KHZ = 0x03

I2C_FREQ_MAP = {
    50000: I2C_CLK_50KHZ,
    100000: I2C_CLK_100KHZ,
    200000: I2C_CLK_200KHZ,
    400000: I2C_CLK_400KHZ,
}


# ============================================================================
# Helper Functions
# ============================================================================
def calculate_checksum(data):
    """
    Calculate checksum for USB-CDC protocol.

    Checksum = (sum of all bytes from command to end of payload) & 0xFF

    Args:
        data (bytes): Data to calculate checksum for (from command byte onwards)

    Returns:
        int: Checksum value (0-255)
    """
    return sum(data) & 0xFF


def create_frame(command, payload):
    """
    Create a complete USB-CDC command frame.

    Args:
        command (int): Command code (0x04-0x06 for I2C)
        payload (bytes): Command payload data

    Returns:
        bytes: Complete frame ready to send
    """
    # Build frame without checksum
    length = len(payload)
    frame = FRAME_HEADER + struct.pack('B', command) + struct.pack('>H', length) + payload

    # Calculate checksum (excluding frame header)
    checksum_data = frame[2:]  # Skip 0xAA55
    checksum = calculate_checksum(checksum_data)

    # Append checksum
    return frame + struct.pack('B', checksum)


def print_frame(frame, description=""):
    """
    Print frame in human-readable hex format.

    Args:
        frame (bytes): Frame to print
        description (str): Optional description
    """
    if description:
        print(f"\n{description}")
        print("=" * len(description))

    hex_str = ' '.join(f'{b:02X}' for b in frame)
    print(f"Frame ({len(frame)} bytes): {hex_str}")

    # Parse and display frame structure
    if len(frame) >= 6:
        header = frame[0:2]
        cmd = frame[2]
        length = struct.unpack('>H', frame[3:5])[0]
        payload = frame[5:-1]
        checksum = frame[-1]

        print(f"  Header:   {header.hex().upper()} ({'Command' if header == FRAME_HEADER else 'Upload'})")
        print(f"  Command:  0x{cmd:02X}")
        print(f"  Length:   {length} (0x{length:04X})")
        print(f"  Payload:  {payload.hex().upper() if payload else '(empty)'}")
        print(f"  Checksum: 0x{checksum:02X}")


# ============================================================================
# I2C Command Generators
# ============================================================================
def i2c_config(slave_addr, freq_hz=100000):
    """
    Generate I2C configuration command.

    Configures the I2C slave address and clock frequency.

    Command Format (from i2c_handler.v:166-180):
        Payload[0]: Slave address (7-bit, right-aligned)
        Payload[1]: Clock frequency code
            0x00 = 50kHz
            0x01 = 100kHz
            0x02 = 200kHz
            0x03 = 400kHz

    Args:
        slave_addr (int): 7-bit I2C slave address (0x00-0x7F)
        freq_hz (int): Clock frequency in Hz (50000, 100000, 200000, or 400000)

    Returns:
        bytes: Complete I2C config command frame

    Example:
        >>> frame = i2c_config(0x50, 100000)
        >>> # Sends: AA 55 04 00 02 50 01 57
    """
    if slave_addr < 0 or slave_addr > 0x7F:
        raise ValueError(f"Slave address must be 7-bit (0x00-0x7F), got 0x{slave_addr:02X}")

    if freq_hz not in I2C_FREQ_MAP:
        raise ValueError(f"Frequency must be one of {list(I2C_FREQ_MAP.keys())}, got {freq_hz}")

    freq_code = I2C_FREQ_MAP[freq_hz]
    payload = struct.pack('BB', slave_addr, freq_code)

    return create_frame(CMD_I2C_CONFIG, payload)


def i2c_write(reg_addr, data):
    """
    Generate I2C write command.

    Writes data to a specific register address on the I2C device.

    Command Format (from i2c_handler.v:187-201):
        Payload[0:1]: Register address (16-bit, big-endian)
        Payload[2:N]: Data to write (1-128 bytes)

    Args:
        reg_addr (int): 16-bit register address
        data (bytes or list): Data bytes to write

    Returns:
        bytes: Complete I2C write command frame

    Example:
        >>> frame = i2c_write(0x003C, [0xDE, 0xAD, 0xBE, 0xEF])
        >>> # Sends: AA 55 05 00 06 00 3C DE AD BE EF 7F
    """
    if reg_addr < 0 or reg_addr > 0xFFFF:
        raise ValueError(f"Register address must be 16-bit (0x0000-0xFFFF), got 0x{reg_addr:04X}")

    if isinstance(data, (list, tuple)):
        data = bytes(data)

    if len(data) == 0:
        raise ValueError("Data must contain at least 1 byte")

    if len(data) > 128:
        raise ValueError(f"Data length exceeds buffer size (128 bytes), got {len(data)} bytes")

    payload = struct.pack('>H', reg_addr) + data

    return create_frame(CMD_I2C_WRITE, payload)


def i2c_read(reg_addr, read_len):
    """
    Generate I2C read command.

    Reads data from a specific register address on the I2C device.

    Command Format (from i2c_handler.v:203-216):
        Payload[0:1]: Register address (16-bit, big-endian)
        Payload[2:3]: Read length (16-bit, big-endian)

    Response Format:
        Header:  0xAA44 (upload data)
        Source:  0x06 (I2C read source)
        Length:  read_len
        Data:    Read data bytes
        Checksum: Sum & 0xFF

    Args:
        reg_addr (int): 16-bit register address
        read_len (int): Number of bytes to read (1-128)

    Returns:
        bytes: Complete I2C read command frame

    Example:
        >>> frame = i2c_read(0x003C, 4)
        >>> # Sends: AA 55 06 00 04 00 3C 00 04 4A
        >>> # Expects response: AA 44 06 00 04 [4 bytes data] [checksum]
    """
    if reg_addr < 0 or reg_addr > 0xFFFF:
        raise ValueError(f"Register address must be 16-bit (0x0000-0xFFFF), got 0x{reg_addr:04X}")

    if read_len < 1 or read_len > 128:
        raise ValueError(f"Read length must be 1-128 bytes, got {read_len}")

    payload = struct.pack('>HH', reg_addr, read_len)

    return create_frame(CMD_I2C_READ, payload)


def i2c_write_single_byte(reg_addr, value):
    """
    Convenience function to write a single byte to a register.

    Args:
        reg_addr (int): 16-bit register address
        value (int): Byte value to write (0-255)

    Returns:
        bytes: Complete I2C write command frame

    Example:
        >>> frame = i2c_write_single_byte(0x0010, 0xFF)
    """
    if value < 0 or value > 0xFF:
        raise ValueError(f"Value must be a byte (0x00-0xFF), got 0x{value:02X}")

    return i2c_write(reg_addr, bytes([value]))


def i2c_read_single_byte(reg_addr):
    """
    Convenience function to read a single byte from a register.

    Args:
        reg_addr (int): 16-bit register address

    Returns:
        bytes: Complete I2C read command frame

    Example:
        >>> frame = i2c_read_single_byte(0x0010)
    """
    return i2c_read(reg_addr, 1)


# ============================================================================
# Common I2C Device Operations
# ============================================================================
def eeprom_write(addr, data):
    """
    Write data to I2C EEPROM (e.g., AT24C series).

    Args:
        addr (int): Memory address (0x0000-0xFFFF)
        data (bytes or list): Data to write

    Returns:
        bytes: I2C write command frame

    Note:
        Remember to configure I2C first:
        - 24C02/04: typically 0x50, 100kHz
        - 24C64: typically 0x50, 400kHz
    """
    return i2c_write(addr, data)


def eeprom_read(addr, length):
    """
    Read data from I2C EEPROM (e.g., AT24C series).

    Args:
        addr (int): Memory address (0x0000-0xFFFF)
        length (int): Number of bytes to read

    Returns:
        bytes: I2C read command frame
    """
    return i2c_read(addr, length)


# ============================================================================
# Command Line Interface
# ============================================================================
def parse_int(s):
    """Parse integer with support for hex (0x), binary (0b), and decimal."""
    return int(s, 0)


def parse_bytes(s):
    """Parse bytes from various formats: hex string, comma-separated, or space-separated."""
    # Remove common separators
    s = s.replace(' ', '').replace(',', '').replace('0x', '')

    # Try to parse as hex string
    try:
        return bytes.fromhex(s)
    except ValueError:
        raise argparse.ArgumentTypeError(f"Invalid byte data format: {s}")


def main():
    """Command line interface for I2C command generation."""
    parser = argparse.ArgumentParser(
        description='Generate I2C command frames for FPGA2025 USB-CDC protocol',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Configure I2C for EEPROM at 0x50, 100kHz
  %(prog)s config --addr 0x50 --freq 100000

  # Write 4 bytes to register 0x003C
  %(prog)s write --reg 0x003C --data "DE AD BE EF"

  # Read 4 bytes from register 0x003C
  %(prog)s read --reg 0x003C --len 4

  # Write single byte
  %(prog)s write --reg 0x10 --data FF

  # EEPROM write example
  %(prog)s write --reg 0x0000 --data "48656C6C6F"  # Write "Hello"

  # EEPROM read example
  %(prog)s read --reg 0x0000 --len 5  # Read 5 bytes
        """)

    subparsers = parser.add_subparsers(dest='command', help='I2C operation', required=True)

    # Config command
    config_parser = subparsers.add_parser('config', help='Configure I2C slave address and clock')
    config_parser.add_argument('--addr', type=parse_int, required=True,
                               help='7-bit I2C slave address (e.g., 0x50)')
    config_parser.add_argument('--freq', type=int, default=100000,
                               choices=[50000, 100000, 200000, 400000],
                               help='I2C clock frequency in Hz (default: 100000)')

    # Write command
    write_parser = subparsers.add_parser('write', help='Write data to I2C register')
    write_parser.add_argument('--reg', type=parse_int, required=True,
                              help='16-bit register address (e.g., 0x003C)')
    write_parser.add_argument('--data', type=parse_bytes, required=True,
                              help='Data bytes in hex format (e.g., "DEADBEEF" or "DE AD BE EF")')

    # Read command
    read_parser = subparsers.add_parser('read', help='Read data from I2C register')
    read_parser.add_argument('--reg', type=parse_int, required=True,
                             help='16-bit register address (e.g., 0x003C)')
    read_parser.add_argument('--len', type=int, required=True,
                             help='Number of bytes to read (1-128)')

    # Output options
    parser.add_argument('-o', '--output', type=str,
                        help='Save frame to binary file')
    parser.add_argument('-x', '--hex-only', action='store_true',
                        help='Print only hex string (no formatting)')

    args = parser.parse_args()

    # Generate command frame
    try:
        if args.command == 'config':
            frame = i2c_config(args.addr, args.freq)
            desc = f"I2C Config: Addr=0x{args.addr:02X}, Freq={args.freq}Hz"

        elif args.command == 'write':
            frame = i2c_write(args.reg, args.data)
            data_hex = args.data.hex().upper()
            desc = f"I2C Write: Reg=0x{args.reg:04X}, Data={data_hex} ({len(args.data)} bytes)"

        elif args.command == 'read':
            frame = i2c_read(args.reg, args.len)
            desc = f"I2C Read: Reg=0x{args.reg:04X}, Length={args.len} bytes"

        else:
            print(f"Error: Unknown command '{args.command}'", file=sys.stderr)
            return 1

        # Output frame
        if args.hex_only:
            print(frame.hex().upper())
        else:
            print_frame(frame, desc)

        # Save to file if requested
        if args.output:
            with open(args.output, 'wb') as f:
                f.write(frame)
            print(f"\nFrame saved to: {args.output}")

        return 0

    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


# ============================================================================
# Module Usage Example
# ============================================================================
if __name__ == '__main__':
    # If imported as module, provide usage examples
    if len(sys.argv) == 1:
        print(__doc__)
        print("\n" + "=" * 70)
        print("USAGE EXAMPLES (as Python module)")
        print("=" * 70)
        print("""
# Import the module
from i2c_command_tool import *

# Example 1: Configure I2C for EEPROM AT24C64
config_frame = i2c_config(slave_addr=0x50, freq_hz=400000)
print(config_frame.hex())  # AA5504000250035D

# Example 2: Write data to EEPROM
write_frame = i2c_write(reg_addr=0x0000, data=[0x48, 0x65, 0x6C, 0x6C, 0x6F])
print(write_frame.hex())  # AA55050007000048656C6C6F...

# Example 3: Read data from EEPROM
read_frame = i2c_read(reg_addr=0x0000, read_len=5)
print(read_frame.hex())  # AA550600040000000509

# Example 4: Single byte operations
write_byte_frame = i2c_write_single_byte(0x0010, 0xFF)
read_byte_frame = i2c_read_single_byte(0x0010)

# Example 5: EEPROM operations
eeprom_wr = eeprom_write(addr=0x0100, data=b"Hello World")
eeprom_rd = eeprom_read(addr=0x0100, length=11)

# Send frames via serial port
import serial
with serial.Serial('COM3', 115200) as ser:
    ser.write(config_frame)
    time.sleep(0.01)
    ser.write(write_frame)
    time.sleep(0.01)
    ser.write(read_frame)
    response = ser.read(100)  # Read response
        """)
        print("\n" + "=" * 70)
        print("For command line usage, run:")
        print(f"  python {sys.argv[0]} --help")
        print("=" * 70)
        sys.exit(0)

    sys.exit(main())
