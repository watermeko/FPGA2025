# ==============================================================================
# ModelSim仿真脚本 - Upload Full Integration Test (Version 0)
# 测试模块: upload_adapter_0 + upload_packer_0 + upload_arbiter_0
# ==============================================================================

# 清理之前的仿真
if {[file exists work]} {
    vdel -all
}

# 创建工作库
vlib work
vmap work work

# ==============================================================================
# 编译源文件（使用带0版本）
# ==============================================================================

puts "=========================================="
puts "  Compiling RTL source files (Version 0)..."
puts "=========================================="

# 编译三个核心模块（带0版本）
puts "\nCompiling upload_adapter_0.v..."
vlog -work work ../../rtl/upload_adapter_0.v

puts "\nCompiling upload_packer_0.v..."
vlog -work work ../../rtl/upload_packer_0.v

puts "\nCompiling upload_arbiter_0.v..."
vlog -work work ../../rtl/upload_arbiter_0.v

# 编译testbench
puts "\nCompiling testbench (V0)..."
vlog -work work ../../tb/upload_full_integration_v0_tb.v

puts "\n=========================================="
puts "  Compilation successful! (Version 0)"
puts "=========================================="

# ==============================================================================
# 启动仿真
# ==============================================================================

puts "\n=========================================="
puts "  Starting simulation (Version 0)..."
puts "=========================================="

vsim -voptargs=+acc work.upload_full_integration_v0_tb

# ==============================================================================
# 添加波形
# ==============================================================================

puts "\n=========================================="
puts "  Adding waveforms..."
puts "=========================================="

# 顶层信号
add wave -divider "=== Clock & Reset ==="
add wave -color Yellow sim:/upload_full_integration_v0_tb/clk
add wave -color Orange sim:/upload_full_integration_v0_tb/rst_n

# UART Handler输入
add wave -divider "=== UART Handler Signals ==="
add wave -color Cyan sim:/upload_full_integration_v0_tb/uart_upload_active
add wave -radix hex sim:/upload_full_integration_v0_tb/uart_upload_data
add wave -radix hex sim:/upload_full_integration_v0_tb/uart_upload_source
add wave sim:/upload_full_integration_v0_tb/uart_upload_valid
add wave sim:/upload_full_integration_v0_tb/uart_upload_ready

# SPI Handler输入
add wave -divider "=== SPI Handler Signals ==="
add wave -color Cyan sim:/upload_full_integration_v0_tb/spi_upload_active
add wave -radix hex sim:/upload_full_integration_v0_tb/spi_upload_data
add wave -radix hex sim:/upload_full_integration_v0_tb/spi_upload_source
add wave sim:/upload_full_integration_v0_tb/spi_upload_valid
add wave sim:/upload_full_integration_v0_tb/spi_upload_ready

# Adapter输出 -> Packer输入
add wave -divider "=== Adapter -> Packer (UART) ==="
add wave sim:/upload_full_integration_v0_tb/uart_packer_req
add wave -radix hex sim:/upload_full_integration_v0_tb/uart_packer_data
add wave sim:/upload_full_integration_v0_tb/uart_packer_valid
add wave sim:/upload_full_integration_v0_tb/uart_packer_ready

add wave -divider "=== Adapter -> Packer (SPI) ==="
add wave sim:/upload_full_integration_v0_tb/spi_packer_req
add wave -radix hex sim:/upload_full_integration_v0_tb/spi_packer_data
add wave sim:/upload_full_integration_v0_tb/spi_packer_valid
add wave sim:/upload_full_integration_v0_tb/spi_packer_ready

# Packer内部状态（UART通道）
add wave -divider "=== Packer Internal (UART Ch0) ==="
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_packer/state\[0\]
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_packer/data_count\[0\]
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_packer/data_index\[0\]

# Packer内部状态（SPI通道）
add wave -divider "=== Packer Internal (SPI Ch1) ==="
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_packer/state\[1\]
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_packer/data_count\[1\]
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_packer/data_index\[1\]

# Packer输出 -> Arbiter输入
add wave -divider "=== Packer -> Arbiter ==="
add wave -radix binary sim:/upload_full_integration_v0_tb/packed_req
add wave -radix hex sim:/upload_full_integration_v0_tb/packed_data
add wave -radix hex sim:/upload_full_integration_v0_tb/packed_source
add wave -radix binary sim:/upload_full_integration_v0_tb/packed_valid
add wave -radix binary sim:/upload_full_integration_v0_tb/arbiter_ready

# Arbiter内部状态（V0版本特有信号）
add wave -divider "=== Arbiter Internal (V0) ==="
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_arbiter/state
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_arbiter/current_source
add wave sim:/upload_full_integration_v0_tb/u_arbiter/in_packet
add wave -radix binary sim:/upload_full_integration_v0_tb/u_arbiter/fifo_has_data
add wave -radix binary sim:/upload_full_integration_v0_tb/u_arbiter/fifo_rd_en_ctrl

# 优先级观察（关键）
add wave -divider "=== Priority Observation (Bug Check) ==="
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_arbiter/next_source
add wave -color Red -label "BUG: SPI Priority" sim:/upload_full_integration_v0_tb/u_arbiter/fifo_has_data\[1\]
add wave -color Green -label "Should be UART" sim:/upload_full_integration_v0_tb/u_arbiter/fifo_has_data\[0\]

# Arbiter FIFO状态
add wave -divider "=== Arbiter FIFO Status ==="
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_arbiter/gen_fifos\[0\].count
add wave -radix unsigned sim:/upload_full_integration_v0_tb/u_arbiter/gen_fifos\[1\].count
add wave sim:/upload_full_integration_v0_tb/u_arbiter/gen_fifos\[0\].fifo_empty
add wave sim:/upload_full_integration_v0_tb/u_arbiter/gen_fifos\[1\].fifo_empty

# Arbiter输出 -> Processor
add wave -divider "=== Arbiter -> Processor (Output) ==="
add wave -color Green sim:/upload_full_integration_v0_tb/merged_req
add wave -color Green -radix hex sim:/upload_full_integration_v0_tb/merged_data
add wave -color Green -radix hex sim:/upload_full_integration_v0_tb/merged_source
add wave -color Green sim:/upload_full_integration_v0_tb/merged_valid
add wave sim:/upload_full_integration_v0_tb/processor_ready

# 统计信息
add wave -divider "=== Statistics ==="
add wave -radix unsigned sim:/upload_full_integration_v0_tb/total_bytes_received
add wave -radix unsigned sim:/upload_full_integration_v0_tb/uart_packets_sent
add wave -radix unsigned sim:/upload_full_integration_v0_tb/spi_packets_sent
add wave -radix hex -label "First Source (Concurrent)" sim:/upload_full_integration_v0_tb/first_concurrent_source

# ==============================================================================
# 配置波形显示
# ==============================================================================

configure wave -timelineunits ns
configure wave -signalnamewidth 1
configure wave -namecolwidth 350
configure wave -valuecolwidth 100

# ==============================================================================
# 运行仿真
# ==============================================================================

puts "\n=========================================="
puts "  Running simulation (Version 0)..."
puts "  Watch for SPI priority bug in Test 3!"
puts "=========================================="

run -all

# ==============================================================================
# 显示结果
# ==============================================================================

puts "\n=========================================="
puts "  Simulation completed! (Version 0)"
puts "=========================================="
puts "  This version demonstrates:"
puts "  1. SPI > UART priority (Bug!)"
puts "  2. fifo_rd_en_ctrl workaround"
puts "=========================================="
puts "  Waveform file: upload_full_integration_v0_tb.vcd"
puts "=========================================="

wave zoom full

