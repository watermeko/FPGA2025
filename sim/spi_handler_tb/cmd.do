# ==============================================================================
# SPI Handler (with Simple SPI Master) Testbench ModelSim Simulation Script
# ==============================================================================

quit -sim

# ------------------------------------------------------------------------------
# 1. 清理并创建库 (保持不变)
# ------------------------------------------------------------------------------
if {[file isdirectory work]} {
  vdel -lib work -all
}
vlib work
vmap work work

# ------------------------------------------------------------------------------
# 2. 编译Gowin原语文件 (不再需要，已删除)
# ------------------------------------------------------------------------------
# 我们不再使用Gowin的.vo网表文件, 因此不再需要Gowin的原语库。

# ------------------------------------------------------------------------------
# 3. 编译设计文件 (已修改)
# ------------------------------------------------------------------------------
echo "Compiling user design and testbench..."
# 不再编译 spi_master.vo
# 转而编译我们自己写的 simple_spi_master.v
vlog -sv ../../rtl/spi/simple_spi_master.v
vlog -sv ../../rtl/spi/spi_handler.v
vlog -sv ../../tb/spi_handler_tb.v

# ------------------------------------------------------------------------------
# 4. 启动仿真 (已修改)
# ------------------------------------------------------------------------------
echo "Starting simulation..."
# 不再需要链接Gowin库 (-L gw5a_lib)
vsim work.spi_handler_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 5. 添加波形 (已修改)
# ------------------------------------------------------------------------------

# --- State Machine (DUT内部状态) ---
add wave -group "State Machine" -radix unsigned /spi_handler_tb/uut/state

# --- Command Interface (顶层接口，保持不变) ---
add wave -group "Command Interface" -radix hex /spi_handler_tb/cmd_type
add wave -group "Command Interface" -radix unsigned /spi_handler_tb/cmd_length
add wave -group "Command Interface" -radix hex /spi_handler_tb/cmd_data
add wave -group "Command Interface" -radix unsigned /spi_handler_tb/cmd_data_index
add wave -group "Command Interface" /spi_handler_tb/cmd_start
add wave -group "Command Interface" /spi_handler_tb/cmd_data_valid
add wave -group "Command Interface" /spi_handler_tb/cmd_done
add wave -group "Command Interface" /spi_handler_tb/cmd_ready

# --- Simple SPI Master Interface (DUT内部信号，已更新) ---
add wave -group "Simple SPI Interface" /spi_handler_tb/uut/spi_start
add wave -group "Simple SPI Interface" -radix hex /spi_handler_tb/uut/current_tx_byte
add wave -group "Simple SPI Interface" -radix hex /spi_handler_tb/uut/spi_rx_byte
add wave -group "Simple SPI Interface" /spi_handler_tb/uut/spi_done

# --- Upload Interface (顶层接口，保持不变) ---
add wave -group "Upload Interface" /spi_handler_tb/upload_req
add wave -group "Upload Interface" /spi_handler_tb/upload_valid
add wave -group "Upload Interface" -radix hex /spi_handler_tb/upload_data
add wave -group "Upload Interface" -radix hex /spi_handler_tb/upload_source
add wave -group "Upload Interface" /spi_handler_tb/upload_ready

# --- Flow Control (DUT内部新增，流式架构关键信号) ---
add wave -group "Flow Control" -radix unsigned /spi_handler_tb/uut/write_len
add wave -group "Flow Control" -radix unsigned /spi_handler_tb/uut/read_len
add wave -group "Flow Control" /spi_handler_tb/uut/header_byte_received
add wave -group "Flow Control" -radix unsigned /spi_handler_tb/uut/tx_count
add wave -group "Flow Control" -radix unsigned /spi_handler_tb/uut/rx_count
add wave -group "Flow Control" -radix hex /spi_handler_tb/uut/current_rx_byte

# --- SPI Bus Timing (顶层信号，保持不变) ---
add wave -group "SPI Bus" /spi_handler_tb/spi_clk
add wave -group "SPI Bus" /spi_handler_tb/spi_cs_n
add wave -group "SPI Bus" /spi_handler_tb/spi_mosi
add wave -group "SPI Bus" /spi_handler_tb/spi_miso

# --- Slave Internals (Testbench内部信号，保持不变) ---
add wave -group "Slave Internals" -radix hex /spi_handler_tb/slave_tx_shift_reg
add wave -group "Slave Internals" /spi_handler_tb/slave_bit_cnt
add wave -group "Slave Internals" /spi_handler_tb/slave_byte_cnt

# ------------------------------------------------------------------
# 6. 运行仿真 (保持不变)
# ------------------------------------------------------------------
run -all
wave zoom full
echo "Simulation completed."