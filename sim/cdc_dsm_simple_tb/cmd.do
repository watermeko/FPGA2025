# ==============================================================================
# CDC DSM Simple Testbench ModelSim Simulation Script
# Testing DSM digital signal measurement in full CDC module
# ==============================================================================

# Quit any running simulation
quit -sim

# ------------------------------------------------------------------------------
# 1. Clean and Create Local Libraries
# ------------------------------------------------------------------------------
if {[file isdirectory work]} {
  vdel -lib work -all
}
if {[file isdirectory gw5a]} {
  vdel -lib gw5a -all
}

vlib work
vmap work work
vlib gw5a
vmap gw5a ./gw5a

# ------------------------------------------------------------------------------
# 2. Compile Gowin Primitives
# ------------------------------------------------------------------------------
echo "Compiling Gowin primitives into local './gw5a' library..."
set GOWIN_PATH "E:/GOWIN/Gowin_V1.9.9_x64/IDE"
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
vlog -sv +incdir+../../rtl ../../tb/cdc_dsm_simple_tb.sv

# ------------------------------------------------------------------------------
# 4. Start Simulation
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim -L gw5a work.cdc_dsm_simple_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 5. Add Waveforms
# ------------------------------------------------------------------------------
echo "Adding waveforms..."

# --- Top Level ---
add wave -group "Top Level" -divider "Clock & Reset"
add wave -group "Top Level" /cdc_dsm_simple_tb/clk
add wave -group "Top Level" /cdc_dsm_simple_tb/rst_n
add wave -group "Top Level" -divider "USB Interface"
add wave -group "Top Level" -radix hex /cdc_dsm_simple_tb/usb_data_in
add wave -group "Top Level" /cdc_dsm_simple_tb/usb_data_valid_in
add wave -group "Top Level" -divider "DSM Signals"
add wave -group "Top Level" -radix binary /cdc_dsm_simple_tb/dsm_signal_in

# --- Protocol Parser ---
add wave -group "Protocol Parser" -divider "State"
add wave -group "Protocol Parser" -radix unsigned /cdc_dsm_simple_tb/dut/u_parser/state
add wave -group "Protocol Parser" -divider "Outputs"
add wave -group "Protocol Parser" /cdc_dsm_simple_tb/dut/u_parser/parse_done
add wave -group "Protocol Parser" /cdc_dsm_simple_tb/dut/u_parser/parse_error
add wave -group "Protocol Parser" -radix hex /cdc_dsm_simple_tb/dut/u_parser/cmd_out
add wave -group "Protocol Parser" -radix unsigned /cdc_dsm_simple_tb/dut/u_parser/len_out

# --- Command Processor ---
add wave -group "Command Processor" -divider "State"
add wave -group "Command Processor" -radix unsigned /cdc_dsm_simple_tb/dut/u_command_processor/state
add wave -group "Command Processor" -divider "Command Bus"
add wave -group "Command Processor" -radix hex /cdc_dsm_simple_tb/dut/cmd_type
add wave -group "Command Processor" -radix unsigned /cdc_dsm_simple_tb/dut/cmd_length
add wave -group "Command Processor" /cdc_dsm_simple_tb/dut/cmd_start
add wave -group "Command Processor" /cdc_dsm_simple_tb/dut/cmd_data_valid
add wave -group "Command Processor" -radix hex /cdc_dsm_simple_tb/dut/cmd_data
add wave -group "Command Processor" /cdc_dsm_simple_tb/dut/cmd_done

# --- DSM Handler ---
add wave -group "DSM Handler" -divider "State"
add wave -group "DSM Handler" -radix unsigned /cdc_dsm_simple_tb/dut/u_dsm_handler/handler_state
add wave -group "DSM Handler" -radix unsigned /cdc_dsm_simple_tb/dut/u_dsm_handler/upload_state
add wave -group "DSM Handler" /cdc_dsm_simple_tb/dut/u_dsm_handler/cmd_ready
add wave -group "DSM Handler" -divider "Control"
add wave -group "DSM Handler" -radix hex /cdc_dsm_simple_tb/dut/u_dsm_handler/channel_mask
add wave -group "DSM Handler" -radix binary /cdc_dsm_simple_tb/dut/u_dsm_handler/measure_start_reg
add wave -group "DSM Handler" -radix binary /cdc_dsm_simple_tb/dut/u_dsm_handler/measure_done_sync
add wave -group "DSM Handler" /cdc_dsm_simple_tb/dut/u_dsm_handler/all_done
add wave -group "DSM Handler" -divider "Upload Control"
add wave -group "DSM Handler" -radix unsigned /cdc_dsm_simple_tb/dut/u_dsm_handler/upload_channel
add wave -group "DSM Handler" -radix unsigned /cdc_dsm_simple_tb/dut/u_dsm_handler/upload_byte_index
add wave -group "DSM Handler" -divider "Upload Interface"
add wave -group "DSM Handler" /cdc_dsm_simple_tb/dut/u_dsm_handler/upload_active
add wave -group "DSM Handler" /cdc_dsm_simple_tb/dut/u_dsm_handler/upload_req
add wave -group "DSM Handler" -radix hex /cdc_dsm_simple_tb/dut/u_dsm_handler/upload_data
add wave -group "DSM Handler" -radix hex /cdc_dsm_simple_tb/dut/u_dsm_handler/upload_source
add wave -group "DSM Handler" /cdc_dsm_simple_tb/dut/u_dsm_handler/upload_valid
add wave -group "DSM Handler" /cdc_dsm_simple_tb/dut/u_dsm_handler/upload_ready

