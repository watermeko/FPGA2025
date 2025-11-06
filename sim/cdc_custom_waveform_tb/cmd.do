# ==============================================================================
# CDC Custom Waveform Testbench Simulation Script
# ==============================================================================

quietly set NumericStdNoWarnings 1

# 结束上一次仿真（若有）
if {[string length [info nameofexecutable]]} {
    quit -sim
}

# 清理/创建工作库
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# ------------------------------------------------------------------------------
# Compile RTL dependencies
# ------------------------------------------------------------------------------

# DDS / DAC path
vlog -sv +incdir+../../rtl ../../rtl/dds/accuml.v
vlog -sv +incdir+../../rtl ../../rtl/dds/Sin.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DDS.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DAC.sv
vlog -sv +incdir+../../rtl ../../rtl/dds/custom_waveform_handler.sv
vlog -sv +incdir+../../rtl ../../rtl/dds/dac_handler.sv

# PWM (required by CDC but not used in this test)
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm.v
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_handler.v

# Digital signal measurement (DSM) path
vlog -sv +incdir+../../rtl ../../rtl/digital_signal_measure.v
vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel_handler.sv

# SPI handler dependencies
vlog -sv +incdir+../../rtl ../../rtl/spi/simple_spi_master.v
vlog -sv +incdir+../../rtl ../../rtl/spi/spi_handler.v

# UART stack (includes VHDL sources)
vcom -2008 -work work ../../rtl/uart/uart_tx.vhd
vcom -2008 -work work ../../rtl/uart/uart_rx.vhd
vlog -sv +incdir+../../rtl ../../rtl/uart/fixed_point_divider/fixed_point_divider.vo
vlog -sv +incdir+../../rtl ../../rtl/uart/uart.v
vlog -sv +incdir+../../rtl ../../rtl/uart/uart_handler.v
vlog -sv +incdir+../../rtl ../../rtl/uart/usb_uart_config.v

# Core CDC infrastructure
vlog -sv +incdir+../../rtl ../../rtl/protocol_parser.v
vlog -sv +incdir+../../rtl ../../rtl/command_processor.v
vlog -sv +incdir+../../rtl ../../rtl/cdc.v

# Testbench
vlog -sv +incdir+../../rtl ../../tb/cdc_custom_waveform_tb.sv

# ------------------------------------------------------------------------------
# Launch simulation
# ------------------------------------------------------------------------------
puts "Starting cdc_custom_waveform_tb simulation..."
vsim -t ps -voptargs=+acc work.cdc_custom_waveform_tb

# ------------------------------------------------------------------------------
# Waveform setup
# ------------------------------------------------------------------------------
if {[catch {
    add wave -group "Clocks" /cdc_custom_waveform_tb/clk
    add wave -group "Clocks" /cdc_custom_waveform_tb/dac_clk
    add wave -group "Reset" /cdc_custom_waveform_tb/rst_n

    add wave -group "USB Stimulus" /cdc_custom_waveform_tb/usb_data_in
    add wave -group "USB Stimulus" /cdc_custom_waveform_tb/usb_data_valid_in

    add wave -group "CDC Outputs" -radix signed /cdc_custom_waveform_tb/dac_data
    add wave -group "CDC Outputs" -radix signed /cdc_custom_waveform_tb/dut/dac_data_custom
    add wave -group "CDC Outputs" -radix signed /cdc_custom_waveform_tb/dut/dac_data_dds
    add wave -group "CDC Outputs" /cdc_custom_waveform_tb/usb_upload_valid
    add wave -group "CDC Outputs" /cdc_custom_waveform_tb/usb_upload_data

    add wave -group "Custom Handler" /cdc_custom_waveform_tb/dut/u_custom_waveform_handler/handler_state
    add wave -group "Custom Handler" /cdc_custom_waveform_tb/dut/u_custom_waveform_handler/playback_active
    add wave -group "Custom Handler" /cdc_custom_waveform_tb/dut/u_custom_waveform_handler/dac_active
    add wave -group "Custom Handler" /cdc_custom_waveform_tb/dut/custom_wave_active
    add wave -group "Custom Handler" -radix unsigned /cdc_custom_waveform_tb/dut/u_custom_waveform_handler/ram_wr_addr
    add wave -group "Custom Handler" -radix unsigned /cdc_custom_waveform_tb/dut/u_custom_waveform_handler/ram_rd_addr
    add wave -group "Custom Handler" -radix unsigned /cdc_custom_waveform_tb/dut/u_custom_waveform_handler/waveform_length
    add wave -group "Custom Handler" -radix hex /cdc_custom_waveform_tb/dut/u_custom_waveform_handler/sample_rate_word

    add wave -group "DAC Handler" /cdc_custom_waveform_tb/dut/u_dac_handler/handler_state
    add wave -group "DAC Handler" /cdc_custom_waveform_tb/dut/u_dac_handler/wave_type
    add wave -group "DAC Handler" -radix hex /cdc_custom_waveform_tb/dut/u_dac_handler/frequency_word
    add wave -group "DAC Handler" -radix hex /cdc_custom_waveform_tb/dut/u_dac_handler/phase_word

    add wave -group "Command Processor" /cdc_custom_waveform_tb/dut/u_command_processor/cmd_start
    add wave -group "Command Processor" /cdc_custom_waveform_tb/dut/u_command_processor/cmd_data_valid
    add wave -group "Command Processor" /cdc_custom_waveform_tb/dut/u_command_processor/cmd_done
    add wave -group "Command Processor" /cdc_custom_waveform_tb/dut/u_command_processor/cmd_type_out
    add wave -group "Command Processor" -radix unsigned /cdc_custom_waveform_tb/dut/u_command_processor/cmd_data_index_out

} result]} {
    puts "Warning: Failed to add some wave signals: $result"
}

configure wave -timelineunits ns
configure wave -signalnamewidth 220
configure wave -valuecolwidth 120

# ------------------------------------------------------------------------------
# Run simulation to completion
# ------------------------------------------------------------------------------
run -all
