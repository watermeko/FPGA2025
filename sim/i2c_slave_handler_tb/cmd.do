# ==============================================================================
# I2C Slave Handler Testbench ModelSim Simulation Script
# Testing CDC commands 0x34/0x35/0x36 and I2C operations
# ==============================================================================

# Quit any running simulation
quit -sim

# ------------------------------------------------------------------------------
# 1. Clean and Create Local Libraries
# ------------------------------------------------------------------------------
echo "Cleaning old libraries..."
if {[file isdirectory work]} {
  vdel -lib work -all
}

vlib work
vmap work work

# ------------------------------------------------------------------------------
# 2. Compile All Design Files
# ------------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Compiling Design Files"
echo "========================================"

# --- I2C Slave Core Modules ---
echo "Compiling I2C slave core modules..."
vlog -sv +incdir+../../rtl/i2c ../../rtl/i2c/synchronizer.sv
vlog -sv +incdir+../../rtl/i2c ../../rtl/i2c/edge_detector.v
vlog -sv +incdir+../../rtl/i2c ../../rtl/i2c/i2c_slave.sv
vlog -sv +incdir+../../rtl/i2c ../../rtl/i2c/reg_map.sv
vlog -sv +incdir+../../rtl/i2c ../../rtl/i2c/bidir.sv
vlog -sv +incdir+../../rtl/i2c ../../rtl/i2c/i2c_slave_handler.sv

# --- Testbench ---
echo "Compiling testbench..."
vlog -sv +incdir+../../rtl ../../tb/i2c_slave_handler_tb.sv

# ------------------------------------------------------------------------------
# 3. Start Simulation
# ------------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Starting Simulation"
echo "========================================"
vsim -voptargs="+acc" work.i2c_slave_handler_tb -t ps

# ------------------------------------------------------------------------------
# 4. Add Waveforms
# ------------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Adding Waveforms"
echo "========================================"

# --- Top Level Signals ---
add wave -group "Top Level" -divider "Clock & Reset"
add wave -group "Top Level" /i2c_slave_handler_tb/clk
add wave -group "Top Level" /i2c_slave_handler_tb/rst_n

add wave -group "Top Level" -divider "Physical I2C Bus"
add wave -group "Top Level" /i2c_slave_handler_tb/i2c_scl
add wave -group "Top Level" /i2c_slave_handler_tb/i2c_sda

# --- CDC Command Bus ---
add wave -group "CDC Command" -divider "Command Control"
add wave -group "CDC Command" /i2c_slave_handler_tb/cmd_start
add wave -group "CDC Command" /i2c_slave_handler_tb/cmd_done
add wave -group "CDC Command" /i2c_slave_handler_tb/cmd_ready

add wave -group "CDC Command" -divider "Command Data"
add wave -group "CDC Command" -radix hex /i2c_slave_handler_tb/cmd_type
add wave -group "CDC Command" -radix unsigned /i2c_slave_handler_tb/cmd_length
add wave -group "CDC Command" -radix hex /i2c_slave_handler_tb/cmd_data
add wave -group "CDC Command" -radix unsigned /i2c_slave_handler_tb/cmd_data_index
add wave -group "CDC Command" /i2c_slave_handler_tb/cmd_data_valid

# --- CDC Upload Bus ---
add wave -group "CDC Upload" -divider "Upload Control"
add wave -group "CDC Upload" /i2c_slave_handler_tb/upload_active
add wave -group "CDC Upload" /i2c_slave_handler_tb/upload_req
add wave -group "CDC Upload" /i2c_slave_handler_tb/upload_valid
add wave -group "CDC Upload" /i2c_slave_handler_tb/upload_ready

add wave -group "CDC Upload" -divider "Upload Data"
add wave -group "CDC Upload" -radix hex /i2c_slave_handler_tb/upload_data
add wave -group "CDC Upload" -radix hex /i2c_slave_handler_tb/upload_source
add wave -group "CDC Upload" -radix unsigned /i2c_slave_handler_tb/upload_count

# --- FPGA Preload Interface ---
add wave -group "FPGA Preload" /i2c_slave_handler_tb/preload_en
add wave -group "FPGA Preload" -radix unsigned /i2c_slave_handler_tb/preload_addr
add wave -group "FPGA Preload" -radix hex /i2c_slave_handler_tb/preload_data

# --- DUT State Machine ---
add wave -group "DUT State" -divider "Handler State"
add wave -group "DUT State" -radix unsigned /i2c_slave_handler_tb/u_dut/state
add wave -group "DUT State" -divider "Internal Pointers"
add wave -group "DUT State" -radix unsigned /i2c_slave_handler_tb/u_dut/cdc_write_ptr
add wave -group "DUT State" -radix unsigned /i2c_slave_handler_tb/u_dut/cdc_read_ptr
add wave -group "DUT State" -radix hex /i2c_slave_handler_tb/u_dut/cdc_start_addr
add wave -group "DUT State" -radix unsigned /i2c_slave_handler_tb/u_dut/cdc_len

add wave -group "DUT State" -divider "Captured Data Buffer"
add wave -group "DUT State" -radix hex /i2c_slave_handler_tb/u_dut/captured_data

add wave -group "DUT State" -divider "Upload Buffer"
add wave -group "DUT State" -radix hex /i2c_slave_handler_tb/u_dut/upload_buffer

# --- I2C Slave Core ---
add wave -group "I2C Slave" -divider "Configuration"
add wave -group "I2C Slave" -radix hex /i2c_slave_handler_tb/u_dut/i2c_slave_address

