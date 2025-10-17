# ==============================================================================
# CDC SPI Testbench ModelSim Simulation Script
# Testing SPI functionality in full CDC module
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
vlog -sv +incdir+../../rtl ../../rtl/upload_packer.v
vlog -sv +incdir+../../rtl ../../rtl/upload_arbiter.v

# --- Core Protocol Modules ---
vlog -sv +incdir+../../rtl ../../rtl/protocol_parser.v
vlog -sv +incdir+../../rtl ../../rtl/command_processor.v

# --- Top CDC Module ---
vlog -sv +incdir+../../rtl ../../rtl/cdc.v

# --- Testbench ---
vlog -sv +incdir+../../rtl ../../tb/cdc_spi_new_tb.sv

# ------------------------------------------------------------------------------
# 4. Start Simulation
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim -L gw5a work.cdc_spi_new_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 5. Add Waveforms
# ------------------------------------------------------------------------------
echo "Adding waveforms..."

# --- Top Level Inputs ---
add wave -group "Top Level" -divider "Inputs"
add wave -group "Top Level" /cdc_spi_new_tb/clk
add wave -group "Top Level" /cdc_spi_new_tb/rst_n
add wave -group "Top Level" -radix hex /cdc_spi_new_tb/usb_data_in
add wave -group "Top Level" /cdc_spi_new_tb/usb_data_valid_in

# --- Protocol Parser ---
add wave -group "Protocol Parser" -divider "State"
add wave -group "Protocol Parser" -radix unsigned /cdc_spi_new_tb/dut/u_parser/state
add wave -group "Protocol Parser" -divider "Inputs"
add wave -group "Protocol Parser" /cdc_spi_new_tb/dut/u_parser/uart_rx_valid
add wave -group "Protocol Parser" -radix hex /cdc_spi_new_tb/dut/u_parser/uart_rx_data
add wave -group "Protocol Parser" -divider "Outputs"
add wave -group "Protocol Parser" /cdc_spi_new_tb/dut/u_parser/parse_done
add wave -group "Protocol Parser" /cdc_spi_new_tb/dut/u_parser/parse_error
add wave -group "Protocol Parser" -radix hex /cdc_spi_new_tb/dut/u_parser/cmd_out
add wave -group "Protocol Parser" -radix unsigned /cdc_spi_new_tb/dut/u_parser/len_out
add wave -group "Protocol Parser" -radix hex /cdc_spi_new_tb/dut/u_parser/checksum

# --- Command Processor ---
add wave -group "Command Processor" -divider "State"
add wave -group "Command Processor" -radix unsigned /cdc_spi_new_tb/dut/u_command_processor/state
add wave -group "Command Processor" -divider "Inputs"
add wave -group "Command Processor" /cdc_spi_new_tb/dut/u_command_processor/parse_done
add wave -group "Command Processor" /cdc_spi_new_tb/dut/u_command_processor/parse_done_edge
add wave -group "Command Processor" /cdc_spi_new_tb/dut/u_command_processor/cmd_ready_in
add wave -group "Command Processor" -divider "Command Bus"
add wave -group "Command Processor" -radix hex /cdc_spi_new_tb/dut/cmd_type
add wave -group "Command Processor" -radix unsigned /cdc_spi_new_tb/dut/cmd_length
add wave -group "Command Processor" /cdc_spi_new_tb/dut/cmd_start
add wave -group "Command Processor" /cdc_spi_new_tb/dut/cmd_data_valid
add wave -group "Command Processor" -radix hex /cdc_spi_new_tb/dut/cmd_data
add wave -group "Command Processor" -radix unsigned /cdc_spi_new_tb/dut/cmd_data_index
add wave -group "Command Processor" /cdc_spi_new_tb/dut/cmd_done
add wave -group "Command Processor" -divider "Payload Memory"
add wave -group "Command Processor" -radix hex /cdc_spi_new_tb/dut/u_command_processor/payload_read_addr
add wave -group "Command Processor" -radix hex /cdc_spi_new_tb/dut/u_command_processor/payload_read_data

