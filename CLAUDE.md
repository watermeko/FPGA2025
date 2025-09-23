# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

**FPGA Development**:
- Open project: Load `fpga_project.gprj` in GOWIN EDA IDE
- Target device: GW5A-25A FPGA (GW5A-LV25UG324C2/I1)
- Build: Use GOWIN EDA GUI (Synthesis → Place & Route → Generate Bitstream)

**Simulation**:
```bash
# Run ModelSim simulation (from project root)
modelsim -do sim/cdc_tb/cmd.do        # Main CDC testbench
modelsim -do sim/dds_tb/cmd.do        # DDS signal generator testbench
```

**Host Software Tools**:
```bash
# PWM command generation
python software/pwm_command_generator.py -c <channel> -f <frequency> -d <duty_cycle>

# UART command generation  
python software/uart_command.py config --baud 115200 --data-bits 8 --stop-bits 0 --parity 0
python software/uart_command.py tx "Hello World"
python software/uart_command.py rx
```

## Architecture Overview

**System Type**: Multi-protocol communication hub with signal generation for GOWIN FPGA

**Core Communication Flow**:
1. **USB CDC Interface** (`rtl/usb/`) - Host PC communication
2. **Protocol Parser** (`rtl/protocol_parser.v`) - Parses command frames (Header: 0xAA55)
3. **Command Processor** (`rtl/command_processor.v`) - Routes to subsystems
4. **Peripheral Modules**: UART (`rtl/uart/`), PWM (`rtl/pwm/`), DDS (`rtl/dds/`)

**Frame Protocol Structure**: 
`Header(2) + Command(1) + Length(2) + Data(0-65535) + Checksum(1) + Status(1)`

**Command Types**:
- UART: 0x07 (config), 0x08 (TX), 0x09 (RX)
- PWM: 0xFE
- Heartbeat: 0xFF

## Key Design Patterns

- **Data-driven architecture** with central command dispatcher
- **FIFO-based data flow** for USB/UART communications  
- **State machine control** for protocol parsing
- **Modular peripheral handlers** with consistent interfaces

## File Structure

- `rtl/` - HDL source (Verilog/SystemVerilog/VHDL)
- `tb/` - Testbenches
- `sim/` - ModelSim simulation projects with `.do` scripts
- `constraints/pin_cons.cst` - Pin constraints
- `impl/` - Synthesis/P&R results (excluded from git)
- `software/` - Python host tools
- `doc/USB-CDC通信协议.md` - Complete protocol specification

## Development Workflow

1. RTL changes: Edit files in `rtl/`, build with GOWIN EDA
2. Testing: Run appropriate ModelSim testbench from `sim/`
3. Protocol testing: Use Python tools in `software/` to generate test commands
4. Hardware validation: Flash to FPGA and test via USB CDC interface