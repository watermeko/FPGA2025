# ==============================================================================
# CDC Digital Capture Integration Testbench ModelSim Simulation Script
# Testing Digital Capture with full CDC module (direct upload mode)
# ==============================================================================

# Quit any running simulation
quit -sim

# ------------------------------------------------------------------------------
# 1. Clean and Create Local Libraries
# ------------------------------------------------------------------------------
# Use catch to prevent errors if libraries don't exist
catch {vdel -lib work -all}
catch {vdel -lib gw5a -all}

vlib work
vmap work work
vlib gw5a
vmap gw5a ./gw5a

# ------------------------------------------------------------------------------
# 2. Compile Gowin Primitives
# ------------------------------------------------------------------------------
echo "Compiling Gowin primitives into local './gw5a' library..."
set GOWIN_PATH "E:/GOWIN/Gowin_V1.9.12_x64/IDE"
vlog -work gw5a "${GOWIN_PATH}/simlib/gw5a/prim_sim.v"

# ------------------------------------------------------------------------------
# 3. Compile All Design and Testbench Files
# ------------------------------------------------------------------------------
echo "Compiling all design and testbench files into './work' library..."

# --- Clock Generation Modules ---
vlog -sv +incdir+../../rtl ../../rtl/clk/gowin_pll/gowin_pll.v
vlog -sv +incdir+../../rtl ../../rtl/clk/Gowin_PLL_24/Gowin_PLL_24.v

# --- DDS Modules ---
vlog -sv +incdir+../../rtl ../../rtl/dds/accuml.v
vlog -sv +incdir+../../rtl ../../rtl/dds/Sin.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DDS.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DAC.sv
vlog -sv +incdir+../../rtl ../../rtl/dds/dac_handler.sv
vlog -sv +incdir+../../rtl ../../rtl/dds/custom_waveform_handler.sv

# --- PWM Modules ---
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm.v
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_handler.v

# --- UART Modules ---
vcom -work work ../../rtl/uart/uart_tx.vhd
vcom -work work ../../rtl/uart/uart_rx.vhd
vlog -sv +incdir+../../rtl ../../rtl/uart/fixed_point_divider/fixed_point_divider.vo
vlog -sv +incdir+../../rtl ../../rtl/uart/uart.v
vlog -sv +incdir+../../rtl ../../rtl/uart/usb_uart_config.v
vlog -sv +incdir+../../rtl ../../rtl/uart/uart_handler.v

# --- SPI Modules ---
vlog -sv +incdir+../../rtl ../../rtl/spi/simple_spi_master.v
vlog -sv +incdir+../../rtl ../../rtl/spi/spi_handler.v

# --- DSM (Digital Signal Measure) Modules ---
vlog -sv +incdir+../../rtl ../../rtl/logic/digital_signal_measure.sv
vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel_handler.sv

# --- Digital Capture Module (NEW) ---
vlog -sv +incdir+../../rtl ../../rtl/logic/digital_capture_handler.v

# --- I2C Modules ---
vlog -sv +incdir+../../rtl ../../rtl/i2c/i2c_bit_shift.v
vlog -sv +incdir+../../rtl ../../rtl/i2c/i2c_control.v
vlog -sv +incdir+../../rtl ../../rtl/i2c/i2c_handler.v

# --- 1-Wire Modules ---
vlog -sv +incdir+../../rtl ../../rtl/one_wire/one_wire_master.v
vlog -sv +incdir+../../rtl ../../rtl/one_wire/one_wire_handler.v

# --- Upload Data Pipeline Modules ---
vlog -sv +incdir+../../rtl ../../rtl/upload_adapter_0.v
vlog -sv +incdir+../../rtl ../../rtl/upload_packer_0.v
vlog -sv +incdir+../../rtl ../../rtl/upload_arbiter_0.v

# --- Core Protocol Modules ---
vlog -sv +incdir+../../rtl ../../rtl/protocol_parser.v
vlog -sv +incdir+../../rtl ../../rtl/command_processor.v

# --- Top CDC Module ---
vlog -sv +incdir+../../rtl ../../rtl/cdc.v

