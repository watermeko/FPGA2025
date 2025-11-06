# ==============================================================================
# Digital Capture Handler ModelSim Simulation Script
# Testing digital capture functionality in standalone handler module
# Based on cdc_dsm_simple_tb reference style
# ==============================================================================

# Quit any running simulation
quit -sim

# ------------------------------------------------------------------------------
# 1. Clean and Create Work Library
# ------------------------------------------------------------------------------
if {[file isdirectory work]} {
  vdel -lib work -all
}

vlib work
vmap work work

# ------------------------------------------------------------------------------
# 2. Compile Design and Testbench Files
# ------------------------------------------------------------------------------
echo "Compiling design and testbench files..."

# Compile RTL source
vlog ../../rtl/logic/digital_capture_handler.v

# Compile testbench with SystemVerilog support
vlog -sv ../../tb/digital_capture_handler_tb.v

# ------------------------------------------------------------------------------
# 3. Start Simulation
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.digital_capture_handler_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. Add Waveforms with Grouping
# ------------------------------------------------------------------------------
echo "Adding waveforms..."

# --- Top Level Signals ---
add wave -group "Top Level" -divider "Clock & Reset"
add wave -group "Top Level" /digital_capture_handler_tb/clk
add wave -group "Top Level" /digital_capture_handler_tb/rst_n
add wave -group "Top Level" -divider "Digital Inputs"
add wave -group "Top Level" -radix binary /digital_capture_handler_tb/dc_signal_in

# --- Command Interface ---
add wave -group "Command Interface" -divider "Command Signals"
add wave -group "Command Interface" -radix hex /digital_capture_handler_tb/cmd_type
add wave -group "Command Interface" -radix unsigned /digital_capture_handler_tb/cmd_length
add wave -group "Command Interface" -radix hex /digital_capture_handler_tb/cmd_data
add wave -group "Command Interface" -radix unsigned /digital_capture_handler_tb/cmd_data_index
add wave -group "Command Interface" /digital_capture_handler_tb/cmd_start
add wave -group "Command Interface" /digital_capture_handler_tb/cmd_data_valid
add wave -group "Command Interface" /digital_capture_handler_tb/cmd_done
add wave -group "Command Interface" /digital_capture_handler_tb/cmd_ready

# --- Handler State Machine ---
add wave -group "Handler FSM" -divider "Main State"
add wave -group "Handler FSM" -radix unsigned /digital_capture_handler_tb/u_dut/handler_state
add wave -group "Handler FSM" -radix unsigned /digital_capture_handler_tb/u_dut/upload_state
add wave -group "Handler FSM" -divider "Control Signals"
add wave -group "Handler FSM" -radix unsigned /digital_capture_handler_tb/u_dut/sample_divider
add wave -group "Handler FSM" -radix unsigned /digital_capture_handler_tb/u_dut/sample_counter
add wave -group "Handler FSM" /digital_capture_handler_tb/u_dut/sample_tick
add wave -group "Handler FSM" /digital_capture_handler_tb/u_dut/capture_enable
add wave -group "Handler FSM" /digital_capture_handler_tb/u_dut/new_sample_flag

# --- Capture Data ---
add wave -group "Capture Data" -divider "Captured Samples"
add wave -group "Capture Data" -radix binary /digital_capture_handler_tb/u_dut/captured_data
add wave -group "Capture Data" -radix binary /digital_capture_handler_tb/u_dut/captured_data_sync
add wave -group "Capture Data" -divider "Command Data Buffer"
add wave -group "Capture Data" -radix hex /digital_capture_handler_tb/u_dut/cmd_data_buf\[0\]
add wave -group "Capture Data" -radix hex /digital_capture_handler_tb/u_dut/cmd_data_buf\[1\]

# --- Upload Interface ---
add wave -group "Upload Interface" -divider "Upload Signals"
add wave -group "Upload Interface" /digital_capture_handler_tb/upload_active
add wave -group "Upload Interface" /digital_capture_handler_tb/upload_req
add wave -group "Upload Interface" -radix hex /digital_capture_handler_tb/upload_data
add wave -group "Upload Interface" -radix hex /digital_capture_handler_tb/upload_source
add wave -group "Upload Interface" /digital_capture_handler_tb/upload_valid
add wave -group "Upload Interface" /digital_capture_handler_tb/upload_ready

# --- Testbench Statistics ---
add wave -group "TB Statistics" -divider "Sample Counter"
add wave -group "TB Statistics" -radix unsigned /digital_capture_handler_tb/sample_count
add wave -group "TB Statistics" -divider "State Tracking"
add wave -group "TB Statistics" -radix unsigned /digital_capture_handler_tb/prev_handler_state
add wave -group "TB Statistics" -radix unsigned /digital_capture_handler_tb/prev_upload_state

# ------------------------------------------------------------------------------
# 5. Configure Wave Window
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
# 6. Run Simulation
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
echo "- Top Level: Basic I/O and digital input signals"
echo "- Command Interface: Command protocol signals"
echo "- Handler FSM: Main and upload state machines"
echo "- Capture Data: Captured samples and buffers"
echo "- Upload Interface: Data upload flow"
echo "- TB Statistics: Testbench counters and tracking"
echo ""
echo "Use Wave window groups to navigate signals efficiently"
echo ""
