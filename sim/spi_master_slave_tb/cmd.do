# ==============================================================================
# SPI Master-Slave Handler联合测试仿真脚本
# 测试SPI主机和从机handler的互联通信
# ==============================================================================

# Quit any running simulation
quit -sim

# ------------------------------------------------------------------------------
# 1. 清理并创建库
# ------------------------------------------------------------------------------
catch {vdel -lib work -all}

vlib work
vmap work work

# ------------------------------------------------------------------------------
# 2. 编译设计文件
# ------------------------------------------------------------------------------
echo "Compiling design files..."

# SPI Physical Layers
vlog -sv +incdir+../../rtl ../../rtl/spi/simple_spi_master.v
vlog -sv +incdir+../../rtl ../../rtl/spi/simple_spi_slave.v

# SPI Handlers
vlog -sv +incdir+../../rtl ../../rtl/spi/spi_handler.v
vlog -sv +incdir+../../rtl ../../rtl/spi/spi_slave_handler.v

# Testbench
vlog -sv +incdir+../../rtl ../../tb/spi_master_slave_tb.sv

# ------------------------------------------------------------------------------
# 3. 启动仿真
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim work.spi_master_slave_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 4. 添加波形
# ------------------------------------------------------------------------------
echo "Adding waveforms..."

# --- Top Level ---
add wave -group "Top Level" -divider "Clock & Reset"
add wave -group "Top Level" /spi_master_slave_tb/clk
add wave -group "Top Level" /spi_master_slave_tb/rst_n

add wave -group "Top Level" -divider "SPI Bus"
add wave -group "Top Level" /spi_master_slave_tb/spi_clk
add wave -group "Top Level" /spi_master_slave_tb/spi_cs_n
add wave -group "Top Level" /spi_master_slave_tb/spi_mosi
add wave -group "Top Level" /spi_master_slave_tb/spi_miso

# --- Master Handler ---
add wave -group "Master" -divider "Command Bus"
add wave -group "Master" -radix hex /spi_master_slave_tb/master_cmd_type
add wave -group "Master" -radix unsigned /spi_master_slave_tb/master_cmd_length
add wave -group "Master" -radix hex /spi_master_slave_tb/master_cmd_data
add wave -group "Master" /spi_master_slave_tb/master_cmd_start
add wave -group "Master" /spi_master_slave_tb/master_cmd_done
add wave -group "Master" /spi_master_slave_tb/master_cmd_ready

add wave -group "Master" -divider "State"
add wave -group "Master" -radix unsigned /spi_master_slave_tb/u_master/state

add wave -group "Master" -divider "Upload"
add wave -group "Master" /spi_master_slave_tb/master_upload_active
add wave -group "Master" -radix hex /spi_master_slave_tb/master_upload_data
add wave -group "Master" /spi_master_slave_tb/master_upload_valid
add wave -group "Master" /spi_master_slave_tb/master_upload_ready

# --- Slave Handler ---
add wave -group "Slave" -divider "Command Bus"
add wave -group "Slave" -radix hex /spi_master_slave_tb/slave_cmd_type
add wave -group "Slave" -radix unsigned /spi_master_slave_tb/slave_cmd_length
add wave -group "Slave" -radix hex /spi_master_slave_tb/slave_cmd_data
add wave -group "Slave" /spi_master_slave_tb/slave_cmd_start
add wave -group "Slave" /spi_master_slave_tb/slave_cmd_done
add wave -group "Slave" /spi_master_slave_tb/slave_cmd_ready

add wave -group "Slave" -divider "State"
add wave -group "Slave" -radix unsigned /spi_master_slave_tb/u_slave/state

add wave -group "Slave" -divider "TX Buffer"
add wave -group "Slave" -radix unsigned /spi_master_slave_tb/u_slave/tx_read_ptr
add wave -group "Slave" -radix unsigned /spi_master_slave_tb/u_slave/tx_buffer_len
add wave -group "Slave" /spi_master_slave_tb/u_slave/tx_buffer_ready

add wave -group "Slave" -divider "RX Buffer"
add wave -group "Slave" -radix unsigned /spi_master_slave_tb/u_slave/rx_write_ptr
add wave -group "Slave" /spi_master_slave_tb/u_slave/rx_upload_enable

add wave -group "Slave" -divider "Upload"
add wave -group "Slave" /spi_master_slave_tb/slave_upload_active
add wave -group "Slave" -radix hex /spi_master_slave_tb/slave_upload_data
add wave -group "Slave" /spi_master_slave_tb/slave_upload_valid
add wave -group "Slave" /spi_master_slave_tb/slave_upload_ready

# --- SPI Master Physical ---
add wave -group "Master Physical" -divider "State"
add wave -group "Master Physical" -radix unsigned /spi_master_slave_tb/u_master/u_spi/state
add wave -group "Master Physical" -radix unsigned /spi_master_slave_tb/u_master/u_spi/bit_count

add wave -group "Master Physical" -divider "Control"
add wave -group "Master Physical" /spi_master_slave_tb/u_master/spi_start
add wave -group "Master Physical" /spi_master_slave_tb/u_master/spi_done
add wave -group "Master Physical" -radix hex /spi_master_slave_tb/u_master/spi_tx_byte
add wave -group "Master Physical" -radix hex /spi_master_slave_tb/u_master/spi_rx_byte

# --- SPI Slave Physical ---
add wave -group "Slave Physical" -divider "State"
add wave -group "Slave Physical" -radix unsigned /spi_master_slave_tb/u_slave/u_spi_slave/state
add wave -group "Slave Physical" -radix unsigned /spi_master_slave_tb/u_slave/u_spi_slave/bit_count

add wave -group "Slave Physical" -divider "Control"
add wave -group "Slave Physical" /spi_master_slave_tb/u_slave/spi_tx_ready
add wave -group "Slave Physical" -radix hex /spi_master_slave_tb/u_slave/spi_tx_byte
add wave -group "Slave Physical" /spi_master_slave_tb/u_slave/spi_byte_received
add wave -group "Slave Physical" -radix hex /spi_master_slave_tb/u_slave/spi_rx_byte

# --- Test Status ---
add wave -group "Test Status" -divider "Counters"
add wave -group "Test Status" -radix unsigned /spi_master_slave_tb/master_upload_count
add wave -group "Test Status" -radix unsigned /spi_master_slave_tb/slave_upload_count
add wave -group "Test Status" -radix unsigned /spi_master_slave_tb/test_pass_count
add wave -group "Test Status" -radix unsigned /spi_master_slave_tb/test_fail_count

# ------------------------------------------------------------------------------
# 5. 配置波形窗口
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
# 6. 运行仿真
# ------------------------------------------------------------------------------
echo "Running simulation..."
run -all

# Zoom to fit
wave zoom full

echo ""
echo "========================================"
echo "Simulation completed!"
echo "========================================"
echo ""
echo "Signal groups:"
echo "- Top Level: System clock/reset, SPI bus"
echo "- Master: Master handler signals"
echo "- Slave: Slave handler signals"
echo "- Master Physical: SPI master physical layer"
echo "- Slave Physical: SPI slave physical layer"
echo "- Test Status: Test counters"
echo ""
echo "Check console output for PASS/FAIL results"
echo ""
