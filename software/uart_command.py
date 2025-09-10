import struct
import argparse

# Constants from the protocol
FRAME_HEADER = b'\xAA\x55'
CMD_UART_CONFIG = 0x07
CMD_UART_TX = 0x08
CMD_UART_RX = 0x09

def calculate_checksum(frame_bytes):
    """Calculates the checksum for a given frame (excluding the header)."""
    return sum(frame_bytes) & 0xFF

def generate_uart_config_command(baud_rate, data_bits, stop_bits, parity):
    """
    Generates a command frame to configure the UART.
    - baud_rate: 32-bit integer (e.g., 115200)
    - data_bits: 8-bit integer (e.g., 8)
    - stop_bits: 8-bit integer (0 for 1, 1 for 1.5, 2 for 2)
    - parity: 8-bit integer (0 for None, 1 for Odd, 2 for Even)
    """
    # Data Body: Baud (4 bytes), Data Bits (1), Stop Bits (1), Parity (1)
    # struct.pack uses '>' for big-endian, 'I' for unsigned 32-bit int, 'B' for 8-bit unsigned int
    data_body = struct.pack('>IBBB', baud_rate, data_bits, stop_bits, parity)
    
    # Data Length: 2 bytes, big-endian
    data_length = len(data_body)
    
    # Frame without header and checksum
    frame_core = struct.pack('>BH', CMD_UART_CONFIG, data_length) + data_body
    
    # Calculate checksum
    checksum = calculate_checksum(frame_core)
    
    # Final frame
    full_frame = FRAME_HEADER + frame_core + struct.pack('B', checksum)
    
    return full_frame

def generate_uart_tx_command(payload):
    """
    Generates a command frame to send data via UART.
    - payload: A bytes object or a string that will be encoded to bytes.
    """
    if isinstance(payload, str):
        payload = payload.encode('utf-8')
        
    # Data Length: 2 bytes, big-endian
    data_length = len(payload)
    
    # Frame without header and checksum
    frame_core = struct.pack('>BH', CMD_UART_TX, data_length) + payload
    
    # Calculate checksum
    checksum = calculate_checksum(frame_core)
    
    # Final frame
    full_frame = FRAME_HEADER + frame_core + struct.pack('B', checksum)
    
    return full_frame

def generate_uart_rx_command():
    """
    Generates a command frame to request data from the UART.
    This command has no data body.
    """
    # Data Length is 0
    data_length = 0
    
    # Frame without header and checksum
    frame_core = struct.pack('>BH', CMD_UART_RX, data_length)
    
    # Calculate checksum
    checksum = calculate_checksum(frame_core)
    
    # Final frame
    full_frame = FRAME_HEADER + frame_core + struct.pack('B', checksum)
    
    return full_frame

def print_frame_as_hex(name, frame):
    """Helper function to print a command frame in a readable hex format."""
    hex_str = ' '.join(f'{b:02X}' for b in frame)
    print(f"{name}:")
    print(f"  - Bytes: {hex_str}")
    print(f"  - Length: {len(frame)} bytes\n")

def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Generate UART command frames for the protocol.")
    
    # Create subparsers for different command types
    subparsers = parser.add_subparsers(dest='command', help='Command type')
    
    # Parser for UART config command
    config_parser = subparsers.add_parser('config', help='Generate UART configuration command')
    config_parser.add_argument('--baud', type=int, default=9600, help='Baud rate (default: 9600)')
    config_parser.add_argument('--data-bits', type=int, default=8, choices=[5, 6, 7, 8], 
                               help='Data bits (5, 6, 7, 8, default: 8)')
    config_parser.add_argument('--stop-bits', type=int, default=0, choices=[0, 1, 2],
                               help='Stop bits (0=1, 1=1.5, 2=2, default: 0)')
    config_parser.add_argument('--parity', type=int, default=0, choices=[0, 1, 2],
                               help='Parity (0=None, 1=Odd, 2=Even, default: 0)')
    
    # Parser for UART TX command
    tx_parser = subparsers.add_parser('tx', help='Generate UART transmit command')
    tx_parser.add_argument('data', type=str, help='Data to send')
    
    # Parser for UART RX command
    rx_parser = subparsers.add_parser('rx', help='Generate UART receive command')
    
    return parser.parse_args()

def main():
    """Main function to handle command line arguments and generate commands."""
    args = parse_arguments()
    
    if args.command == 'config':
        # Generate UART configuration command
        frame = generate_uart_config_command(
            args.baud, args.data_bits, args.stop_bits, args.parity
        )
        print_frame_as_hex("UART Config Command", frame)
        
    elif args.command == 'tx':
        # Generate UART transmit command
        frame = generate_uart_tx_command(args.data)
        print_frame_as_hex("UART TX Command", frame)
        
    elif args.command == 'rx':
        # Generate UART receive command
        frame = generate_uart_rx_command()
        print_frame_as_hex("UART RX Command", frame)
        
    else:
        print("Please specify a command type: config, tx, or rx")
        print("Use --help for more information.")

if __name__ == "__main__":
    main()
