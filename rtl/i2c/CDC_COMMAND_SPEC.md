# I2C Slave CDC Commands Specification

## Overview
This document describes the CDC (Communication Data Channel) commands for controlling the I2C slave module.

---

## Command List

| Command Code | Command Name | Description |
|--------------|--------------|-------------|
| **0x34** | SET_I2C_ADDR | Dynamically set I2C slave address |
| **0x35** | WRITE_REGS | Write data to I2C registers (CDC Preload) |
| **0x36** | READ_REGS | Read data from I2C registers and upload |

---

## Command Details

### 0x34 - SET_I2C_ADDR (Set I2C Slave Address)

**Purpose**: Change the I2C slave address dynamically at runtime.

**Command Format**:
```
Byte Index | Description
-----------|------------------
    0      | New I2C slave address (7-bit, 0x00-0x7F)
```

**Example**:
```c
// Change I2C slave address to 0x50
cmd_type = 0x34
captured_data[0] = 0x50  // New address
```

**Notes**:
- Address is 7-bit (valid range: 0x00-0x7F)
- Takes effect immediately after command execution
- Default address on reset: 0x24

---

### 0x35 - WRITE_REGS (CDC Write to I2C Registers)

**Purpose**: Write data to I2C slave registers from CDC bus. This is the **CDC preload** function that allows internal FPGA logic to preset register values.

**Command Format**:
```
Byte Index | Description
-----------|----------------------------------
    0      | Start register address (0-3)
    1      | Number of bytes to write (1-4)
    2      | Data byte 0
    3      | Data byte 1 (optional)
    4      | Data byte 2 (optional)
    5      | Data byte 3 (optional)
```

**Example 1**: Write single byte to register 0
```c
cmd_type = 0x35
captured_data[0] = 0x00  // Start address = 0
captured_data[1] = 0x01  // Length = 1 byte
captured_data[2] = 0xAA  // Data to write
```

**Example 2**: Write 4 bytes starting from register 0
```c
cmd_type = 0x35
captured_data[0] = 0x00  // Start address = 0
captured_data[1] = 0x04  // Length = 4 bytes
captured_data[2] = 0xAA  // Register 0 = 0xAA
captured_data[3] = 0xBB  // Register 1 = 0xBB
captured_data[4] = 0xCC  // Register 2 = 0xCC
captured_data[5] = 0xDD  // Register 3 = 0xDD
```

**Example 3**: Write 2 bytes starting from register 2
```c
cmd_type = 0x35
captured_data[0] = 0x02  // Start address = 2
captured_data[1] = 0x02  // Length = 2 bytes
captured_data[2] = 0x11  // Register 2 = 0x11
captured_data[3] = 0x22  // Register 3 = 0x22
```

**Notes**:
- Register address range: 0-3 (4 registers total)
- Auto-increment: Address increments automatically for multi-byte writes
- Write data appears in `captured_data[2]` onwards

---

### 0x36 - READ_REGS (CDC Read from I2C Registers)

**Purpose**: Read data from I2C slave registers and upload via CDC upload bus.

**Command Format**:
```
Byte Index | Description
-----------|----------------------------------
    0      | Start register address (0-3)
    1      | Number of bytes to read (1-4)
```

**Upload Data Format**:
- Data is sent via the `upload_data[7:0]` bus
- `upload_source = 0x36` identifies the data source
- `upload_valid` pulses high when data is valid
- Data bytes are sent sequentially with auto-increment addressing

**Example 1**: Read single byte from register 0
```c
cmd_type = 0x36
captured_data[0] = 0x00  // Start address = 0
captured_data[1] = 0x01  // Length = 1 byte

// Response via upload bus:
// upload_data = register[0]
// upload_source = 0x36
```

**Example 2**: Read all 4 registers
```c
cmd_type = 0x36
captured_data[0] = 0x00  // Start address = 0
captured_data[1] = 0x04  // Length = 4 bytes

// Response via upload bus (sequential):
// Cycle 1: upload_data = register[0]
// Cycle 2: upload_data = register[1]
// Cycle 3: upload_data = register[2]
// Cycle 4: upload_data = register[3]
// upload_source = 0x36 for all
```

**Example 3**: Read 2 bytes starting from register 2
```c
cmd_type = 0x36
captured_data[0] = 0x02  // Start address = 2
captured_data[1] = 0x02  // Length = 2 bytes

// Response via upload bus (sequential):
// Cycle 1: upload_data = register[2]
// Cycle 2: upload_data = register[3]
```

**Notes**:
- Register address range: 0-3 (4 registers total)
- Auto-increment: Address increments automatically for multi-byte reads
- Upload is sequential, controlled by `upload_ready` handshake
- Data source identifier: `upload_source = 0x36`

---

## CDC Interface Signals

### Command Input Signals
```systemverilog
input  logic [7:0]  cmd_type;        // Command type (0x34/0x35/0x36)
input  logic [15:0] cmd_length;      // Command length
input  logic [7:0]  cmd_data;        // Command data
input  logic [15:0] cmd_data_index;  // Data index
input  logic        cmd_start;       // Command start pulse
input  logic        cmd_data_valid;  // Data valid signal
input  logic        cmd_done;        // Command done pulse
output logic        cmd_ready;       // Ready for new command
```

### Upload Output Signals
```systemverilog
output logic        upload_active;   // Upload operation active
output logic        upload_req;      // Upload request
output logic [7:0]  upload_data;     // Upload data byte
output logic [7:0]  upload_source;   // Upload source ID (0x36)
output logic        upload_valid;    // Upload data valid
input  logic        upload_ready;    // Upload ready (from receiver)
```

---

## State Machine Flow

```
IDLE → CMD_CAPTURE → EXEC_xxx → FINISH → IDLE
                         ↓
                    (0x34: EXEC_SET_ADDR)
                    (0x35: EXEC_WRITE)
                    (0x36: EXEC_READ_SETUP → UPLOAD_DATA)
```

### States:
- **S_IDLE**: Waiting for command
- **S_CMD_CAPTURE**: Capturing command data
- **S_EXEC_SET_ADDR**: Execute set address (0x34)
- **S_EXEC_WRITE**: Execute write registers (0x35)
- **S_EXEC_READ_SETUP**: Setup read operation (0x36)
- **S_UPLOAD_DATA**: Upload read data
- **S_FINISH**: Command complete

---

## Implementation Notes

1. **Command Priority**: Commands are processed sequentially. New command is accepted only when `cmd_ready = 1` (state = IDLE).

2. **Write Operation** (0x35):
   - Data is written to registers immediately
   - Overwrites previous values (including preloaded values)
   - No acknowledgment signal - assumes success

3. **Read Operation** (0x36):
   - Data is buffered before upload
   - Upload uses handshake protocol with `upload_req` and `upload_ready`
   - Upload continues until all requested bytes are sent

4. **Address Bounds**: All commands check address validity (0-3 range)

5. **Timing**: All operations are synchronous to system clock

---

## Code References

- Command decoder: `i2c_slave_handler.sv:151-159`
- Command 0x34 execution: `i2c_slave_handler.sv:163-167`
- Command 0x35 execution: `i2c_slave_handler.sv:169-177`
- Command 0x36 execution: `i2c_slave_handler.sv:179-203`
- Upload source assignment: `i2c_slave_handler.sv:234`

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-03 | Changed command codes from 0x14/0x15/0x16 to 0x34/0x35/0x36 |

---
