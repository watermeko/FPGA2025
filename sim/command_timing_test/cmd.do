# ============================================================================
# ModelSim simulation script for command_processor timing test
# Tests zero-length command timing behavior
# ============================================================================

# Create work library
vlib work
vmap work work

# Compile source files
vlog -work work ../../rtl/protocol_parser.v
vlog -work work ../../rtl/command_processor.v
vlog -work work test_command_processor.v

# Start simulation
vsim -voptargs=+acc work.test_command_processor

# Add waves
add wave -noupdate -divider {Clock and Reset}
add wave -noupdate /test_command_processor/clk
add wave -noupdate /test_command_processor/rst_n

add wave -noupdate -divider {Parser Interface}
add wave -noupdate /test_command_processor/parse_done
add wave -noupdate -radix hexadecimal /test_command_processor/cmd_out
add wave -noupdate -radix unsigned /test_command_processor/len_out
add wave -noupdate -radix hexadecimal /test_command_processor/payload_read_data
add wave -noupdate -radix unsigned /test_command_processor/payload_read_addr

add wave -noupdate -divider {Command Bus Outputs}
add wave -noupdate -radix hexadecimal /test_command_processor/cmd_type_out
add wave -noupdate -radix unsigned /test_command_processor/cmd_length_out
add wave -noupdate -radix hexadecimal /test_command_processor/cmd_data_out
add wave -noupdate -radix unsigned /test_command_processor/cmd_data_index_out
add wave -noupdate /test_command_processor/cmd_start_out
add wave -noupdate /test_command_processor/cmd_data_valid_out
add wave -noupdate /test_command_processor/cmd_done_out

add wave -noupdate -divider {Handler Interface}
add wave -noupdate /test_command_processor/cmd_ready_in

add wave -noupdate -divider {Test Status}
add wave -noupdate /test_command_processor/cmd_start_seen
add wave -noupdate /test_command_processor/cmd_done_seen
add wave -noupdate /test_command_processor/both_seen_same_cycle

# Run simulation
run -all

# Zoom to show full waveform
wave zoom full
