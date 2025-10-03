`timescale 1ns / 1ps

module tb_cdc;

    //==============================================================
    //====== 参数定义
    //==============================================================
    // PHY_CLK (60MHz) -> 16.667 ns period
    parameter real PHY_CLK_PERIOD = 16.667; 
    // dac_clk (200MHz) -> 5 ns period
    parameter real DAC_CLK_PERIOD = 5.0;

    //==============================================================
    //====== 信号定义
    //==============================================================
    // --- Inputs to CDC module ---
    reg         clk;
    reg         rst_n;
    reg  [7:0]  usb_data_in;
    reg         usb_data_valid_in;
    reg         ext_uart_rx;
    reg         dac_clk;

    // --- Outputs from CDC module ---
    wire        led_out;
    wire [7:0]  pwm_pins;
    wire        ext_uart_tx;
    wire [13:0] dac_data;
    wire [7:0]  usb_upload_data;
    wire        usb_upload_valid;

    // --- Inouts for I2C ---
    // The testbench uses wires for inout ports to observe the signals driven by the DUT.
    wire        SCL;
    wire        SDA;

    //==============================================================
    //====== 实例化被测模块 (DUT: cdc)
    //==============================================================
    cdc u_cdc (
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_rx(ext_uart_rx),
        .ext_uart_tx(ext_uart_tx),

        // I2C
        .SCL(SCL),
        .SDA(SDA),

        .dac_clk(dac_clk),
        .dac_data(dac_data),
        
        // 数据上传接口
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid)
    );

    //==============================================================
    //====== 时钟生成
    //==============================================================
    initial begin
        clk = 0;
        dac_clk = 0;
    end

    always #(PHY_CLK_PERIOD / 2) clk = ~clk;
    always #(DAC_CLK_PERIOD / 2) dac_clk = ~dac_clk;

    //==============================================================
    //====== 任务：模拟USB发送一个字节
    //==============================================================
    task send_byte;
        input [7:0] data;
        begin
            @(posedge clk);
            usb_data_valid_in = 1'b1;
            usb_data_in       = data;
            @(posedge clk);
            usb_data_valid_in = 1'b0;
            usb_data_in       = 8'h00;
        end
    endtask

    //==============================================================
    //====== 测试激励序列
    //==============================================================
    initial begin
        // --- 1. 初始化和复位 ---
        rst_n             = 1'b0;
        usb_data_valid_in = 1'b0;
        usb_data_in       = 8'h00;
        ext_uart_rx       = 1'b1; // UART RX保持空闲
        
        $display("[%t] >>> Test Start: Applying reset.", $time);
        #(PHY_CLK_PERIOD * 10);
        rst_n = 1'b1;
        $display("[%t] >>> Reset released. System is running.", $time);
        #(PHY_CLK_PERIOD * 20);

        // --- 2. 发送 I2C 配置命令 ---
        // 该命令来自: python i2c_oled_command.py config --clk 100000 --addr 0x3C
        // 帧内容: AA 55 04 00 05 00 01 86 A0 3C F0 (11 字节)
        // 帧头 (AA 55), 功能码(04), 长度(00 05), 数据体(00 01 86 A0 3C), 校验和(F0)
        $display("[%t] >>> Sending I2C Config Command (100kHz, Addr: 0x3C)...", $time);
        send_byte(8'hAA); // 帧头
        send_byte(8'h55);
        send_byte(8'h04); // 功能码: I2C Config
        send_byte(8'h00); // 长度高位
        send_byte(8'h05); // 长度低位 (5)
        send_byte(8'h00); // 数据: 时钟频率 (100000 = 0x000186A0)
        send_byte(8'h01);
        send_byte(8'h86);
        send_byte(8'hA0);
        send_byte(8'h3C); // 数据: 从机地址 (0x3C)
        send_byte(8'hF0); // 校验和
        
        #(PHY_CLK_PERIOD * 20); // 等待命令处理
        $display("[%t] >>> I2C Config Command Sent.", $time);


        // --- 3. 发送 OLED 初始化命令 ---
        // 该命令来自: python i2c_oled_command.py init
        // 这是一个较长的数据帧，将所有初始化字节作为I2C的payload发送
        // 功能码(05), 数据体第一个字节(00)表示I2C command
        $display("[%t] >>> Sending OLED Init Command...", $time);
        send_byte(8'hAA); // 帧头
        send_byte(8'h55);
        send_byte(8'h05); // 功能码: I2C TX
        send_byte(8'h00); // 长度高位
        send_byte(8'h1C); // 长度低位 (28 = 1(control) + 27(payload))
        send_byte(8'h00); // 数据体: I2C控制字节 (0x00 for command)
        // --- SSD1306 Init Payload (27 bytes) ---
        send_byte(8'hAE); send_byte(8'hD5); send_byte(8'h80); send_byte(8'hA8);
        send_byte(8'h3F); send_byte(8'hD3); send_byte(8'h00); send_byte(8'h40);
        send_byte(8'h8D); send_byte(8'h14); send_byte(8'h20); send_byte(8'h00);
        send_byte(8'hA1); send_byte(8'hC8); send_byte(8'hDA); send_byte(8'h12);
        send_byte(8'h81); send_byte(8'hCF); send_byte(8'hD9); send_byte(8'hF1);
        send_byte(8'hDB); send_byte(8'h40); send_byte(8'hA4); send_byte(8'hA6);
        send_byte(8'hAF);
        send_byte(8'hB1); // 校验和 (此处的校验和需要根据完整帧计算，请替换为实际值)
                          // 注意：为便于演示，这里的校验和B1是示意值，您需要用脚本生成准确的值
        
        // 等待足够长的时间让I2C传输完成
        #(PHY_CLK_PERIOD * 20000); 
        $display("[%t] >>> OLED Init Command Sent. Check I2C waves on SCL/SDA.", $time);


        // --- 4. 结束仿真 ---
        $display("[%t] >>> Test Finished.", $time);
        $finish;
    end

endmodule