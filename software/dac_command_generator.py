#!/usr/bin/env python3
"""
DAC Command Generator for FPGA CDC Communication System (Dual-Channel)

This script generates DAC configuration commands for the USB-CDC protocol.
It calculates the correct frequency and phase words for DDS waveform generation.
Supports dual-channel (A/B) independent configuration.

Author: Claude Code Assistant
Date: 2025-01-26
"""

import argparse
import struct
import math

# Protocol constants
DAC_CMD = 0xFD
FRAME_HEADER = [0xAA, 0x55]
DATA_LENGTH = 10  # Channel (1) + Wave type (1) + Frequency word (4) + Phase word (4)

# DAC clock frequency in Hz
DAC_CLOCK_FREQ = 120_000_000  # 120MHz

# Wave type definitions
WAVE_TYPES = {
    'sine': 0,
    'sin': 0,
    'triangle': 1,
    'tri': 1,
    'sawtooth': 2,
    'saw': 2,
    'square': 3,
    'sqr': 3
}

def calculate_frequency_word(target_freq_hz, dac_clock_hz=DAC_CLOCK_FREQ):
    """
    Calculate DDS frequency control word.
    
    Formula: fre_word = (target_frequency × 2^32) / dac_clock_frequency
    
    Args:
        target_freq_hz: Target frequency in Hz
        dac_clock_hz: DAC clock frequency in Hz (default: 200MHz)
    
    Returns:
        32-bit frequency word as integer
    """
    if target_freq_hz <= 0:
        raise ValueError("Target frequency must be positive")
    
    if target_freq_hz > dac_clock_hz / 2:
        raise ValueError(f"Target frequency ({target_freq_hz} Hz) exceeds Nyquist limit ({dac_clock_hz/2} Hz)")
    
    freq_word = int((target_freq_hz * (2**32)) // dac_clock_hz)
    return freq_word

def calculate_phase_word(phase_degrees):
    """
    Calculate DDS phase control word.
    
    Formula: pha_word = (phase_degrees × 2^32) / 360°
    
    Args:
        phase_degrees: Phase in degrees (0-360)
    
    Returns:
        32-bit phase word as integer
    """
    if not (0 <= phase_degrees <= 360):
        raise ValueError("Phase must be between 0 and 360 degrees")
    
    phase_word = int((phase_degrees * (2**32)) // 360)
    return phase_word

def calculate_checksum(data):
    """
    Calculate checksum as sum of all bytes (low 8 bits).
    
    Args:
        data: List of bytes
    
    Returns:
        8-bit checksum
    """
    return sum(data) & 0xFF

def generate_dac_command(wave_type, frequency_hz, phase_degrees=0, channel='A'):
    """
    Generate complete DAC configuration command frame.

    Args:
        wave_type: Wave type string ('sine', 'triangle', 'sawtooth', 'square')
        frequency_hz: Target frequency in Hz
        phase_degrees: Phase in degrees (default: 0)
        channel: DAC channel 'A' or 'B' (default: 'A')

    Returns:
        List of bytes representing the complete command frame
    """
    # Validate wave type
    if wave_type.lower() not in WAVE_TYPES:
        raise ValueError(f"Invalid wave type. Must be one of: {list(WAVE_TYPES.keys())}")

    # Validate channel
    if channel.upper() not in ['A', 'B']:
        raise ValueError("Channel must be 'A' or 'B'")

    wave_type_code = WAVE_TYPES[wave_type.lower()]
    channel_code = 0 if channel.upper() == 'A' else 1

    # Calculate frequency and phase words
    freq_word = calculate_frequency_word(frequency_hz)
    phase_word = calculate_phase_word(phase_degrees)

    # Build command frame
    frame = []

    # Header
    frame.extend(FRAME_HEADER)  # [0xAA, 0x55]

    # Command
    frame.append(DAC_CMD)  # 0xFD

    # Data length (big-endian)
    frame.append(0x00)  # Length high byte
    frame.append(DATA_LENGTH)  # Length low byte (10 bytes)

    # Data payload
    frame.append(channel_code)    # Channel selection (1 byte)
    frame.append(wave_type_code)  # Wave type (1 byte)

    # Frequency word (32-bit, big-endian)
    freq_bytes = struct.pack('>I', freq_word)  # Big-endian 32-bit unsigned int
    frame.extend(freq_bytes)

    # Phase word (32-bit, big-endian)
    phase_bytes = struct.pack('>I', phase_word)  # Big-endian 32-bit unsigned int
    frame.extend(phase_bytes)

    # Calculate and append checksum
    checksum_data = [DAC_CMD, 0x00, DATA_LENGTH] + frame[5:]  # CMD + LEN + DATA
    checksum = calculate_checksum(checksum_data)
    frame.append(checksum)

    return frame

def format_command_output(command_bytes, wave_type, frequency_hz, phase_degrees, channel='A'):
    """
    Format command output for display.

    Args:
        command_bytes: List of command bytes
        wave_type: Wave type string
        frequency_hz: Frequency in Hz
        phase_degrees: Phase in degrees
        channel: DAC channel 'A' or 'B'

    Returns:
        Formatted string
    """
    # Extract frequency and phase words for display
    freq_word = struct.unpack('>I', bytes(command_bytes[7:11]))[0]
    phase_word = struct.unpack('>I', bytes(command_bytes[11:15]))[0]

    output = []
    output.append("=" * 60)
    output.append("DAC COMMAND GENERATOR (Dual-Channel)")
    output.append("=" * 60)
    output.append(f"DAC Channel:    {channel}")
    output.append(f"Wave Type:      {wave_type.capitalize()} ({WAVE_TYPES[wave_type.lower()]})")
    output.append(f"Frequency:      {frequency_hz:,} Hz")
    output.append(f"Phase:          {phase_degrees}°")
    output.append(f"DAC Clock:      {DAC_CLOCK_FREQ / 1e6:.1f} MHz")
    output.append("")
    output.append("Calculated Values:")
    output.append(f"Frequency Word: 0x{freq_word:08X} ({freq_word})")
    output.append(f"Phase Word:     0x{phase_word:08X} ({phase_word})")
    output.append("")
    output.append("Command Frame ({} bytes):".format(len(command_bytes)))

    # Format as hex bytes
    hex_str = " ".join([f"{b:02X}" for b in command_bytes])
    output.append(hex_str)

    # Format as C array
    c_array = "{" + ", ".join([f"0x{b:02X}" for b in command_bytes]) + "}"
    output.append("")
    output.append("C Array Format:")
    output.append(f"uint8_t dac_cmd[] = {c_array};")

    # Format as Python bytes
    output.append("")
    output.append("Python Bytes Format:")
    output.append(f"dac_cmd = bytes([{', '.join([f'0x{b:02X}' for b in command_bytes])}])")

    # Format for UART/Serial transmission
    output.append("")
    output.append("Serial Transmission (one byte per line):")
    for i, byte in enumerate(command_bytes):
        if i < 2:
            desc = "Header"
        elif i == 2:
            desc = "Command"
        elif i < 5:
            desc = f"Length {'H' if i == 3 else 'L'}"
        elif i == 5:
            desc = "Channel"
        elif i == 6:
            desc = "Wave Type"
        elif i < 11:
            desc = f"Freq Word [{i-7}]"
        elif i < 15:
            desc = f"Phase Word [{i-11}]"
        else:
            desc = "Checksum"
        output.append(f"  0x{byte:02X}  // {desc}")

    output.append("=" * 60)

    return "\n".join(output)

def validate_frequency(freq_str):
    """
    Parse and validate frequency string with unit suffixes.
    
    Args:
        freq_str: Frequency string (e.g., "1kHz", "2.5MHz", "1000")
    
    Returns:
        Frequency in Hz as float
    """
    freq_str = freq_str.strip().lower()
    
    # Handle unit suffixes
    multipliers = {
        'ghz': 1e9, 'g': 1e9,
        'mhz': 1e6, 'm': 1e6,
        'khz': 1e3, 'k': 1e3,
        'hz': 1, 'h': 1
    }
    
    # Extract numeric part and unit
    import re
    match = re.match(r'^([0-9]*\.?[0-9]+)([a-z]*)$', freq_str)
    if not match:
        raise ValueError("Invalid frequency format")
    
    value_str, unit = match.groups()
    value = float(value_str)
    
    if unit == '':
        # No unit specified, assume Hz
        multiplier = 1
    elif unit in multipliers:
        multiplier = multipliers[unit]
    else:
        raise ValueError(f"Unknown frequency unit: {unit}")
    
    return value * multiplier

def main():
    """Main function with command-line interface."""
    parser = argparse.ArgumentParser(
        description="Generate DAC configuration commands for FPGA CDC system",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s sine 1MHz                      # 1MHz sine wave on Channel A, 0° phase
  %(prog)s sine 1MHz -c B                 # 1MHz sine wave on Channel B
  %(prog)s triangle 500kHz -p 90 -c A     # 500kHz triangle wave, 90° phase, Channel A
  %(prog)s square 2.5MHz -p 180 -c B      # 2.5MHz square wave, 180° phase, Channel B
  %(prog)s sawtooth 100kHz                # 100kHz sawtooth wave on Channel A
  %(prog)s sine 1000 -o output.txt        # 1kHz sine wave, save to file
        """
    )
    
    parser.add_argument('wave_type',
                        choices=['sine', 'sin', 'triangle', 'tri', 'sawtooth', 'saw', 'square', 'sqr'],
                        help='Waveform type')

    parser.add_argument('frequency',
                        help='Target frequency (supports units: Hz, kHz, MHz, GHz)')

    parser.add_argument('-c', '--channel',
                        choices=['A', 'B', 'a', 'b'],
                        default='A',
                        help='DAC channel (A or B, default: A)')

    parser.add_argument('-p', '--phase',
                        type=float,
                        default=0,
                        help='Phase in degrees (0-360, default: 0)')
    
    parser.add_argument('-o', '--output',
                        help='Output file (default: print to stdout)')
    
    parser.add_argument('-q', '--quiet',
                        action='store_true',
                        help='Only output raw hex bytes')
    
    parser.add_argument('--binary',
                        help='Write binary command to file')
    
    parser.add_argument('--verify',
                        action='store_true',
                        help='Verify calculated values')
    
    args = parser.parse_args()
    
    try:
        # Parse frequency
        frequency_hz = validate_frequency(args.frequency)

        # Validate phase
        if not (0 <= args.phase <= 360):
            raise ValueError("Phase must be between 0 and 360 degrees")

        # Validate channel
        channel = args.channel.upper()

        # Generate command
        command_bytes = generate_dac_command(args.wave_type, frequency_hz, args.phase, channel)
        
        if args.quiet:
            # Output only hex bytes
            hex_output = " ".join([f"{b:02X}" for b in command_bytes])
            if args.output:
                with open(args.output, 'w') as f:
                    f.write(hex_output + "\n")
            else:
                print(hex_output)
        else:
            # Full formatted output
            output_text = format_command_output(command_bytes, args.wave_type, frequency_hz, args.phase, channel)
            
            if args.output:
                with open(args.output, 'w') as f:
                    f.write(output_text)
                print(f"Command saved to {args.output}")
            else:
                print(output_text)
        
        # Write binary file if requested
        if args.binary:
            with open(args.binary, 'wb') as f:
                f.write(bytes(command_bytes))
            print(f"Binary command saved to {args.binary}")
        
        # Verification
        if args.verify:
            freq_word = struct.unpack('>I', bytes(command_bytes[7:11]))[0]
            phase_word = struct.unpack('>I', bytes(command_bytes[11:15]))[0]
            
            # Verify frequency calculation
            calculated_freq = (freq_word * DAC_CLOCK_FREQ) / (2**32)
            freq_error = abs(calculated_freq - frequency_hz) / frequency_hz * 100
            
            # Verify phase calculation  
            calculated_phase = (phase_word * 360) / (2**32)
            phase_error = abs(calculated_phase - args.phase)
            
            print(f"\nVerification:")
            print(f"Target Freq:     {frequency_hz:,.2f} Hz")
            print(f"Calculated Freq: {calculated_freq:,.2f} Hz")
            print(f"Frequency Error: {freq_error:.6f}%")
            print(f"Target Phase:    {args.phase}°")
            print(f"Calculated Phase:{calculated_phase:.6f}°") 
            print(f"Phase Error:     {phase_error:.6f}°")
            
    except Exception as e:
        print(f"Error: {e}", file=__import__('sys').stderr)
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())