#!/usr/bin/env python3
"""
I2C Slave CDC Command Test Tool for FPGA2025
=============================================

This tool generates CDC commands for testing the I2C slave module via the
CDC command bus interface (not the physical I2C interface).

Supported CDC Commands:
    0x34: Set I2C Slave Address - Configure slave address dynamically
    0x35: CDC Write to Registers - Write data to slave registers via CDC bus
    0x36: CDC Read from Registers - Read data from slave registers via CDC bus

Protocol Frame Format:
    [Header(2)] [Command(1)] [Length(2)] [Payload(N)] [Checksum(1)]
    0xAA55      0x34-0x36    Big-Endian  Data         Sum & 0xFF

Author: FPGA2025 Project
License: MIT
"""

import struct
import argparse
import sys
import serial
import time

# ============================================================================
# Protocol Constants
# ============================================================================
FRAME_HEADER = b'\xAA\x55'
UPLOAD_HEADER = b'\xAA\x44'

CMD_I2C_SLAVE_SET_ADDR = 0x34  # Set I2C slave address
CMD_I2C_SLAVE_WRITE = 0x35     # CDC write to slave registers
CMD_I2C_SLAVE_READ = 0x36      # CDC read from slave registers

UPLOAD_SOURCE_I2C_SLAVE = 0x36  # Data source identifier for uploads


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
        command (int): Command code (0x34-0x36 for I2C slave)
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


def parse_upload_response(response):
    """
    Parse upload response from FPGA.

    Expected format: AA 44 [SOURCE] [LEN_H] [LEN_L] [DATA...] [CHECKSUM]

    Args:
        response (bytes): Response data from FPGA

    Returns:
        dict: Parsed response with 'source', 'data', 'valid' fields
    """
    if len(response) < 6:
        return {'valid': False, 'error': 'Response too short'}

    if response[0:2] != UPLOAD_HEADER:
        return {'valid': False, 'error': f'Invalid header: {response[0:2].hex()}'}

    source = response[2]
    length = struct.unpack('>H', response[3:5])[0]

    expected_len = 5 + length + 1  # header(2) + source(1) + len(2) + data(N) + checksum(1)
    if len(response) < expected_len:
        return {'valid': False, 'error': f'Incomplete response: got {len(response)}, expected {expected_len}'}

    data = response[5:5+length]
    checksum_received = response[5+length]

    # Verify checksum
    checksum_calc = calculate_checksum(response[2:5+length])
    if checksum_calc != checksum_received:
        return {
            'valid': False,
            'error': f'Checksum mismatch: calculated 0x{checksum_calc:02X}, received 0x{checksum_received:02X}'
        }

    return {
        'valid': True,
        'source': source,
        'length': length,
        'data': data
    }


# ============================================================================
# I2C Slave CDC Command Generators
# ============================================================================
def i2c_slave_set_address(slave_addr):
    """
    Generate command to set I2C slave address dynamically (0x34).

    This command configures the I2C slave address at runtime.

    Payload Format:
        Byte[0]: New 7-bit slave address

    Args:
        slave_addr (int): 7-bit I2C slave address (0x00-0x7F)

    Returns:
        bytes: Complete CDC command frame

    Example:
        >>> frame = i2c_slave_set_address(0x25)
        >>> # Sends: AA 55 34 00 01 25 5A
    """
    if slave_addr < 0 or slave_addr > 0x7F:
        raise ValueError(f"Slave address must be 7-bit (0x00-0x7F), got 0x{slave_addr:02X}")

    payload = struct.pack('B', slave_addr)
    return create_frame(CMD_I2C_SLAVE_SET_ADDR, payload)


def i2c_slave_write_registers(start_addr, data):
    """
    Generate command to write data to I2C slave registers via CDC bus (0x35).

    This writes to the internal register map of the I2C slave module
    through the CDC command interface (not via physical I2C).

    Payload Format:
        Byte[0]:   Start register address (0-3)
        Byte[1]:   Data length (number of bytes to write)
        Byte[2:N]: Data bytes to write

    Args:
        start_addr (int): Starting register address (0-3)
        data (bytes or list): Data bytes to write (1-4 bytes)

    Returns:
        bytes: Complete CDC command frame

    Example:
        >>> frame = i2c_slave_write_registers(2, [0x11, 0x22])
        >>> # Writes 0x11 to reg[2], 0x22 to reg[3]
        >>> # Sends: AA 55 35 00 04 02 02 11 22 A0
    """
    if start_addr < 0 or start_addr > 3:
        raise ValueError(f"Start address must be 0-3, got {start_addr}")

    if isinstance(data, (list, tuple)):
        data = bytes(data)

    if len(data) == 0:
        raise ValueError("Data must contain at least 1 byte")

    if len(data) > 4:
        raise ValueError(f"Data length exceeds register count (4 bytes max), got {len(data)} bytes")

    if start_addr + len(data) > 4:
        raise ValueError(f"Write would exceed register range: start={start_addr}, len={len(data)}")

    # Payload: [start_addr, data_length, data_bytes...]
    payload = struct.pack('BB', start_addr, len(data)) + data

    return create_frame(CMD_I2C_SLAVE_WRITE, payload)


