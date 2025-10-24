# ==============================================================================
# Standalone Sequence Handler Testbench - ModelSim Simulation Script
# Testing seq_handler independently without CDC integration
# ==============================================================================

# Quit any running simulation
quit -sim

# ------------------------------------------------------------------------------
# 1. Clean and Create Local Libraries
# ------------------------------------------------------------------------------
catch {vdel -lib work -all}

vlib work
vmap work work

# ------------------------------------------------------------------------------
# 2. Compile Design and Testbench Files
# ------------------------------------------------------------------------------
echo "Compiling sequence generator modules..."

# --- Sequence Generator Modules ---
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
# 4. Add Waveforms
# ------------------------------------------------------------------------------
echo "Adding waveforms..."

# --- Top Level ---
add wave -group "Top Level" /seq_handler_tb/clk
add wave -group "Top Level" /seq_handler_tb/rst_n
add wave -group "Top Level" -divider "Command Interface"
add wave -group "Top Level" -radix hex /seq_handler_tb/cmd_type
add wave -group "Top Level" -radix unsigned /seq_handler_tb/cmd_length
add wave -group "Top Level" /seq_handler_tb/cmd_start
add wave -group "Top Level" /seq_handler_tb/cmd_data_valid
add wave -group "Top Level" -radix hex /seq_handler_tb/cmd_data
add wave -group "Top Level" /seq_handler_tb/cmd_done
add wave -group "Top Level" /seq_handler_tb/cmd_ready
add wave -group "Top Level" -divider "Sequence Outputs"
add wave -group "Top Level" -radix binary /seq_handler_tb/seq_pins

# --- Sequence Handler ---
add wave -group "SEQ Handler" -divider "State"
add wave -group "SEQ Handler" -radix unsigned /seq_handler_tb/dut/handler_state
add wave -group "SEQ Handler" -divider "Configuration"
add wave -group "SEQ Handler" -radix unsigned /seq_handler_tb/dut/seq_ch_index
add wave -group "SEQ Handler" /seq_handler_tb/dut/seq_enable
add wave -group "SEQ Handler" -radix unsigned /seq_handler_tb/dut/seq_freq_div
add wave -group "SEQ Handler" -radix unsigned /seq_handler_tb/dut/seq_length
add wave -group "SEQ Handler" -radix hex /seq_handler_tb/dut/seq_data
add wave -group "SEQ Handler" /seq_handler_tb/dut/seq_update_strobe

# --- Multi-Channel Outputs ---
add wave -group "All Channels" /seq_handler_tb/dut/u_seq_multi/seq_out_vector[0]
add wave -group "All Channels" /seq_handler_tb/dut/u_seq_multi/seq_out_vector[1]
add wave -group "All Channels" /seq_handler_tb/dut/u_seq_multi/seq_out_vector[2]
add wave -group "All Channels" /seq_handler_tb/dut/u_seq_multi/seq_out_vector[3]
add wave -group "All Channels" /seq_handler_tb/dut/u_seq_multi/seq_out_vector[4]
add wave -group "All Channels" /seq_handler_tb/dut/u_seq_multi/seq_out_vector[5]
add wave -group "All Channels" /seq_handler_tb/dut/u_seq_multi/seq_out_vector[6]
add wave -group "All Channels" /seq_handler_tb/dut/u_seq_multi/seq_out_vector[7]

# --- Channel 0 Detail ---
add wave -group "CH0 Detail" -divider "Config"
add wave -group "CH0 Detail" -radix unsigned /seq_handler_tb/dut/u_seq_multi/freq_div_regs[0]
add wave -group "CH0 Detail" -radix hex /seq_handler_tb/dut/u_seq_multi/seq_data_regs[0]
add wave -group "CH0 Detail" -radix unsigned /seq_handler_tb/dut/u_seq_multi/seq_len_regs[0]
add wave -group "CH0 Detail" /seq_handler_tb/dut/u_seq_multi/enable_regs[0]
add wave -group "CH0 Detail" -divider "Internal"
add wave -group "CH0 Detail" -radix unsigned /seq_handler_tb/dut/u_seq_multi/seq_instances[0]/u_seq_inst/clk_div_counter
add wave -group "CH0 Detail" /seq_handler_tb/dut/u_seq_multi/seq_instances[0]/u_seq_inst/bit_clk_tick
add wave -group "CH0 Detail" -radix unsigned /seq_handler_tb/dut/u_seq_multi/seq_instances[0]/u_seq_inst/bit_index
add wave -group "CH0 Detail" /seq_handler_tb/dut/u_seq_multi/seq_instances[0]/u_seq_inst/seq_out

# --- Channel 1 Detail ---
add wave -group "CH1 Detail" -divider "Config"
add wave -group "CH1 Detail" -radix unsigned /seq_handler_tb/dut/u_seq_multi/freq_div_regs[1]
add wave -group "CH1 Detail" -radix hex /seq_handler_tb/dut/u_seq_multi/seq_data_regs[1]
add wave -group "CH1 Detail" -radix unsigned /seq_handler_tb/dut/u_seq_multi/seq_len_regs[1]
add wave -group "CH1 Detail" /seq_handler_tb/dut/u_seq_multi/enable_regs[1]
add wave -group "CH1 Detail" -divider "Internal"
add wave -group "CH1 Detail" -radix unsigned /seq_handler_tb/dut/u_seq_multi/seq_instances[1]/u_seq_inst/clk_div_counter
add wave -group "CH1 Detail" /seq_handler_tb/dut/u_seq_multi/seq_instances[1]/u_seq_inst/bit_clk_tick
add wave -group "CH1 Detail" -radix unsigned /seq_handler_tb/dut/u_seq_multi/seq_instances[1]/u_seq_inst/bit_index
add wave -group "CH1 Detail" /seq_handler_tb/dut/u_seq_multi/seq_instances[1]/u_seq_inst/seq_out

# ------------------------------------------------------------------------------
# 5. Configure Wave Window
# ------------------------------------------------------------------------------
configure wave -namecolwidth 300
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -timelineunits us

# ------------------------------------------------------------------------------
# 6. Run Simulation
# ------------------------------------------------------------------------------
echo "Running simulation..."
run -all

# Zoom to fit
wave zoom full

echo ""
echo "========================================"
echo "Simulation completed!"
echo "========================================"
