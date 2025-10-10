# ==============================================================================
# Upload Arbiter Testbench ModelSim Simulation Script
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
echo "Compiling upload_arbiter module and testbench..."
vlog -sv ../../rtl/upload_arbiter.v
vlog -sv ../../tb/upload_arbiter_tb.v

# ------------------------------------------------------------------------------
# 3. 启动仿真
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.upload_arbiter_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. 添加波形
# ------------------------------------------------------------------------------

# --- Clock and Reset ---
add wave -group "Clock & Reset" /upload_arbiter_tb/clk
add wave -group "Clock & Reset" /upload_arbiter_tb/rst_n

# --- UART Source Signals ---
add wave -group "UART Source" /upload_arbiter_tb/uart_req
add wave -group "UART Source" -radix hex /upload_arbiter_tb/uart_data
add wave -group "UART Source" /upload_arbiter_tb/uart_valid
add wave -group "UART Source" /upload_arbiter_tb/uart_ready

# --- SPI Source Signals ---
add wave -group "SPI Source" /upload_arbiter_tb/spi_req
add wave -group "SPI Source" -radix hex /upload_arbiter_tb/spi_data
add wave -group "SPI Source" /upload_arbiter_tb/spi_valid
add wave -group "SPI Source" /upload_arbiter_tb/spi_ready

# --- Arbiter State Machine ---
add wave -group "Arbiter Internals" -radix unsigned /upload_arbiter_tb/u_arbiter/state
add wave -group "Arbiter Internals" -radix unsigned /upload_arbiter_tb/u_arbiter/current_source
add wave -group "Arbiter Internals" -radix unsigned /upload_arbiter_tb/u_arbiter/next_source

# --- Merged Output to Processor ---
add wave -group "Merged Output" /upload_arbiter_tb/merged_upload_req
add wave -group "Merged Output" -radix hex /upload_arbiter_tb/merged_upload_data
add wave -group "Merged Output" -radix hex /upload_arbiter_tb/merged_upload_source
add wave -group "Merged Output" /upload_arbiter_tb/merged_upload_valid
add wave -group "Merged Output" /upload_arbiter_tb/processor_upload_ready

# --- Test Statistics ---
add wave -group "Statistics" -radix unsigned /upload_arbiter_tb/uart_sent_count
add wave -group "Statistics" -radix unsigned /upload_arbiter_tb/spi_sent_count
add wave -group "Statistics" -radix unsigned /upload_arbiter_tb/total_received

# ------------------------------------------------------------------------------
# 5. 运行仿真
# ------------------------------------------------------------------------------
run -all
wave zoom full
echo "Simulation completed."