def i2c_slave_read_registers(start_addr, read_len):
    """
    Generate command to read data from I2C slave registers via CDC bus (0x36).

    This reads from the internal register map of the I2C slave module
    through the CDC command interface (not via physical I2C).

    Payload Format:
        Byte[0]: Start register address (0-3)
        Byte[1]: Number of bytes to read (1-4)

    Response Format:
        Header:  0xAA44 (upload data)
        Source:  0x36 (I2C_SLAVE)
        Length:  read_len
        Data:    Register values
        Checksum: Sum & 0xFF

    Args:
        start_addr (int): Starting register address (0-3)
        read_len (int): Number of bytes to read (1-4)

    Returns:
        bytes: Complete CDC command frame

    Example:
        >>> frame = i2c_slave_read_registers(0, 2)
        >>> # Reads reg[0] and reg[1]
        >>> # Sends: AA 55 36 00 02 00 02 6E
        >>> # Expects: AA 44 36 00 02 [DATA0] [DATA1] [CS]
    """
    if start_addr < 0 or start_addr > 3:
        raise ValueError(f"Start address must be 0-3, got {start_addr}")

    if read_len < 1 or read_len > 4:
        raise ValueError(f"Read length must be 1-4 bytes, got {read_len}")

    if start_addr + read_len > 4:
        raise ValueError(f"Read would exceed register range: start={start_addr}, len={read_len}")

    # Payload: [start_addr, read_length]
    payload = struct.pack('BB', start_addr, read_len)

    return create_frame(CMD_I2C_SLAVE_READ, payload)


