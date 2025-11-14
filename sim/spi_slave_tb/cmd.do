# ==============================================================================
# SPI Slave Handler Testbench ModelSim Simulation Script
# Testing SPI slave功能码 0x14 (预装数据) and 0x15 (控制上传)
# ==============================================================================

# Quit any running simulation
quit -sim

# ------------------------------------------------------------------------------
# 1. Clean and Create Local Libraries
# ------------------------------------------------------------------------------
catch {vdel -lib work -all}

vlib work
vmap work work

# ------------------------------------------------------------------------------
# 2. Compile Design Files
# ------------------------------------------------------------------------------
echo "Compiling design files..."

# SPI Slave Physical Layer
vlog -sv +incdir+../../rtl ../../rtl/spi/simple_spi_slave.v

# SPI Slave Handler
vlog -sv +incdir+../../rtl ../../rtl/spi/spi_slave_handler.v

# Testbench
vlog -sv +incdir+../../rtl ../../tb/spi_slave_handler_tb.sv

# ------------------------------------------------------------------------------
# 3. Start Simulation
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.spi_slave_handler_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. Add Waveforms with Grouping
# ------------------------------------------------------------------------------
echo "Adding waveforms..."

# --- Top Level ---
add wave -group "Top Level" -divider "Clock & Reset"
add wave -group "Top Level" /spi_slave_handler_tb/clk
add wave -group "Top Level" /spi_slave_handler_tb/rst_n

add wave -group "Top Level" -divider "Command Bus"
add wave -group "Top Level" -radix hex /spi_slave_handler_tb/cmd_type
add wave -group "Top Level" -radix unsigned /spi_slave_handler_tb/cmd_length
add wave -group "Top Level" -radix hex /spi_slave_handler_tb/cmd_data
add wave -group "Top Level" -radix unsigned /spi_slave_handler_tb/cmd_data_index
add wave -group "Top Level" /spi_slave_handler_tb/cmd_start
add wave -group "Top Level" /spi_slave_handler_tb/cmd_data_valid
add wave -group "Top Level" /spi_slave_handler_tb/cmd_done
add wave -group "Top Level" /spi_slave_handler_tb/cmd_ready

add wave -group "Top Level" -divider "SPI Physical"
add wave -group "Top Level" /spi_slave_handler_tb/spi_clk
add wave -group "Top Level" /spi_slave_handler_tb/spi_cs_n
add wave -group "Top Level" /spi_slave_handler_tb/spi_mosi
add wave -group "Top Level" /spi_slave_handler_tb/spi_miso

add wave -group "Top Level" -divider "Upload Interface"
add wave -group "Top Level" /spi_slave_handler_tb/upload_active
add wave -group "Top Level" /spi_slave_handler_tb/upload_req
add wave -group "Top Level" -radix hex /spi_slave_handler_tb/upload_data
add wave -group "Top Level" -radix hex /spi_slave_handler_tb/upload_source
add wave -group "Top Level" /spi_slave_handler_tb/upload_valid
add wave -group "Top Level" /spi_slave_handler_tb/upload_ready

# --- SPI Slave Handler ---
add wave -group "Handler" -divider "State"
add wave -group "Handler" -radix unsigned /spi_slave_handler_tb/dut/state
add wave -group "Handler" -radix unsigned /spi_slave_handler_tb/dut/upload_state

add wave -group "Handler" -divider "TX Buffer Control"
add wave -group "Handler" -radix unsigned /spi_slave_handler_tb/dut/tx_write_ptr
add wave -group "Handler" -radix unsigned /spi_slave_handler_tb/dut/tx_read_ptr
add wave -group "Handler" -radix unsigned /spi_slave_handler_tb/dut/tx_buffer_len
add wave -group "Handler" /spi_slave_handler_tb/dut/tx_buffer_ready
add wave -group "Handler" /spi_slave_handler_tb/dut/tx_buffer_reset

add wave -group "Handler" -divider "RX Buffer Control"
add wave -group "Handler" -radix unsigned /spi_slave_handler_tb/dut/rx_write_ptr
add wave -group "Handler" -radix unsigned /spi_slave_handler_tb/dut/rx_read_ptr
add wave -group "Handler" /spi_slave_handler_tb/dut/rx_upload_enable

