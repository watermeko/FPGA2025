# ==============================================================================
# SPI Handler 简化测试 - 用于快速验证流式架构
# ==============================================================================

quit -sim

# 清理并创建库
if {[file isdirectory work]} {
  vdel -lib work -all
}
vlib work
vmap work work

# 编译设计文件
echo "Compiling RTL files..."
vlog -sv ../../rtl/spi/simple_spi_master.v
vlog -sv ../../rtl/spi/spi_handler.v
vlog -sv ../../tb/spi_handler_simple_tb.v

# 启动仿真
echo "Starting simulation..."
vsim work.spi_handler_simple_tb -voptargs="+acc" -t ps

# 添加波形
add wave -group "Clock & Reset" /spi_handler_simple_tb/clk
add wave -group "Clock & Reset" /spi_handler_simple_tb/rst_n

add wave -group "State Machine" -radix unsigned /spi_handler_simple_tb/uut/state
add wave -group "State Machine" /spi_handler_simple_tb/uut/header_byte_received
add wave -group "State Machine" -radix unsigned /spi_handler_simple_tb/uut/write_len
add wave -group "State Machine" -radix unsigned /spi_handler_simple_tb/uut/read_len
add wave -group "State Machine" -radix unsigned /spi_handler_simple_tb/uut/tx_count
add wave -group "State Machine" -radix unsigned /spi_handler_simple_tb/uut/rx_count

add wave -group "Command Interface" /spi_handler_simple_tb/cmd_start
add wave -group "Command Interface" /spi_handler_simple_tb/cmd_ready
add wave -group "Command Interface" /spi_handler_simple_tb/cmd_data_valid
add wave -group "Command Interface" -radix hex /spi_handler_simple_tb/cmd_data
add wave -group "Command Interface" /spi_handler_simple_tb/cmd_done

add wave -group "SPI Interface" /spi_handler_simple_tb/uut/spi_start
add wave -group "SPI Interface" -radix hex /spi_handler_simple_tb/uut/current_tx_byte
add wave -group "SPI Interface" -radix hex /spi_handler_simple_tb/uut/current_rx_byte
add wave -group "SPI Interface" /spi_handler_simple_tb/uut/spi_done

add wave -group "SPI Physical" /spi_handler_simple_tb/spi_clk
add wave -group "SPI Physical" /spi_handler_simple_tb/spi_cs_n
add wave -group "SPI Physical" /spi_handler_simple_tb/spi_mosi
add wave -group "SPI Physical" /spi_handler_simple_tb/spi_miso

add wave -group "Upload Interface" /spi_handler_simple_tb/upload_active
add wave -group "Upload Interface" /spi_handler_simple_tb/upload_valid
add wave -group "Upload Interface" -radix hex /spi_handler_simple_tb/upload_data
add wave -group "Upload Interface" -radix hex /spi_handler_simple_tb/upload_source

# 运行仿真
run -all
wave zoom full
echo "Simulation completed."
