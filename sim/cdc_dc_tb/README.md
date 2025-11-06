# CDC Digital Capture Integration Simulation

This directory contains the ModelSim simulation environment for testing the Digital Capture Handler integrated with the full CDC module.

## Overview

This simulation verifies the **Digital Capture (DC) Handler** integration with the CDC system, testing:
- Command parsing for START (0x0B) and STOP (0x0C) commands
- MUX arbitration between DC direct upload and protocol-encapsulated upload
- Direct upload mode (raw data streaming without protocol headers)
- Multi-rate sampling configurations
- Data correctness across different test patterns

## Key Features

- **Direct Upload Mode**: DC data bypasses protocol encapsulation
- **MUX Arbitration**: DC handler gets highest priority when active
- **Configurable Sample Rate**: Via clock divider parameter
- **Real-time Streaming**: Continuous 8-channel capture
- **Full CDC Integration**: Tests complete system including protocol parser, command processor, and upload pipeline

## Files

- `cmd.do` - ModelSim TCL simulation script
- `../../rtl/cdc.v` - Top-level CDC module with DC integration
- `../../rtl/logic/digital_capture_handler.v` - DC handler module
- `../../tb/cdc_dc_tb.sv` - SystemVerilog testbench

## Running Simulation

### Method 1: From ModelSim GUI
```tcl
cd F:\FPGA2025\sim\cdc_dc_tb
do cmd.do
```

### Method 2: From Command Line
```bash
cd F:\FPGA2025\sim\cdc_dc_tb
vsim -do cmd.do
```

## Test Coverage

The testbench runs 5 comprehensive tests:

### Test 1: Static Pattern 0xAA @ 1MHz
- **Divider**: 60 (60MHz / 60 = 1MHz)
- **Input**: 10101010 (static)
- **Duration**: 100μs
- **Expected**: ~100 samples, all 0xAA

### Test 2: Static Pattern 0x55 @ 2MHz
- **Divider**: 30 (60MHz / 30 = 2MHz)
- **Input**: 01010101 (static)
- **Duration**: 50μs
- **Expected**: ~100 samples, all 0x55

### Test 3: Static Pattern 0xFF @ 500kHz
- **Divider**: 120 (60MHz / 120 = 500kHz)
- **Input**: 11111111 (static)
- **Duration**: 200μs
- **Expected**: ~100 samples, all 0xFF

### Test 4: Dynamic Pattern @ 1MHz
- **Divider**: 60 (1MHz)
- **Input**: 0x11 → 0x22 → 0x44 → 0x88 (changes every 30μs)
- **Expected**: ~30 samples of each pattern
- **Note**: Requires waveform inspection

### Test 5: Maximum Sample Rate @ 1.2MHz
- **Divider**: 50 (60MHz / 50 = 1.2MHz)
- **Input**: 10101010 (static)
- **Duration**: 83μs
- **Expected**: ~100 samples, all 0xAA
- **Purpose**: Tests bandwidth limit

## Command Format

### START Command (0x0B)
```
AA 55 0B 00 02 [divider_H] [divider_L] [checksum]
```
- **divider**: 16-bit value, sample_rate = 60MHz / divider
- **Example**: `AA 55 0B 00 02 00 3C 9F` (1MHz sampling)

### STOP Command (0x0C)
```
AA 55 0C 00 00 [checksum]
```
- **Example**: `AA 55 0C 00 00 12`

## Expected Output

### Console Output
- State transitions (H_IDLE → H_RX_CMD → H_CAPTURING)
- Sample data with timestamps
- Pattern verification results
- Pass/Fail summary

### Waveform Signals
1. **Top Level**: Clock, reset, USB interface, DC inputs
2. **Protocol Parser**: Frame parsing and command extraction
3. **Command Processor**: Command distribution to handlers
4. **DC Handler**: State machine, control signals, captured data
5. **MUX Arbitration**: Direct upload path selection logic
6. **USB Upload**: Final output data stream

## Verification Points

