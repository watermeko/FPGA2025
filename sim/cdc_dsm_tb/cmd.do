# ==============================================================================
# CDC DSM Testbench ModelSim Simulation Script
# This script compiles and simulates the CDC system with DSM functionality
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

# 1. DSM模块
vlog -sv +incdir+../../rtl ../../rtl/logic/digital_signal_measure.sv
vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel_handler.sv

# 1.1. USB上传仲裁器模块
vlog -sv +incdir+../../rtl ../../rtl/usb_upload_arbiter.sv

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

# 6. 主CDC模块
vlog -sv +incdir+../../rtl ../../rtl/cdc.v

# 7. Testbench
vlog -sv +incdir+../../rtl ../../tb/cdc_dsm_tb.sv

# ==============================================================================
# 开始仿真
# ==============================================================================
echo "Starting CDC DSM testbench simulation..."

# 启动仿真，如果需要GOWIN库支持，取消下面一行的注释
# vsim work.cdc_dsm_tb -voptargs="+acc" -t ps -L gw5a
#vsim work.cdc_dsm_tb -voptargs="+acc" -t ps
vsim -L gw5a -Lf gw5a work.cdc_dsm_tb -voptargs="+acc" -vopt 

# ==============================================================================
# 添加信号到波形窗口
# ==============================================================================
if {[catch {
    # 顶层时钟和复位信号
    add wave -group "Clock & Reset" /cdc_dsm_tb/clk
    add wave -group "Clock & Reset" /cdc_dsm_tb/rst_n
    
    # USB数据输入接口
    add wave -group "USB Input" /cdc_dsm_tb/usb_data_in
    add wave -group "USB Input" /cdc_dsm_tb/usb_data_valid_in
    
    # DSM信号输入
    add wave -group "DSM Input" -radix binary /cdc_dsm_tb/dsm_signal_in
    
    # DUT输出信号
    add wave -group "DUT Outputs" /cdc_dsm_tb/led_out
    add wave -group "DUT Outputs" /cdc_dsm_tb/usb_upload_data
    add wave -group "DUT Outputs" /cdc_dsm_tb/usb_upload_valid
    add wave -group "DUT Outputs" /cdc_dsm_tb/pwm_pins
    
    # 协议解析器信号
    add wave -group "Protocol Parser" /cdc_dsm_tb/dut/u_parser/parser_state
    add wave -group "Protocol Parser" /cdc_dsm_tb/dut/u_parser/cmd_out
    add wave -group "Protocol Parser" /cdc_dsm_tb/dut/u_parser/len_out
    add wave -group "Protocol Parser" /cdc_dsm_tb/dut/u_parser/parse_done
    add wave -group "Protocol Parser" /cdc_dsm_tb/dut/u_parser/parse_error
    
    # 命令处理器信号
    add wave -group "Command Processor" /cdc_dsm_tb/dut/u_command_processor/cmd_type_out
    add wave -group "Command Processor" /cdc_dsm_tb/dut/u_command_processor/cmd_start_out
    add wave -group "Command Processor" /cdc_dsm_tb/dut/u_command_processor/cmd_done_out
    add wave -group "Command Processor" /cdc_dsm_tb/dut/u_command_processor/cmd_data_valid_out
    add wave -group "Command Processor" /cdc_dsm_tb/dut/u_command_processor/cmd_data_out
    add wave -group "Command Processor" /cdc_dsm_tb/dut/u_command_processor/cmd_data_index_out
    
    # DSM Handler信号
    add wave -group "DSM Handler" /cdc_dsm_tb/dut/u_dsm_handler/handler_state
    add wave -group "DSM Handler" /cdc_dsm_tb/dut/u_dsm_handler/upload_state
    add wave -group "DSM Handler" -radix hex /cdc_dsm_tb/dut/u_dsm_handler/channel_mask
    add wave -group "DSM Handler" /cdc_dsm_tb/dut/u_dsm_handler/upload_channel
    add wave -group "DSM Handler" /cdc_dsm_tb/dut/u_dsm_handler/upload_byte_index
    add wave -group "DSM Handler" /cdc_dsm_tb/dut/u_dsm_handler/cmd_ready
    add wave -group "DSM Handler" /cdc_dsm_tb/dut/u_dsm_handler/all_done
    
    # DSM上传接口
    add wave -group "DSM Upload" /cdc_dsm_tb/dut/u_dsm_handler/upload_req
    add wave -group "DSM Upload" -radix hex /cdc_dsm_tb/dut/u_dsm_handler/upload_data
    add wave -group "DSM Upload" -radix hex /cdc_dsm_tb/dut/u_dsm_handler/upload_source
    add wave -group "DSM Upload" /cdc_dsm_tb/dut/u_dsm_handler/upload_valid
    add wave -group "DSM Upload" /cdc_dsm_tb/dut/u_dsm_handler/upload_ready
    
    # DSM测量控制信号
    add wave -group "DSM Measurement" -radix binary /cdc_dsm_tb/dut/u_dsm_handler/measure_start
    add wave -group "DSM Measurement" -radix binary /cdc_dsm_tb/dut/u_dsm_handler/measure_done
    
    # 通道0 DSM测量详细状态
    add wave -group "DSM Ch0 Detail" /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/state
    add wave -group "DSM Ch0 Detail" /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/measure_start
    add wave -group "DSM Ch0 Detail" /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/measure_pin
    add wave -group "DSM Ch0 Detail" /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/measure_pin_sync2
    add wave -group "DSM Ch0 Detail" /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/rising_edge
    add wave -group "DSM Ch0 Detail" /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/falling_edge
    add wave -group "DSM Ch0 Detail" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/high_counter
    add wave -group "DSM Ch0 Detail" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/low_counter
    add wave -group "DSM Ch0 Detail" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/period_counter
    add wave -group "DSM Ch0 Detail" /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/measure_done
    
    # DSM测量结果 (显示前4个通道)
    add wave -group "DSM Ch0 Results" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/high_time[15:0]
    add wave -group "DSM Ch0 Results" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/low_time[15:0]
    add wave -group "DSM Ch0 Results" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/period_time[15:0]
    add wave -group "DSM Ch0 Results" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/duty_cycle[15:0]
    
    add wave -group "DSM Ch1 Results" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/high_time[31:16]
    add wave -group "DSM Ch1 Results" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/low_time[31:16]
    add wave -group "DSM Ch1 Results" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/period_time[31:16]
    add wave -group "DSM Ch1 Results" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/duty_cycle[31:16]
    
    # DSM内部模块信号 (通道0为例)
    add wave -group "DSM Ch0 Internal" /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/state
    add wave -group "DSM Ch0 Internal" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/high_counter
    add wave -group "DSM Ch0 Internal" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/low_counter
    add wave -group "DSM Ch0 Internal" -radix decimal /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/period_counter
    add wave -group "DSM Ch0 Internal" /cdc_dsm_tb/dut/u_dsm_handler/u_dsm_multichannel/dsm_instances[0]/dsm_inst/measure_done
    
    # 测试信号生成器状态
    add wave -group "Test Signals" -radix decimal /cdc_dsm_tb/signal_gen_period[0]
    add wave -group "Test Signals" -radix decimal /cdc_dsm_tb/signal_gen_high_time[0]
    add wave -group "Test Signals" -radix decimal /cdc_dsm_tb/signal_gen_counter[0]
    
    # 测试监控信号
    add wave -group "Test Monitor" -radix decimal /cdc_dsm_tb/received_count
    add wave -group "Test Monitor" -radix decimal /cdc_dsm_tb/channels_received
    add wave -group "Test Monitor" -radix decimal /cdc_dsm_tb/test_freq_hz
    add wave -group "Test Monitor" -radix decimal /cdc_dsm_tb/test_duty_percent
    
} result]} {
    puts "Warning: Some signals could not be added to waveform: $result"
}

