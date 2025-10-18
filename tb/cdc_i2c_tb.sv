// ============================================================================
// Module:      cdc_tb (已更新以匹配 cdc.v)
// Author:      Gemini
// Date:        2025-10-16
// Description:
// - 此测试平台已更新，以匹配 'cdc' 模块扩展后的端口列表。
// - 声明了所有新的输入端口并赋予默认值。
// - 声明了所有新的输出端口。
// - DUT 实例化已更新，以连接所有端口。
// - 核心的 I2C 测试功能保持不变。
// ============================================================================

`timescale 1ns / 1ns

module cdc_tb;

    //-----------------------------------------------------------------------------
    // 测试平台参数
    //-----------------------------------------------------------------------------
    localparam CLK_FREQ      = 50_000_000;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;
    localparam DAC_CLK_PERIOD_NS = 10; // DAC 时钟的示例周期

    //-----------------------------------------------------------------------------
    // I2C 测试参数
    //-----------------------------------------------------------------------------
    localparam I2C_CONFIG_CMD = 8'h04;
    localparam I2C_WRITE_CMD  = 8'h05;
    localparam I2C_READ_CMD   = 8'h06;
    localparam EEPROM_DEVICE_ADDR_8BIT = 8'hA0;
    localparam EEPROM_DEVICE_ADDR_7BIT = EEPROM_DEVICE_ADDR_8BIT >> 1;
    localparam WRITE_ADDR = 16'h003C;
    localparam NUM_BYTES_TO_TEST = 4;
    localparam READ_TIMEOUT = 100_000;

    //-----------------------------------------------------------------------------
    // 测试平台信号
    //-----------------------------------------------------------------------------
    // --- 核心和 USB 信号 ---
    reg clk;
    reg rst_n;
    reg [7:0] usb_data_in;
    reg usb_data_valid_in;
    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;

    // --- DUT I/O 信号 (为兼容性新增或更新) ---
    wire led_out;
    wire [7:0] pwm_pins;
    reg  ext_uart_rx;
    wire ext_uart_tx;
    wire i2c_scl;
    wire i2c_sda;
    reg  dac_clk;
    wire signed [13:0] dac_data; // ** 新增 **
    wire spi_clk;
    wire spi_cs_n;
    wire spi_mosi;
    reg  spi_miso;
    reg [7:0] dsm_signal_in;
    reg [7:0] dc_signal_in;
    wire debug_out;

    // --- 测试平台专用变量 ---
    reg [7:0] tb_payload [0:127];
    reg [7:0] expected_data [0:NUM_BYTES_TO_TEST-1];
    integer i;

    // --- I2C SDA 线上拉电阻 ---
    pullup PUP(i2c_sda);

    //-----------------------------------------------------------------------------
    // DUT 和从设备实例化
    //-----------------------------------------------------------------------------
    // --- ** 修改: 更新 DUT 实例化以连接所有端口 ** ---
    cdc dut (
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_rx(ext_uart_rx),
        .ext_uart_tx(ext_uart_tx),
        .i2c_scl(i2c_scl),
        .i2c_sda(i2c_sda),
        .dac_clk(dac_clk),
        .dac_data(dac_data), // ** 新增连接 **
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .dsm_signal_in(dsm_signal_in),
        .dc_signal_in(dc_signal_in),
        .debug_out(debug_out),
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid)
    );

    M24LC64 u_eeprom (
        .A0(1'b0), .A1(1'b0), .A2(1'b0), .WP(1'b0),
        .SDA(i2c_sda), .SCL(i2c_scl), .RESET(~rst_n) // 注意: EEPROM 模型使用高电平有效复位
    );

    //-----------------------------------------------------------------------------
    // 时钟和复位生成
    //-----------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    // --- ** 新增: dac_clk 的时钟生成 ** ---
    initial begin
        dac_clk = 0;
        forever #(DAC_CLK_PERIOD_NS / 2) dac_clk = ~dac_clk;
    end

    initial begin
        rst_n = 1'b0;
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
    end

    // --- ** 新增: 为新的 DUT 输入信号进行初始化 ** ---
    initial begin
        // 为 DUT 输入提供默认值以避免 'X' 状态
        ext_uart_rx   = 1'b1; // UART RX 默认空闲状态
        spi_miso      = 1'b0;
        dsm_signal_in = 8'h00;
        dc_signal_in  = 8'h00;
        usb_data_valid_in = 1'b0;
        usb_data_in = 8'h00;
    end

    //-----------------------------------------------------------------------------
    // 辅助任务和验证任务 (此处无需更改)
    //-----------------------------------------------------------------------------
    task send_usb_byte(input [7:0] data);
        begin @(posedge clk); usb_data_in = data; usb_data_valid_in = 1'b1; @(posedge clk); usb_data_valid_in = 1'b0; end
    endtask

    task automatic send_i2c_command(input [7:0] cmd, input [15:0] len);
        reg [7:0] checksum = 0;
        begin
            send_usb_byte(8'hAA); send_usb_byte(8'h55);
            send_usb_byte(cmd); checksum = checksum + cmd;
            send_usb_byte(len[15:8]); checksum = checksum + len[15:8];
            send_usb_byte(len[7:0]); checksum = checksum + len[7:0];
            for (i = 0; i < len; i = i + 1) begin
                send_usb_byte(tb_payload[i]);
                checksum = checksum + tb_payload[i];
            end
            send_usb_byte(checksum);
        end
    endtask

    task automatic verify_single_read(input [7:0] expected_byte, input integer byte_index);
        reg timeout_l = 1'b0; reg [7:0] received_data;
        begin $display("  Verifying byte %0d...", byte_index); fork begin : v_thread while (dut.usb_upload_valid !== 1'b1) @(posedge clk); received_data = dut.usb_upload_data; if (received_data === expected_byte) $display("    -> SUCCESS: Expected 0x%h, Got 0x%h", expected_byte, received_data); else $error("    -> FAILURE: Expected 0x%h, Got 0x%h", expected_byte, received_data); @(posedge clk); end begin : t_thread #(READ_TIMEOUT); timeout_l = 1'b1; end join_any if(timeout_l) disable v_thread; else disable t_thread; if (timeout_l) $error("  -> FAILURE: Timeout waiting for byte %0d from DUT.", byte_index); end
    endtask

    //-----------------------------------------------------------------------------
    // 主测试序列 (测试逻辑本身无需更改)
    //-----------------------------------------------------------------------------
    initial begin

        wait (rst_n === 1'b1);
        #1000;

        expected_data[0] = 8'hDE;
        expected_data[1] = 8'hAD;
        expected_data[2] = 8'hBE;
        expected_data[3] = 8'hEF;

        $display("=== Starting I2C EEPROM Verification (Sequential Single-Byte Read) ===");

        $display("[%0t] Step 1: Sending I2C Config command...", $time);
        tb_payload[0] = EEPROM_DEVICE_ADDR_7BIT;
        send_i2c_command(I2C_CONFIG_CMD, 1);
        #2000;

        $display("[%0t] Step 2: Sending I2C Write command to EEPROM address 0x%h...", $time, WRITE_ADDR);
        tb_payload[0] = WRITE_ADDR[15:8]; // 地址高位
        tb_payload[1] = WRITE_ADDR[7:0];  // 地址低位
        for (i=0; i<NUM_BYTES_TO_TEST; i=i+1) begin
            tb_payload[i+2] = expected_data[i];
        end
        send_i2c_command(I2C_WRITE_CMD, NUM_BYTES_TO_TEST + 2);

        $display("[%0t] Waiting for physical I2C write to complete...", $time);
        #5_000_000; // 等待5ms，确保EEPROM写入完成

        $display("-----------------------------------------------------");
        $display("[%0t] Step 3: Sending ONE multi-byte I2C Read command...", $time);
        $display("[%0t] Issuing READ command for address 0x%h, length %0d", $time, WRITE_ADDR, NUM_BYTES_TO_TEST);

        tb_payload[0] = WRITE_ADDR[15:8];
        tb_payload[1] = WRITE_ADDR[7:0];
        tb_payload[2] = NUM_BYTES_TO_TEST[15:8];
        tb_payload[3] = NUM_BYTES_TO_TEST[7:0];

        send_i2c_command(I2C_READ_CMD, 4);

        $display("[%0t] Now waiting to verify %0d consecutive bytes from DUT...", $time, NUM_BYTES_TO_TEST);
        for (i = 0; i < NUM_BYTES_TO_TEST; i = i + 1) begin
            verify_single_read(expected_data[i], i);
            @(posedge clk);
        end

        #10000;

        $display("-----------------------------------------------------");
        $display("=== I2C Test Complete ===");
        #5000;

        $display("[%0t] Simulation finished.", $time);
        #3000000;
        $stop;
    end

endmodule