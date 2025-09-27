# ==============================================================================
# SPI Handler Testbench ModelSim Simulation Script（已修正信号名）
# ==============================================================================

quit -sim

# ------------------------------------------------------------------------------
# 1. 清理并创建库
# ------------------------------------------------------------------------------
if {[file isdirectory work]} {
  vdel -lib work -all
}
if {[file isdirectory gw5a_lib]} {
  vdel -lib gw5a_lib -all
}
vlib work
vmap work work
vlib gw5a_lib

# ------------------------------------------------------------------------------
# 2. 编译Gowin原语文件
# ------------------------------------------------------------------------------
echo "Compiling Gowin primitive source files..."
set GOWIN_PATH "E:/GOWIN/Gowin_V1.9.9_x64/IDE"
vlog -work gw5a_lib "${GOWIN_PATH}/simlib/gw5a/prim_sim.v"

# ------------------------------------------------------------------------------
# 3. 编译设计文件
# ------------------------------------------------------------------------------
echo "Compiling user design and testbench..."
vlog -sv ../../rtl/spi/spi_master/spi_master.vo
vlog -sv ../../rtl/spi/spi_handler.v
vlog -sv ../../tb/spi_handler_tb.v

# ------------------------------------------------------------------------------
# 4. 启动仿真
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim -L gw5a_lib work.spi_handler_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 5. 添加波形
# ------------------------------------------------------------------------------

# --- State Machine ---
add wave -group "State Machine" -radix unsigned /spi_handler_tb/uut/state
add wave -group "State Machine" -label "State Name" /spi_handler_tb/uut/state

# --- Command Interface ---
add wave -group "Command Interface" -radix hex /spi_handler_tb/cmd_type
add wave -group "Command Interface" -radix unsigned /spi_handler_tb/cmd_length
add wave -group "Command Interface" -radix hex /spi_handler_tb/cmd_data
add wave -group "Command Interface" -radix unsigned /spi_handler_tb/cmd_data_index
add wave -group "Command Interface" /spi_handler_tb/cmd_start
add wave -group "Command Interface" /spi_handler_tb/cmd_data_valid
add wave -group "Command Interface" /spi_handler_tb/cmd_done
add wave -group "Command Interface" /spi_handler_tb/cmd_ready

# --- SPI IP Core Interface ---
add wave -group "SPI IP Core" /spi_handler_tb/uut/spi_tx_en
add wave -group "SPI IP Core" /spi_handler_tb/uut/spi_rx_en
add wave -group "SPI IP Core" -radix hex /spi_handler_tb/uut/spi_waddr
add wave -group "SPI IP Core" -radix hex /spi_handler_tb/uut/spi_wdata
add wave -group "SPI IP Core" -radix hex /spi_handler_tb/uut/spi_rdata
add wave -group "SPI IP Core" /spi_handler_tb/uut/spi_int

# --- Upload Interface ---
add wave -group "Upload Interface" /spi_handler_tb/upload_req
add wave -group "Upload Interface" /spi_handler_tb/upload_valid
add wave -group "Upload Interface" -radix hex /spi_handler_tb/upload_data
add wave -group "Upload Interface" -radix hex /spi_handler_tb/upload_source
add wave -group "Upload Interface" /spi_handler_tb/upload_ready

# --- TX/RX Buffers (前3字节) ---
add wave -group "TX Buffer" -radix hex /spi_handler_tb/uut/tx_buffer(0)
add wave -group "TX Buffer" -radix hex /spi_handler_tb/uut/tx_buffer(1)
add wave -group "TX Buffer" -radix hex /spi_handler_tb/uut/tx_buffer(2)

add wave -group "RX Buffer" -radix hex /spi_handler_tb/uut/rx_buffer(0)
add wave -group "RX Buffer" -radix hex /spi_handler_tb/uut/rx_buffer(1)
add wave -group "RX Buffer" -radix hex /spi_handler_tb/uut/rx_buffer(2)

# --- SPI Bus Timing ---
add wave -group "SPI Bus" /spi_handler_tb/spi_clk
add wave -group "SPI Bus" /spi_handler_tb/spi_cs_n
add wave -group "SPI Bus" /spi_handler_tb/spi_mosi
add wave -group "SPI Bus" /spi_handler_tb/spi_miso

# --- Slave Internals ---
add wave -group "Slave Internals" /spi_handler_tb/spi_miso
add wave -group "Slave Internals" -radix hex /spi_handler_tb/slave_tx_shift_reg
add wave -group "Slave Internals" /spi_handler_tb/slave_bit_cnt
add wave -group "Slave Internals" /spi_handler_tb/slave_byte_cnt

# ------------------------------------------------------------------
# 6. 运行仿真
# ------------------------------------------------------------------
run -all
wave zoom full
echo "Simulation completed."