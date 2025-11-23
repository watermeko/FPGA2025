# ==============================================================================
# DS18B20 Read Test - ModelSim Simulation Script
# Tests one_wire_handler READ functionality with DS18B20 model
# ==============================================================================

quit -sim

# ------------------------------------------------------------------------------
# 1. Clean and create library
# ------------------------------------------------------------------------------
if {[file isdirectory work]} {
  vdel -lib work -all
}
vlib work
vmap work work

# ------------------------------------------------------------------------------
# 2. Compile design files
# ------------------------------------------------------------------------------
echo "Compiling DS18B20 read testbench..."

# Compile 1-Wire master
vlog -sv ../../rtl/one_wire/one_wire_master.v

# Compile 1-Wire handler
vlog -sv ../../rtl/one_wire/one_wire_handler.v

# Compile DS18B20 model
vlog -sv ../../tb/ds18b20_simple_model.v

# Compile testbench
vlog -sv ../../tb/ds18b20_read_tb.v

# ------------------------------------------------------------------------------
# 3. Start simulation
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.ds18b20_read_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. Add waveforms
# ------------------------------------------------------------------------------

# --- Clock & Reset ---
add wave -group "Clock & Reset" /ds18b20_read_tb/clk
add wave -group "Clock & Reset" /ds18b20_read_tb/rst_n

# --- 1-Wire Bus ---
add wave -group "1-Wire Bus" /ds18b20_read_tb/onewire_io

# --- Command Interface ---
add wave -group "Command" -radix hex /ds18b20_read_tb/cmd_type
add wave -group "Command" -radix unsigned /ds18b20_read_tb/cmd_length
add wave -group "Command" -radix hex /ds18b20_read_tb/cmd_data
add wave -group "Command" /ds18b20_read_tb/cmd_start
add wave -group "Command" /ds18b20_read_tb/cmd_data_valid
add wave -group "Command" /ds18b20_read_tb/cmd_done

# --- Upload Interface ---
add wave -group "Upload" /ds18b20_read_tb/upload_req
add wave -group "Upload" -radix hex /ds18b20_read_tb/upload_data
add wave -group "Upload" /ds18b20_read_tb/upload_valid
add wave -group "Upload" /ds18b20_read_tb/upload_ready

# --- Handler State ---
add wave -group "Handler" -radix unsigned /ds18b20_read_tb/dut_master/handler_state
add wave -group "Handler" -radix unsigned /ds18b20_read_tb/dut_master/bit_counter
add wave -group "Handler" -radix unsigned /ds18b20_read_tb/dut_master/byte_counter
add wave -group "Handler" -radix hex /ds18b20_read_tb/dut_master/current_byte

# --- Master Core ---
add wave -group "Master Core" -radix unsigned /ds18b20_read_tb/dut_master/u_one_wire_master/state
add wave -group "Master Core" /ds18b20_read_tb/dut_master/u_one_wire_master/busy
add wave -group "Master Core" /ds18b20_read_tb/dut_master/u_one_wire_master/done
add wave -group "Master Core" /ds18b20_read_tb/dut_master/u_one_wire_master/oe
add wave -group "Master Core" /ds18b20_read_tb/dut_master/ow_read_bit_data

# --- RX FIFO ---
add wave -group "RX FIFO" -radix unsigned /ds18b20_read_tb/dut_master/rx_fifo_count
add wave -group "RX FIFO" /ds18b20_read_tb/dut_master/rx_fifo_empty
add wave -group "RX FIFO" -radix hex /ds18b20_read_tb/dut_master/rx_fifo_data_out

# ------------------------------------------------------------------
# 5. Configure wave display
# ------------------------------------------------------------------
configure wave -namecolwidth 280
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# ------------------------------------------------------------------
# 6. Run simulation
# ------------------------------------------------------------------
echo "Running DS18B20 read test..."
run -all

wave zoom full

echo "Simulation complete."
