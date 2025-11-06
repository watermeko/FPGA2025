# ==============================================================================
# CDC Sequence Generator Integration Testbench ModelSim Simulation Script
# Testing Sequence Generator with full CDC module
# ==============================================================================

# Quit any running simulation
quit -sim

# ------------------------------------------------------------------------------
# 1. Clean and Create Local Libraries
# ------------------------------------------------------------------------------
catch {vdel -lib work -all}
catch {vdel -lib gw5a -all}

vlib work
vmap work work
vlib gw5a
vmap gw5a ./gw5a

# ------------------------------------------------------------------------------
# 2. Compile Gowin Primitives
# ------------------------------------------------------------------------------
echo "Compiling Gowin primitives into local './gw5a' library..."
set GOWIN_PATH "E:/GOWIN/Gowin_V1.9.12_x64/IDE"
vlog -work gw5a "${GOWIN_PATH}/simlib/gw5a/prim_sim.v"

# ------------------------------------------------------------------------------
# 3. Compile All Design and Testbench Files
# ------------------------------------------------------------------------------
echo "Compiling all design and testbench files into './work' library..."

# --- Clock Generation Modules ---
vlog -sv +incdir+../../rtl ../../rtl/clk/gowin_pll/gowin_pll.v
vlog -sv +incdir+../../rtl ../../rtl/clk/Gowin_PLL_24/Gowin_PLL_24.v

# --- DDS Modules ---
vlog -sv +incdir+../../rtl ../../rtl/dds/accuml.v
vlog -sv +incdir+../../rtl ../../rtl/dds/Sin.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DDS.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DAC.sv
vlog -sv +incdir+../../rtl ../../rtl/dds/dac_handler.sv
vlog -sv +incdir+../../rtl ../../rtl/dds/custom_waveform_handler.sv

# --- PWM Modules ---
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm.v
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_handler.v

# --- Sequence Generator Modules (NEW) ---
vlog -sv +incdir+../../rtl ../../rtl/pwm/seq_generator.v
vlog -sv +incdir+../../rtl ../../rtl/pwm/seq_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/seq_handler.v

# --- UART Modules ---
vcom -work work ../../rtl/uart/uart_tx.vhd
vcom -work work ../../rtl/uart/uart_rx.vhd
vlog -sv +incdir+../../rtl ../../rtl/uart/fixed_point_divider/fixed_point_divider.vo
vlog -sv +incdir+../../rtl ../../rtl/uart/uart.v
vlog -sv +incdir+../../rtl ../../rtl/uart/usb_uart_config.v
vlog -sv +incdir+../../rtl ../../rtl/uart/uart_handler.v

# --- SPI Modules ---
vlog -sv +incdir+../../rtl ../../rtl/spi/simple_spi_master.v
vlog -sv +incdir+../../rtl ../../rtl/spi/simple_spi_slave.v
vlog -sv +incdir+../../rtl ../../rtl/spi/spi_handler.v
vlog -sv +incdir+../../rtl ../../rtl/spi/spi_slave_handler.v

# --- DSM (Digital Signal Measure) Modules ---
vlog -sv +incdir+../../rtl ../../rtl/logic/digital_signal_measure.sv
vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/logic/dsm_multichannel_handler.sv

# --- Digital Capture Module ---
vlog -sv +incdir+../../rtl ../../rtl/logic/digital_capture_handler.v

# --- I2C Modules ---
vlog -sv +incdir+../../rtl ../../rtl/i2c/i2c_bit_shift.v
vlog -sv +incdir+../../rtl ../../rtl/i2c/i2c_control.v
vlog -sv +incdir+../../rtl ../../rtl/i2c/i2c_handler.v

# --- 1-Wire Modules ---
vlog -sv +incdir+../../rtl ../../rtl/one_wire/one_wire_master.v
vlog -sv +incdir+../../rtl ../../rtl/one_wire/one_wire_handler.v

# --- Upload Data Pipeline Modules ---
vlog -sv +incdir+../../rtl ../../rtl/upload_adapter_0.v
vlog -sv +incdir+../../rtl ../../rtl/upload_packer_0.v
vlog -sv +incdir+../../rtl ../../rtl/upload_arbiter_0.v

# --- Core Protocol Modules ---
vlog -sv +incdir+../../rtl ../../rtl/protocol_parser.v
vlog -sv +incdir+../../rtl ../../rtl/command_processor.v

