# ==============================================================================
# 1-Wire Loopback Testbench ModelSim Simulation Script
# Tests one_wire_handler (Master) with real one_wire.v (Slave)
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
echo "Compiling 1-Wire loopback testbench with real slave..."

# 编译底层模块 - Master side
vlog -sv ../../rtl/one_wire/one_wire_master.v

# 编译handler模块 - Master
vlog -sv ../../rtl/one_wire/one_wire_handler.v

# 编译真实的slave模块
vlog -sv ../../rtl/one_wire/one_wire.v

# 编译测试台
vlog -sv ../../tb/one_wire_loopback_tb.v

# ------------------------------------------------------------------------------
# 3. 启动仿真
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.one_wire_loopback_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. 添加波形
# ------------------------------------------------------------------------------

# --- Clock & Reset ---
add wave -group "Clock & Reset" /one_wire_loopback_tb/clk
add wave -group "Clock & Reset" /one_wire_loopback_tb/rst_n

# --- 1-Wire Bus ---
add wave -group "1-Wire Bus" /one_wire_loopback_tb/onewire_io

# --- Master Command Interface ---
add wave -group "Master Cmd" -radix hex /one_wire_loopback_tb/cmd_type
add wave -group "Master Cmd" -radix unsigned /one_wire_loopback_tb/cmd_length
add wave -group "Master Cmd" -radix hex /one_wire_loopback_tb/cmd_data
add wave -group "Master Cmd" /one_wire_loopback_tb/cmd_start
add wave -group "Master Cmd" /one_wire_loopback_tb/cmd_data_valid
add wave -group "Master Cmd" /one_wire_loopback_tb/cmd_done
add wave -group "Master Cmd" /one_wire_loopback_tb/cmd_ready

# --- Master State ---
add wave -group "Master State" -radix unsigned /one_wire_loopback_tb/dut_master/handler_state
add wave -group "Master State" -radix unsigned /one_wire_loopback_tb/dut_master/byte_counter
add wave -group "Master State" -radix unsigned /one_wire_loopback_tb/dut_master/bit_counter
add wave -group "Master State" -radix unsigned /one_wire_loopback_tb/dut_master/bytes_to_process

# --- Master FIFO ---
add wave -group "Master FIFO" -radix unsigned /one_wire_loopback_tb/dut_master/tx_fifo_count
add wave -group "Master FIFO" /one_wire_loopback_tb/dut_master/tx_fifo_empty
add wave -group "Master FIFO" -radix hex /one_wire_loopback_tb/dut_master/tx_fifo_data_out

# --- Master 1-Wire Master Core ---
add wave -group "Master Core" -radix unsigned /one_wire_loopback_tb/dut_master/u_one_wire_master/state
add wave -group "Master Core" -radix unsigned /one_wire_loopback_tb/dut_master/u_one_wire_master/timer
add wave -group "Master Core" /one_wire_loopback_tb/dut_master/u_one_wire_master/busy
add wave -group "Master Core" /one_wire_loopback_tb/dut_master/u_one_wire_master/done
add wave -group "Master Core" /one_wire_loopback_tb/dut_master/u_one_wire_master/oe
add wave -group "Master Core" /one_wire_loopback_tb/dut_master/u_one_wire_master/onewire_io

# --- Slave State ---
add wave -group "Slave State" -radix unsigned /one_wire_loopback_tb/slave_state_out
add wave -group "Slave State" /one_wire_loopback_tb/slave_error
add wave -group "Slave State" /one_wire_loopback_tb/slave_synchro_success

# --- Slave Received Data ---
add wave -group "Slave Data" -radix hex /one_wire_loopback_tb/slave_data_byte
add wave -group "Slave Data" -radix hex /one_wire_loopback_tb/slave_mpcd
add wave -group "Slave Data" /one_wire_loopback_tb/slave_b_count
add wave -group "Slave Data" /one_wire_loopback_tb/slave_by_count

# --- Slave Internal (if accessible) ---
add wave -group "Slave Internal" -radix unsigned /one_wire_loopback_tb/dut_slave/presence_first_counter
add wave -group "Slave Internal" -radix unsigned /one_wire_loopback_tb/dut_slave/bit_counter
add wave -group "Slave Internal" -radix unsigned /one_wire_loopback_tb/dut_slave/byte_counter
add wave -group "Slave Internal" -radix hex /one_wire_loopback_tb/dut_slave/input_byte

# ------------------------------------------------------------------
# 5. 配置波形显示
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
# 6. 运行仿真
# ------------------------------------------------------------------
echo "Running Master-Slave loopback test..."
run -all

# 缩放以适应全部波形
wave zoom full

echo "Simulation complete."
echo "Check console output for test results."