# --- Testbench ---
vlog -sv +incdir+../../rtl ../../tb/cdc_dc_tb.sv

# ------------------------------------------------------------------------------
# 4. Start Simulation
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim -L gw5a work.cdc_dc_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 5. Add Waveforms with Grouping
# ------------------------------------------------------------------------------
echo "Adding waveforms..."

# --- Top Level ---
add wave -group "Top Level" -divider "Clock & Reset"
add wave -group "Top Level" /cdc_dc_tb/clk
add wave -group "Top Level" /cdc_dc_tb/rst_n
add wave -group "Top Level" -divider "USB Interface"
add wave -group "Top Level" -radix hex /cdc_dc_tb/usb_data_in
add wave -group "Top Level" /cdc_dc_tb/usb_data_valid_in
add wave -group "Top Level" -divider "DC Signals"
add wave -group "Top Level" -radix binary /cdc_dc_tb/dc_signal_in

# --- Protocol Parser ---
add wave -group "Protocol Parser" -divider "State"
add wave -group "Protocol Parser" -radix unsigned /cdc_dc_tb/dut/u_parser/state
add wave -group "Protocol Parser" -divider "Outputs"
add wave -group "Protocol Parser" /cdc_dc_tb/dut/u_parser/parse_done
add wave -group "Protocol Parser" /cdc_dc_tb/dut/u_parser/parse_error
add wave -group "Protocol Parser" -radix hex /cdc_dc_tb/dut/u_parser/cmd_out
add wave -group "Protocol Parser" -radix unsigned /cdc_dc_tb/dut/u_parser/len_out

# --- Command Processor ---
add wave -group "Command Processor" -divider "State"
add wave -group "Command Processor" -radix unsigned /cdc_dc_tb/dut/u_command_processor/state
add wave -group "Command Processor" -divider "Command Bus"
add wave -group "Command Processor" -radix hex /cdc_dc_tb/dut/cmd_type
add wave -group "Command Processor" -radix unsigned /cdc_dc_tb/dut/cmd_length
add wave -group "Command Processor" /cdc_dc_tb/dut/cmd_start
add wave -group "Command Processor" /cdc_dc_tb/dut/cmd_data_valid
add wave -group "Command Processor" -radix hex /cdc_dc_tb/dut/cmd_data
add wave -group "Command Processor" /cdc_dc_tb/dut/cmd_done
add wave -group "Command Processor" /cdc_dc_tb/dut/cmd_ready

# --- DC Handler ---
add wave -group "DC Handler" -divider "State"
add wave -group "DC Handler" -radix unsigned /cdc_dc_tb/dut/u_dc_handler/handler_state
add wave -group "DC Handler" -radix unsigned /cdc_dc_tb/dut/u_dc_handler/upload_state
add wave -group "DC Handler" /cdc_dc_tb/dut/u_dc_handler/cmd_ready
add wave -group "DC Handler" -divider "Control Signals"
add wave -group "DC Handler" -radix unsigned /cdc_dc_tb/dut/u_dc_handler/sample_divider
add wave -group "DC Handler" -radix unsigned /cdc_dc_tb/dut/u_dc_handler/sample_counter
add wave -group "DC Handler" /cdc_dc_tb/dut/u_dc_handler/sample_tick
add wave -group "DC Handler" /cdc_dc_tb/dut/u_dc_handler/capture_enable
add wave -group "DC Handler" /cdc_dc_tb/dut/u_dc_handler/new_sample_flag
add wave -group "DC Handler" -divider "Captured Data"
add wave -group "DC Handler" -radix binary /cdc_dc_tb/dut/u_dc_handler/captured_data
add wave -group "DC Handler" -radix binary /cdc_dc_tb/dut/u_dc_handler/captured_data_sync
add wave -group "DC Handler" -divider "Upload Interface"
add wave -group "DC Handler" /cdc_dc_tb/dut/u_dc_handler/upload_active
add wave -group "DC Handler" /cdc_dc_tb/dut/u_dc_handler/upload_req
add wave -group "DC Handler" -radix hex /cdc_dc_tb/dut/u_dc_handler/upload_data
add wave -group "DC Handler" /cdc_dc_tb/dut/u_dc_handler/upload_valid
add wave -group "DC Handler" /cdc_dc_tb/dut/u_dc_handler/upload_ready