# ============================================================================
# Serial Communication Functions
# ============================================================================
def send_and_receive(port, baudrate, frame, wait_response=False, timeout=1.0):
    """
    Send command frame via serial port and optionally wait for response.

    Args:
        port (str): Serial port name (e.g., 'COM3' or '/dev/ttyUSB0')
        baudrate (int): Baud rate (default: 115200)
        frame (bytes): Command frame to send
        wait_response (bool): Whether to wait for response
        timeout (float): Response timeout in seconds

    Returns:
        bytes: Response data if wait_response=True, else None
    """
    try:
        with serial.Serial(port, baudrate, timeout=timeout) as ser:
            # Flush buffers
            ser.reset_input_buffer()
            ser.reset_output_buffer()

            # Send command
            print(f"\nSending {len(frame)} bytes to {port}...")
            ser.write(frame)
            print("✓ Sent successfully")

            if wait_response:
                print(f"Waiting for response (timeout: {timeout}s)...")
                time.sleep(0.05)  # Small delay for FPGA processing

                # Read response header first
                response = ser.read(5)  # Read header + source + length
                if len(response) < 5:
                    print(f"✗ No response or incomplete header (got {len(response)} bytes)")
                    return None

                # Calculate expected total length
                data_len = struct.unpack('>H', response[3:5])[0]
                total_len = 5 + data_len + 1  # header(2) + source(1) + len(2) + data(N) + checksum(1)

                # Read remaining bytes
                remaining = total_len - 5
                response += ser.read(remaining)

                if len(response) == total_len:
                    print(f"✓ Received {len(response)} bytes")
                    return response
                else:
                    print(f"✗ Incomplete response: got {len(response)}/{total_len} bytes")
                    return response

            return None

    except serial.SerialException as e:
        print(f"✗ Serial error: {e}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"✗ Unexpected error: {e}", file=sys.stderr)
        return None


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
    """Command line interface for I2C slave CDC command generation."""
    parser = argparse.ArgumentParser(
        description='Generate CDC commands for I2C slave module testing',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Set I2C slave address to 0x25
  %(prog)s set-addr --addr 0x25

  # Write data to registers 2 and 3
  %(prog)s write --start 2 --data "11 22"

  # Read all 4 registers
  %(prog)s read --start 0 --len 4

  # Send command via serial port and get response
  %(prog)s read --start 0 --len 4 --port COM3

  # Complete test sequence
  %(prog)s write --start 0 --data "AA BB CC DD" --port COM3
  %(prog)s read --start 0 --len 4 --port COM3
        """)

    subparsers = parser.add_subparsers(dest='command', help='CDC operation', required=True)

    # Set address command
    addr_parser = subparsers.add_parser('set-addr', help='Set I2C slave address (0x34)')
    addr_parser.add_argument('--addr', type=parse_int, required=True,
                            help='7-bit I2C slave address (0x00-0x7F, e.g., 0x25)')

    # Write command
    write_parser = subparsers.add_parser('write', help='Write to slave registers via CDC (0x35)')
    write_parser.add_argument('--start', type=int, required=True,
                             help='Starting register address (0-3)')
    write_parser.add_argument('--data', type=parse_bytes, required=True,
                             help='Data bytes in hex format (e.g., "11 22 33 44")')

    # Read command
    read_parser = subparsers.add_parser('read', help='Read from slave registers via CDC (0x36)')
    read_parser.add_argument('--start', type=int, required=True,
                            help='Starting register address (0-3)')
    read_parser.add_argument('--len', type=int, required=True,
                            help='Number of bytes to read (1-4)')

    # Common arguments for all commands
    for subparser in [addr_parser, write_parser, read_parser]:
        subparser.add_argument('-p', '--port', type=str,
                              help='Serial port (e.g., COM3 or /dev/ttyUSB0)')
        subparser.add_argument('-b', '--baudrate', type=int, default=115200,
                              help='Baud rate (default: 115200)')
        subparser.add_argument('-o', '--output', type=str,
                              help='Save frame to binary file')
        subparser.add_argument('-x', '--hex-only', action='store_true',
                              help='Print only hex string (no formatting)')

    args = parser.parse_args()

    # Generate command frame
    try:
        if args.command == 'set-addr':
            frame = i2c_slave_set_address(args.addr)
            desc = f"Set I2C Slave Address: 0x{args.addr:02X}"
            wait_response = False

        elif args.command == 'write':
            frame = i2c_slave_write_registers(args.start, args.data)
            data_hex = args.data.hex().upper()
            desc = f"CDC Write: Start=Reg[{args.start}], Data={data_hex} ({len(args.data)} bytes)"
            wait_response = False

        elif args.command == 'read':
            frame = i2c_slave_read_registers(args.start, args.len)
            desc = f"CDC Read: Start=Reg[{args.start}], Length={args.len} bytes"
            wait_response = True

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
            print(f"\n✓ Frame saved to: {args.output}")

        # Send via serial port if specified
        if args.port:
            response = send_and_receive(args.port, args.baudrate, frame, wait_response)

            if response and wait_response:
                print("\n" + "="*70)
                print("RESPONSE RECEIVED")
                print("="*70)
                hex_str = ' '.join(f'{b:02X}' for b in response)
                print(f"Raw ({len(response)} bytes): {hex_str}")

                parsed = parse_upload_response(response)
                if parsed['valid']:
                    print(f"\n✓ Valid response:")
                    print(f"  Source:   0x{parsed['source']:02X} (I2C_SLAVE)")
                    print(f"  Length:   {parsed['length']} bytes")
                    print(f"  Data:     {parsed['data'].hex().upper()}")

                    # Display register values
                    print(f"\n  Register Values:")
                    for i, byte in enumerate(parsed['data']):
                        reg_addr = args.start + i
                        print(f"    Reg[{reg_addr}] = 0x{byte:02X} ({byte})")
                else:
                    print(f"\n✗ Invalid response: {parsed['error']}")

        return 0

    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


# ============================================================================
# Module Usage Example
# ============================================================================
if __name__ == '__main__':
    if len(sys.argv) == 1:
        print(__doc__)
        print("\n" + "=" * 70)
        print("USAGE EXAMPLES (as Python module)")
        print("=" * 70)
        print("""
# Import the module
from i2c_slave_cdc_test import *

# Example 1: Set slave address to 0x25
frame = i2c_slave_set_address(0x25)
print(frame.hex())  # AA5534000125...

# Example 2: Write to registers
frame = i2c_slave_write_registers(start_addr=2, data=[0x11, 0x22])
print(frame.hex())  # AA5535000402021122...

# Example 3: Read from registers
frame = i2c_slave_read_registers(start_addr=0, read_len=4)
print(frame.hex())  # AA5536000200046E

# Example 4: Send via serial and get response
import serial
with serial.Serial('COM3', 115200, timeout=1) as ser:
    # Write test data
    write_frame = i2c_slave_write_registers(0, [0xAA, 0xBB, 0xCC, 0xDD])
    ser.write(write_frame)

    time.sleep(0.1)

    # Read back
    read_frame = i2c_slave_read_registers(0, 4)
    ser.write(read_frame)
    response = ser.read(100)

    parsed = parse_upload_response(response)
    if parsed['valid']:
        print(f"Register values: {parsed['data'].hex()}")
        """)
        print("\n" + "=" * 70)
        print("For command line usage, run:")
        print(f"  python {sys.argv[0]} --help")
        print("=" * 70)
        sys.exit(0)

    sys.exit(main())