# --- DSM Multichannel Core ---
add wave -group "DSM Core" -divider "Control Signals"
add wave -group "DSM Core" -radix binary /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/measure_start
add wave -group "DSM Core" -radix binary /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/measure_pin
add wave -group "DSM Core" -radix binary /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/measure_done
add wave -group "DSM Core" -divider "Results (Packed)"
add wave -group "DSM Core" -radix hex /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/high_time
add wave -group "DSM Core" -radix hex /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/low_time

# --- DSM Channel 0 Detail ---
add wave -group "DSM Ch0" -divider "State"
add wave -group "DSM Ch0" -radix unsigned /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/state
add wave -group "DSM Ch0" -divider "Control"
add wave -group "DSM Ch0" /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/measure_start
add wave -group "DSM Ch0" /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/measure_pin
add wave -group "DSM Ch0" /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/measure_done
add wave -group "DSM Ch0" -divider "Synchronized Input"
add wave -group "DSM Ch0" /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/measure_pin_sync1
add wave -group "DSM Ch0" /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/measure_pin_sync2
add wave -group "DSM Ch0" /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/measure_pin_sync3
add wave -group "DSM Ch0" /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/rising_edge
add wave -group "DSM Ch0" /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/falling_edge
add wave -group "DSM Ch0" -divider "Counters"
add wave -group "DSM Ch0" -radix unsigned /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/high_counter
add wave -group "DSM Ch0" -radix unsigned /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/low_counter
add wave -group "DSM Ch0" -divider "Results"
add wave -group "DSM Ch0" -radix unsigned /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/high_time
add wave -group "DSM Ch0" -radix unsigned /cdc_dsm_simple_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances\[0\]/dsm_inst/low_time

# --- Upload Pipeline ---
add wave -group "Upload Pipeline" -divider "DSM Adapter Output"
add wave -group "Upload Pipeline" /cdc_dsm_simple_tb/dut/dsm_packer_req
add wave -group "Upload Pipeline" -radix hex /cdc_dsm_simple_tb/dut/dsm_packer_data
add wave -group "Upload Pipeline" -radix hex /cdc_dsm_simple_tb/dut/dsm_packer_source
add wave -group "Upload Pipeline" /cdc_dsm_simple_tb/dut/dsm_packer_valid
add wave -group "Upload Pipeline" /cdc_dsm_simple_tb/dut/dsm_packer_ready
add wave -group "Upload Pipeline" -divider "Packer Output (Channel 2 = DSM)"
add wave -group "Upload Pipeline" /cdc_dsm_simple_tb/dut/packed_req\[2\]
add wave -group "Upload Pipeline" -radix hex /cdc_dsm_simple_tb/dut/packed_data\[23:16\]
add wave -group "Upload Pipeline" /cdc_dsm_simple_tb/dut/packed_valid\[2\]
add wave -group "Upload Pipeline" /cdc_dsm_simple_tb/dut/arbiter_ready\[2\]
add wave -group "Upload Pipeline" -divider "Merged Output"
add wave -group "Upload Pipeline" /cdc_dsm_simple_tb/dut/merged_upload_req
add wave -group "Upload Pipeline" -radix hex /cdc_dsm_simple_tb/dut/merged_upload_data
add wave -group "Upload Pipeline" -radix hex /cdc_dsm_simple_tb/dut/merged_upload_source
add wave -group "Upload Pipeline" /cdc_dsm_simple_tb/dut/merged_upload_valid
add wave -group "Upload Pipeline" /cdc_dsm_simple_tb/dut/processor_upload_ready

# --- USB Upload Output ---
add wave -group "USB Upload" -radix hex /cdc_dsm_simple_tb/usb_upload_data
add wave -group "USB Upload" /cdc_dsm_simple_tb/usb_upload_valid
add wave -group "USB Upload" -divider "Captured Data"
add wave -group "USB Upload" -radix unsigned /cdc_dsm_simple_tb/usb_received_count

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
echo "- Top Level: Basic I/O and DSM input signals"
echo "- Protocol Parser: Command frame parsing"
echo "- Command Processor: Command distribution"
echo "- DSM Handler: Handler state and control"
echo "- DSM Core: Multi-channel measurement core"
echo "- DSM Ch0: Detailed view of channel 0"
echo "- Upload Pipeline: Data upload flow"
echo "- USB Upload: Final USB output data"
echo ""
