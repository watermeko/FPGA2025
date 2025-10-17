# ============================================================================
# ModelSim Simulation Script for custom_waveform_handler
# ============================================================================

# 创建工作库
vlib work

# 编译RTL源文件
echo "Compiling RTL files..."

# 编译自定义波形处理器
vlog -sv +incdir+../../rtl/dds ../../rtl/dds/custom_waveform_handler.sv

# 编译testbench
if {[catch {vlog -sv ../../tb/custom_waveform_tb.sv} result]} {
    echo "ERROR: Testbench compilation failed!"
    echo $result
    #quit -f
}

echo "Compilation successful!"

# 启动仿真
vsim -t ps work.custom_waveform_tb -voptargs=+acc

# 添加波形信号
echo "Adding waveforms..."

# 时钟和复位
add wave -divider "Clock & Reset"
add wave -format Logic /custom_waveform_tb/clk
add wave -format Logic /custom_waveform_tb/dac_clk
add wave -format Logic /custom_waveform_tb/rst_n

# 命令接口
add wave -divider "Command Interface"
add wave -format Hex /custom_waveform_tb/cmd_type
add wave -format Unsigned /custom_waveform_tb/cmd_length
add wave -format Hex /custom_waveform_tb/cmd_data
add wave -format Unsigned /custom_waveform_tb/cmd_data_index
add wave -format Logic /custom_waveform_tb/cmd_start
add wave -format Logic /custom_waveform_tb/cmd_data_valid
add wave -format Logic /custom_waveform_tb/cmd_done
add wave -format Logic /custom_waveform_tb/cmd_ready

# DUT内部状态
add wave -divider "Handler State"
add wave -format Hex /custom_waveform_tb/u_dut/handler_state
add wave -format Logic /custom_waveform_tb/u_dut/sample_byte_sel

# 波形参数
add wave -divider "Waveform Parameters"
add wave -format Unsigned /custom_waveform_tb/u_dut/waveform_length
add wave -format Hex /custom_waveform_tb/u_dut/sample_rate_word
add wave -format Logic /custom_waveform_tb/u_dut/loop_enable
add wave -format Logic /custom_waveform_tb/u_dut/play_enable

# RAM写入控制
add wave -divider "RAM Write Control"
add wave -format Logic /custom_waveform_tb/u_dut/ram_wr_en
add wave -format Unsigned /custom_waveform_tb/u_dut/ram_wr_addr
add wave -format Hex /custom_waveform_tb/u_dut/ram_wr_data
add wave -format Unsigned /custom_waveform_tb/u_dut/write_addr

# 播放控制
add wave -divider "Playback Control"
add wave -format Logic /custom_waveform_tb/playing
add wave -format Hex /custom_waveform_tb/u_dut/phase_acc
add wave -format Unsigned /custom_waveform_tb/u_dut/ram_rd_addr
add wave -format Hex /custom_waveform_tb/u_dut/ram_rd_data

# DAC输出
add wave -divider "DAC Output"
add wave -format Logic /custom_waveform_tb/playing
add wave -format Unsigned /custom_waveform_tb/dac_data
add wave -radix unsigned /custom_waveform_tb/dac_data

# 跨时钟域同步信号
add wave -divider "Clock Domain Crossing"
add wave -format Logic /custom_waveform_tb/u_dut/play_enable_sync1
add wave -format Logic /custom_waveform_tb/u_dut/play_enable_sync2
add wave -format Logic /custom_waveform_tb/u_dut/loop_enable_sync2
add wave -format Unsigned /custom_waveform_tb/u_dut/waveform_length_sync2

# 配置波形窗口
configure wave -namecolwidth 300
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# 运行仿真
echo "Running simulation..."
run -all

# 自动缩放波形
wave zoom full

echo "Simulation completed. Wave window is ready."
echo "Use 'run <time>' to continue simulation."
echo "Use 'wave zoom full' to fit all waveforms."
