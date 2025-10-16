# ==============================================================================
# 1-Wire Master Testbench ModelSim Simulation Script
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
echo "Compiling 1-Wire master design and testbench..."

# 编译 1-Wire Master 核心模块
vlog -sv ../../rtl/one_wire/one_wire_master.v

# 编译测试台
vlog -sv ../../tb/one_wire_master_tb.v

# ------------------------------------------------------------------------------
# 3. 启动仿真
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.one_wire_master_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. 添加波形
# ------------------------------------------------------------------------------

# --- Clock and Reset ---
add wave -group "Clock & Reset" /one_wire_master_tb/clk
add wave -group "Clock & Reset" /one_wire_master_tb/rst_n

# --- Control Signals ---
add wave -group "Control" /one_wire_master_tb/start_reset
add wave -group "Control" /one_wire_master_tb/start_write_bit
add wave -group "Control" /one_wire_master_tb/start_read_bit
add wave -group "Control" /one_wire_master_tb/write_bit_data

# --- Status Signals ---
add wave -group "Status" /one_wire_master_tb/busy
add wave -group "Status" /one_wire_master_tb/done
add wave -group "Status" /one_wire_master_tb/read_bit_data
add wave -group "Status" /one_wire_master_tb/presence_detected

# --- 1-Wire Bus ---
add wave -group "1-Wire Bus" /one_wire_master_tb/onewire_io
add wave -group "1-Wire Bus" /one_wire_master_tb/onewire_drive
add wave -group "1-Wire Bus" /one_wire_master_tb/onewire_value

# --- DUT Internal State Machine ---
add wave -group "State Machine" -radix unsigned /one_wire_master_tb/dut/state
add wave -group "State Machine" -radix unsigned /one_wire_master_tb/dut/timer

# --- DUT Internal Control ---
add wave -group "DUT Internal" /one_wire_master_tb/dut/oe
add wave -group "DUT Internal" /one_wire_master_tb/dut/output_val

# ------------------------------------------------------------------
# 5. 配置波形显示
# ------------------------------------------------------------------
configure wave -namecolwidth 200
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

echo "Simulation completed."
echo "Check waveform for results."
