#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import argparse

# --- Configuration Constants ---
CMD_SPI_WRITE = 0x11
FRAME_HEADER = [0xAA, 0x55]

def generate_spi_command(write_data: list, read_len: int):
    """
    Generates an SPI command frame for write and/or read operations.

    Args:
        write_data (list): List of bytes to write (can be empty for read-only).
        read_len (int): Number of bytes to read back from SPI slave.

    Returns:
        tuple: (hex_string, frame_bytes) or None if inputs are invalid.
    """
    print("--- Generating SPI Command ---")

    # 1. Parameter validation
    if not isinstance(write_data, list):
        print("Error: write_data must be a list of bytes.")
        return None

    if read_len < 0 or read_len > 255:
        print(f"Error: read_len must be between 0 and 255. Got: {read_len}")
        return None

    write_len = len(write_data)
    if write_len > 255:
        print(f"Error: write_data length must not exceed 255 bytes. Got: {write_len}")
        return None

    # Check all write data bytes are in valid range
    for i, byte in enumerate(write_data):
        if not (0 <= byte <= 255):
            print(f"Error: write_data[{i}] = {byte} is not a valid byte (0-255).")
            return None

    print(f"  Write Length: {write_len} bytes")
    print(f"  Read Length:  {read_len} bytes")
    if write_len > 0:
        print(f"  Write Data:   {' '.join(f'0x{b:02X}' for b in write_data)}")

    # 2. Build payload
    # Payload format: [write_len, read_len, data0, data1, ...]
    payload = [write_len, read_len]
    payload.extend(write_data)

    payload_length = len(payload)  # 2 + write_len

    # 3. Build frame for checksum calculation
    frame_for_checksum = [
        CMD_SPI_WRITE,
        (payload_length >> 8) & 0xFF,  # Length High Byte
        payload_length & 0xFF,         # Length Low Byte
    ]
    frame_for_checksum.extend(payload)

    # 4. Calculate checksum
    checksum = sum(frame_for_checksum) & 0xFF

    # 5. Assemble final frame
    final_frame = FRAME_HEADER + frame_for_checksum + [checksum]

    # 6. Format as hex string
    hex_string = ' '.join(f"{byte:02X}" for byte in final_frame)

    print(f"\n  Payload Length: {payload_length} bytes")
    print(f"  Checksum: 0x{checksum:02X}")

    return hex_string, final_frame

def parse_hex_string(hex_str: str):
    """
    Parse a hex string like "DE AD BE EF" into a list of integers.

    Args:
        hex_str (str): Space or comma-separated hex values.

    Returns:
        list: List of byte values.
    """
    # Remove possible separators and split
    hex_str = hex_str.replace(',', ' ').strip()
    if not hex_str:
        return []

    bytes_list = []
    for token in hex_str.split():
        try:
            # Support both 0x prefix and plain hex
            if token.startswith('0x') or token.startswith('0X'):
                value = int(token, 16)
            else:
                value = int(token, 16)

            if 0 <= value <= 255:
                bytes_list.append(value)
            else:
                print(f"Warning: Value {token} is out of byte range (0-255), skipping.")
        except ValueError:
            print(f"Warning: Invalid hex value '{token}', skipping.")

    return bytes_list

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate an SPI command for the FPGA Multifunctional Debugger.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog="""
Examples:
  # Write 4 bytes, read 4 bytes back
  python spi_command.py -w "DE AD BE EF" -r 4

  # Read only (2 bytes)
  python spi_command.py -r 2

  # Write only (no read)
  python spi_command.py -w "01 02 03"

  # Using hex prefix
  python spi_command.py -w "0xDE 0xAD 0xBE 0xEF" -r 4
"""
    )
    parser.add_argument("-w", "--write", type=str, default="",
                        help='Hex string of bytes to write (e.g., "DE AD BE EF" or "0xDE 0xAD")')
    parser.add_argument("-r", "--read", type=int, default=0,
                        help="Number of bytes to read back from SPI slave (0-255)")

    args = parser.parse_args()

    # Parse write data
    write_data = parse_hex_string(args.write) if args.write else []

    # Check at least one operation specified
    if len(write_data) == 0 and args.read == 0:
        print("Error: Must specify at least one of --write or --read.")
        parser.print_help()
        exit(1)

    result = generate_spi_command(write_data, args.read)

    if result:
        hex_str, frame_bytes = result
        print("\n--- Generated Command ---")
        print(f"Instruction Frame (Hex):")
        print(f"\n{hex_str}\n")
        print("Action: Copy the line above and send it using your serial terminal's hex mode.")
        print(f"\nFrame breakdown:")
        print(f"  Header:     AA 55")
        print(f"  CMD:        11 (SPI_WRITE)")
        print(f"  Length:     {(len(frame_bytes)-6) >> 8:02X} {(len(frame_bytes)-6) & 0xFF:02X}")
        print(f"  Write Len:  {len(write_data):02X}")
        print(f"  Read Len:   {args.read:02X}")
        if write_data:
            print(f"  Write Data: {' '.join(f'{b:02X}' for b in write_data)}")
        print(f"  Checksum:   {frame_bytes[-1]:02X}")
