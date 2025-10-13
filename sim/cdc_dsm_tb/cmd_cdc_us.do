# ==============================================================================
# CDC_US (Ultimate with DSM) Testbench ModelSim Simulation Script
# This script compiles and simulates the CDC_US system with isolated DSM testing
# ==============================================================================

# 退出上次仿真
quit -sim

# 清理并重新创建工作库（强制删除旧库）
#vdel -lib work -all
vlib work
vmap work work

# ==============================================================================
# 映射 GOWIN 仿真库
# ==============================================================================
echo "正在映射 GOWIN 仿真库..."

# 首先尝试使用本地编译的 gw5a 库
if {[file exists "./gw5a/_info"]} {
    vmap gw5a ./gw5a
    echo "✓ 使用本地 gw5a 仿真库 (./gw5a)"
} elseif {[file exists "E:/GOWIN/Gowin_V1.9.9_x64/IDE/simlib/gw5a/_info"]} {
    vmap gw5a "E:/GOWIN/Gowin_V1.9.9_x64/IDE/simlib/gw5a"
    echo "✓ 使用系统 gw5a 仿真库"
} else {
    echo "✗ 警告: 未找到已编译的 gw5a 库!"
    echo "  请先运行: do compile_gowin_lib.do"
    echo "  或者在 GOWIN IDE 中编译仿真库"
    echo ""
    echo "继续尝试编译（可能会失败）..."
}

# ==============================================================================
# 编译源文件 (按依赖顺序)
# ==============================================================================

# 1. DSM模块
vlog -sv +incdir+../../rtl ../../rtl/logic/digital_signal_measure.sv
vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel_handler.sv

# 2. SPI模块
vlog -sv +incdir+../../rtl ../../rtl/spi/simple_spi_master.v
vlog -sv +incdir+../../rtl ../../rtl/spi/spi_handler.v

# 3. DDS和DAC模块
vlog -sv +incdir+../../rtl ../../rtl/dds/accuml.v
vlog -sv +incdir+../../rtl ../../rtl/dds/Sin.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DDS.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DAC.sv
vlog -sv +incdir+../../rtl ../../rtl/dds/dac_handler.sv

# 4. PWM模块
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm.v
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_handler.v

# 5. UART模块 (包含VHDL文件)
vcom -work work ../../rtl/uart/uart_tx.vhd
vcom -work work ../../rtl/uart/uart_rx.vhd
# 恢复编译 fixed_point_divider.vo (现在有 GOWIN 库支持)
vlog -sv +incdir+../../rtl ../../rtl/uart/fixed_point_divider/fixed_point_divider.vo
vlog -sv +incdir+../../rtl ../../rtl/uart/uart.v
vlog -sv +incdir+../../rtl ../../rtl/uart/uart_handler.v
vlog -sv +incdir+../../rtl ../../rtl/uart/usb_uart_config.v

# 6. 协议处理模块
vlog -sv +incdir+../../rtl ../../rtl/protocol_parser.v
vlog -sv +incdir+../../rtl ../../rtl/command_processor.v

# 7. 主CDC模块 (编译两个版本以支持条件编译)
#vlog -sv +incdir+../../rtl ../../rtl/cdc.v
vlog -sv +incdir+../../rtl ../../rtl/cdc_us.v

# 8. Testbench (使用cdc_dsm_tb但DUT改为cdc_us)
vlog -sv +incdir+../../rtl +define+USE_CDC_US ../../tb/cdc_dsm_tb.sv

# ==============================================================================
# 开始仿真
# ==============================================================================
echo "Starting CDC_US (Ultimate with DSM) testbench simulation..."

# 启动仿真 - 使用 gw5a 库
vsim -L gw5a work.cdc_dsm_tb -voptargs="+acc"

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

    # CDC_US内部ready信号
    add wave -group "CDC_US Ready" /cdc_dsm_tb/dut/cmd_ready
    add wave -group "CDC_US Ready" /cdc_dsm_tb/dut/dsm_ready
    add wave -group "CDC_US Ready" /cdc_dsm_tb/dut/spi_ready
    add wave -group "CDC_US Ready" /cdc_dsm_tb/dut/ext_uart_ready

    # CDC_US上传仲裁信号
    add wave -group "Upload Arbitration" /cdc_dsm_tb/dut/merged_upload_req
    add wave -group "Upload Arbitration" /cdc_dsm_tb/dut/merged_upload_valid
    add wave -group "Upload Arbitration" -radix hex /cdc_dsm_tb/dut/merged_upload_data
    add wave -group "Upload Arbitration" -radix hex /cdc_dsm_tb/dut/merged_upload_source
    add wave -group "Upload Arbitration" /cdc_dsm_tb/dut/processor_upload_ready

    # DSM上传隔离状态
    add wave -group "DSM Upload Isolated" /cdc_dsm_tb/dut/dsm_upload_req
    add wave -group "DSM Upload Isolated" /cdc_dsm_tb/dut/dsm_upload_valid
    add wave -group "DSM Upload Isolated" -radix hex /cdc_dsm_tb/dut/dsm_upload_data
    add wave -group "DSM Upload Isolated" -radix hex /cdc_dsm_tb/dut/dsm_upload_source
    add wave -group "DSM Upload Isolated" /cdc_dsm_tb/dut/dsm_upload_ready

    # UART和SPI上传(应该被隔离为0)
    add wave -group "UART Upload (Isolated)" /cdc_dsm_tb/dut/uart_upload_ready
    add wave -group "UART Upload (Isolated)" /cdc_dsm_tb/dut/uart_upload_valid
    add wave -group "SPI Upload (Isolated)" /cdc_dsm_tb/dut/spi_upload_ready
    add wave -group "SPI Upload (Isolated)" /cdc_dsm_tb/dut/spi_upload_valid

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

    # 测试信号生成器状态
    add wave -group "Test Signals" -radix decimal /cdc_dsm_tb/dsm_signal_in

    # 测试监控信号
    add wave -group "Test Monitor" -radix decimal /cdc_dsm_tb/usb_received_count
    add wave -group "Test Monitor" -radix decimal /cdc_dsm_tb/usb_valid_pulse_count

} result]} {
    puts "Warning: Some signals could not be added to waveform: $result"
}

# ==============================================================================
# 配置波形显示
# ==============================================================================
configure wave -timelineunits ns
configure wave -signalnamewidth 350
configure wave -valuecolwidth 120
configure wave -justifyvalue left

# ==============================================================================
# 运行仿真
# ==============================================================================
echo "Running CDC_US (Ultimate with isolated DSM) testbench simulation..."

# 运行仿真 - DSM测试需要较长时间
run -all

# 缩放到合适的时间范围
wave zoom full

# ==============================================================================
# 显示仿真结果
# ==============================================================================
echo "Simulation completed."
echo "Check the waveform for:"
echo "  - cmd_ready should be dsm_ready only"
echo "  - merged_upload_* should connect to DSM only"
echo "  - uart_upload_ready and spi_upload_ready should be 0"
echo "  - DSM measurement and upload functionality"

# 显示所有窗口
view *

echo "CDC_US testbench simulation script completed."
