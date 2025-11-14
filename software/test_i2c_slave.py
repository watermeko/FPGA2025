#!/usr/bin/env python3
"""
I2C Slave CDC Test Script
=========================

Complete test suite for I2C slave register read/write via CDC commands.

This script performs comprehensive testing of:
  - 0x35: CDC Write to Registers
  - 0x36: CDC Read from Registers

Usage:
    python test_i2c_slave.py COM3          # Test on COM3
    python test_i2c_slave.py /dev/ttyUSB0  # Test on Linux
"""

import sys
import serial
import time
from i2c_slave_cdc_test import (
    i2c_slave_write_registers,
    i2c_slave_read_registers,
    parse_upload_response,
    print_frame
)

def test_full_register_write_read(ser):
    """
    Test Case 1: Full Register Write-Read Cycle
    Write all 4 registers and read them back
    """
    print("\n" + "="*70)
    print("TEST CASE 1: Full Register Write-Read Cycle")
    print("="*70)

    # Clear buffers
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    # Write test data to all registers
    test_data = [0xAA, 0xBB, 0xCC, 0xDD]
    print(f"\nStep 1: Writing test data to Reg[0:3]")
    print(f"  Data: {' '.join(f'0x{b:02X}' for b in test_data)}")

    write_frame = i2c_slave_write_registers(0, test_data)
    print(f"  Command: {write_frame.hex().upper()}")
    ser.write(write_frame)
    time.sleep(0.1)
    print("  ✓ Write command sent")

    # Read back all registers
    print(f"\nStep 2: Reading back Reg[0:3]")
    read_frame = i2c_slave_read_registers(0, 4)
    print(f"  Command: {read_frame.hex().upper()}")
    ser.write(read_frame)
    time.sleep(0.15)

    # Parse response
    response = ser.read(100)
    if not response:
        print("  ✗ ERROR: No response received")
        return False

    print(f"  Received: {response.hex().upper()}")

    parsed = parse_upload_response(response)
    if not parsed['valid']:
        print(f"  ✗ ERROR: Invalid response - {parsed['error']}")
        return False

    print(f"  ✓ Valid response received")
    print(f"\nStep 3: Verifying data")

    # Verify each register
    all_match = True
    for i, byte in enumerate(parsed['data']):
        expected = test_data[i]
        match = byte == expected
        status = "✓" if match else "✗"
        print(f"  {status} Reg[{i}] = 0x{byte:02X} {'(OK)' if match else f'(Expected 0x{expected:02X})'}")
        all_match = all_match and match

    if all_match:
        print(f"\n  ✓ TEST 1 PASSED: All registers match!")
        return True
    else:
        print(f"\n  ✗ TEST 1 FAILED: Data mismatch")
        return False


def test_partial_register_write_read(ser):
    """
    Test Case 2: Partial Register Write-Read
    Write only Reg[2:3] and read them back
    """
    print("\n" + "="*70)
    print("TEST CASE 2: Partial Register Write-Read")
    print("="*70)

    ser.reset_input_buffer()
    ser.reset_output_buffer()

    # Write to registers 2 and 3
    test_data = [0x11, 0x22]
    print(f"\nStep 1: Writing test data to Reg[2:3]")
    print(f"  Data: {' '.join(f'0x{b:02X}' for b in test_data)}")

    write_frame = i2c_slave_write_registers(2, test_data)
    print(f"  Command: {write_frame.hex().upper()}")
    ser.write(write_frame)
    time.sleep(0.1)
    print("  ✓ Write command sent")

    # Read back registers 2 and 3
    print(f"\nStep 2: Reading back Reg[2:3]")
    read_frame = i2c_slave_read_registers(2, 2)
    print(f"  Command: {read_frame.hex().upper()}")
    ser.write(read_frame)
    time.sleep(0.15)

    response = ser.read(100)
    if not response:
        print("  ✗ ERROR: No response received")
        return False

    print(f"  Received: {response.hex().upper()}")

    parsed = parse_upload_response(response)
    if not parsed['valid']:
        print(f"  ✗ ERROR: Invalid response - {parsed['error']}")
        return False

    print(f"  ✓ Valid response received")
    print(f"\nStep 3: Verifying data")

    all_match = True
    for i, byte in enumerate(parsed['data']):
        reg_addr = 2 + i
        expected = test_data[i]
        match = byte == expected
        status = "✓" if match else "✗"
        print(f"  {status} Reg[{reg_addr}] = 0x{byte:02X} {'(OK)' if match else f'(Expected 0x{expected:02X})'}")
        all_match = all_match and match

    if all_match:
        print(f"\n  ✓ TEST 2 PASSED: Partial registers match!")
        return True
    else:
        print(f"\n  ✗ TEST 2 FAILED: Data mismatch")
        return False


