# ============================================================================
# ModelSim仿真脚本 - upload_controller测试 (绝对路径版本)
# 使用方法:
#   cd F:\FPGA2025\sim\upload_controller_tb
#   modelsim -do upload_controller_sim.do
# ============================================================================

# 删除旧的工作库
if {[file exists work]} {
    vdel -all -lib work
}

# 创建工作库
vlib work

# 编译源文件（使用SystemVerilog编译器）
vlog -sv -work work F:/FPGA2025/rtl/upload_controller.v
vlog -sv -work work F:/FPGA2025/tb/upload_controller_tb.v

# 启动仿真
vsim -voptargs=+acc work.upload_controller_tb

# 添加波形
add wave -divider "时钟与复位"
add wave -format Logic /upload_controller_tb/clk
add wave -format Logic /upload_controller_tb/rst_n

add wave -divider "输入信号 - 5个数据源"
add wave -format Binary -radix binary /upload_controller_tb/src_upload_req
add wave -format Hex -radix hex /upload_controller_tb/src_upload_data
add wave -format Hex -radix hex /upload_controller_tb/src_upload_source
add wave -format Binary -radix binary /upload_controller_tb/src_upload_valid
add wave -format Binary -radix binary /upload_controller_tb/src_upload_ready

add wave -divider "输出信号 - 合并后数据流"
add wave -format Logic /upload_controller_tb/merged_upload_req
add wave -format Hex -radix hex /upload_controller_tb/merged_upload_data
add wave -format Hex -radix hex /upload_controller_tb/merged_upload_source
add wave -format Logic /upload_controller_tb/merged_upload_valid
add wave -format Logic /upload_controller_tb/processor_upload_ready

add wave -divider "DUT内部状态"
add wave -format Literal /upload_controller_tb/u_dut/state
add wave -format Decimal -radix unsigned /upload_controller_tb/u_dut/current_source
add wave -format Hex -radix hex /upload_controller_tb/u_dut/current_source_id
add wave -format Decimal -radix unsigned /upload_controller_tb/u_dut/data_count
add wave -format Decimal -radix unsigned /upload_controller_tb/u_dut/data_index
add wave -format Hex -radix hex /upload_controller_tb/u_dut/checksum
add wave -format Logic /upload_controller_tb/u_dut/in_packet

add wave -divider "测试辅助信号"
add wave -format Decimal -radix unsigned /upload_controller_tb/received_count

# 运行仿真
run -all

# 缩放波形以适应窗口
wave zoom full
