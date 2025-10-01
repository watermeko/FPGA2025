# ==============================================================================
# CDC_SPI Testbench ModelSim Simulation Script (FINAL CORRECTED VERSION)
# ==============================================================================

# 確保在開始前退出任何正在運行的模擬
quit -sim

# ------------------------------------------------------------------------------
# 1. 清理並創建本地庫
# ------------------------------------------------------------------------------
# 如果存在舊的庫，則刪除
if {[file isdirectory work]} {
  vdel -lib work -all
}
if {[file isdirectory gw5a]} {
  vdel -lib gw5a -all
}

# 創建並映射新的庫
vlib work
vmap work work
vlib gw5a
vmap gw5a ./gw5a

# ------------------------------------------------------------------------------
# 2. 編譯Gowin原語到本地庫
# ------------------------------------------------------------------------------
echo "Compiling Gowin primitives into local './gw5a' library..."
# 注意：這個路徑是硬編碼的，請確保它在您的電腦上是正確的
set GOWIN_PATH "E:/GOWIN/Gowin_V1.9.9_x64/IDE"
vlog -work gw5a "${GOWIN_PATH}/simlib/gw5a/prim_sim.v"

# ------------------------------------------------------------------------------
# 3. 編譯所有設計和測試文件
# ------------------------------------------------------------------------------
echo "Compiling all design and testbench files into './work' library..."

# --- 設計文件 ---
vlog -sv +incdir+../../rtl ../../rtl/dds/accuml.v
vlog -sv +incdir+../../rtl ../../rtl/dds/Sin.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DDS.v
vlog -sv +incdir+../../rtl ../../rtl/dds/DAC.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm.v
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_multichannel.sv
vcom -work work ../../rtl/uart/uart_tx.vhd
vcom -work work ../../rtl/uart/uart_rx.vhd
vlog -sv +incdir+../../rtl ../../rtl/uart/fixed_point_divider/fixed_point_divider.vo
vlog -sv +incdir+../../rtl ../../rtl/uart/uart.v
vlog -sv +incdir+../../rtl ../../rtl/uart/usb_uart_config.v
vlog -sv +incdir+../../rtl ../../rtl/spi/simple_spi_master.v
vlog -sv +incdir+../../rtl ../../rtl/spi/spi_handler.v
vlog -sv +incdir+../../rtl ../../rtl/dds/dac_handler.sv
vlog -sv +incdir+../../rtl ../../rtl/pwm/pwm_handler.v
vlog -sv +incdir+../../rtl ../../rtl/uart/uart_handler.v
vlog -sv +incdir+../../rtl ../../rtl/protocol_parser.v
vlog -sv +incdir+../../rtl ../../rtl/command_processor.v
vlog -sv +incdir+../../rtl ../../rtl/cdc_spi.v

# --- 測試平台文件 ---
vlog -sv +incdir+../../rtl ../../tb/cdc_spi_tb.sv

# ------------------------------------------------------------------------------
# 4. 啟動仿真
# ------------------------------------------------------------------------------
echo "Starting simulation..."
vsim -L gw5a work.cdc_spi_tb -voptargs="+acc" -t ps

# ------------------------------------------------------------------------------
# 5. 添加波形 (完全移除不存在的信号)
# ------------------------------------------------------------------------------
# --- 頂層輸入 ---
add wave -group "Top Level Inputs" /cdc_spi_tb/clk
add wave -group "Top Level Inputs" /cdc_spi_tb/rst_n
add wave -group "Top Level Inputs" -radix hex /cdc_spi_tb/usb_data_in
add wave -group "Top Level Inputs" /cdc_spi_tb/usb_data_valid_in

# --- 協議解析器 (protocol_parser) ---
add wave -group "Protocol Parser" -divider "Inputs"
add wave -group "Protocol Parser" /cdc_spi_tb/dut/u_parser/uart_rx_valid
add wave -group "Protocol Parser" -radix hex /cdc_spi_tb/dut/u_parser/uart_rx_data
add wave -group "Protocol Parser" -divider "Internals"
add wave -group "Protocol Parser" -radix unsigned /cdc_spi_tb/dut/u_parser/state
add wave -group "Protocol Parser" -radix hex /cdc_spi_tb/dut/u_parser/checksum
add wave -group "Protocol Parser" -radix hex /cdc_spi_tb/dut/u_parser/cmd_out
add wave -group "Protocol Parser" -radix unsigned /cdc_spi_tb/dut/u_parser/len_out
#add wave -group "SPI Handler" -radix unsigned /cdc_spi_tb/dut/u_spi_handler/transfer_len
add wave -group "Protocol Parser" -divider "Outputs"
add wave -group "Protocol Parser" /cdc_spi_tb/dut/u_parser/parse_done
add wave -group "Protocol Parser" /cdc_spi_tb/dut/u_parser/parse_error