# ==============================================================================
# 配置波形显示
# ==============================================================================
configure wave -timelineunits ns
configure wave -signalnamewidth 300
configure wave -valuecolwidth 100
configure wave -justifyvalue left

# 设置默认数字格式
#configure wave -datasetprefix "wave"

# ==============================================================================
# 设置断点和运行仿真
# ==============================================================================
echo "Running CDC DSM testbench simulation..."

# 可选：设置断点
# when {/cdc_dsm_tb/dut/u_dsm_handler/handler_state == 3} {
#     echo "DSM measurement completed at time $now"
# }

# 运行仿真 - DSM测试需要较长时间
run -all 

# 缩放到合适的时间范围
wave zoom full

# ==============================================================================
# 显示仿真结果
# ==============================================================================
echo "Simulation completed."
echo "Check the waveform for:"
echo "  - DSM single channel test around 100us"
echo "  - DSM multi-channel test around 500us"
echo "  - DSM high frequency test around 800us" 
echo "  - DSM low frequency test around 1200us"
echo "  - DSM all channels test around 1500us"
echo "  - DSM edge cases test towards the end"

# 显示所有窗口
view *

# 自动保存波形
# write format wave -window .main_pane.wave.interior.cs.body.pw.wf dsm_wave_output.vcd

echo "CDC DSM testbench simulation script completed."