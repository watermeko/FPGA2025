# ==============================================================================
# ModelSim仿真脚本 - Upload Full Integration Test
# 测试模块: upload_adapter + upload_packer + upload_arbiter
# ==============================================================================

# 清理之前的仿真
if {[file exists work]} {
    vdel -all
}

# 创建工作库
vlib work
vmap work work

# ==============================================================================
# 编译源文件
# ==============================================================================

puts "=========================================="
puts "  Compiling RTL source files..."
puts "=========================================="

# 编译三个核心模块
vlog -work work ../../rtl/upload_adapter_0.v
if {$? != 0} {
    puts "ERROR: Failed to compile upload_adapter_0.v"
    quit -f
}

vlog -work work ../../rtl/upload_packer.v
if {$? != 0} {
    puts "ERROR: Failed to compile upload_packer.v"
    quit -f
}

vlog -work work ../../rtl/upload_arbiter.v
if {$? != 0} {
    puts "ERROR: Failed to compile upload_arbiter.v"
    quit -f
}

# 编译testbench
vlog -work work ../../tb/upload_full_integration_tb.v
if {$? != 0} {
    puts "ERROR: Failed to compile testbench"
    quit -f
}

puts "\n=========================================="
puts "  Compilation successful!"
puts "=========================================="

# ==============================================================================
# 启动仿真
# ==============================================================================

puts "\n=========================================="
puts "  Starting simulation..."
puts "=========================================="

vsim -voptargs=+acc work.upload_full_integration_tb

# ==============================================================================
# 添加波形
# ==============================================================================

puts "\n=========================================="
puts "  Adding waveforms..."
puts "=========================================="

# 顶层信号
add wave -divider "Clock & Reset"
add wave -color Yellow sim:/upload_full_integration_tb/clk
add wave -color Orange sim:/upload_full_integration_tb/rst_n

# UART Handler输入
add wave -divider "UART Handler Signals"
add wave -color Cyan sim:/upload_full_integration_tb/uart_upload_active
add wave -radix hex sim:/upload_full_integration_tb/uart_upload_data
add wave -radix hex sim:/upload_full_integration_tb/uart_upload_source
add wave sim:/upload_full_integration_tb/uart_upload_valid
add wave sim:/upload_full_integration_tb/uart_upload_ready

# SPI Handler输入
add wave -divider "SPI Handler Signals"
add wave -color Cyan sim:/upload_full_integration_tb/spi_upload_active
add wave -radix hex sim:/upload_full_integration_tb/spi_upload_data
add wave -radix hex sim:/upload_full_integration_tb/spi_upload_source
add wave sim:/upload_full_integration_tb/spi_upload_valid
add wave sim:/upload_full_integration_tb/spi_upload_ready

# Adapter输出 -> Packer输入
add wave -divider "Adapter -> Packer (UART)"
add wave sim:/upload_full_integration_tb/uart_packer_req
add wave -radix hex sim:/upload_full_integration_tb/uart_packer_data
add wave sim:/upload_full_integration_tb/uart_packer_valid
add wave sim:/upload_full_integration_tb/uart_packer_ready

add wave -divider "Adapter -> Packer (SPI)"
add wave sim:/upload_full_integration_tb/spi_packer_req
add wave -radix hex sim:/upload_full_integration_tb/spi_packer_data
add wave sim:/upload_full_integration_tb/spi_packer_valid
add wave sim:/upload_full_integration_tb/spi_packer_ready

# Packer内部状态（UART通道）
add wave -divider "Packer Internal (UART Ch0)"
add wave -radix unsigned sim:/upload_full_integration_tb/u_packer/state[0]
add wave -radix unsigned sim:/upload_full_integration_tb/u_packer/data_count[0]
add wave -radix unsigned sim:/upload_full_integration_tb/u_packer/data_index[0]

# Packer内部状态（SPI通道）
add wave -divider "Packer Internal (SPI Ch1)"
add wave -radix unsigned sim:/upload_full_integration_tb/u_packer/state[1]
add wave -radix unsigned sim:/upload_full_integration_tb/u_packer/data_count[1]
add wave -radix unsigned sim:/upload_full_integration_tb/u_packer/data_index[1]

# Packer输出 -> Arbiter输入
add wave -divider "Packer -> Arbiter"
add wave -radix binary sim:/upload_full_integration_tb/packed_req
add wave -radix hex sim:/upload_full_integration_tb/packed_data
add wave -radix hex sim:/upload_full_integration_tb/packed_source
add wave -radix binary sim:/upload_full_integration_tb/packed_valid
add wave -radix binary sim:/upload_full_integration_tb/arbiter_ready

# Arbiter内部状态
add wave -divider "Arbiter Internal"
add wave -radix unsigned sim:/upload_full_integration_tb/u_arbiter/state
add wave -radix unsigned sim:/upload_full_integration_tb/u_arbiter/current_source
add wave sim:/upload_full_integration_tb/u_arbiter/in_packet
add wave -radix binary sim:/upload_full_integration_tb/u_arbiter/fifo_has_data

# Arbiter FIFO状态
add wave -divider "Arbiter FIFO Status"
add wave -radix unsigned sim:/upload_full_integration_tb/u_arbiter/gen_fifos[0]/count
add wave -radix unsigned sim:/upload_full_integration_tb/u_arbiter/gen_fifos[1]/count

# Arbiter输出 -> Processor
add wave -divider "Arbiter -> Processor (Output)"
add wave -color Green sim:/upload_full_integration_tb/merged_req
add wave -color Green -radix hex sim:/upload_full_integration_tb/merged_data
add wave -color Green -radix hex sim:/upload_full_integration_tb/merged_source
add wave -color Green sim:/upload_full_integration_tb/merged_valid
add wave sim:/upload_full_integration_tb/processor_ready

# 统计信息
add wave -divider "Statistics"
add wave -radix unsigned sim:/upload_full_integration_tb/total_bytes_received
add wave -radix unsigned sim:/upload_full_integration_tb/uart_packets_sent
add wave -radix unsigned sim:/upload_full_integration_tb/spi_packets_sent

# ==============================================================================
# 配置波形显示
# ==============================================================================

# 设置时间单位
configure wave -timelineunits ns

# 设置数字显示格式
configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100

# ==============================================================================
# 运行仿真
# ==============================================================================

puts "\n=========================================="
puts "  Running simulation..."
puts "=========================================="

# 运行仿真（足够长的时间）
run -all

# ==============================================================================
# 显示结果
# ==============================================================================

puts "\n=========================================="
puts "  Simulation completed!"
puts "=========================================="
puts "  Waveform file: upload_full_integration_tb.vcd"
puts "  To view waveform: gtkwave upload_full_integration_tb.vcd"
puts "=========================================="

# 缩放波形以适应窗口
wave zoom full

# 保持仿真器打开以便查看波形
# quit -sim