# --- Top CDC Module ---
vlog -sv +incdir+../../rtl ../../rtl/cdc.v

# --- Testbench ---
vlog -sv +incdir+../../rtl ../../tb/cdc_seq_tb.sv

# ------------------------------------------------------------------------------
# 4. Start Simulation
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim -L gw5a work.cdc_seq_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 5. Add Waveforms with Grouping
# ------------------------------------------------------------------------------
echo "Adding waveforms..."

# --- Top Level ---
add wave -group "Top Level" -divider "Clock & Reset"
add wave -group "Top Level" /cdc_seq_tb/clk
add wave -group "Top Level" /cdc_seq_tb/rst_n
add wave -group "Top Level" -divider "USB Interface"
add wave -group "Top Level" -radix hex /cdc_seq_tb/usb_data_in
add wave -group "Top Level" /cdc_seq_tb/usb_data_valid_in
add wave -group "Top Level" -divider "Sequence Outputs"
add wave -group "Top Level" -radix binary /cdc_seq_tb/seq_pins

# --- Protocol Parser ---
add wave -group "Protocol Parser" -divider "State"
add wave -group "Protocol Parser" -radix unsigned /cdc_seq_tb/dut/u_parser/state
add wave -group "Protocol Parser" -divider "Outputs"
add wave -group "Protocol Parser" /cdc_seq_tb/dut/u_parser/parse_done
add wave -group "Protocol Parser" /cdc_seq_tb/dut/u_parser/parse_error
add wave -group "Protocol Parser" -radix hex /cdc_seq_tb/dut/u_parser/cmd_out
add wave -group "Protocol Parser" -radix unsigned /cdc_seq_tb/dut/u_parser/len_out

# --- Command Processor ---
add wave -group "Command Processor" -divider "State"
add wave -group "Command Processor" -radix unsigned /cdc_seq_tb/dut/u_command_processor/state
add wave -group "Command Processor" -divider "Command Bus"
add wave -group "Command Processor" -radix hex /cdc_seq_tb/dut/cmd_type
add wave -group "Command Processor" -radix unsigned /cdc_seq_tb/dut/cmd_length
add wave -group "Command Processor" /cdc_seq_tb/dut/cmd_start
add wave -group "Command Processor" /cdc_seq_tb/dut/cmd_data_valid
add wave -group "Command Processor" -radix hex /cdc_seq_tb/dut/cmd_data
add wave -group "Command Processor" -radix unsigned /cdc_seq_tb/dut/cmd_data_index
add wave -group "Command Processor" /cdc_seq_tb/dut/cmd_done
add wave -group "Command Processor" /cdc_seq_tb/dut/cmd_ready

# --- Sequence Handler ---
add wave -group "SEQ Handler" -divider "State"
add wave -group "SEQ Handler" -radix unsigned /cdc_seq_tb/dut/u_seq_handler/handler_state
add wave -group "SEQ Handler" /cdc_seq_tb/dut/u_seq_handler/cmd_ready
add wave -group "SEQ Handler" -divider "Configuration"
add wave -group "SEQ Handler" -radix unsigned /cdc_seq_tb/dut/u_seq_handler/seq_ch_index
add wave -group "SEQ Handler" /cdc_seq_tb/dut/u_seq_handler/seq_enable
add wave -group "SEQ Handler" -radix unsigned /cdc_seq_tb/dut/u_seq_handler/seq_freq_div
add wave -group "SEQ Handler" -radix unsigned /cdc_seq_tb/dut/u_seq_handler/seq_length
add wave -group "SEQ Handler" -radix hex /cdc_seq_tb/dut/u_seq_handler/seq_data
add wave -group "SEQ Handler" /cdc_seq_tb/dut/u_seq_handler/seq_update_strobe

# --- Sequence Multi-Channel ---
add wave -group "SEQ Multi-Channel" -divider "Channel Outputs"
add wave -group "SEQ Multi-Channel" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_out_vector[0]}
add wave -group "SEQ Multi-Channel" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_out_vector[1]}
add wave -group "SEQ Multi-Channel" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_out_vector[2]}
add wave -group "SEQ Multi-Channel" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_out_vector[3]}
add wave -group "SEQ Multi-Channel" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_out_vector[4]}
add wave -group "SEQ Multi-Channel" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_out_vector[5]}
add wave -group "SEQ Multi-Channel" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_out_vector[6]}
add wave -group "SEQ Multi-Channel" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_out_vector[7]}

