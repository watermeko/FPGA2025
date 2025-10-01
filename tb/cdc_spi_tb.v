`timescale 1ns / 1ps

module cdc_spi_tb;

    //-----------------------------------------------------------------------------
    // 参数定义
    //-----------------------------------------------------------------------------
    localparam CLK_FREQ      = 100_000_000;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;
    
    // SPI 指令定义
    localparam CMD_SPI_WRITE = 8'h11;
    localparam CMD_SPI_READ  = 8'h12;
    
    //-----------------------------------------------------------------------------
    // 信号声明
    //-----------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg  [7:0]  usb_data_in;
    reg         usb_data_valid_in;

    // 连接到 DUT 的 SPI 和其他必要端口
    wire        spi_clk;
    wire        spi_cs_n;
    wire        spi_mosi;
    reg         spi_miso; // 由从机模型驱动
    
    wire [7:0]  usb_upload_data;
    wire        usb_upload_valid;
    
    // 虚拟端口 (本次测试不使用)
    wire        led_out;
    wire [7:0]  pwm_pins;
    wire        ext_uart_tx;
    reg         ext_uart_rx = 1'b1;
    reg         dac_clk = 0;
    wire [13:0] dac_data;

    //-----------------------------------------------------------------------------
    // DUT 实例化
    //-----------------------------------------------------------------------------
    cdc_spi dut (
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
        
        // SPI 端口
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        
        // USB 上传端口 (用于验证读操作)
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid),
        
        // 其他不使用的端口
        .led_out(led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_tx(ext_uart_tx),
        .ext_uart_rx(ext_uart_rx),
        .dac_clk(dac_clk),
        .dac_data(dac_data)
    );

    //-----------------------------------------------------------------------------
    // 时钟与复位生成
    //-----------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end
    
    initial begin
        rst_n             = 1'b0;
        usb_data_in       = 8'h00;
        usb_data_valid_in = 1'b0;
        spi_miso          = 1'bz;
        #100;
        rst_n = 1'b1;
    end

    //-----------------------------------------------------------------------------
    // SPI 从机模型 (用于响应 DUT)
    //-----------------------------------------------------------------------------
    reg [7:0] slave_ram [0:255];      // 存储 DUT 写入的数据
    reg [7:0] slave_read_mem [0:255]; // 预存的数据，供 DUT 读取
    
    reg [7:0] slave_tx_shift_reg;
    reg [7:0] slave_rx_shift_reg;
    reg [3:0] slave_bit_cnt;
    integer   slave_byte_cnt;

    always @(negedge spi_cs_n or negedge rst_n) begin
        if (!rst_n) begin
            slave_byte_cnt <= 0;
            slave_bit_cnt <= 0;
        end else begin
            slave_byte_cnt <= 0;
            slave_bit_cnt <= 0;
        end
    end

    always @(posedge spi_clk) begin
        if (!spi_cs_n) begin
            // 接收数据 (MOSI -> MISO)
            slave_rx_shift_reg <= {slave_rx_shift_reg[6:0], spi_mosi};
            
            // 发送数据 (MISO -> MOSI)
            spi_miso <= slave_tx_shift_reg[7];
            if (slave_bit_cnt == 0) begin // 每个字节开始时加载新数据
                slave_tx_shift_reg <= slave_read_mem[slave_byte_cnt];
            end else begin
                slave_tx_shift_reg <= {slave_tx_shift_reg[6:0], 1'b0};
            end
            
            slave_bit_cnt <= slave_bit_cnt + 1;
            if (slave_bit_cnt == 7) begin
                slave_ram[slave_byte_cnt] <= {slave_rx_shift_reg[6:0], spi_mosi};
                slave_byte_cnt <= slave_byte_cnt + 1;
            end
        end else begin
            spi_miso <= 1'bz;
        end
    end
    
    //-----------------------------------------------------------------------------
    // USB 字节发送任务 (基础构建块)
    //-----------------------------------------------------------------------------
    task send_usb_byte(input [7:0] byte_to_send);
    begin
        @(posedge clk);
        usb_data_in = byte_to_send;
        usb_data_valid_in = 1'b1;
        @(posedge clk);
        usb_data_valid_in = 1'b0;
        #(CLK_PERIOD_NS * 2); // 字节间延时
    end
    endtask

    //-----------------------------------------------------------------------------
    // SPI 写指令帧发送任务
    //-----------------------------------------------------------------------------
    task send_spi_write_command(input integer len, input [7:0] payload []);
        reg [7:0] checksum;
        integer i;
    begin
        // *** 关键：使用加法计算校验和，以匹配 protocol_parser ***
        checksum = CMD_SPI_WRITE + len[15:8] + len[7:0];
        for (i = 0; i < len; i = i + 1) begin
            checksum = checksum + payload[i];
        end

        // 发送帧
        send_usb_byte(8'hAA); // SOF1
        send_usb_byte(8'h55); // SOF2
        send_usb_byte(CMD_SPI_WRITE);
        send_usb_byte(len[15:8]);
        send_usb_byte(len[7:0]);
        for (i = 0; i < len; i = i + 1) begin
            send_usb_byte(payload[i]);
        end
        send_usb_byte(checksum);
    end
    endtask
    
    //-----------------------------------------------------------------------------
    // SPI 读指令帧发送任务
    //-----------------------------------------------------------------------------
    task send_spi_read_command(input integer len);
        reg [7:0] checksum;
    begin
        // *** 关键：使用加法计算校验和 ***
        checksum = CMD_SPI_READ + len[15:8] + len[7:0];

        // 发送帧
        send_usb_byte(8'hAA); // SOF1
        send_usb_byte(8'h55); // SOF2
        send_usb_byte(CMD_SPI_READ);
        send_usb_byte(len[15:8]);
        send_usb_byte(len[7:0]);
        // 读指令的 payload 是由 DUT 生成的，所以 testbench 发送空的 payload
        send_usb_byte(checksum);
    end
    endtask

    //-----------------------------------------------------------------------------
    // USB 上传数据监视器 (用于验证 SPI 读)
    //-----------------------------------------------------------------------------
    reg [7:0] usb_received_data [0:255];
    integer   usb_received_count;

    always @(posedge clk) begin
        if (usb_upload_valid) begin
            usb_received_data[usb_received_count] = usb_upload_data;
            $display("[%0t ns] [MONITOR] USB Upload Received byte %0d: 0x%02h", $time, usb_received_count, usb_upload_data);
            usb_received_count = usb_received_count + 1;
        end
    end
    
    //-----------------------------------------------------------------------------
    // 主测试序列
    //-----------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        #1000;
        
        // --- TEST CASE 1: SPI 写操作 ---
        $display("\n[%0t ns] [TEST] ====== Starting SPI Write Test ======", $time);
        begin
            reg [7:0] write_payload [0:3];
            write_payload[0] = 8'hDE;
            write_payload[1] = 8'hAD;
            write_payload[2] = 8'hBE;
            write_payload[3] = 8'hEF;
            
            send_spi_write_command(4, write_payload);
        end
        
        #50000; // 等待传输完成
        
        $display("\n[%0t ns] [VERIFY] Verifying SPI Write...", $time);
        if (slave_ram[0] == 8'hDE && slave_ram[1] == 8'hAD && slave_ram[2] == 8'hBE && slave_ram[3] == 8'hEF) begin
            $display("✅ SUCCESS: SPI Write data matches expected [DE, AD, BE, EF].");
        end else begin
            $display("❌ FAIL: SPI Write data mismatch! Read: [%0h, %0h, %0h, %0h]", slave_ram[0], slave_ram[1], slave_ram[2], slave_ram[3]);
        end

        // --- TEST CASE 2: SPI 读操作 ---
        $display("\n[%0t ns] [TEST] ====== Starting SPI Read Test ======", $time);
        // 初始化 USB 接收计数器和从机内存
        usb_received_count = 0;
        slave_read_mem[0] = 8'hAA;
        slave_read_mem[1] = 8'hBB;
        slave_read_mem[2] = 8'hCC;
        
        send_spi_read_command(3);
        
        #50000; // 等待传输和上传完成

        $display("\n[%0t ns] [VERIFY] Verifying SPI Read...", $time);
        if (usb_received_count == 3) begin
            if (usb_received_data[0] == 8'hAA && usb_received_data[1] == 8'hBB && usb_received_data[2] == 8'hCC) begin
                $display("✅ SUCCESS: SPI Read data matches expected [AA, BB, CC].");
            end else begin
                $display("❌ FAIL: SPI Read data mismatch! Read: [%0h, %0h, %0h]", usb_received_data[0], usb_received_data[1], usb_received_data[2]);
            end
        end else begin
            $display("❌ FAIL: Expected 3 bytes to be uploaded, but received %0d bytes.", usb_received_count);
        end
        
        #1000;
        $display("\n[%0t ns] [TEST] ====== SPI Test Complete ======", $time);
        $finish;
    end

endmodule