add wave -group "Handler" -divider "SPI Interface Signals"
add wave -group "Handler" -radix hex /spi_slave_handler_tb/dut/spi_tx_byte
add wave -group "Handler" /spi_slave_handler_tb/dut/spi_tx_ready
add wave -group "Handler" -radix hex /spi_slave_handler_tb/dut/spi_rx_byte
add wave -group "Handler" /spi_slave_handler_tb/dut/spi_byte_received
add wave -group "Handler" /spi_slave_handler_tb/dut/spi_req_next_byte

# --- SPI Slave Physical Layer ---
add wave -group "Physical" -divider "State"
add wave -group "Physical" -radix unsigned /spi_slave_handler_tb/dut/u_spi_slave/state
add wave -group "Physical" -radix unsigned /spi_slave_handler_tb/dut/u_spi_slave/bit_count

add wave -group "Physical" -divider "Synchronized Signals"
add wave -group "Physical" /spi_slave_handler_tb/dut/u_spi_slave/spi_clk_s
add wave -group "Physical" /spi_slave_handler_tb/dut/u_spi_slave/spi_cs_n_s
add wave -group "Physical" /spi_slave_handler_tb/dut/u_spi_slave/spi_mosi_s

add wave -group "Physical" -divider "Edge Detection"
add wave -group "Physical" /spi_slave_handler_tb/dut/u_spi_slave/spi_clk_posedge
add wave -group "Physical" /spi_slave_handler_tb/dut/u_spi_slave/spi_clk_negedge
add wave -group "Physical" /spi_slave_handler_tb/dut/u_spi_slave/spi_cs_falling
add wave -group "Physical" /spi_slave_handler_tb/dut/u_spi_slave/spi_cs_rising

add wave -group "Physical" -divider "Shift Registers"
add wave -group "Physical" -radix hex /spi_slave_handler_tb/dut/u_spi_slave/tx_shift_reg
add wave -group "Physical" -radix hex /spi_slave_handler_tb/dut/u_spi_slave/rx_shift_reg
add wave -group "Physical" -radix hex /spi_slave_handler_tb/dut/u_spi_slave/o_rx_byte

add wave -group "Physical" -divider "Control"
add wave -group "Physical" /spi_slave_handler_tb/dut/u_spi_slave/o_byte_received
add wave -group "Physical" /spi_slave_handler_tb/dut/u_spi_slave/o_req_next_byte
add wave -group "Physical" /spi_slave_handler_tb/dut/u_spi_slave/i_tx_ready

# --- Test Status ---
add wave -group "Test Status" -divider "Counters"
add wave -group "Test Status" -radix unsigned /spi_slave_handler_tb/uploaded_count
add wave -group "Test Status" -radix unsigned /spi_slave_handler_tb/test_pass_count
add wave -group "Test Status" -radix unsigned /spi_slave_handler_tb/test_fail_count

# ------------------------------------------------------------------------------
# 5. Configure Wave Window
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
# 6. Run Simulation
# ------------------------------------------------------------------------------
echo "Running simulation..."
run -all

# Zoom to fit
wave zoom full

echo ""
echo "========================================"
echo "Simulation completed!"
echo "========================================"
echo ""
echo "Key signal groups:"
echo "- Top Level: Command bus, SPI interface, upload interface"
echo "- Handler: State machines, buffer control, internal signals"
echo "- Physical: SPI slave physical layer (synchronization, edge detection)"
echo "- Test Status: Test progress and results"
echo ""
echo "Tests performed:"
echo "1. Test 1: 预装发送数据 (0x14) - 'FPGA2025'"
echo "2. Test 2: 启用接收上传 (0x15) - Write 4 bytes"
echo "3. Test 3: 禁用接收上传 (0x15, data=0)"
echo "4. Test 4: 大数据块预装 (128 bytes)"
echo "5. Test 5: 双向通信测试"
echo ""
echo "Check console output for PASS/FAIL results"
echo ""
