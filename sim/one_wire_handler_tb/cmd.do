# ==============================================================================
# 1-Wire Handler Testbench ModelSim Simulation Script
# ==============================================================================

quit -sim

# ------------------------------------------------------------------------------
# 1. 清理并创建库
# ------------------------------------------------------------------------------
if {[file isdirectory work]} {
  vdel -lib work -all
}
vlib work
vmap work work

# ------------------------------------------------------------------------------
# 2. 编译设计文件
# ------------------------------------------------------------------------------
echo "Compiling 1-Wire handler design and testbench..."

# 编译底层模块
vlog -sv ../../rtl/one_wire/one_wire_master.v

# 编译上层模块
vlog -sv ../../rtl/one_wire/one_wire_handler.v

# 编译测试台
vlog -sv ../../tb/one_wire_handler_tb.v

# ------------------------------------------------------------------------------
# 3. 启动仿真
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.one_wire_handler_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. 添加波形
# ------------------------------------------------------------------------------

# --- Clock & Reset ---
add wave -group "Clock & Reset" /one_wire_handler_tb/clk
add wave -group "Clock & Reset" /one_wire_handler_tb/rst_n

# --- Command Interface ---
add wave -group "Command Interface" -radix hex /one_wire_handler_tb/cmd_type
add wave -group "Command Interface" -radix unsigned /one_wire_handler_tb/cmd_length
add wave -group "Command Interface" -radix hex /one_wire_handler_tb/cmd_data
add wave -group "Command Interface" /one_wire_handler_tb/cmd_start
add wave -group "Command Interface" /one_wire_handler_tb/cmd_data_valid
add wave -group "Command Interface" /one_wire_handler_tb/cmd_done
add wave -group "Command Interface" /one_wire_handler_tb/cmd_ready

# --- Handler State ---
add wave -group "Handler State" -radix unsigned /one_wire_handler_tb/dut/handler_state
add wave -group "Handler State" -radix unsigned /one_wire_handler_tb/dut/byte_counter
add wave -group "Handler State" -radix unsigned /one_wire_handler_tb/dut/bit_counter
add wave -group "Handler State" -radix unsigned /one_wire_handler_tb/dut/bytes_to_process

# --- FIFO Status ---
add wave -group "TX FIFO" -radix unsigned /one_wire_handler_tb/dut/tx_fifo_count
add wave -group "TX FIFO" /one_wire_handler_tb/dut/tx_fifo_empty
add wave -group "TX FIFO" /one_wire_handler_tb/dut/tx_fifo_full
add wave -group "TX FIFO" -radix hex /one_wire_handler_tb/dut/tx_fifo_data_out
add wave -group "RX FIFO" -radix unsigned /one_wire_handler_tb/dut/rx_fifo_count
add wave -group "RX FIFO" /one_wire_handler_tb/dut/rx_fifo_empty
add wave -group "RX FIFO" /one_wire_handler_tb/dut/rx_fifo_full
add wave -group "RX FIFO" -radix hex /one_wire_handler_tb/dut/rx_fifo_data_out

# --- Upload Interface ---
add wave -group "Upload" /one_wire_handler_tb/upload_active
add wave -group "Upload" /one_wire_handler_tb/upload_req
add wave -group "Upload" /one_wire_handler_tb/upload_valid
add wave -group "Upload" -radix hex /one_wire_handler_tb/upload_data
add wave -group "Upload" -radix hex /one_wire_handler_tb/upload_source
add wave -group "Upload" /one_wire_handler_tb/upload_ready

# --- 1-Wire Bus ---
add wave -group "1-Wire" /one_wire_handler_tb/onewire_io

# --- Slave Signals ---
add wave -group "Slave" /one_wire_handler_tb/slave_drive
add wave -group "Slave" -radix hex /one_wire_handler_tb/slave_tx_data
add wave -group "Slave" -radix unsigned /one_wire_handler_tb/slave_bit_idx
add wave -group "Slave" -radix unsigned /one_wire_handler_tb/slave_state
add wave -group "Slave" -radix unsigned /one_wire_handler_tb/slave_timer
add wave -group "Slave" -radix unsigned /one_wire_handler_tb/bus_low_counter

# --- Master State (from one_wire_master) ---
add wave -group "Master State" -radix unsigned /one_wire_handler_tb/dut/u_one_wire_master/state
add wave -group "Master State" -radix unsigned /one_wire_handler_tb/dut/u_one_wire_master/timer
add wave -group "Master State" /one_wire_handler_tb/dut/u_one_wire_master/busy
add wave -group "Master State" /one_wire_handler_tb/dut/u_one_wire_master/done

# --- Captured Upload Data ---
add wave -group "Captured Data" -radix unsigned /one_wire_handler_tb/captured_count
add wave -group "Captured Data" -radix hex /one_wire_handler_tb/captured_data

# ------------------------------------------------------------------
# 5. 配置波形显示
# ------------------------------------------------------------------
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# ------------------------------------------------------------------
# 6. 运行仿真
# ------------------------------------------------------------------
echo "Running simulation..."
run -all

# 缩放以适应全部波形
wave zoom full

echo "Simulation complete."
echo "Check waveform and console output for results."
