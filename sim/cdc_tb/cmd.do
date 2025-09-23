# ==============================================================================
# CDC Testbench ModelSim Simulation Script
# This script compiles and simulates the complete CDC communication system
# ==============================================================================

# 退出上次仿真
quit -sim

# 清理并重新创建工作库
# vdel -lib work -all
vlib work
vmap work work

# 添加GOWIN仿真库支持 (如果需要)
# vmap gw5a "$env(GOWIN_HOME)/simlib/gw5a"

# ==============================================================================
# 编译源文件 (按依赖顺序)
# ==============================================================================

# 2. DDS和DAC模块
vlog -sv +incdir+../../rtl ../../rtl/dds/accuml.v
vlog -sv +incdir+../../rtl ../../rtl/dds/Sin.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DDS.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DAC.sv
vlog -sv +incdir+../../rtl ../../rtl/dds/dac_handler.sv

# 3. PWM模块
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm.v
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_handler.v

# 4. UART模块 (包含VHDL文件)
vcom -work work ../../rtl/uart/uart_tx.vhd
vcom -work work ../../rtl/uart/uart_rx.vhd
vlog -sv +incdir+../../rtl ../../rtl/usb/fixed_point_divider/fixed_point_divider.vo
vlog -sv +incdir+../../rtl ../../rtl/uart/uart.v
vlog -sv +incdir+../../rtl ../../rtl/uart/uart_handler.v
vlog -sv +incdir+../../rtl ../../rtl/uart/usb_uart_config.v

# 5. 协议处理模块
vlog -sv +incdir+../../rtl ../../rtl/protocol_parser.v
vlog -sv +incdir+../../rtl ../../rtl/command_processor.v


# 7. 主CDC模块
vlog -sv +incdir+../../rtl ../../rtl/cdc.v

# 8. Testbench
vlog -sv +incdir+../../rtl ../../tb/cdc_tb.sv

# ==============================================================================
# 开始仿真
# ==============================================================================
echo "Starting CDC testbench simulation..."

# 启动仿真，如果需要GOWIN库支持，取消下面一行的注释
# vsim work.cdc_tb -voptargs="+acc" -t ps -L gw5a
#vsim work.cdc_tb -voptargs="+acc" -t ps
vsim -L gw5a -Lf gw5a work.cdc_tb -voptargs="+acc" -vopt 

