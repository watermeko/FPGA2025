# 测试编译脚本 - 逐步编译查找问题

quit -sim
vlib work
vmap work work

echo "==== Step 1: 编译 DSM 模块 ===="
vlog -sv +incdir+../../rtl ../../rtl/logic/digital_signal_measure.sv
if {[catch {vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel.sv} err]} {
    echo "错误：dsm_multichannel.sv 编译失败"
    echo $err
    quit -f
}
if {[catch {vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel_handler.sv} err]} {
    echo "错误：dsm_multichannel_handler.sv 编译失败"
    echo $err
    quit -f
}

echo "==== Step 2: 编译 SPI 模块 ===="
if {[catch {vlog -sv +incdir+../../rtl ../../rtl/spi/simple_spi_master.v} err]} {
    echo "错误：simple_spi_master.v 编译失败"
    echo $err
    quit -f
}
if {[catch {vlog -sv +incdir+../../rtl ../../rtl/spi/spi_handler.v} err]} {
    echo "错误：spi_handler.v 编译失败"
    echo $err
    quit -f
}

echo "==== Step 3: 编译 DDS/DAC 模块 ===="
vlog -sv +incdir+../../rtl ../../rtl/dds/accuml.v
vlog -sv +incdir+../../rtl ../../rtl/dds/Sin.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DDS.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DAC.sv
vlog -sv +incdir+../../rtl ../../rtl/dds/dac_handler.sv

echo "==== Step 4: 编译 PWM 模块 ===="
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm.v
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_handler.v

echo "==== Step 5: 编译 UART 模块 ===="
vcom -work work ../../rtl/uart/uart_tx.vhd
vcom -work work ../../rtl/uart/uart_rx.vhd
vlog -sv +incdir+../../rtl ../../rtl/usb/fixed_point_divider/fixed_point_divider.vo
vlog -sv +incdir+../../rtl ../../rtl/uart/uart.v
vlog -sv +incdir+../../rtl ../../rtl/uart/uart_handler.v
vlog -sv +incdir+../../rtl ../../rtl/uart/usb_uart_config.v

echo "==== Step 6: 编译协议处理模块 ===="
vlog -sv +incdir+../../rtl ../../rtl/protocol_parser.v
vlog -sv +incdir+../../rtl ../../rtl/command_processor.v

echo "==== Step 7: 编译 CDC_US 模块 ===="
if {[catch {vlog -sv +incdir+../../rtl ../../rtl/cdc_us.v} err]} {
    echo "错误：cdc_us.v 编译失败"
    echo $err
    quit -f
}

echo "==== Step 8: 编译 Testbench ===="
if {[catch {vlog -sv +incdir+../../rtl +define+USE_CDC_US ../../tb/cdc_dsm_tb.sv} err]} {
    echo "错误：cdc_dsm_tb.sv 编译失败"
    echo $err
    quit -f
}

echo ""
echo "==== 所有编译成功！===="
echo ""
echo "现在尝试优化..."

if {[catch {vopt work.cdc_dsm_tb -o cdc_dsm_tb_opt} err]} {
    echo "错误：优化失败"
    echo $err
    quit -f
}

echo ""
echo "==== 优化成功！===="
echo ""