# --- 指令處理器 (command_processor) ---
add wave -group "Command Processor" -divider "Inputs & Internals"
add wave -group "Command Processor" /cdc_spi_tb/dut/u_command_processor/parse_done_edge
add wave -group "Command Processor" -radix unsigned /cdc_spi_tb/dut/u_command_processor/state
add wave -group "Command Processor" -radix hex /cdc_spi_tb/dut/u_command_processor/payload_read_addr
add wave -group "Command Processor" -radix hex /cdc_spi_tb/dut/u_command_processor/payload_read_data
add wave -group "Command Processor" /cdc_spi_tb/dut/u_command_processor/cmd_ready_in
add wave -group "Command Processor" -divider "Command Bus Outputs"
add wave -group "Command Processor" -radix hex /cdc_spi_tb/dut/cmd_type
add wave -group "Command Processor" -radix unsigned /cdc_spi_tb/dut/cmd_length
add wave -group "Command Processor" /cdc_spi_tb/dut/cmd_start
add wave -group "Command Processor" /cdc_spi_tb/dut/cmd_data_valid
add wave -group "Command Processor" -radix hex /cdc_spi_tb/dut/cmd_data
add wave -group "Command Processor" -radix unsigned /cdc_spi_tb/dut/cmd_data_index
add wave -group "Command Processor" /cdc_spi_tb/dut/cmd_done

# --- SPI 控制器 (spi_handler) ---
add wave -group "SPI Handler" -divider "Internals"
add wave -group "SPI Handler" /cdc_spi_tb/dut/spi_ready
add wave -group "SPI Handler" -radix unsigned /cdc_spi_tb/dut/u_spi_handler/state
add wave -group "SPI Handler" -radix unsigned /cdc_spi_tb/dut/u_spi_handler/byte_index
add wave -group "SPI Handler" -radix hex /cdc_spi_tb/dut/u_spi_handler/tx_buffer(0)
add wave -group "SPI Handler" -radix hex /cdc_spi_tb/dut/u_spi_handler/tx_buffer(1)
add wave -group "SPI Handler" -radix hex /cdc_spi_tb/dut/u_spi_handler/tx_buffer(2)
add wave -group "SPI Handler" -radix hex /cdc_spi_tb/dut/u_spi_handler/tx_buffer(3)
add wave -group "SPI Handler" -radix hex /cdc_spi_tb/dut/u_spi_handler/rx_buffer(0)
add wave -group "SPI Handler" -radix hex /cdc_spi_tb/dut/u_spi_handler/rx_buffer(1)
add wave -group "SPI Handler" -radix hex /cdc_spi_tb/dut/u_spi_handler/rx_buffer(2)
add wave -group "SPI Handler" -radix hex /cdc_spi_tb/dut/u_spi_handler/rx_buffer(3)
add wave -group "SPI Handler" -divider "SPI Master Control"
add wave -group "SPI Handler" /cdc_spi_tb/dut/u_spi_handler/spi_start
add wave -group "SPI Handler" -radix hex /cdc_spi_tb/dut/u_spi_handler/spi_tx_byte
add wave -group "SPI Handler" -radix hex /cdc_spi_tb/dut/u_spi_handler/spi_rx_byte
add wave -group "SPI Handler" /cdc_spi_tb/dut/u_spi_handler/spi_done
#add wave -group "SPI Handler" /cdc_spi_tb/dut/u_spi_handler/spi_busy

# --- SPI 主控制器内部信号 ---
add wave -group "SPI Master Internal" -divider "SPI Master Core"
add wave -group "SPI Master Internal" /cdc_spi_tb/dut/u_spi_handler/u_spi/i_start
add wave -group "SPI Master Internal" -radix hex /cdc_spi_tb/dut/u_spi_handler/u_spi/i_tx_byte
add wave -group "SPI Master Internal" -radix hex /cdc_spi_tb/dut/u_spi_handler/u_spi/o_rx_byte
add wave -group "SPI Master Internal" /cdc_spi_tb/dut/u_spi_handler/u_spi/o_done
add wave -group "SPI Master Internal" /cdc_spi_tb/dut/u_spi_handler/u_spi/o_busy
add wave -group "SPI Master Internal" /cdc_spi_tb/dut/u_spi_handler/u_spi/state

# --- SPI 物理總線 ---
add wave -group "SPI Bus" /cdc_spi_tb/spi_clk
add wave -group "SPI Bus" /cdc_spi_tb/spi_cs_n
add wave -group "SPI Bus" /cdc_spi_tb/spi_mosi
add wave -group "SPI Bus" /cdc_spi_tb/spi_miso



# --- 上传接口 (Upload Interface) ---
add wave -group "Upload Interface" -divider "SPI Handler Upload"
add wave -group "Upload Interface" /cdc_spi_tb/dut/u_spi_handler/upload_req
add wave -group "Upload Interface" -radix hex /cdc_spi_tb/dut/u_spi_handler/upload_data
add wave -group "Upload Interface" /cdc_spi_tb/dut/u_spi_handler/upload_valid
add wave -group "Upload Interface" /cdc_spi_tb/dut/u_spi_handler/upload_ready
add wave -group "Upload Interface" -divider "Command Processor Upload"
add wave -group "Upload Interface" /cdc_spi_tb/dut/processor_upload_ready
add wave -group "Upload Interface" /cdc_spi_tb/dut/merged_upload_valid
add wave -group "Upload Interface" -radix hex /cdc_spi_tb/dut/merged_upload_data

# --- 最終輸出 (USB上傳) ---
add wave -group "USB Upload Output" -radix hex /cdc_spi_tb/usb_upload_data
add wave -group "USB Upload Output" /cdc_spi_tb/usb_upload_valid

# ------------------------------------------------------------------
# 6. 運行仿真
# ------------------------------------------------------------------
run -all
wave zoom full
echo "Simulation completed."