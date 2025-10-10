# ModelSim/QuestaSim simulation script for upload integration test

# Create and map work library
vlib work
vmap work work

# Compile all required modules
puts "Compiling upload_packer_simple module..."
vlog -sv ../../rtl/upload_packer_simple.v

puts "Compiling upload_arbiter module..."
vlog -sv ../../rtl/upload_arbiter.v

puts "Compiling integration testbench..."
vlog -sv ../../tb/upload_integration_tb.v

# Start simulation
puts "Starting simulation..."
vsim work.upload_integration_tb -voptargs="+acc" -t ps

# Add waveforms
add wave -group "Clock & Reset" /upload_integration_tb/clk
add wave -group "Clock & Reset" /upload_integration_tb/rst_n

# UART raw input signals
add wave -group "UART Raw Input" -radix hex /upload_integration_tb/uart_raw_data
add wave -group "UART Raw Input" -radix hex /upload_integration_tb/uart_raw_source
add wave -group "UART Raw Input" /upload_integration_tb/uart_raw_req
add wave -group "UART Raw Input" /upload_integration_tb/uart_raw_valid
add wave -group "UART Raw Input" /upload_integration_tb/uart_raw_ready

# SPI raw input signals
add wave -group "SPI Raw Input" -radix hex /upload_integration_tb/spi_raw_data
add wave -group "SPI Raw Input" -radix hex /upload_integration_tb/spi_raw_source
add wave -group "SPI Raw Input" /upload_integration_tb/spi_raw_req
add wave -group "SPI Raw Input" /upload_integration_tb/spi_raw_valid
add wave -group "SPI Raw Input" /upload_integration_tb/spi_raw_ready

# UART Packer output
add wave -group "UART Packer Output" -radix hex {/upload_integration_tb/packer_data[7:0]}
add wave -group "UART Packer Output" -radix hex {/upload_integration_tb/packer_source[7:0]}
add wave -group "UART Packer Output" {/upload_integration_tb/packer_req[0]}
add wave -group "UART Packer Output" {/upload_integration_tb/packer_valid[0]}
add wave -group "UART Packer Output" {/upload_integration_tb/arbiter_ready[0]}
add wave -group "UART Packer Output" -radix unsigned /upload_integration_tb/u_uart_packer/state

# SPI Packer output
add wave -group "SPI Packer Output" -radix hex {/upload_integration_tb/packer_data[15:8]}
add wave -group "SPI Packer Output" -radix hex {/upload_integration_tb/packer_source[15:8]}
add wave -group "SPI Packer Output" {/upload_integration_tb/packer_req[1]}
add wave -group "SPI Packer Output" {/upload_integration_tb/packer_valid[1]}
add wave -group "SPI Packer Output" {/upload_integration_tb/arbiter_ready[1]}
add wave -group "SPI Packer Output" -radix unsigned /upload_integration_tb/u_spi_packer/state

# Arbiter internals
add wave -group "Arbiter Internal" -radix unsigned /upload_integration_tb/u_arbiter/state
add wave -group "Arbiter Internal" -radix unsigned /upload_integration_tb/u_arbiter/current_source
add wave -group "Arbiter Internal" /upload_integration_tb/u_arbiter/in_packet
add wave -group "Arbiter Internal" -radix unsigned {/upload_integration_tb/u_arbiter/gen_fifos[0].count}
add wave -group "Arbiter Internal" -radix unsigned {/upload_integration_tb/u_arbiter/gen_fifos[1].count}

# Merged output to processor
add wave -group "Merged Output" -radix hex /upload_integration_tb/merged_data
add wave -group "Merged Output" -radix hex /upload_integration_tb/merged_source
add wave -group "Merged Output" /upload_integration_tb/merged_req
add wave -group "Merged Output" /upload_integration_tb/merged_valid
add wave -group "Merged Output" /upload_integration_tb/processor_ready

# Test statistics
add wave -group "Statistics" -radix unsigned /upload_integration_tb/total_bytes_received
add wave -group "Statistics" -radix unsigned /upload_integration_tb/uart_packets_sent
add wave -group "Statistics" -radix unsigned /upload_integration_tb/spi_packets_sent

# Run simulation
run -all

# Zoom to show all waveforms
wave zoom full

puts "Simulation completed."