add wave -group "I2C Slave" -divider "Core Signals"
add wave -group "I2C Slave" /i2c_slave_handler_tb/u_dut/u_i2c_slave/i2c_active
add wave -group "I2C Slave" /i2c_slave_handler_tb/u_dut/u_i2c_slave/rd_en
add wave -group "I2C Slave" /i2c_slave_handler_tb/u_dut/u_i2c_slave/wr_en
add wave -group "I2C Slave" -radix unsigned /i2c_slave_handler_tb/u_dut/u_i2c_slave/bit_counter

add wave -group "I2C Slave" -divider "Start/Stop Detection"
add wave -group "I2C Slave" /i2c_slave_handler_tb/u_dut/u_i2c_slave/start
add wave -group "I2C Slave" /i2c_slave_handler_tb/u_dut/u_i2c_slave/stop
add wave -group "I2C Slave" /i2c_slave_handler_tb/u_dut/u_i2c_slave/check_id
add wave -group "I2C Slave" /i2c_slave_handler_tb/u_dut/u_i2c_slave/valid_id

add wave -group "I2C Slave" -divider "Data Path"
add wave -group "I2C Slave" -radix hex /i2c_slave_handler_tb/u_dut/u_i2c_slave/shift_reg
add wave -group "I2C Slave" -radix hex /i2c_slave_handler_tb/u_dut/core_addr
add wave -group "I2C Slave" -radix hex /i2c_slave_handler_tb/u_dut/core_wdata
add wave -group "I2C Slave" -radix hex /i2c_slave_handler_tb/u_dut/core_rdata
add wave -group "I2C Slave" /i2c_slave_handler_tb/u_dut/core_wr_en_wdata

add wave -group "I2C Slave" -divider "SDA Control"
add wave -group "I2C Slave" /i2c_slave_handler_tb/u_dut/sda_in
add wave -group "I2C Slave" /i2c_slave_handler_tb/u_dut/sda_out

# --- Register Map ---
add wave -group "Register Map" -divider "Control Signals"
add wave -group "Register Map" -radix hex /i2c_slave_handler_tb/u_dut/handler_addr
add wave -group "Register Map" -radix hex /i2c_slave_handler_tb/u_dut/handler_wdata
add wave -group "Register Map" /i2c_slave_handler_tb/u_dut/handler_wr_en

add wave -group "Register Map" -divider "Preload Interface"
add wave -group "Register Map" /i2c_slave_handler_tb/u_dut/u_reg_map/preload_en
add wave -group "Register Map" -radix unsigned /i2c_slave_handler_tb/u_dut/u_reg_map/preload_addr
add wave -group "Register Map" -radix hex /i2c_slave_handler_tb/u_dut/u_reg_map/preload_data

add wave -group "Register Map" -divider "Register Contents"
add wave -group "Register Map" -radix hex /i2c_slave_handler_tb/u_dut/u_reg_map/registers
add wave -group "Register Map" -radix hex /i2c_slave_handler_tb/u_dut/reg_val_0
add wave -group "Register Map" -radix hex /i2c_slave_handler_tb/u_dut/reg_val_1
add wave -group "Register Map" -radix hex /i2c_slave_handler_tb/u_dut/reg_val_2
add wave -group "Register Map" -radix hex /i2c_slave_handler_tb/u_dut/reg_val_3

add wave -group "Register Map" -divider "Write Enable"
add wave -group "Register Map" /i2c_slave_handler_tb/u_dut/u_reg_map/wr_en_wdata
add wave -group "Register Map" /i2c_slave_handler_tb/u_dut/u_reg_map/wr_en_wdata_hold
add wave -group "Register Map" /i2c_slave_handler_tb/u_dut/u_reg_map/wr_en_wdata_fedge

# --- Test Control ---
add wave -group "Test Control" -divider "I2C Master Drive"
add wave -group "Test Control" /i2c_slave_handler_tb/scl_drive
add wave -group "Test Control" /i2c_slave_handler_tb/sda_drive_out
add wave -group "Test Control" /i2c_slave_handler_tb/sda_oe

add wave -group "Test Control" -divider "Upload Capture"
add wave -group "Test Control" -radix hex /i2c_slave_handler_tb/upload_buffer
add wave -group "Test Control" -radix unsigned /i2c_slave_handler_tb/upload_count

# ------------------------------------------------------------------------------
# 5. Configure Wave Window
# ------------------------------------------------------------------------------
configure wave -namecolwidth 350
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
configure wave -timelineunits ns

# ------------------------------------------------------------------------------
# 6. Run Simulation
# ------------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Running Simulation"
echo "========================================"

run -all

# Zoom to fit all waveforms
wave zoom full

echo ""
echo "========================================"
echo "Simulation Completed!"
echo "========================================"
echo ""
echo "Signal Groups:"
echo "- Top Level:      Clock, reset, and I2C physical bus"
echo "- CDC Command:    CDC command bus interface"
echo "- CDC Upload:     CDC upload data interface"
echo "- FPGA Preload:   Internal FPGA preload interface"
echo "- DUT State:      Handler state machine and buffers"
echo "- I2C Slave:      I2C slave core operation"
echo "- Register Map:   Register storage and control"
echo "- Test Control:   Testbench control signals"
echo ""
echo "Key Tests Performed:"
echo "1. CDC Write Single Register (0x35)"
echo "2. CDC Read Single Register (0x36)"
echo "3. CDC Write All 4 Registers (0x35)"
echo "4. CDC Read All 4 Registers (0x36)"
echo ""
