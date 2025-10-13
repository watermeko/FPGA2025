# ==============================================================================
# Upload Packer Testbench ModelSim Simulation Script
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
echo "Compiling upload_packer module and testbench..."
vlog -sv ../../rtl/upload_packer.v
vlog -sv ../../tb/upload_packer_tb.v

# ------------------------------------------------------------------------------
# 3. 启动仿真
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.upload_packer_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. 添加波形
# ------------------------------------------------------------------------------

# --- Clock and Reset ---
add wave -group "Clock & Reset" /upload_packer_tb/clk
add wave -group "Clock & Reset" /upload_packer_tb/rst_n

# --- UART Channel (Channel 0) ---
add wave -group "UART Channel" /upload_packer_tb/uart_req
add wave -group "UART Channel" -radix hex /upload_packer_tb/uart_data
add wave -group "UART Channel" /upload_packer_tb/uart_valid
add wave -group "UART Channel" /upload_packer_tb/uart_ready
add wave -group "UART Channel" /upload_packer_tb/uart_packed_valid
add wave -group "UART Channel" -radix hex /upload_packer_tb/uart_packed_data

# --- SPI Channel (Channel 1) ---
add wave -group "SPI Channel" /upload_packer_tb/spi_req
add wave -group "SPI Channel" -radix hex /upload_packer_tb/spi_data
add wave -group "SPI Channel" /upload_packer_tb/spi_valid
add wave -group "SPI Channel" /upload_packer_tb/spi_ready
add wave -group "SPI Channel" /upload_packer_tb/spi_packed_valid
add wave -group "SPI Channel" -radix hex /upload_packer_tb/spi_packed_data

# --- Multi-channel Vectors (Input) ---
add wave -group "Multi-channel Input" -radix binary /upload_packer_tb/raw_upload_req
add wave -group "Multi-channel Input" -radix hex /upload_packer_tb/raw_upload_data
add wave -group "Multi-channel Input" -radix hex /upload_packer_tb/raw_upload_source
add wave -group "Multi-channel Input" -radix binary /upload_packer_tb/raw_upload_valid
add wave -group "Multi-channel Input" -radix binary /upload_packer_tb/raw_upload_ready

# --- Multi-channel Vectors (Output) ---
add wave -group "Multi-channel Output" -radix binary /upload_packer_tb/packed_upload_req
add wave -group "Multi-channel Output" -radix hex /upload_packer_tb/packed_upload_data
add wave -group "Multi-channel Output" -radix hex /upload_packer_tb/packed_upload_source
add wave -group "Multi-channel Output" -radix binary /upload_packer_tb/packed_upload_valid
add wave -group "Multi-channel Output" -radix binary /upload_packer_tb/packed_upload_ready

# --- Packer Module Ports ---
add wave -group "Packer Ports" -radix binary /upload_packer_tb/u_packer/raw_upload_req
add wave -group "Packer Ports" -radix hex /upload_packer_tb/u_packer/raw_upload_data
add wave -group "Packer Ports" -radix binary /upload_packer_tb/u_packer/raw_upload_valid
add wave -group "Packer Ports" -radix binary /upload_packer_tb/u_packer/raw_upload_ready
add wave -group "Packer Ports" -radix binary /upload_packer_tb/u_packer/packed_upload_req
add wave -group "Packer Ports" -radix hex /upload_packer_tb/u_packer/packed_upload_data
add wave -group "Packer Ports" -radix binary /upload_packer_tb/u_packer/packed_upload_valid
add wave -group "Packer Ports" -radix binary /upload_packer_tb/u_packer/packed_upload_ready

# --- Packer Internal Signals (关键调试信号!) ---
add wave -group "Packer Internals" -radix binary /upload_packer_tb/u_packer/ch_packed_valid
add wave -group "Packer Internals" -radix hex /upload_packer_tb/u_packer/ch_packed_data
add wave -group "Packer Internals" -radix binary /upload_packer_tb/u_packer/ch_packed_req
add wave -group "Packer Internals" -radix hex /upload_packer_tb/u_packer/state
add wave -group "Packer Internals" -radix hex /upload_packer_tb/u_packer/data_count

# Note: Internal signals of generate blocks may not be directly accessible
# Use the GUI to manually add signals from u_packer/gen_packer_channels[0] and [1] if needed

# --- Test Statistics ---
add wave -group "Statistics" -radix unsigned /upload_packer_tb/uart_bytes_received
add wave -group "Statistics" -radix unsigned /upload_packer_tb/spi_bytes_received

# ------------------------------------------------------------------------------
# 5. 运行仿真
# ------------------------------------------------------------------------------
run -all
wave zoom full
echo "Simulation completed."
