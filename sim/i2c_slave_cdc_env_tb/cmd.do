# ============================================================================
# ModelSim Simulation Script for I2C Slave Complete CDC Environment Test
# Tests: Parser → Processor → Handler → Adapter → Packer (Full Stack)
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

# Compile protocol modules
puts "Compiling protocol modules..."
vlog -reportprogress 300 -sv "+incdir+../../rtl" ../../rtl/protocol_parser.v
vlog -reportprogress 300 -sv "+incdir+../../rtl" ../../rtl/command_processor.v

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
vlog -reportprogress 300 -sv "+incdir+../../rtl" ../../tb/i2c_slave_cdc_env_tb.sv

puts ""
puts "========================================"
puts "Starting Simulation"
puts "========================================"

# Run simulation
vsim -voptargs="+acc" work.i2c_slave_cdc_env_tb -t ps

puts ""
puts "========================================"
puts "Adding Waveforms"
puts "========================================"

# System signals
add wave -group "System" sim:/i2c_slave_cdc_env_tb/clk
add wave -group "System" sim:/i2c_slave_cdc_env_tb/rst_n

# USB CDC Input (simulated from host)
add wave -group "USB CDC Input" sim:/i2c_slave_cdc_env_tb/usb_data_in
add wave -group "USB CDC Input" sim:/i2c_slave_cdc_env_tb/usb_data_valid_in

# USB Upload Output (responses to host)
add wave -group "USB Upload Output" sim:/i2c_slave_cdc_env_tb/usb_upload_data
add wave -group "USB Upload Output" sim:/i2c_slave_cdc_env_tb/usb_upload_valid
add wave -group "USB Upload Output" sim:/i2c_slave_cdc_env_tb/frame_count

# Parser outputs
add wave -group "Parser" sim:/i2c_slave_cdc_env_tb/parser_done
add wave -group "Parser" sim:/i2c_slave_cdc_env_tb/parser_error
add wave -group "Parser" sim:/i2c_slave_cdc_env_tb/cmd_out
add wave -group "Parser" sim:/i2c_slave_cdc_env_tb/len_out

# Command Bus
add wave -group "Command Bus" sim:/i2c_slave_cdc_env_tb/cmd_type
add wave -group "Command Bus" sim:/i2c_slave_cdc_env_tb/cmd_start
add wave -group "Command Bus" sim:/i2c_slave_cdc_env_tb/cmd_done
add wave -group "Command Bus" sim:/i2c_slave_cdc_env_tb/cmd_ready
add wave -group "Command Bus" sim:/i2c_slave_cdc_env_tb/cmd_data
add wave -group "Command Bus" sim:/i2c_slave_cdc_env_tb/cmd_data_valid

# Handler → Adapter
add wave -group "Handler→Adapter" sim:/i2c_slave_cdc_env_tb/handler_upload_active
add wave -group "Handler→Adapter" sim:/i2c_slave_cdc_env_tb/handler_upload_req
add wave -group "Handler→Adapter" sim:/i2c_slave_cdc_env_tb/handler_upload_data
add wave -group "Handler→Adapter" sim:/i2c_slave_cdc_env_tb/handler_upload_source
add wave -group "Handler→Adapter" sim:/i2c_slave_cdc_env_tb/handler_upload_valid
add wave -group "Handler→Adapter" sim:/i2c_slave_cdc_env_tb/handler_upload_ready

# Adapter → Packer
add wave -group "Adapter→Packer" sim:/i2c_slave_cdc_env_tb/packer_upload_req
add wave -group "Adapter→Packer" sim:/i2c_slave_cdc_env_tb/packer_upload_data
add wave -group "Adapter→Packer" sim:/i2c_slave_cdc_env_tb/packer_upload_source
add wave -group "Adapter→Packer" sim:/i2c_slave_cdc_env_tb/packer_upload_valid
add wave -group "Adapter→Packer" sim:/i2c_slave_cdc_env_tb/packer_upload_ready

# Packer → Processor
add wave -group "Packer→Processor" sim:/i2c_slave_cdc_env_tb/packed_req
add wave -group "Packer→Processor" sim:/i2c_slave_cdc_env_tb/packed_data
add wave -group "Packer→Processor" sim:/i2c_slave_cdc_env_tb/packed_source
add wave -group "Packer→Processor" sim:/i2c_slave_cdc_env_tb/packed_valid
add wave -group "Packer→Processor" sim:/i2c_slave_cdc_env_tb/packed_ready

# Handler Internal State
add wave -group "Handler Internal" sim:/i2c_slave_cdc_env_tb/u_handler/state
add wave -group "Handler Internal" sim:/i2c_slave_cdc_env_tb/u_handler/cdc_read_ptr
add wave -group "Handler Internal" sim:/i2c_slave_cdc_env_tb/u_handler/cdc_len
add wave -group "Handler Internal" sim:/i2c_slave_cdc_env_tb/u_handler/cdc_start_addr

# Packer Internal State
add wave -group "Packer Internal" sim:/i2c_slave_cdc_env_tb/u_packer/state
add wave -group "Packer Internal" sim:/i2c_slave_cdc_env_tb/u_packer/data_count
add wave -group "Packer Internal" sim:/i2c_slave_cdc_env_tb/u_packer/data_index

# Processor Internal
add wave -group "Processor Internal" sim:/i2c_slave_cdc_env_tb/u_processor/state
add wave -group "Processor Internal" sim:/i2c_slave_cdc_env_tb/u_processor/upload_ready_out

# Registers
add wave -group "Registers" sim:/i2c_slave_cdc_env_tb/u_handler/u_reg_map/registers

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
