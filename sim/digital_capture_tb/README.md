# Digital Capture Handler Simulation

This directory contains the ModelSim simulation environment for the digital capture handler module.

## Overview

The **digital_capture_handler** is an 8-channel digital signal capture module that continuously samples digital input channels and uploads their logic states in real-time.

### Key Features
- **Configurable sampling rate** via clock divider
- **Start/Stop control** via commands (0x0B/0x0C)
- **Real-time streaming** of captured data
- **8 channels** packed into 1 byte per sample
- **Upload source identifier**: 0x0B

## Files

- `cmd.do` - ModelSim TCL simulation script
- `../../rtl/logic/digital_capture_handler.v` - RTL source
- `../../tb/digital_capture_handler_tb.v` - Testbench

## Running Simulation

### Method 1: From ModelSim GUI
```tcl
cd F:\FPGA2025\sim\digital_capture_tb
do cmd.do
```

### Method 2: From Command Line
```bash
cd F:\FPGA2025\sim\digital_capture_tb
vsim -do cmd.do
```

## Test Coverage

The testbench runs 5 comprehensive tests:

### Test 1: 1MHz Sampling, Pattern 0xAA
- Divider: 60 (60MHz / 60 = 1MHz)
- Input: 10101010 (static)
- Duration: 100μs
- Expected samples: ~100

### Test 2: 2MHz Sampling, Pattern 0x55
- Divider: 30 (60MHz / 30 = 2MHz)
- Input: 01010101 (static)
- Duration: 50μs
- Expected samples: ~100

### Test 3: 500kHz Sampling, Pattern 0xFF
- Divider: 120 (60MHz / 120 = 500kHz)
- Input: 11111111 (static)
- Duration: 100μs
- Expected samples: ~50

### Test 4: 100kHz Sampling, Pattern 0x00
- Divider: 600 (60MHz / 600 = 100kHz)
- Input: 00000000 (static)
- Duration: 100μs
- Expected samples: ~10

### Test 5: Dynamic Pattern
- Divider: 60 (1MHz)
- Input: 0x11 → 0x22 → 0x44 → 0x88 (changes every 50μs)
- Tests real-time capture of changing inputs

## Expected Output

The simulation will display:
- State transitions (IDLE → RX_CMD → CAPTURING)
- Sample tick events
- Upload activity
- Captured sample data
- Verification results (✅ PASS / ❌ FAIL)

## Signal Groups in Wave Window

1. **Top Level**: Clock, reset, digital inputs
2. **Command Interface**: Command protocol signals
3. **Handler FSM**: State machines and control
4. **Capture Data**: Captured samples and buffers
5. **Upload Interface**: Data upload flow
6. **TB Statistics**: Sample counters

## Success Criteria

✅ Handler responds to START/STOP commands
✅ Sampling rate matches configured divider
✅ Captured data matches input pattern
✅ Upload source identifier is 0x0B
✅ Capture stops when STOP command sent

## Debugging

If simulation fails, check:
1. **Handler State**: Should transition IDLE → RX_CMD → CAPTURING
2. **Sample Tick**: Should pulse at configured rate
3. **Upload Valid**: Should assert when new sample available
4. **Sample Count**: Should increase during capture

## Waveform Analysis

Key signals to observe:
- `sample_tick` - Sampling clock
- `captured_data` - Raw 8-channel data
- `upload_valid` - Data being uploaded
- `sample_count` - Cumulative samples

## Notes

- Based on `cdc_dsm_simple_tb` reference design
- Uses SystemVerilog constructs (tasks, automatic)
- Includes comprehensive debug monitors
- VCD waveform dump enabled for GTKWave compatibility

---

**Last Updated**: 2025-01-15
**Author**: AI Assistant
**Reference**: F:\FPGA2025\sim\cdc_dsm_simple_tb
