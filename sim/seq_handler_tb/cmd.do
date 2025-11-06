# ==============================================================================
# Standalone Sequence Handler Testbench - ModelSim Simulation Script
# Testing seq_handler independently (no CDC dependency)
# ==============================================================================

# Quit any running simulation
quit -sim

# ------------------------------------------------------------------------------
# 1. Clean and Create Work Library
# ------------------------------------------------------------------------------
catch {vdel -lib work -all}

vlib work
vmap work work

# ------------------------------------------------------------------------------
# 2. Compile Design and Testbench Files
# ------------------------------------------------------------------------------
echo "Compiling sequence generator modules..."

# --- Core Sequence Generator Modules ---
vlog -sv +incdir+../../rtl ../../rtl/pwm/seq_generator.v
vlog -sv +incdir+../../rtl ../../rtl/pwm/seq_multichannel.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/seq_handler.v

# --- Testbench ---
vlog -sv +incdir+../../rtl ../../tb/seq_handler_tb.v

# ------------------------------------------------------------------------------
# 3. Start Simulation
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.seq_handler_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. Add Waveforms with Grouping
# ------------------------------------------------------------------------------
echo "Adding waveforms..."

# --- Top Level ---
add wave -group "Top Level" -divider "Clock & Reset"
add wave -group "Top Level" /seq_handler_tb/clk
add wave -group "Top Level" /seq_handler_tb/rst_n

add wave -group "Top Level" -divider "Command Interface"
add wave -group "Top Level" -radix hex /seq_handler_tb/cmd_type
add wave -group "Top Level" -radix unsigned /seq_handler_tb/cmd_length
add wave -group "Top Level" /seq_handler_tb/cmd_start
add wave -group "Top Level" /seq_handler_tb/cmd_data_valid
add wave -group "Top Level" -radix hex /seq_handler_tb/cmd_data
add wave -group "Top Level" -radix unsigned /seq_handler_tb/cmd_data_index
add wave -group "Top Level" /seq_handler_tb/cmd_done
add wave -group "Top Level" /seq_handler_tb/cmd_ready

add wave -group "Top Level" -divider "Sequence Outputs"
add wave -group "Top Level" -radix binary /seq_handler_tb/seq_pins

# --- Sequence Handler ---
add wave -group "SEQ Handler" -divider "State Machine"
add wave -group "SEQ Handler" -radix unsigned /seq_handler_tb/dut/handler_state
add wave -group "SEQ Handler" /seq_handler_tb/dut/cmd_ready

add wave -group "SEQ Handler" -divider "Configuration Registers"
add wave -group "SEQ Handler" -radix unsigned /seq_handler_tb/dut/seq_ch_index
add wave -group "SEQ Handler" /seq_handler_tb/dut/seq_enable
add wave -group "SEQ Handler" -radix unsigned /seq_handler_tb/dut/seq_freq_div
add wave -group "SEQ Handler" -radix unsigned /seq_handler_tb/dut/seq_length
add wave -group "SEQ Handler" -radix hex /seq_handler_tb/dut/seq_data
add wave -group "SEQ Handler" /seq_handler_tb/dut/seq_update_strobe

# --- Multi-Channel Outputs ---
add wave -group "All 8 Channels" -divider "Individual Outputs"
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/seq_out_vector[0]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/seq_out_vector[1]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/seq_out_vector[2]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/seq_out_vector[3]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/seq_out_vector[4]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/seq_out_vector[5]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/seq_out_vector[6]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/seq_out_vector[7]}

add wave -group "All 8 Channels" -divider "Enable Flags"
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/enable_regs[0]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/enable_regs[1]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/enable_regs[2]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/enable_regs[3]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/enable_regs[4]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/enable_regs[5]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/enable_regs[6]}
add wave -group "All 8 Channels" {/seq_handler_tb/dut/u_seq_multi/enable_regs[7]}

# --- Channel 0 Detail ---
add wave -group "CH0 Detail" -divider "Configuration"
add wave -group "CH0 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/freq_div_regs[0]}
add wave -group "CH0 Detail" -radix hex {/seq_handler_tb/dut/u_seq_multi/seq_data_regs[0]}
add wave -group "CH0 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/seq_len_regs[0]}
add wave -group "CH0 Detail" {/seq_handler_tb/dut/u_seq_multi/enable_regs[0]}