def test_single_register_operations(ser):
    """
    Test Case 3: Single Register Operations
    Test writing and reading individual registers
    """
    print("\n" + "="*70)
    print("TEST CASE 3: Single Register Operations")
    print("="*70)

    test_values = [0x12, 0x34, 0x56, 0x78]
    all_passed = True

    for reg_addr in range(4):
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        test_value = test_values[reg_addr]
        print(f"\nTesting Reg[{reg_addr}]")
        print(f"  Writing: 0x{test_value:02X}")

        # Write single register
        write_frame = i2c_slave_write_registers(reg_addr, [test_value])
        ser.write(write_frame)
        time.sleep(0.1)

        # Read single register
        read_frame = i2c_slave_read_registers(reg_addr, 1)
        ser.write(read_frame)
        time.sleep(0.15)

        response = ser.read(100)
        if not response:
            print(f"  ✗ ERROR: No response")
            all_passed = False
            continue

        parsed = parse_upload_response(response)
        if not parsed['valid']:
            print(f"  ✗ ERROR: Invalid response - {parsed['error']}")
            all_passed = False
            continue

        read_value = parsed['data'][0]
        match = read_value == test_value
        status = "✓" if match else "✗"
        print(f"  {status} Read: 0x{read_value:02X} {'(OK)' if match else f'(Expected 0x{test_value:02X})'}")

        if not match:
            all_passed = False

    if all_passed:
        print(f"\n  ✓ TEST 3 PASSED: All single register operations OK!")
        return True
    else:
        print(f"\n  ✗ TEST 3 FAILED: Some operations failed")
        return False


def test_boundary_conditions(ser):
    """
    Test Case 4: Boundary Conditions
    Test edge cases and limits
    """
    print("\n" + "="*70)
    print("TEST CASE 4: Boundary Conditions")
    print("="*70)

    all_passed = True

    # Test 4a: Write maximum values
    print(f"\nTest 4a: Write maximum values (0xFF) to all registers")
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    max_data = [0xFF, 0xFF, 0xFF, 0xFF]
    write_frame = i2c_slave_write_registers(0, max_data)
    ser.write(write_frame)
    time.sleep(0.1)

    read_frame = i2c_slave_read_registers(0, 4)
    ser.write(read_frame)
    time.sleep(0.15)

    response = ser.read(100)
    if response:
        parsed = parse_upload_response(response)
        if parsed['valid'] and list(parsed['data']) == max_data:
            print(f"  ✓ Maximum values OK: {parsed['data'].hex().upper()}")
        else:
            print(f"  ✗ Maximum values failed")
            all_passed = False
    else:
        print(f"  ✗ No response")
        all_passed = False

    # Test 4b: Write minimum values
    print(f"\nTest 4b: Write minimum values (0x00) to all registers")
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    min_data = [0x00, 0x00, 0x00, 0x00]
    write_frame = i2c_slave_write_registers(0, min_data)
    ser.write(write_frame)
    time.sleep(0.1)

    read_frame = i2c_slave_read_registers(0, 4)
    ser.write(read_frame)
    time.sleep(0.15)

    response = ser.read(100)
    if response:
        parsed = parse_upload_response(response)
        if parsed['valid'] and list(parsed['data']) == min_data:
            print(f"  ✓ Minimum values OK: {parsed['data'].hex().upper()}")
        else:
            print(f"  ✗ Minimum values failed")
            all_passed = False
    else:
        print(f"  ✗ No response")
        all_passed = False

    # Test 4c: Write to last register
    print(f"\nTest 4c: Write to last register only (Reg[3])")
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    last_reg_data = [0xEE]
    write_frame = i2c_slave_write_registers(3, last_reg_data)
    ser.write(write_frame)
    time.sleep(0.1)

    read_frame = i2c_slave_read_registers(3, 1)
    ser.write(read_frame)
    time.sleep(0.15)

    response = ser.read(100)
    if response:
        parsed = parse_upload_response(response)
        if parsed['valid'] and parsed['data'][0] == 0xEE:
            print(f"  ✓ Last register OK: 0x{parsed['data'][0]:02X}")
        else:
            print(f"  ✗ Last register failed")
            all_passed = False
    else:
        print(f"  ✗ No response")
        all_passed = False

    if all_passed:
        print(f"\n  ✓ TEST 4 PASSED: All boundary conditions OK!")
        return True
    else:
        print(f"\n  ✗ TEST 4 FAILED: Some boundary tests failed")
        return False


