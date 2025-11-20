# ============================================================================
# ModelSim Simulation Script for CAN Handler Testbench
# ============================================================================

# 清理之前的编译
if {[file exists work]} {
    vdel -lib work -all
}

# 创建工作库
vlib work
vmap work work

# 编译RTL文件
echo "Compiling CAN modules..."
vlog -work work ../../rtl/can/can_level_bit.v
vlog -work work ../../rtl/can/can_level_packet.v
vlog -work work ../../rtl/can/can_top.v
vlog -work work ../../rtl/can/can_handler.v

# 编译测试台
echo "Compiling testbench..."
vlog -work work ../../tb/can_handler_tb.v

# 启动仿真
echo "Starting simulation..."
vsim -voptargs=+acc work.can_handler_tb

# 添加波形
add wave -group "Clock & Reset" /can_handler_tb/clk
add wave -group "Clock & Reset" /can_handler_tb/rst_n

add wave -group "Command Interface" /can_handler_tb/cmd_type
add wave -group "Command Interface" /can_handler_tb/cmd_length
add wave -group "Command Interface" /can_handler_tb/cmd_data
add wave -group "Command Interface" /can_handler_tb/cmd_data_index
add wave -group "Command Interface" /can_handler_tb/cmd_start
add wave -group "Command Interface" /can_handler_tb/cmd_data_valid
add wave -group "Command Interface" /can_handler_tb/cmd_done
add wave -group "Command Interface" /can_handler_tb/cmd_ready

add wave -group "CAN Bus" /can_handler_tb/can_bus
add wave -group "CAN Bus" /can_handler_tb/handler_can_tx
add wave -group "CAN Bus" /can_handler_tb/peer_can_tx

add wave -group "Upload Interface" /can_handler_tb/upload_active
add wave -group "Upload Interface" /can_handler_tb/upload_req
add wave -group "Upload Interface" /can_handler_tb/upload_data
add wave -group "Upload Interface" /can_handler_tb/upload_source
add wave -group "Upload Interface" /can_handler_tb/upload_valid
add wave -group "Upload Interface" /can_handler_tb/upload_ready

add wave -group "Peer Device TX" /can_handler_tb/peer_tx_valid
add wave -group "Peer Device TX" /can_handler_tb/peer_tx_ready
add wave -group "Peer Device TX" /can_handler_tb/peer_tx_data

add wave -group "Peer Device RX" /can_handler_tb/peer_rx_valid
add wave -group "Peer Device RX" /can_handler_tb/peer_rx_last
add wave -group "Peer Device RX" /can_handler_tb/peer_rx_data
add wave -group "Peer Device RX" /can_handler_tb/peer_rx_id

add wave -group "Handler Internals" /can_handler_tb/u_dut/handler_state
add wave -group "Handler Internals" /can_handler_tb/u_dut/rx_count
add wave -group "Handler Internals" /can_handler_tb/u_dut/tx_write_ptr

# 运行仿真
echo "Running simulation..."
run -all

# 查看波形
wave zoom full
