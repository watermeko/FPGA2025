# ==============================================================================
# Upload Packer Simple Testbench ModelSim Simulation Script
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
echo "Compiling upload_packer_simple module and testbench..."
vlog -sv ../../rtl/upload_packer_simple.v
vlog -sv ../../tb/upload_packer_simple_tb.v

# ------------------------------------------------------------------------------
# 3. 启动仿真
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.upload_packer_simple_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. 添加波形
# ------------------------------------------------------------------------------

# --- Clock and Reset ---
add wave -group "Clock & Reset" /upload_packer_simple_tb/clk
add wave -group "Clock & Reset" /upload_packer_simple_tb/rst_n

# --- Input Signals ---
add wave -group "Input" /upload_packer_simple_tb/raw_upload_req
add wave -group "Input" -radix hex /upload_packer_simple_tb/raw_upload_data
add wave -group "Input" -radix hex /upload_packer_simple_tb/raw_upload_source
add wave -group "Input" /upload_packer_simple_tb/raw_upload_valid
add wave -group "Input" /upload_packer_simple_tb/raw_upload_ready

# --- Output Signals ---
add wave -group "Output" /upload_packer_simple_tb/packed_upload_req
add wave -group "Output" -radix hex /upload_packer_simple_tb/packed_upload_data
add wave -group "Output" -radix hex /upload_packer_simple_tb/packed_upload_source
add wave -group "Output" /upload_packer_simple_tb/packed_upload_valid
add wave -group "Output" /upload_packer_simple_tb/packed_upload_ready

# --- Packer Internal Signals ---
add wave -group "Packer Internal" -radix unsigned /upload_packer_simple_tb/u_packer/state
add wave -group "Packer Internal" -radix unsigned /upload_packer_simple_tb/u_packer/data_count
add wave -group "Packer Internal" -radix unsigned /upload_packer_simple_tb/u_packer/data_index
add wave -group "Packer Internal" -radix hex /upload_packer_simple_tb/u_packer/checksum
add wave -group "Packer Internal" -radix hex /upload_packer_simple_tb/u_packer/current_source

# --- Test Statistics ---
add wave -group "Statistics" -radix unsigned /upload_packer_simple_tb/bytes_received

# ------------------------------------------------------------------------------
# 5. 运行仿真
# ------------------------------------------------------------------------------
run -all
wave zoom full
echo "Simulation completed."