# --- Channel 0 Detail ---
add wave -group "SEQ CH0 Detail" -divider "Configuration"
add wave -group "SEQ CH0 Detail" -radix unsigned {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/freq_div_regs[0]}
add wave -group "SEQ CH0 Detail" -radix hex {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_data_regs[0]}
add wave -group "SEQ CH0 Detail" -radix unsigned {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_len_regs[0]}
add wave -group "SEQ CH0 Detail" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/enable_regs[0]}
add wave -group "SEQ CH0 Detail" -divider "Internal State"
add wave -group "SEQ CH0 Detail" -radix unsigned {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_instances[0]/u_seq_inst/clk_div_counter}
add wave -group "SEQ CH0 Detail" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_instances[0]/u_seq_inst/bit_clk_tick}
add wave -group "SEQ CH0 Detail" -radix unsigned {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_instances[0]/u_seq_inst/bit_index}
add wave -group "SEQ CH0 Detail" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_instances[0]/u_seq_inst/seq_out}

# --- Channel 1 Detail ---
add wave -group "SEQ CH1 Detail" -divider "Configuration"
add wave -group "SEQ CH1 Detail" -radix unsigned {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/freq_div_regs[1]}
add wave -group "SEQ CH1 Detail" -radix hex {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_data_regs[1]}
add wave -group "SEQ CH1 Detail" -radix unsigned {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_len_regs[1]}
add wave -group "SEQ CH1 Detail" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/enable_regs[1]}
add wave -group "SEQ CH1 Detail" -divider "Internal State"
add wave -group "SEQ CH1 Detail" -radix unsigned {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_instances[1]/u_seq_inst/clk_div_counter}
add wave -group "SEQ CH1 Detail" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_instances[1]/u_seq_inst/bit_clk_tick}
add wave -group "SEQ CH1 Detail" -radix unsigned {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_instances[1]/u_seq_inst/bit_index}
add wave -group "SEQ CH1 Detail" {/cdc_seq_tb/dut/u_seq_handler/u_seq_multi/seq_instances[1]/u_seq_inst/seq_out}

# --- Testbench Status ---
add wave -group "TB Status" -divider "State Tracking"
add wave -group "TB Status" -radix unsigned /cdc_seq_tb/prev_handler_state
add wave -group "TB Status" -divider "Transition Counts"
add wave -group "TB Status" -radix unsigned {/cdc_seq_tb/transition_count[0]}
add wave -group "TB Status" -radix unsigned {/cdc_seq_tb/transition_count[1]}
add wave -group "TB Status" -radix unsigned {/cdc_seq_tb/transition_count[2]}
add wave -group "TB Status" -radix unsigned {/cdc_seq_tb/transition_count[3]}
add wave -group "TB Status" -radix unsigned {/cdc_seq_tb/transition_count[4]}
add wave -group "TB Status" -radix unsigned {/cdc_seq_tb/transition_count[5]}
add wave -group "TB Status" -radix unsigned {/cdc_seq_tb/transition_count[6]}
add wave -group "TB Status" -radix unsigned {/cdc_seq_tb/transition_count[7]}

# ------------------------------------------------------------------------------
# 6. Configure Wave Window
# ------------------------------------------------------------------------------
configure wave -namecolwidth 300
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1000
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits us

# ------------------------------------------------------------------------------
# 7. Run Simulation
# ------------------------------------------------------------------------------
echo "Running simulation..."
run -all

# Zoom to fit all waveforms
wave zoom full

echo ""
echo "========================================"
echo "Simulation completed successfully!"
echo "========================================"
echo ""
echo "Key signal groups:"
echo "- Top Level: Basic I/O and sequence output signals"
echo "- Protocol Parser: Command frame parsing"
echo "- Command Processor: Command distribution"
echo "- SEQ Handler: Sequence handler state and configuration"
echo "- SEQ Multi-Channel: All 8 channel outputs"
echo "- SEQ CH0/CH1 Detail: Detailed internal state for channels 0 and 1"
echo "- TB Status: Testbench statistics and transition counts"
echo ""
echo "Verification:"
echo "- Check that SEQ Handler transitions through states correctly"
echo "- Verify seq_pins outputs match configured patterns"
echo "- Confirm bit_clk_tick frequency matches freq_div setting"
echo "- Validate bit_index cycles through sequence length"
echo ""
