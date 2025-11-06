# ============================================================================
# ModelSim Simulation Script for I2C Slave Handler Full Chain Test
# ============================================================================

# Cleaning old libraries...
if {[file exists work]} {
    vdel -lib work -all
}

# Create work library
vlib work
vmap work work

puts ""
puts "========================================"
puts "Compiling Design Files"
puts "========================================"

# Compile I2C slave modules
puts "Compiling I2C slave modules..."
vlog -reportprogress 300 -sv "+incdir+../../rtl/i2c" ../../rtl/i2c/synchronizer.sv
vlog -reportprogress 300 -sv "+incdir+../../rtl/i2c" ../../rtl/i2c/edge_detector.v
vlog -reportprogress 300 -sv "+incdir+../../rtl/i2c" ../../rtl/i2c/i2c_slave.sv
vlog -reportprogress 300 -sv "+incdir+../../rtl/i2c" ../../rtl/i2c/reg_map.sv
vlog -reportprogress 300 -sv "+incdir+../../rtl/i2c" ../../rtl/i2c/bidir.sv
vlog -reportprogress 300 -sv "+incdir+../../rtl/i2c" ../../rtl/i2c/i2c_slave_handler.sv

# Compile upload chain modules
puts "Compiling upload chain modules..."
vlog -reportprogress 300 -sv "+incdir+../../rtl" ../../rtl/upload_adapter_0.v
vlog -reportprogress 300 -sv "+incdir+../../rtl" ../../rtl/upload_packer_0.v

# Compile testbench
puts "Compiling testbench..."
vlog -reportprogress 300 -sv "+incdir+../../rtl" ../../tb/i2c_slave_handler_full_tb.sv

puts ""
puts "========================================"
puts "Starting Simulation"
puts "========================================"

# Run simulation
vsim -voptargs="+acc" work.i2c_slave_handler_full_tb -t ps

puts ""
puts "========================================"
puts "Adding Waveforms"
puts "========================================"

# Add waveforms
add wave -group "System" sim:/i2c_slave_handler_full_tb/clk
add wave -group "System" sim:/i2c_slave_handler_full_tb/rst_n

add wave -group "CDC Command" sim:/i2c_slave_handler_full_tb/cmd_type
add wave -group "CDC Command" sim:/i2c_slave_handler_full_tb/cmd_start
add wave -group "CDC Command" sim:/i2c_slave_handler_full_tb/cmd_done
add wave -group "CDC Command" sim:/i2c_slave_handler_full_tb/cmd_ready
add wave -group "CDC Command" sim:/i2c_slave_handler_full_tb/cmd_data
add wave -group "CDC Command" sim:/i2c_slave_handler_full_tb/cmd_data_valid

add wave -group "Handler→Adapter" sim:/i2c_slave_handler_full_tb/handler_upload_active
add wave -group "Handler→Adapter" sim:/i2c_slave_handler_full_tb/handler_upload_req
add wave -group "Handler→Adapter" sim:/i2c_slave_handler_full_tb/handler_upload_data
add wave -group "Handler→Adapter" sim:/i2c_slave_handler_full_tb/handler_upload_source
add wave -group "Handler→Adapter" sim:/i2c_slave_handler_full_tb/handler_upload_valid
add wave -group "Handler→Adapter" sim:/i2c_slave_handler_full_tb/handler_upload_ready

add wave -group "Adapter→Packer" sim:/i2c_slave_handler_full_tb/packer_upload_req
add wave -group "Adapter→Packer" sim:/i2c_slave_handler_full_tb/packer_upload_data
add wave -group "Adapter→Packer" sim:/i2c_slave_handler_full_tb/packer_upload_source
add wave -group "Adapter→Packer" sim:/i2c_slave_handler_full_tb/packer_upload_valid
add wave -group "Adapter→Packer" sim:/i2c_slave_handler_full_tb/packer_upload_ready

add wave -group "Packer→Test" sim:/i2c_slave_handler_full_tb/packed_req
add wave -group "Packer→Test" sim:/i2c_slave_handler_full_tb/packed_data
add wave -group "Packer→Test" sim:/i2c_slave_handler_full_tb/packed_source
add wave -group "Packer→Test" sim:/i2c_slave_handler_full_tb/packed_valid
add wave -group "Packer→Test" sim:/i2c_slave_handler_full_tb/packer_ready_from_test

add wave -group "Handler Internal" sim:/i2c_slave_handler_full_tb/u_handler/state
add wave -group "Handler Internal" sim:/i2c_slave_handler_full_tb/u_handler/cdc_read_ptr
add wave -group "Handler Internal" sim:/i2c_slave_handler_full_tb/u_handler/cdc_len
add wave -group "Handler Internal" sim:/i2c_slave_handler_full_tb/u_handler/cdc_start_addr

add wave -group "Adapter Internal" sim:/i2c_slave_handler_full_tb/u_adapter/packer_upload_req
add wave -group "Adapter Internal" sim:/i2c_slave_handler_full_tb/u_adapter/packer_upload_valid

add wave -group "Packer Internal" sim:/i2c_slave_handler_full_tb/u_packer/state
add wave -group "Packer Internal" sim:/i2c_slave_handler_full_tb/u_packer/data_count
add wave -group "Packer Internal" sim:/i2c_slave_handler_full_tb/u_packer/data_index

add wave -group "Registers" sim:/i2c_slave_handler_full_tb/u_handler/u_reg_map/registers

puts ""
puts "========================================"
puts "Running Simulation"
puts "========================================"

# Run
run -all

puts ""
puts "========================================"
puts "Simulation Completed!"
puts "========================================"