add wave -group "CH0 Detail" -divider "Generator Internal State"
add wave -group "CH0 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/seq_instances[0]/u_seq_inst/clk_div_counter}
add wave -group "CH0 Detail" {/seq_handler_tb/dut/u_seq_multi/seq_instances[0]/u_seq_inst/bit_clk_tick}
add wave -group "CH0 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/seq_instances[0]/u_seq_inst/bit_index}
add wave -group "CH0 Detail" {/seq_handler_tb/dut/u_seq_multi/seq_instances[0]/u_seq_inst/seq_out}

# --- Channel 1 Detail ---
add wave -group "CH1 Detail" -divider "Configuration"
add wave -group "CH1 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/freq_div_regs[1]}
add wave -group "CH1 Detail" -radix hex {/seq_handler_tb/dut/u_seq_multi/seq_data_regs[1]}
add wave -group "CH1 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/seq_len_regs[1]}
add wave -group "CH1 Detail" {/seq_handler_tb/dut/u_seq_multi/enable_regs[1]}

add wave -group "CH1 Detail" -divider "Generator Internal State"
add wave -group "CH1 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/seq_instances[1]/u_seq_inst/clk_div_counter}
add wave -group "CH1 Detail" {/seq_handler_tb/dut/u_seq_multi/seq_instances[1]/u_seq_inst/bit_clk_tick}
add wave -group "CH1 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/seq_instances[1]/u_seq_inst/bit_index}
add wave -group "CH1 Detail" {/seq_handler_tb/dut/u_seq_multi/seq_instances[1]/u_seq_inst/seq_out}

# --- Channel 2 Detail ---
add wave -group "CH2 Detail" -divider "Configuration"
add wave -group "CH2 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/freq_div_regs[2]}
add wave -group "CH2 Detail" -radix hex {/seq_handler_tb/dut/u_seq_multi/seq_data_regs[2]}
add wave -group "CH2 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/seq_len_regs[2]}
add wave -group "CH2 Detail" {/seq_handler_tb/dut/u_seq_multi/enable_regs[2]}

add wave -group "CH2 Detail" -divider "Generator Internal State"
add wave -group "CH2 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/seq_instances[2]/u_seq_inst/clk_div_counter}
add wave -group "CH2 Detail" {/seq_handler_tb/dut/u_seq_multi/seq_instances[2]/u_seq_inst/bit_clk_tick}
add wave -group "CH2 Detail" -radix unsigned {/seq_handler_tb/dut/u_seq_multi/seq_instances[2]/u_seq_inst/bit_index}
add wave -group "CH2 Detail" {/seq_handler_tb/dut/u_seq_multi/seq_instances[2]/u_seq_inst/seq_out}

# ------------------------------------------------------------------------------
# 5. Configure Wave Window
# ------------------------------------------------------------------------------
configure wave -namecolwidth 350
configure wave -valuecolwidth 120
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
# 6. Run Simulation
# ------------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Running simulation..."
echo "========================================"
run -all

# Zoom to fit all waveforms
wave zoom full

echo ""
echo "========================================"
echo "Simulation completed successfully!"
echo "========================================"
echo ""
echo "Wave Groups:"
echo "- Top Level: Command interface and outputs"
echo "- SEQ Handler: State machine and configuration"
echo "- All 8 Channels: All channel outputs and enable flags"
echo "- CH0/CH1/CH2 Detail: Internal state for first 3 channels"
echo ""
echo "Key Signals to Check:"
echo "1. handler_state transitions: IDLE->RECEIVING->UPDATE_CONFIG->STROBE->IDLE"
echo "2. seq_update_strobe pulses when configuration is loaded"
echo "3. clk_div_counter counts to freq_div-1 then resets"
echo "4. bit_clk_tick pulses every freq_div clock cycles"
echo "5. bit_index cycles through 0 to seq_len-1"
echo "6. seq_out follows the pattern in seq_data"
echo ""
