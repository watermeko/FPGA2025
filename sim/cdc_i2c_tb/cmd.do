# ==============================================================================
# I2C Testbench ModelSim Simulation Script
# This script compiles and simulates the I2C Controller Testbench (i2c_tb.sv)
# ==============================================================================
# 退出上次仿真
quit -sim

# 清理并重新创建工作库
# vdel -lib work -all
vlib work
vmap work work

# ==============================================================================
# 编译源文件 (按依赖顺序)
# 假设所有文件 (v, sv) 都在当前目录下
# ==============================================================================

1. 编译 SystemVerilog 实用工具 (包含时钟/复位生成和 USB 协议任务)
vlog -sv +incdir+../../rtl ../../tb/utils.sv

vlog -sv +incdir+../../rtl ../../rtl/i2c/Gowin_i2c/i2c_master.vo

vlog -sv +incdir+../../rtl ../../rtl/i2c/i2c_handler.v
vlog -sv +incdir+../../rtl ../../rtl/i2c/master_i2c_sram.v

# 外部模块
vlog -sv +incdir+../../rtl ../../rtl/dds/accuml.v
vlog -sv +incdir+../../rtl ../../rtl/dds/Sin.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DDS.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DAC.sv
vlog -sv +incdir+../../rtl ../../rtl/dds/dac_handler.sv

vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm.v
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_handler.v

vcom -work work ../../rtl/uart/uart_tx.vhd
vcom -work work ../../rtl/uart/uart_rx.vhd
vlog -sv +incdir+../../rtl ../../rtl/usb/fixed_point_divider/fixed_point_divider.vo
#    vlog -sv +incdir+../../rtl ../../rtl/usb/tb/prim_sim.v
#    vlog -sv +incdir+../../rtl ../../rtl/usb/tb/Fixed_Point_Divider_tb.v
# vlog -sv +incdir+../../rtl ../../rtl/usb/usb_device_control/usb_device_control.vo

vlog -sv +incdir+../../rtl ../../rtl/uart/uart.v
vlog -sv +incdir+../../rtl ../../rtl/uart/uart_handler.v
vlog -sv +incdir+../../rtl ../../rtl/uart/usb_uart_config.v


vlog -sv +incdir+../../rtl ../../rtl/protocol_parser.v
vlog -sv +incdir+../../rtl ../../rtl/command_processor.v


vlog -sv +incdir+../../rtl ../../rtl/cdc.v

vlog -sv +incdir+../../rtl ../../tb/i2c_tb.sv

# ==============================================================================
# 启动仿真
# ==============================================================================
echo "Starting simulation for top module: i2c_tb"
vsim -L gw5a -Lf gw5a work.i2c_tb -voptargs="+acc" -vopt 

# ==============================================================================
# 添加波形信号
# ==============================================================================
# 移除旧的波形
if [catch {onerror {resume} {wave forget *}} result] {
puts "Warning: Could not clear previous wave configuration: $result"
}

#------------------------------------------------------------------------------
#顶层 I2C 总线和时钟
#------------------------------------------------------------------------------
add wave -group {Top Level} /i2c_tb/clk
add wave -group {Top Level} /i2c_tb/rst_n
add wave -group {Top Level} /i2c_tb/SCL
add wave -group {Top Level} /i2c_tb/SDA

# ------------------------------------------------------------------------------
# CDC/USB 命令输入接口
# ------------------------------------------------------------------------------
add wave -group {USB Command Input} /i2c_tb/tb_usb_data
add wave -group {USB Command Input} /i2c_tb/tb_usb_valid

# ------------------------------------------------------------------------------
# I2C 控制器 FSM 信号 (DUT 内部)
# ------------------------------------------------------------------------------
# 假设层次结构: i2c_tb -> u_cdc -> u_i2c_handler (在 i2c.v 中被实例化) -> u_master_i2c_sram
# 注意: 具体的信号路径可能根据您的文件内容有所不同，这里以 master_i2c_sram 为例
if [catch {
# CDC 命令接口信号
add wave -group {CDC Interface} /i2c_tb/u_cdc/cmd_type
add wave -group {CDC Interface} /i2c_tb/u_cdc/cmd_start
add wave -group {CDC Interface} /i2c_tb/u_cdc/cmd_ready

# 尝试添加 master_i2c_sram 的状态机 (如果层次结构正确)
add wave -group {I2C FSM Core} /i2c_tb/u_cdc/u_i2c_handler/u_master_i2c_sram/state
add wave -group {I2C FSM Core} /i2c_tb/u_cdc/u_i2c_handler/u_master_i2c_sram/op_len
add wave -group {I2C FSM Core} /i2c_tb/u_cdc/u_i2c_handler/u_master_i2c_sram/data_ptr

} result] {
puts "Warning: Some internal signals could not be added to waveform. Check hierarchy: $result"
}

# ------------------------------------------------------------------------------
# 配置波形显示
# ------------------------------------------------------------------------------
configure wave -timelineunits ns
configure wave -signalnamewidth 250
configure wave -valuecolwidth 120
configure wave -justifyvalue left

# 设置默认数字格式
#configure wave -datasetprefix "wave"

# ==============================================================================
# 设置断点和运行仿真
# ==============================================================================
echo "Running I2C testbench simulation..."
# 运行仿真 - 增加仿真时间以覆盖所有测试用例
run 20us

# 缩放到合适的时间范围
wave zoom full

# ==============================================================================
# 显示仿真结果
# ==============================================================================
echo "Simulation completed."

# 显示所有窗口
view *

echo "CDC testbench simulation script completed."