# --- SPI Handler ---
add wave -group "SPI Handler" -divider "State"
add wave -group "SPI Handler" -radix unsigned /cdc_spi_new_tb/dut/u_spi_handler/state
add wave -group "SPI Handler" /cdc_spi_new_tb/dut/spi_ready
add wave -group "SPI Handler" /cdc_spi_new_tb/dut/u_spi_handler/cmd_ready
add wave -group "SPI Handler" -divider "Protocol Header"
add wave -group "SPI Handler" -radix unsigned /cdc_spi_new_tb/dut/u_spi_handler/write_len
add wave -group "SPI Handler" -radix unsigned /cdc_spi_new_tb/dut/u_spi_handler/read_len
add wave -group "SPI Handler" -radix unsigned /cdc_spi_new_tb/dut/u_spi_handler/data_received_count
add wave -group "SPI Handler" -divider "Transfer Control"
add wave -group "SPI Handler" -radix unsigned /cdc_spi_new_tb/dut/u_spi_handler/byte_index
add wave -group "SPI Handler" -radix unsigned /cdc_spi_new_tb/dut/u_spi_handler/upload_index
add wave -group "SPI Handler" -radix unsigned /cdc_spi_new_tb/dut/u_spi_handler/upload_state
add wave -group "SPI Handler" -radix hex /cdc_spi_new_tb/dut/u_spi_handler/spi_tx_byte
add wave -group "SPI Handler" -divider "SPI Master Interface"
add wave -group "SPI Handler" /cdc_spi_new_tb/dut/u_spi_handler/spi_start
add wave -group "SPI Handler" -radix hex /cdc_spi_new_tb/dut/u_spi_handler/spi_rx_byte
add wave -group "SPI Handler" /cdc_spi_new_tb/dut/u_spi_handler/spi_done
add wave -group "SPI Handler" -divider "Upload Interface"
add wave -group "SPI Handler" /cdc_spi_new_tb/dut/u_spi_handler/upload_active
add wave -group "SPI Handler" /cdc_spi_new_tb/dut/u_spi_handler/upload_req
add wave -group "SPI Handler" -radix hex /cdc_spi_new_tb/dut/u_spi_handler/upload_data
add wave -group "SPI Handler" -radix hex /cdc_spi_new_tb/dut/u_spi_handler/upload_source
add wave -group "SPI Handler" /cdc_spi_new_tb/dut/u_spi_handler/upload_valid
add wave -group "SPI Handler" /cdc_spi_new_tb/dut/u_spi_handler/upload_ready

# --- SPI Master Core ---
add wave -group "SPI Master" -divider "Control"
add wave -group "SPI Master" -radix unsigned /cdc_spi_new_tb/dut/u_spi_handler/u_spi/state
add wave -group "SPI Master" /cdc_spi_new_tb/dut/u_spi_handler/u_spi/i_start
add wave -group "SPI Master" /cdc_spi_new_tb/dut/u_spi_handler/u_spi/o_done
add wave -group "SPI Master" /cdc_spi_new_tb/dut/u_spi_handler/u_spi/o_busy
add wave -group "SPI Master" -divider "Data"
add wave -group "SPI Master" -radix hex /cdc_spi_new_tb/dut/u_spi_handler/u_spi/i_tx_byte
add wave -group "SPI Master" -radix hex /cdc_spi_new_tb/dut/u_spi_handler/u_spi/o_rx_byte
add wave -group "SPI Master" -radix unsigned /cdc_spi_new_tb/dut/u_spi_handler/u_spi/bit_count

# --- SPI Physical Bus ---
add wave -group "SPI Bus" /cdc_spi_new_tb/spi_clk
add wave -group "SPI Bus" /cdc_spi_new_tb/spi_cs_n
add wave -group "SPI Bus" /cdc_spi_new_tb/spi_mosi
add wave -group "SPI Bus" /cdc_spi_new_tb/spi_miso

# --- Upload Pipeline ---
add wave -group "Upload Pipeline" -divider "SPI Adapter Output"
add wave -group "Upload Pipeline" /cdc_spi_new_tb/dut/spi_packer_req
add wave -group "Upload Pipeline" -radix hex /cdc_spi_new_tb/dut/spi_packer_data
add wave -group "Upload Pipeline" -radix hex /cdc_spi_new_tb/dut/spi_packer_source
add wave -group "Upload Pipeline" /cdc_spi_new_tb/dut/spi_packer_valid
add wave -group "Upload Pipeline" /cdc_spi_new_tb/dut/spi_packer_ready
add wave -group "Upload Pipeline" -divider "Merged Output"
add wave -group "Upload Pipeline" /cdc_spi_new_tb/dut/merged_upload_req
add wave -group "Upload Pipeline" -radix hex /cdc_spi_new_tb/dut/merged_upload_data
add wave -group "Upload Pipeline" -radix hex /cdc_spi_new_tb/dut/merged_upload_source
add wave -group "Upload Pipeline" /cdc_spi_new_tb/dut/merged_upload_valid
add wave -group "Upload Pipeline" /cdc_spi_new_tb/dut/processor_upload_ready

# --- USB Upload Output ---
add wave -group "USB Upload" -radix hex /cdc_spi_new_tb/usb_upload_data
add wave -group "USB Upload" /cdc_spi_new_tb/usb_upload_valid
add wave -group "USB Upload" -divider "Captured Data"
add wave -group "USB Upload" -radix unsigned /cdc_spi_new_tb/usb_received_count

# --- SPI Slave Model ---
add wave -group "SPI Slave" -radix unsigned /cdc_spi_new_tb/spi_slave_bit_count
add wave -group "SPI Slave" -radix unsigned /cdc_spi_new_tb/spi_slave_byte_count
add wave -group "SPI Slave" -radix hex /cdc_spi_new_tb/spi_slave_tx_reg
add wave -group "SPI Slave" -radix hex /cdc_spi_new_tb/spi_slave_rx_reg
add wave -group "SPI Slave" /cdc_spi_new_tb/spi_slave_miso_en
add wave -group "SPI Slave" /cdc_spi_new_tb/spi_slave_miso_out

# ------------------------------------------------------------------------------
# 6. Run Simulation
# ------------------------------------------------------------------------------
echo "Running simulation..."
run -all

# Zoom to fit all waveforms
wave zoom full

echo "Simulation completed."