# --- MUX Arbitration ---
add wave -group "MUX Arbitration" -divider "DC Upload Path"
add wave -group "MUX Arbitration" /cdc_dc_tb/dut/dc_upload_active
add wave -group "MUX Arbitration" /cdc_dc_tb/dut/dc_upload_req
add wave -group "MUX Arbitration" -radix hex /cdc_dc_tb/dut/dc_upload_data
add wave -group "MUX Arbitration" /cdc_dc_tb/dut/dc_upload_valid
add wave -group "MUX Arbitration" -divider "Merged Upload Path"
add wave -group "MUX Arbitration" /cdc_dc_tb/dut/merged_upload_req
add wave -group "MUX Arbitration" -radix hex /cdc_dc_tb/dut/merged_upload_data
add wave -group "MUX Arbitration" -radix hex /cdc_dc_tb/dut/merged_upload_source
add wave -group "MUX Arbitration" /cdc_dc_tb/dut/merged_upload_valid
add wave -group "MUX Arbitration" -divider "Final Output (After MUX)"
add wave -group "MUX Arbitration" /cdc_dc_tb/dut/final_upload_req
add wave -group "MUX Arbitration" -radix hex /cdc_dc_tb/dut/final_upload_data
add wave -group "MUX Arbitration" -radix hex /cdc_dc_tb/dut/final_upload_source
add wave -group "MUX Arbitration" /cdc_dc_tb/dut/final_upload_valid
add wave -group "MUX Arbitration" /cdc_dc_tb/dut/processor_upload_ready

# --- USB Upload Output ---
add wave -group "USB Upload" -radix hex /cdc_dc_tb/usb_upload_data
add wave -group "USB Upload" /cdc_dc_tb/usb_upload_valid
add wave -group "USB Upload" -divider "Statistics"
add wave -group "USB Upload" -radix unsigned /cdc_dc_tb/usb_received_count
add wave -group "USB Upload" -radix unsigned /cdc_dc_tb/sample_count
add wave -group "USB Upload" -radix unsigned /cdc_dc_tb/error_count

# --- Testbench Status ---
add wave -group "TB Status" -divider "Test Control"
add wave -group "TB Status" -radix hex /cdc_dc_tb/expected_pattern
add wave -group "TB Status" -radix unsigned /cdc_dc_tb/error_count
add wave -group "TB Status" -divider "State Tracking"
add wave -group "TB Status" -radix unsigned /cdc_dc_tb/prev_handler_state
add wave -group "TB Status" -radix unsigned /cdc_dc_tb/prev_upload_state

# ------------------------------------------------------------------------------
# 6. Configure Wave Window
# ------------------------------------------------------------------------------
configure wave -namecolwidth 300
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1000
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits us

# ------------------------------------------------------------------------------
# 7. Run Simulation
# ------------------------------------------------------------------------------
echo "Running simulation..."
run -all

# Zoom to fit all waveforms
wave zoom full

echo ""
echo "========================================"
echo "Simulation completed successfully!"
echo "========================================"
echo ""
echo "Key signal groups:"
echo "- Top Level: Basic I/O and DC input signals"
echo "- Protocol Parser: Command frame parsing"
echo "- Command Processor: Command distribution"
echo "- DC Handler: Digital capture state and control"
echo "- MUX Arbitration: Direct upload vs. protocol path selection"
echo "- USB Upload: Final USB output data (raw samples)"
echo "- TB Status: Testbench statistics and verification"
echo ""
echo "Verification:"
echo "- Check that DC Handler transitions to CAPTURING state"
echo "- Verify upload_active goes high during capture"
echo "- Confirm final_upload_source = 0x0B during DC capture"
echo "- Validate usb_upload_data matches dc_signal_in patterns"
echo ""
