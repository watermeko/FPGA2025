# ModelSim simulation script for DSM-only upload integration testbench
# Tests DSM handler with upload pipeline (Adapter -> Packer -> Arbiter)

# Create work library
vlib work

# Compile upload pipeline modules
puts "Compiling upload pipeline modules..."
vlog -work work ../../rtl/upload_adapter_0.v
vlog -work work ../../rtl/upload_packer_0.v
vlog -work work ../../rtl/upload_arbiter_0.v

# Compile DSM handler modules
puts "Compiling DSM handler modules..."
vlog -sv -work work ../../rtl/logic/digital_signal_measure.sv
vlog -sv -work work ../../rtl/logic/dsm_multichannel.sv
vlog -sv -work work ../../rtl/logic/dsm_multichannel_handler.sv

# Note: upload_arbiter_0.v uses internal register-based FIFO, no external FIFO needed

# Compile testbench
puts "Compiling testbench..."
vlog -work work ../../tb/upload_dsm_only_tb.v

# Start simulation
puts "Starting simulation..."
vsim -t 1ns -voptargs=+acc -L work work.upload_dsm_only_tb

# Add waveforms
puts "Adding waveforms..."

# Clock and reset
add wave -divider "Clock and Reset"
add wave -format Logic /upload_dsm_only_tb/clk
add wave -format Logic /upload_dsm_only_tb/rst_n

# Command interface
add wave -divider "Command Interface"
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/cmd_type
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/cmd_length
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/cmd_data
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/cmd_data_index
add wave -format Logic /upload_dsm_only_tb/cmd_start
add wave -format Logic /upload_dsm_only_tb/cmd_data_valid
add wave -format Logic /upload_dsm_only_tb/cmd_done

# DSM Input Signal
add wave -divider "DSM Input Signal"
add wave -format Literal -radix binary /upload_dsm_only_tb/dsm_signal_in
add wave -format Logic /upload_dsm_only_tb/dsm_signal_in(0)

# DSM Handler
add wave -divider "DSM Handler"
add wave -format Literal -radix ascii /upload_dsm_only_tb/u_dsm_handler/handler_state
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/u_dsm_handler/channel_mask
add wave -format Logic /upload_dsm_only_tb/dsm_upload_active
add wave -format Logic /upload_dsm_only_tb/dsm_upload_req
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/dsm_upload_data
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/dsm_upload_source
add wave -format Logic /upload_dsm_only_tb/dsm_upload_valid
add wave -format Logic /upload_dsm_only_tb/dsm_upload_ready

# DSM Measurement Results
add wave -divider "DSM Measurement Results"
add wave -format Literal -radix unsigned /upload_dsm_only_tb/u_dsm_handler/u_dsm_multichannel/high_time(15:0)
add wave -format Literal -radix unsigned /upload_dsm_only_tb/u_dsm_handler/u_dsm_multichannel/low_time(15:0)
add wave -format Literal -radix binary /upload_dsm_only_tb/u_dsm_handler/measure_done

# DSM Adapter
add wave -divider "DSM Adapter"
add wave -format Logic /upload_dsm_only_tb/dsm_packer_req
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/dsm_packer_data
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/dsm_packer_source
add wave -format Logic /upload_dsm_only_tb/dsm_packer_valid
add wave -format Logic /upload_dsm_only_tb/dsm_packer_ready

# Packer Output (Channel 2 - DSM)
add wave -divider "Packer Output (DSM Channel)"
add wave -format Literal -radix ascii /upload_dsm_only_tb/u_packer/state(2)
add wave -format Logic /upload_dsm_only_tb/packed_req(2)
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/packed_data(23:16)
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/packed_source(23:16)
add wave -format Logic /upload_dsm_only_tb/packed_valid(2)
add wave -format Logic /upload_dsm_only_tb/arbiter_ready(2)

# Arbiter Output
add wave -divider "Arbiter Merged Output"
add wave -format Literal -radix ascii /upload_dsm_only_tb/u_arbiter/state
add wave -format Literal -radix unsigned /upload_dsm_only_tb/u_arbiter/current_source
add wave -format Logic /upload_dsm_only_tb/u_arbiter/in_packet
add wave -format Logic /upload_dsm_only_tb/merged_upload_req
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/merged_upload_data
add wave -format Literal -radix hexadecimal /upload_dsm_only_tb/merged_upload_source
add wave -format Logic /upload_dsm_only_tb/merged_upload_valid
add wave -format Logic /upload_dsm_only_tb/merged_upload_ready

# Monitor counter
add wave -divider "Monitor Counter"
add wave -format Literal -radix unsigned /upload_dsm_only_tb/dsm_byte_count
add wave -format Literal -radix unsigned /upload_dsm_only_tb/merged_byte_count

# Run simulation
puts "Running simulation for 2ms..."
run 2ms

puts ""
puts "================================================"
puts "Simulation complete!"
puts "================================================"
puts ""
puts "Check waveforms to verify:"
puts "  1. DSM channel 0 measurement (1kHz square wave)"
puts "  2. Upload data format:"
puts "     - Header: 0xAA 0x44"
puts "     - Source: 0x0A (DSM)"
puts "     - Length: 0x00 0x05 (5 bytes per channel - UPDATED)"
puts "     - Data: Ch_num + High(2B) + Low(2B)"
puts "     - Checksum: XOR of all bytes"
puts "  3. Total bytes: 11 (6 header + 5 data - UPDATED)"
puts ""
