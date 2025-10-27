// ============================================================================
// Module:      cdc_tb (已更新以测试有地址和无地址I2C)
// Author:      Gemini
// Date:        2025-10-16
// Description:
// - 此测试平台已更新，以同时验证标准的I2C读写和新增的无地址I2C读写。
// - 定义了新的I2C命令码 0x12 和 0x13。
// - 增加了专门的测试序列来发送无地址读写命令。
// - 复用EEPROM模型来巧妙地验证无地址模式的功能。
// - 更新了日志输出，以清晰区分不同模式的测试。
// ============================================================================

`timescale 1ns / 1ns

module cdc_tb;

    //-----------------------------------------------------------------------------
    // 测试平台参数
    //-----------------------------------------------------------------------------
    localparam CLK_FREQ      = 50_000_000;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;
    localparam DAC_CLK_PERIOD_NS = 10; 

    //-----------------------------------------------------------------------------
    // I2C 测试参数
    //-----------------------------------------------------------------------------
    localparam I2C_CONFIG_CMD = 8'h04;
    localparam I2C_WRITE_CMD  = 8'h05;
    localparam I2C_READ_CMD   = 8'h06;
    // <<< NEW: 定义无地址模式的命令码
    localparam I2C_WRITE_NO_ADDR_CMD = 8'h12;
    localparam I2C_READ_NO_ADDR_CMD  = 8'h13;
    
    localparam EEPROM_DEVICE_ADDR_8BIT = 8'hA0;
    localparam EEPROM_DEVICE_ADDR_7BIT = EEPROM_DEVICE_ADDR_8BIT >> 1; // 值为 0x50
    localparam I2C_SCL_FREQ_CODE_100KHZ = 8'h01; 
    localparam READ_TIMEOUT = 100_000;
    
    // <<< NEW: 为两组测试定义不同的地址和数据
    localparam WRITE_ADDR        = 16'h003C;
    localparam NUM_BYTES_TO_TEST = 4;

    localparam WRITE_ADDR_NOADDR = 16'h00A8;
    localparam NUM_BYTES_NOADDR  = 5;

    //-----------------------------------------------------------------------------
    // 测试平台信号 (此部分无变化)
    //-----------------------------------------------------------------------------
    // ... 信号定义保持不变 ...
    reg clk;
    reg rst_n;
    reg [7:0] usb_data_in;
    reg usb_data_valid_in;
    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;
    wire led_out;
    wire [7:0] pwm_pins;
    reg  ext_uart_rx;
    wire ext_uart_tx;
    wire i2c_scl;
    wire i2c_sda;
    reg  dac_clk;
    wire signed [13:0] dac_data; 
    wire spi_clk;
    wire spi_cs_n;
    wire spi_mosi;
    reg  spi_miso;
    reg [7:0] dsm_signal_in;
    wire debug_out;

    // --- 测试平台专用变量 ---
    reg [7:0] tb_payload [0:127];
    // <<< NEW: 为两组测试定义不同的期望数据数组
    reg [7:0] expected_data [0:NUM_BYTES_TO_TEST-1];
    reg [7:0] expected_data_noaddr [0:NUM_BYTES_NOADDR-1];
    integer i;

    // --- I2C SDA 线上拉电阻 ---
    pullup PUP(i2c_sda);

    //-----------------------------------------------------------------------------
    // DUT 和从设备实例化 (此部分无变化)
    //-----------------------------------------------------------------------------
    // ... 实例化保持不变 ...
    cdc dut (
        .clk(clk), .rst_n(rst_n), .usb_data_in(usb_data_in), .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out), .pwm_pins(pwm_pins), .ext_uart_rx(ext_uart_rx), .ext_uart_tx(ext_uart_tx),
        .i2c_scl(i2c_scl), .i2c_sda(i2c_sda), .dac_clk(dac_clk), .dac_data(dac_data),
        .spi_clk(spi_clk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .dsm_signal_in(dsm_signal_in), .debug_out(debug_out), .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid)
    );
    M24LC64 u_eeprom (
        .A0(1'b0), .A1(1'b0), .A2(1'b0), .WP(1'b0), .SDA(i2c_sda), .SCL(i2c_scl), .RESET(~rst_n)
    );

    //-----------------------------------------------------------------------------
    // 时钟、复位和信号初始化 (此部分无变化)
    //-----------------------------------------------------------------------------
    // ... 初始化代码保持不变 ...
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end
    initial begin
        dac_clk = 0;
        forever #(DAC_CLK_PERIOD_NS / 2) dac_clk = ~dac_clk;
    end
    initial begin
        rst_n = 1'b0;
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
    end
    initial begin
        ext_uart_rx   = 1'b1; 
        spi_miso      = 1'b0;
        dsm_signal_in = 8'h00;
        usb_data_valid_in = 1'b0;
        usb_data_in = 8'h00;
    end

    //-----------------------------------------------------------------------------
    // 辅助任务和验证任务 (此部分无变化)
    //-----------------------------------------------------------------------------
    // ... 任务定义保持不变 ...
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
    // 主测试序列
    //-----------------------------------------------------------------------------
    initial begin

        wait (rst_n === 1'b1);
        #1000;

        // --- 初始化测试数据 ---
        expected_data[0] = 8'hDE;
        expected_data[1] = 8'hAD;
        expected_data[2] = 8'hBE;
        expected_data[3] = 8'hEF;

        expected_data_noaddr[0] = 8'h11;
        expected_data_noaddr[1] = 8'h22;
        expected_data_noaddr[2] = 8'h33;
        expected_data_noaddr[3] = 8'h44;
        expected_data_noaddr[4] = 8'h55;

        // =========================================================================
        // 测试部分 1: 标准带地址的 I2C 读写
        // =========================================================================
        $display("\n=== [TEST 1] Starting I2C EEPROM Verification (Standard Mode with Address) ===");

        $display("[%0t] Step 1.1: Sending I2C Config command (Addr: 0x%h, Freq: 100kHz)...", $time, EEPROM_DEVICE_ADDR_7BIT);
        tb_payload[0] = EEPROM_DEVICE_ADDR_7BIT;    
        tb_payload[1] = I2C_SCL_FREQ_CODE_100KHZ;   
        send_i2c_command(I2C_CONFIG_CMD, 2);        
        #2000;

        $display("[%0t] Step 1.2: Sending I2C Write command to EEPROM address 0x%h...", $time, WRITE_ADDR);
        tb_payload[0] = WRITE_ADDR[15:8]; 
        tb_payload[1] = WRITE_ADDR[7:0];  
        for (i=0; i<NUM_BYTES_TO_TEST; i=i+1) begin
            tb_payload[i+2] = expected_data[i];
        end
        send_i2c_command(I2C_WRITE_CMD, NUM_BYTES_TO_TEST + 2);

        $display("[%0t] Waiting for physical I2C write to complete...", $time);
        #5_000_000; 

        $display("-----------------------------------------------------");
        $display("[%0t] Step 1.3: Sending ONE multi-byte I2C Read command...", $time);
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
        
        // =========================================================================
        // <<< NEW: 测试部分 2: 无寄存器地址的 I2C 读写
        // =========================================================================
        $display("\n=== [TEST 2] Starting I2C EEPROM Verification (No-Address Mode) ===");

        // Step 2.1: 配置命令是共享的，无需重复发送，除非需要更改设备地址或频率

        $display("[%0t] Step 2.1: Sending I2C No-Address Write command...", $time);
        // 数据格式: [设备地址] + [数据1] + [数据2] ...
        tb_payload[0] = EEPROM_DEVICE_ADDR_7BIT;
        for (i=0; i<NUM_BYTES_NOADDR; i=i+1) begin
            tb_payload[i+1] = expected_data_noaddr[i];
        end
        // 先用一个标准写来定位地址指针，这样我们才知道无地址写从哪里开始
        // 这一步不是必须的，但为了验证的确定性，这样做更好
        $display("[%0t]   (Helper step: Setting EEPROM address pointer to 0x%h first)...", $time, WRITE_ADDR_NOADDR);
        tb_payload[0] = WRITE_ADDR_NOADDR[15:8];
        tb_payload[1] = WRITE_ADDR_NOADDR[7:0];
        tb_payload[2] = expected_data_noaddr[0]; // 只写第一个字节来定位
        send_i2c_command(I2C_WRITE_CMD, 3);
        #5_000_000; // 等待写入完成

        $display("[%0t]   Now sending the actual No-Address Write for subsequent bytes...", $time);
        // EEPROM指针已在 WRITE_ADDR_NOADDR + 1，现在我们用无地址模式写入剩下的字节
        tb_payload[0] = EEPROM_DEVICE_ADDR_7BIT;
        for (i=1; i<NUM_BYTES_NOADDR; i=i+1) begin // 从第2个字节开始
            tb_payload[i] = expected_data_noaddr[i];
        
        send_i2c_command(I2C_WRITE_NO_ADDR_CMD, NUM_BYTES_NOADDR); // 长度是设备地址+数据字节数

        $display("[%0t] Waiting for physical I2C write to complete...", $time);
        #5_000_000;
        
        $display("-----------------------------------------------------");
        $display("[%0t] Step 2.2: Sending I2C No-Address Read command...", $time);
        // 为了验证，我们首先需要再次用标准写来设置EEPROM的地址指针
        $display("[%0t]   (Helper step: Resetting EEPROM address pointer to 0x%h)...", $time, WRITE_ADDR_NOADDR);
        tb_payload[0] = WRITE_ADDR_NOADDR[15:8];
        tb_payload[1] = WRITE_ADDR_NOADDR[7:0];
        send_i2c_command(I2C_WRITE_CMD, 2); // 这次只发送地址，不带数据，这是一种常见的指针设置方法
        #5_000_000;

        $display("[%0t]   Now issuing the actual No-Address READ command for length %0d", $time, NUM_BYTES_NOADDR);
        // 数据格式: [设备地址] + [长度高8位] + [长度低8位]
        tb_payload[0] = EEPROM_DEVICE_ADDR_7BIT;
        tb_payload[1] = NUM_BYTES_NOADDR[15:8];
        tb_payload[2] = NUM_BYTES_NOADDR[7:0];
        send_i2c_command(I2C_READ_NO_ADDR_CMD, 3);
        
        $display("[%0t] Now waiting to verify %0d consecutive bytes from DUT...", $time, NUM_BYTES_NOADDR);
        for (i = 0; i < NUM_BYTES_NOADDR; i = i + 1) begin
            verify_single_read(expected_data_noaddr[i], i);
            @(posedge clk);
        end
        #10000;

        // =========================================================================
        // 测试结束
        // =========================================================================
        $display("\n-----------------------------------------------------");
        $display("=== All I2C Tests Complete ===");
        #5000;

        $display("[%0t] Simulation finished.", $time);
        #3000000;
        $stop;
    end
    end

endmodule