# ==============================================================================
# 添加信号到波形窗口
# ==============================================================================
if {[catch {
    # 顶层时钟和复位信号
    add wave -group "Clock & Reset" /cdc_tb/clk
    add wave -group "Clock & Reset" /cdc_tb/rst_n
    
    # USB数据输入接口
    add wave -group "USB Input" /cdc_tb/usb_data_in
    add wave -group "USB Input" /cdc_tb/usb_data_valid_in
    
    # DUT输出信号
    add wave -group "DUT Outputs" /cdc_tb/led_out
    add wave -group "DUT Outputs" /cdc_tb/pwm_pins
    add wave -group "DUT Outputs" /cdc_tb/ext_uart_tx
    add wave -group "DUT Outputs" /cdc_tb/ext_uart_rx
    
    # USB上传接口
    add wave -group "USB Upload" /cdc_tb/usb_upload_data
    add wave -group "USB Upload" /cdc_tb/usb_upload_valid
    
    # DAC输出信号
    add wave -group "DAC Output" /cdc_tb/dac_data
    add wave -group "DAC Output" -radix decimal /cdc_tb/dac_data
    
    # DAC内部调试信号
    add wave -group "DAC Debug" /cdc_tb/dac_cmd_ready
    add wave -group "DAC Debug" /cdc_tb/dac_wave_type
    add wave -group "DAC Debug" -radix hex /cdc_tb/dac_freq_word
    add wave -group "DAC Debug" -radix hex /cdc_tb/dac_phase_word
    add wave -group "DAC Debug" /cdc_tb/dac_handler_state
    
    # 协议解析器信号
    add wave -group "Protocol Parser" /cdc_tb/dut/u_parser/parser_state
    add wave -group "Protocol Parser" /cdc_tb/dut/u_parser/cmd_out
    add wave -group "Protocol Parser" /cdc_tb/dut/u_parser/len_out
    add wave -group "Protocol Parser" /cdc_tb/dut/u_parser/parser_done
    add wave -group "Protocol Parser" /cdc_tb/dut/u_parser/parser_error
    
    # 命令处理器信号
    add wave -group "Command Processor" /cdc_tb/dut/u_cmd_processor/cmd_start
    add wave -group "Command Processor" /cdc_tb/dut/u_cmd_processor/cmd_done
    add wave -group "Command Processor" /cdc_tb/dut/u_cmd_processor/cmd_data_valid
    add wave -group "Command Processor" /cdc_tb/dut/u_cmd_processor/cmd_data_index
    add wave -group "Command Processor" /cdc_tb/dut/u_cmd_processor/cmd_data
    
    # DAC handler内部信号
    add wave -group "DAC Handler" /cdc_tb/dut/u_dac_handler/handler_state
    add wave -group "DAC Handler" /cdc_tb/dut/u_dac_handler/wave_type
    add wave -group "DAC Handler" -radix hex /cdc_tb/dut/u_dac_handler/frequency_word
    add wave -group "DAC Handler" -radix hex /cdc_tb/dut/u_dac_handler/phase_word
    
    # DDS内部信号
    add wave -group "DDS Internal" /cdc_tb/dut/u_dac_handler/u_DAC/u_DDS/Q
    add wave -group "DDS Internal" /cdc_tb/dut/u_dac_handler/u_DAC/u_DDS/phase
    add wave -group "DDS Internal" /cdc_tb/dut/u_dac_handler/u_DAC/u_DDS/addr
    add wave -group "DDS Internal" /cdc_tb/dut/u_dac_handler/u_DAC/wave_sin
    add wave -group "DDS Internal" /cdc_tb/dut/u_dac_handler/u_DAC/wave_tri
    add wave -group "DDS Internal" /cdc_tb/dut/u_dac_handler/u_DAC/wave_saw
    add wave -group "DDS Internal" /cdc_tb/dut/u_dac_handler/u_DAC/wave_sqr
    
    # PWM调试信号
    add wave -group "PWM Debug" /cdc_tb/dut/u_pwm_handler/handler_state
    add wave -group "PWM Debug" /cdc_tb/dut/u_pwm_handler/pwm_ch_index
    add wave -group "PWM Debug" /cdc_tb/dut/u_pwm_handler/pwm_period
    add wave -group "PWM Debug" /cdc_tb/dut/u_pwm_handler/pwm_duty
    
    # UART调试信号
    add wave -group "UART Debug" /cdc_tb/dut/u_uart_handler/handler_state
    add wave -group "UART Debug" /cdc_tb/dut/u_uart_handler/u_uart_rx/rx_data
    add wave -group "UART Debug" /cdc_tb/dut/u_uart_handler/u_uart_rx/rx_data_valid
    add wave -group "UART Debug" /cdc_tb/dut/u_uart_handler/u_uart_tx/tx_data
    add wave -group "UART Debug" /cdc_tb/dut/u_uart_handler/u_uart_tx/tx_data_valid
    
    # 测试监控信号
    add wave -group "Test Monitor" /cdc_tb/dac_data_prev
    add wave -group "Test Monitor" /cdc_tb/dac_transitions
    add wave -group "Test Monitor" /cdc_tb/dac_cycle_count
    add wave -group "Test Monitor" /cdc_tb/usb_received_count
    
} result]} {
    puts "Warning: Some signals could not be added to waveform: $result"
}

# ==============================================================================
# 配置波形显示
# ==============================================================================
configure wave -timelineunits ns
configure wave -signalnamewidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left

# 设置默认数字格式
#configure wave -datasetprefix "wave"

# ==============================================================================
# 设置断点和运行仿真
# ==============================================================================
echo "Running CDC testbench simulation..."

# 可选：设置断点
# when {/cdc_tb/dac_cmd_ready == 1} {
#     echo "DAC command ready at time $now"
# }

# 运行仿真 - 增加仿真时间以覆盖所有测试用例
run 200us

# 缩放到合适的时间范围
wave zoom full

# ==============================================================================
# 显示仿真结果
# ==============================================================================
echo "Simulation completed."
echo "Check the waveform for:"
echo "  - Heartbeat test around 1us"
echo "  - PWM test around 2us"
echo "  - UART config test around 5us" 
echo "  - DAC tests from 10us onwards"
echo "  - UART TX/RX tests towards the end"

# 显示所有窗口
view *

# 自动保存波形
# write format wave -window .main_pane.wave.interior.cs.body.pw.wf wave_output.vcd

echo "CDC testbench simulation script completed."