def test_sequential_pattern(ser):
    """
    Test Case 5: Sequential Pattern Test
    Write sequential values and verify
    """
    print("\n" + "="*70)
    print("TEST CASE 5: Sequential Pattern Test")
    print("="*70)

    ser.reset_input_buffer()
    ser.reset_output_buffer()

    # Write sequential pattern
    pattern = [0x01, 0x02, 0x04, 0x08]
    print(f"\nStep 1: Writing sequential pattern: {' '.join(f'0x{b:02X}' for b in pattern)}")

    write_frame = i2c_slave_write_registers(0, pattern)
    ser.write(write_frame)
    time.sleep(0.1)
    print("  ✓ Pattern written")

    # Read back
    print(f"\nStep 2: Reading back pattern")
    read_frame = i2c_slave_read_registers(0, 4)
    ser.write(read_frame)
    time.sleep(0.15)

    response = ser.read(100)
    if not response:
        print("  ✗ ERROR: No response")
        return False

    parsed = parse_upload_response(response)
    if not parsed['valid']:
        print(f"  ✗ ERROR: Invalid response - {parsed['error']}")
        return False

    print(f"  ✓ Response received: {parsed['data'].hex().upper()}")

    if list(parsed['data']) == pattern:
        print(f"\n  ✓ TEST 5 PASSED: Sequential pattern verified!")
        return True
    else:
        print(f"\n  ✗ TEST 5 FAILED: Pattern mismatch")
        return False


def main():
    """Main test runner"""
    if len(sys.argv) < 2:
        print(__doc__)
        print("\nError: Serial port not specified")
        print(f"Usage: python {sys.argv[0]} <serial_port>")
        print("\nExamples:")
        print(f"  python {sys.argv[0]} COM3          # Windows")
        print(f"  python {sys.argv[0]} /dev/ttyUSB0  # Linux")
        sys.exit(1)

    port = sys.argv[1]
    baudrate = 115200

    print("="*70)
    print("I2C SLAVE CDC COMMAND TEST SUITE")
    print("="*70)
    print(f"\nConfiguration:")
    print(f"  Serial Port: {port}")
    print(f"  Baud Rate:   {baudrate}")
    print(f"  Timeout:     2 seconds")

    # Try to open serial port
    try:
        ser = serial.Serial(port, baudrate, timeout=2)
        print(f"\n✓ Serial port opened successfully")
    except serial.SerialException as e:
        print(f"\n✗ Failed to open serial port: {e}")
        print("\nTroubleshooting:")
        print("  1. Check if the port name is correct")
        print("  2. Make sure the FPGA board is connected")
        print("  3. Close any other applications using the port")
        sys.exit(1)

    # Run test suite
    results = {}

    try:
        with ser:
            results['test1'] = test_full_register_write_read(ser)
            time.sleep(0.2)

            results['test2'] = test_partial_register_write_read(ser)
            time.sleep(0.2)

            results['test3'] = test_single_register_operations(ser)
            time.sleep(0.2)

            results['test4'] = test_boundary_conditions(ser)
            time.sleep(0.2)

            results['test5'] = test_sequential_pattern(ser)

    except KeyboardInterrupt:
        print("\n\n✗ Test interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n✗ Test error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # Print summary
    print("\n" + "="*70)
    print("TEST SUMMARY")
    print("="*70)

    test_names = [
        "Test 1: Full Register Write-Read",
        "Test 2: Partial Register Write-Read",
        "Test 3: Single Register Operations",
        "Test 4: Boundary Conditions",
        "Test 5: Sequential Pattern"
    ]

    passed = sum(results.values())
    total = len(results)

    for i, (test_key, test_name) in enumerate(zip(results.keys(), test_names), 1):
        result = results[test_key]
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {status}  {test_name}")

    print(f"\n  Results: {passed}/{total} tests passed")

    if passed == total:
        print("\n  🎉 ALL TESTS PASSED! 🎉")
        print("\n  I2C Slave CDC commands are working correctly!")
        sys.exit(0)
    else:
        print(f"\n  ⚠️  {total - passed} test(s) failed")
        print("\n  Check the test output above for details.")
        sys.exit(1)


if __name__ == '__main__':
    main()