✅ **Command Parsing**
- Parser correctly extracts 0x0B and 0x0C commands
- Command processor routes to DC handler
- Handler enters RX_CMD state

✅ **MUX Arbitration**
- `dc_upload_active` asserts when capturing
- `final_upload_source` = 0x0B during capture
- DC path bypasses protocol encapsulation

✅ **Direct Upload**
- `usb_upload_data` contains raw samples (no protocol headers)
- No 0xAA44 frame headers in upload stream
- Data matches `dc_signal_in` patterns

✅ **Sample Rate Control**
- `sample_tick` frequency matches configured divider
- Sample count matches expected rate × duration

✅ **Data Correctness**
- Static patterns: All samples match input pattern
- Dynamic patterns: Samples track input changes
- No sample loss or corruption

## Signal Groups in Wave Window

1. **Top Level**: Basic I/O and digital capture inputs
2. **Protocol Parser**: Command frame parsing
3. **Command Processor**: Command distribution
4. **DC Handler**: State machine and capture control
5. **MUX Arbitration**: Direct upload path selection
6. **USB Upload**: Final output data stream
7. **TB Status**: Testbench statistics and errors

## Success Criteria

✅ Handler responds to START/STOP commands
✅ MUX selects DC path when `dc_upload_active` is high
✅ Sampling rate matches configured divider
✅ Captured data matches input pattern
✅ Upload source identifier is 0x0B
✅ Capture stops when STOP command sent
✅ No protocol headers in upload stream (direct mode)

## Debugging

If simulation fails, check:

1. **Command Parsing**:
   - `u_parser/parse_done` should pulse after complete frame
   - `u_parser/cmd_out` should be 0x0B or 0x0C

2. **Handler State**:
   - Should transition: H_IDLE → H_RX_CMD → H_CAPTURING
   - `cmd_ready` should be high when idle

3. **MUX Selection**:
   - `dc_upload_active` should be high during capture
   - `final_upload_source` should be 0x0B (not 0x01/0x03/0x0A)

4. **Sample Timing**:
   - `sample_tick` period should match: divider × CLK_PERIOD
   - `upload_valid` should pulse for each new sample

5. **Data Path**:
   - `captured_data_sync` should match `dc_signal_in`
   - `usb_upload_data` should match `captured_data_sync`

## Known Issues

- **First Sample Latency**: Due to double-buffering, first sample may show previous pattern (design feature, not bug)
- **Sample Count Variance**: Actual sample count may vary ±5% due to timing edges
- **Dynamic Pattern Test**: Requires manual waveform inspection for validation

## Architecture Notes

### Direct Upload Path
```
DC Handler → MUX → Command Processor → USB Output
             ↑
             └── Merged Upload Path (UART/SPI/DSM with protocol)
```

### MUX Selection Logic
```verilog
assign final_upload_req    = dc_upload_active ? dc_upload_req    : merged_upload_req;
assign final_upload_data   = dc_upload_active ? dc_upload_data   : merged_upload_data;
assign final_upload_source = dc_upload_active ? 8'h0B            : merged_upload_source;
assign final_upload_valid  = dc_upload_active ? dc_upload_valid  : merged_upload_valid;
```

## Performance Limits

- **Maximum Sample Rate**: 1.2 MHz (divider = 50)
- **Recommended Rate**: ≤ 1 MHz for stability
- **Bandwidth**: ~1.2 MB/s (USB Full Speed limit)
- **Channels**: 8 parallel channels (1 byte per sample)

## Related Documentation

- [USB-CDC Protocol Specification](../../doc/USB-CDC通信协议.md)
- [Digital Capture Handler](../../rtl/logic/digital_capture_handler.v)
- [CDC Top Module](../../rtl/cdc.v)
- [Standalone DC Simulation](../digital_capture_tb/)

---

**Created**: 2025-01-15
**Author**: AI Assistant
**Reference**: F:\FPGA2025\sim\cdc_dsm_simple_tb
**Status**: Ready for testing
